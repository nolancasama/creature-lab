class_name PaceDeformer
extends RefCounted
## FAST / SLOW: how the animal moves through time. Nothing here touches what the animal
## IS - no size, proportion, muscle, age or colour - so SPEED stacks cleanly with every
## other adjective. A big old strong animal can still be ridiculously fast, and that
## combination is meant to be funny.
##
## Deliberately not "playback speed x2 / x0.5". A student reading only a faster loop has
## to compare it against a memory of the normal one; a student watching the animal blur
## sideways and leave a ghost behind does not. So each state gets its own behaviour, and
## playback speed is only a supporting cue:
##   FAST -> normal idle, interrupted by sudden bursts: twitch, micro-dash with
##           afterimages and speed lines, foot shuffle, snap turn, occasional arc run.
##   SLOW -> everything drawn out: long head turns, a foot raised and held, long pauses.
##
## Both run off one countdown in tick(), not per-frame math: an action is picked, a tween
## plays it, and the next one is scheduled at a randomised interval so the loop never
## reads as mechanical. Between actions this costs a subtraction.

enum Pace { NEUTRAL, FAST, SLOW }

# --- FAST tuning -------------------------------------------------------------
## Only a mild lift. The bursts are what say "fast"; a doubled idle loop is the thing
## this whole class exists to replace, and at 2x the animal just looks badly animated.
const FAST_PLAYBACK := 1.25
const FAST_GAP := Vector2(0.55, 1.6) ## Between actions. Short, but never zero: see below.
const FAST_DASH_DISTANCE := Vector2(0.15, 0.35) ## Fractions of stand height.
const FAST_DASH_DURATION := Vector2(0.05, 0.15)
## Max wander from where it started, as a fraction of stand height. Tight on purpose:
## this animal is being presented on a small platform, and a run of dashes that all
## happened to agree on a direction used to walk it to the edge of frame.
const FAST_DASH_LEASH := 0.34
## How far the animal may turn away from facing the student. A real snap turn is 90 or
## 180 degrees, but this animal is being looked at - left facing away it stops teaching
## anything - so it turns hard and comes straight back instead of accumulating heading.
const FAST_SNAP_LIMIT := 0.95
const FAST_AFTERIMAGES := Vector2i(1, 3)
const FAST_AFTERIMAGE_LIFE := 0.20
const FAST_SHUFFLE_DURATION := Vector2(0.30, 0.60)
const FAST_SHUFFLE_RATE := 34.0 ## Radians/sec of leg swing - blurred feet, not a tremble.
const FAST_SHUFFLE_SWING := 0.30
const FAST_SNAP_DURATION := 0.09
const FAST_TWITCH_DURATION := 0.07
const FAST_BURST_DURATION := 0.85
const FAST_BURST_RADIUS := 0.72 ## Fraction of stand height.

# --- SLOW tuning -------------------------------------------------------------
const SLOW_PAUSE := Vector2(1.0, 2.2)
const SLOW_TURN_DURATION := Vector2(2.0, 3.0)
const SLOW_TURN_HOLD := Vector2(0.7, 1.4)
const SLOW_STEP_DURATION := 1.15 ## Per phase; a whole step is lift + hold + lower.
const SLOW_STEP_HOLD := 0.9
const SLOW_STEP_LIFT := 0.55 ## Radians at the shin.
const SLOW_SWEEP_DURATION := Vector2(1.6, 2.6)
const SLOW_ANTICIPATION_CHANCE := 0.3
const SLOW_ANTICIPATION := Vector2(0.25, 0.5)

## Read by CreatureRig each frame and folded into the body transform, the same way
## MuscleDeformer's shake and FeelDeformer's offset are.
var offset := Vector3.ZERO
var yaw := 0.0

var pace := Pace.NEUTRAL
var playback := 1.0 ## Idle animation speed multiplier the rig should run its clock at.

var _rig: CreatureRig = null
var _def: AnimalDefinition = null
var _tweens: Array[Tween] = []
var _next_action := 0.0
var _shuffle_left := 0.0
var _shuffle_clock := 0.0
var _head_yaw := 0.0 ## Applied to the head bone about its own up axis.
var _ear_flick := 0.0
var _tail_swing := 0.0
var _step_lift := 0.0
var _step_leg := -1
var _posed_cache := {} ## bone name -> index, so tick() is not doing find_bone() every frame.


func _init(rig: CreatureRig) -> void:
	_rig = rig
	_def = rig.definition


## FAST above 1.0, SLOW below it. The authored SPEED values carry the intent; SLOW uses
## its value directly as playback speed because "35-50% of normal" is exactly what that
## number means, while FAST deliberately ignores it in favour of behaviour.
func set_state(value: float) -> void:
	kill_tweens()
	_clear_action_state()
	if value > 1.001:
		pace = Pace.FAST
		playback = FAST_PLAYBACK
	elif value < 0.999:
		pace = Pace.SLOW
		playback = clampf(value, 0.30, 0.60)
	else:
		pace = Pace.NEUTRAL
		playback = 1.0
	_next_action = _first_gap()


func animate_to(value: float) -> void:
	var was := pace
	set_state(value)
	if pace == was or _rig == null or not _rig.is_inside_tree():
		return
	# One cue on the way in, so the change of pace is something you hear as well as see.
	if pace == Pace.FAST:
		Audio.play("zip", 1.15)
		_next_action = 0.12 # Show the student what fast means immediately.
	elif pace == Pace.SLOW:
		Audio.play("stretch", 0.7)


func reset() -> void:
	set_state(1.0)
	offset = Vector3.ZERO
	yaw = 0.0
	playback = 1.0
	pace = Pace.NEUTRAL


func is_animating() -> bool:
	for tween in _tweens:
		if tween != null and tween.is_valid() and tween.is_running():
			return true
	return false


func kill_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


## Called by the rig after its own idle animation has posed the skeleton, so these
## rotations sit on top of the walk swing and appendage sway rather than being erased
## by them.
func tick(delta: float) -> void:
	if pace == Pace.NEUTRAL or _rig == null or _rig.skeleton == null:
		return
	if _shuffle_left > 0.0:
		_shuffle_left -= delta
		_shuffle_clock += delta
		_apply_shuffle()
	_next_action -= delta
	if _next_action <= 0.0:
		_start_next_action()
	_apply_poses()


# --- Scheduling --------------------------------------------------------------

func _first_gap() -> float:
	if pace == Pace.FAST:
		return randf_range(FAST_GAP.x, FAST_GAP.y)
	if pace == Pace.SLOW:
		return randf_range(SLOW_PAUSE.x, SLOW_PAUSE.y)
	return 999.0


## Weighted rather than uniform: the micro-dash is the signature FAST behaviour and the
## drawn-out head turn the signature SLOW one, so both come up often, while the arc run
## stays rare enough to still read as an event when it happens.
func _start_next_action() -> void:
	_next_action = _first_gap()
	if _rig == null or not _rig.is_inside_tree():
		return
	if pace == Pace.FAST:
		var roll := randf()
		if roll < 0.34:
			_dash()
		elif roll < 0.56:
			_twitch()
		elif roll < 0.72:
			_shuffle()
		elif roll < 0.88:
			_snap_turn()
		else:
			_burst()
	elif pace == Pace.SLOW:
		var roll := randf()
		if roll < 0.45:
			_slow_head_turn()
		elif roll < 0.78:
			_slow_step()
		else:
			_slow_sweep()


# --- FAST behaviours ---------------------------------------------------------

## The signature move: gone and stopped again before the eye can track it, with ghosts
## strung along the path so the movement is still readable afterwards. Interpolated over
## a few frames rather than teleported, because an instant position change reads as a
## glitch or a magic trick instead of speed.
func _dash() -> void:
	var direction := _dash_direction()
	var distance := randf_range(FAST_DASH_DISTANCE.x, FAST_DASH_DISTANCE.y) * _unit()
	var duration := randf_range(FAST_DASH_DURATION.x, FAST_DASH_DURATION.y)
	var from := offset
	var to := offset + direction * distance

	_speed_lines(direction)
	_ground_puff(from)
	Audio.play("zip", randf_range(1.05, 1.3))
	var ghosts := randi_range(FAST_AFTERIMAGES.x, FAST_AFTERIMAGES.y)
	for i in ghosts:
		# Strung along the path, not stacked at the ends, so they read as one animal
		# smeared across the move rather than a small herd of them.
		var at: Vector3 = from.lerp(to, float(i + 1) / float(ghosts + 1))
		_rig.spawn_afterimage(at, FAST_AFTERIMAGE_LIFE)

	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_method(_set_offset, from, to, duration).set_trans(Tween.TRANS_QUINT) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _ground_puff(to))
	# A hard stop, no settle or overshoot: stopping dead is half of what makes it look fast.


## Away from home once the animal has wandered, so a run of dashes cannot walk it off
## the edge of the platform, but never in a single predictable direction.
func _dash_direction() -> Vector3:
	var candidates := [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var leash := FAST_DASH_LEASH * _unit()
	if offset.length() > leash:
		var home := -offset.normalized()
		# Keep some spread so the return trip is not a straight line back every time.
		return (home + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))).normalized()
	var pick: Vector3 = candidates[randi() % candidates.size()]
	# Forward and back are shortened hard: seen from the front those read as the animal
	# growing and shrinking rather than moving sideways, which is the one thing SPEED
	# must never look like.
	if absf(pick.z) > 0.5:
		pick *= 0.45
	return pick


## Brief and separated by real idle, never continuous. A creature that twitches every
## frame reads as frightened, glitchy or broken - all meanings that belong to other
## words, or to no word at all.
func _twitch() -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	match randi() % 4:
		0: # Rapid head turn and back.
			var side := 0.55 * (1.0 if randf() < 0.5 else -1.0)
			tween.tween_method(_set_head_yaw, 0.0, side, FAST_TWITCH_DURATION)
			tween.tween_interval(randf_range(0.05, 0.18))
			tween.tween_method(_set_head_yaw, side, 0.0, FAST_TWITCH_DURATION * 1.4)
		1: # Ear flick.
			tween.tween_method(_set_ear_flick, 0.0, 0.5, FAST_TWITCH_DURATION)
			tween.tween_method(_set_ear_flick, 0.5, 0.0, FAST_TWITCH_DURATION * 2.2) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		2: # Tail snap.
			var swing := 0.7 * (1.0 if randf() < 0.5 else -1.0)
			tween.tween_method(_set_tail_swing, 0.0, swing, FAST_TWITCH_DURATION)
			tween.tween_method(_set_tail_swing, swing, 0.0, FAST_TWITCH_DURATION * 2.6) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_: # Tiny whole-body twitch: a jolt of a few centimetres, not a shake.
			var jolt := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() \
				* _unit() * 0.035
			var home := offset
			tween.tween_method(_set_offset, home, home + jolt, 0.045)
			tween.tween_method(_set_offset, home + jolt, home, 0.09)


## Cartoon wind-up: the feet blur while the animal stays put. Driven in tick() rather
## than by a tween because it is a fast oscillation, not a path between two values.
func _shuffle() -> void:
	_shuffle_left = randf_range(FAST_SHUFFLE_DURATION.x, FAST_SHUFFLE_DURATION.y)
	_shuffle_clock = 0.0
	_ground_puff(offset)


## Whipping round to face a new way, over in a couple of frames. Reads as reflexes.
func _snap_turn() -> void:
	var target := FAST_SNAP_LIMIT * (1.0 if randf() < 0.5 else -1.0)
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_method(_set_yaw, yaw, target, FAST_SNAP_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(randf_range(0.12, 0.4))
	# Snapped back just as hard, so the turn reads as reflexes rather than as the animal
	# quietly rotating away from the class over the course of the lesson.
	tween.tween_method(_set_yaw, target, 0.0, FAST_SNAP_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if randf() < 0.45:
		# Look left, right, forward in quick succession on top of the turn.
		tween.parallel().tween_method(_set_head_yaw, 0.0, -0.5, 0.06)
		tween.tween_method(_set_head_yaw, -0.5, 0.5, 0.08)
		tween.tween_method(_set_head_yaw, 0.5, 0.0, 0.07)


## The rare one: a quick arc across the platform and back to roughly where it started.
## Kept occasional on purpose - a behaviour this big stops being an event if it repeats.
func _burst() -> void:
	var radius := FAST_BURST_RADIUS * _unit()
	var start_angle := randf() * TAU
	var sweep := (1.0 if randf() < 0.5 else -1.0) * randf_range(PI * 0.7, TAU)
	var home := offset
	var centre := home - Vector3(cos(start_angle), 0.0, sin(start_angle)) * radius

	Audio.play("whoosh", 1.0)
	_ground_puff(home)
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_method(func(t: float) -> void:
			var angle := start_angle + sweep * t
			_set_offset(centre + Vector3(cos(angle), 0.0, sin(angle)) * radius)
			# Lean into the turn, the way anything running a tight arc has to.
			_set_yaw(angle + (PI * 0.5 if sweep > 0.0 else -PI * 0.5)),
		0.0, 1.0, FAST_BURST_DURATION).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		_ground_puff(offset)
		Audio.play("zip", 1.2))
	# Square back up to the student. Without this the arc leaves the animal parked at
	# whatever heading it happened to finish on.
	tween.tween_method(_set_yaw, yaw, 0.0, 0.14).set_trans(Tween.TRANS_CUBIC)
	# Ghosts at intervals along the arc, so the run itself is legible and not just a blur.
	for i in 3:
		var when := FAST_BURST_DURATION * (float(i) + 1.0) / 4.0
		var ghost := _rig.create_tween()
		_tweens.append(ghost)
		ghost.tween_interval(when)
		ghost.tween_callback(func() -> void: _rig.spawn_afterimage(offset, FAST_AFTERIMAGE_LIFE))


# --- SLOW behaviours ---------------------------------------------------------

## The clearest SLOW cue: a head turn that takes as long as a whole sentence, held at
## the end, then brought back just as slowly. Calm and deliberate, never a droop.
func _slow_head_turn() -> void:
	var side := randf_range(0.45, 0.75) * (1.0 if randf() < 0.5 else -1.0)
	var out := randf_range(SLOW_TURN_DURATION.x, SLOW_TURN_DURATION.y)
	var tween := _rig.create_tween()
	_tweens.append(tween)
	if randf() < SLOW_ANTICIPATION_CHANCE:
		tween.tween_interval(randf_range(SLOW_ANTICIPATION.x, SLOW_ANTICIPATION.y))
	tween.tween_method(_set_head_yaw, _head_yaw, side, out) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(randf_range(SLOW_TURN_HOLD.x, SLOW_TURN_HOLD.y))
	tween.tween_method(_set_head_yaw, side, 0.0, out * 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Hold the next action off until this one has actually finished playing.
	_next_action = out * 2.1 + SLOW_TURN_HOLD.y + randf_range(SLOW_PAUSE.x, SLOW_PAUSE.y)


## One front foot lifted, held in the air, and put back down - the whole thing taking
## the better part of four seconds. The animal is perfectly steady the entire time,
## which is what separates SLOW from WEAK or OLD.
func _slow_step() -> void:
	var legs := _def.legs
	if legs.is_empty():
		_slow_head_turn()
		return
	_step_leg = randi() % legs.size()
	var tween := _rig.create_tween()
	_tweens.append(tween)
	if randf() < SLOW_ANTICIPATION_CHANCE:
		# The comic beat: visibly about to move, then not moving yet.
		tween.tween_interval(randf_range(SLOW_ANTICIPATION.x, SLOW_ANTICIPATION.y))
	tween.tween_method(_set_step_lift, 0.0, SLOW_STEP_LIFT, SLOW_STEP_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(SLOW_STEP_HOLD)
	tween.tween_method(_set_step_lift, SLOW_STEP_LIFT, 0.0, SLOW_STEP_DURATION * 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: _step_leg = -1)
	_next_action = SLOW_STEP_DURATION * 2.2 + SLOW_STEP_HOLD \
		+ randf_range(SLOW_PAUSE.x, SLOW_PAUSE.y)


## Ears and tail moving through their whole range at a fraction of normal speed.
func _slow_sweep() -> void:
	var swing := randf_range(0.3, 0.5) * (1.0 if randf() < 0.5 else -1.0)
	var duration := randf_range(SLOW_SWEEP_DURATION.x, SLOW_SWEEP_DURATION.y)
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_method(_set_tail_swing, _tail_swing, swing, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_method(_set_ear_flick, _ear_flick, swing * 0.5, duration) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_method(_set_tail_swing, swing, 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_method(_set_ear_flick, swing * 0.5, 0.0, duration) \
		.set_trans(Tween.TRANS_SINE)
	_next_action = duration * 2.0 + randf_range(SLOW_PAUSE.x, SLOW_PAUSE.y)


# --- Applying it to the skeleton ---------------------------------------------

func _apply_poses() -> void:
	if not is_zero_approx(_head_yaw):
		_rotate_bone(_head_bone(), Vector3.UP, _head_yaw)
	if not is_zero_approx(_ear_flick):
		var side := 1.0
		for bone in _def.floppy_bones:
			if bone.begins_with("ear") or bone.contains("ear"):
				_rotate_bone(bone, Vector3.FORWARD, _ear_flick * side)
				side *= -1.0 # Mirrored, so both ears flick outward rather than sideways.
	if not is_zero_approx(_tail_swing):
		_rotate_bone(_tail_bone(), Vector3.UP, _tail_swing)
	if _step_leg >= 0 and not is_zero_approx(_step_lift):
		var legs := _def.legs
		if _step_leg < legs.size():
			var bones: PackedStringArray = legs[_step_leg].get("bones", PackedStringArray())
			if not bones.is_empty():
				_rotate_bone(str(bones[0]), Vector3.RIGHT, -_step_lift)


func _apply_shuffle() -> void:
	# Alternating legs at a rate the eye cannot resolve: blurred feet, not a shiver.
	var swing := sin(_shuffle_clock * FAST_SHUFFLE_RATE) * FAST_SHUFFLE_SWING
	var index := 0
	for leg in _def.legs:
		var bones: PackedStringArray = leg.get("bones", PackedStringArray())
		index += 1
		if bones.is_empty():
			continue
		_rotate_bone(str(bones[0]), Vector3.RIGHT, swing * (1.0 if index % 2 == 0 else -1.0))


## Rotates about whichever of the bone's OWN axes lines up with the given world
## direction. Bone axis conventions differ between these models - a skull bone's local Y
## is not reliably "up" - so picking the axis by its rest orientation is what keeps a
## head turn a turn instead of a head roll on some animals and not others.
func _rotate_bone(bone_name: String, world_axis: Vector3, angle: float) -> void:
	if bone_name.is_empty():
		return
	var idx := _bone_index(bone_name)
	if idx == -1:
		return
	var rest := _rig.skeleton.get_bone_rest(idx)
	var global_rest := _rig.skeleton.get_bone_global_rest(idx).basis
	var best := Vector3.UP
	var best_dot := 0.0
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var mapped: Vector3 = global_rest.orthonormalized() * axis
		var score: float = mapped.dot(world_axis)
		if absf(score) > absf(best_dot):
			best_dot = score
			best = axis
	if is_zero_approx(best_dot):
		best_dot = 1.0
	var turn := Quaternion(best.normalized(), angle * signf(best_dot))
	_rig.skeleton.set_bone_pose_rotation(idx, rest.basis.get_rotation_quaternion() * turn)
	_rig.mark_posed(idx)


func _bone_index(bone_name: String) -> int:
	if _posed_cache.has(bone_name):
		return int(_posed_cache[bone_name])
	var idx := _rig.skeleton.find_bone(bone_name)
	_posed_cache[bone_name] = idx
	return idx


## Sockets already name the head bone per species, so nothing here hard-codes "scull".
func _head_bone() -> String:
	for socket_name in ["face", "head_top"]:
		var socket = _def.sockets.get(socket_name, {})
		if socket is Dictionary and not str(socket.get("bone", "")).is_empty():
			return str(socket.get("bone"))
	return ""


## The floppy list is authored as ears plus the one loose spine bone at the back, so
## whatever in it is not an ear is the tail.
func _tail_bone() -> String:
	for bone in _def.floppy_bones:
		if not bone.contains("ear"):
			return str(bone)
	return ""


# --- Effects -----------------------------------------------------------------

## Stylised streaks trailing the animal, pointed against the direction of travel and
## gone within the second. Shown only while moving - speed lines on a standing animal
## are just decoration and stop meaning anything.
func _speed_lines(direction: Vector3) -> void:
	var lines := Fx.make("speed", Color("#dff2ff"), _unit() * 0.14)
	lines.one_shot = true
	lines.basis = Basis.looking_at(-direction)
	_rig.add_fx(lines, offset + Vector3(0.0, _unit() * 0.38, 0.0))
	_free_after(lines, 0.8)


## A small puff where the feet leave and land. Kept subtle: this is punctuation for the
## dash, not weather.
func _ground_puff(at: Vector3) -> void:
	var puff := Fx.make("dust", Color("#d8d2c4"), _unit() * 0.10, 0.5)
	puff.one_shot = true
	_rig.add_fx(puff, at + Vector3(0.0, _unit() * 0.03, 0.0))
	_free_after(puff, 1.4)


func _free_after(node: Node3D, seconds: float) -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(seconds)
	tween.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.queue_free())


# --- Plumbing ----------------------------------------------------------------

func _unit() -> float:
	return _def.stand_height


func _clear_action_state() -> void:
	offset = Vector3.ZERO
	yaw = 0.0
	_head_yaw = 0.0
	_ear_flick = 0.0
	_tail_swing = 0.0
	_step_lift = 0.0
	_step_leg = -1
	_shuffle_left = 0.0


func _set_offset(value: Vector3) -> void:
	offset = value


func _set_yaw(value: float) -> void:
	yaw = value


func _set_head_yaw(value: float) -> void:
	_head_yaw = value


func _set_ear_flick(value: float) -> void:
	_ear_flick = value


func _set_tail_swing(value: float) -> void:
	_tail_swing = value


func _set_step_lift(value: float) -> void:
	_step_lift = value
