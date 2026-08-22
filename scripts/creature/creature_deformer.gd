class_name CreatureDeformer
extends RefCounted
## Cartoon body/leg deformation for one creature, and the animated transitions into it.
##
## Five values are controlled independently, as the design asks: body_length plus one
## length per leg, with the body's height handled separately so the two never fight.
##
## Bones are *translated*, never scaled. Scaling a spine bone would drag the head and
## legs into the stretch too; pushing bones apart lets the skinning stretch only the mesh
## spanning the gap, so the torso lengthens while head, legs, feet and tail keep their
## shape. It also costs nothing per frame beyond setting a handful of bone poses - no
## soft body, no mesh rebuilding, fine for a Chromebook.
##
## TALL floats the body up to its final height first and then drops each leg down to
## meet the ground one at a time. An earlier version instead derived the body's height
## from whatever the legs were currently doing, which made the animal lurch around on
## part-grown legs and splay them outward. Floating keeps it level and reads much more
## clearly: the animal hangs in the air and puts its landing gear down leg by leg.

const LEG_STAGGER := 0.30 ## Gap between one leg starting and the next.
const FLOAT_TIME := 0.50
const LONG_OVERSHOOT := 1.08
const LONG_REBOUND := 0.97
const SHORT_OVERSHOOT := 0.90
const SHORT_REBOUND := 1.08
const LEG_POP := 1.14
const LEG_UNDERSHOOT := 0.88

## Independent controls. 1.0 is the animal's natural proportion.
var body_length := 1.0
var leg_target := 1.0 ## What the trait asked for, before per-leg normalisation.
var leg_lengths: Array[float] = [] ## Actual per-leg factors, animated one at a time.

## How high the body rides. Driven by leg_target, but animated on its own schedule so
## the body can float up before the legs come down.
var lift := 0.0
var bounce := 0.0 ## Transient settle bounce, added on top of lift.
var squash := Vector3.ONE

var _rig: CreatureRig = null
var _skeleton: Skeleton3D = null
var _def: AnimalDefinition = null
var _leg_reach: Array[float] = [] ## Rest length of each leg's telescoping section.
var _leg_vertical_reach: Array[float] = [] ## Downward response when translations extend.
var _ground_extensions: Array[float] = [] ## Final stance-only reach added per leg, world units.
var _mean_reach := 0.0
var _mean_vertical_reach := 0.0
var _body_tip := -1
var _tweens: Array[Tween] = []


func _init(rig: CreatureRig) -> void:
	_rig = rig
	_skeleton = rig.skeleton
	_def = rig.definition
	_cache_rest_metrics()


func _cache_rest_metrics() -> void:
	leg_lengths.clear()
	_leg_reach.clear()
	_leg_vertical_reach.clear()
	_ground_extensions.clear()
	_mean_reach = 0.0
	_mean_vertical_reach = 0.0
	if _skeleton == null or _def == null:
		return
	for leg in _def.legs:
		leg_lengths.append(1.0)
		_ground_extensions.append(0.0)
		var reach := 0.0
		var bones: PackedStringArray = leg["bones"]
		for bone in bones:
			var idx := _skeleton.find_bone(bone)
			if idx != -1:
				reach += _skeleton.get_bone_rest(idx).origin.length()
		# Measure the result of extending the COMPLETE configured chain. Measuring only from
		# the first listed bone to the foot omits that first bone's own translated offset,
		# even though apply() scales it too. That understated the front-leg response on deer,
		# horse and tiger, leaving their front hooves floating at full TALL.
		var vertical_reach := _measure_vertical_response(bones)
		var guarded: float = maxf(vertical_reach, reach * 0.05)
		_leg_reach.append(reach)
		_leg_vertical_reach.append(guarded)
		_mean_reach += reach
		_mean_vertical_reach += guarded
	_mean_reach /= float(maxi(_leg_reach.size(), 1))
	_mean_vertical_reach /= float(maxi(_leg_vertical_reach.size(), 1))
	if not _def.body_bones.is_empty():
		_body_tip = _skeleton.find_bone(_def.body_bones[_def.body_bones.size() - 1])


## Downward foot travel caused by adding one full factor to every configured segment.
## Each local rest offset is expressed in its parent's frame, so rotate it through that
## parent's global rest basis before summing. This is the exact foot-position derivative
## for scaling those translations, without temporarily posing an out-of-tree skeleton.
func _measure_vertical_response(bones: PackedStringArray) -> float:
	var response := Vector3.ZERO
	for bone in bones:
		var idx := _skeleton.find_bone(bone)
		if idx == -1:
			continue
		var parent := _skeleton.get_bone_parent(idx)
		var parent_basis := _skeleton.get_bone_global_rest(parent).basis \
			if parent != -1 else Basis.IDENTITY
		response += parent_basis * _skeleton.get_bone_rest(idx).origin
	return absf(response.y)


# --- Applying the pose --------------------------------------------------------

## Snap straight to a state, with no animation. Used when a creature is built already
## transformed: zoo residents, the naming-screen ghost, the finished creature.
func set_state(body_value: float, leg_value: float) -> void:
	kill_tweens()
	_ground_extensions.fill(0.0)
	body_length = body_value
	leg_target = leg_value
	for i in leg_lengths.size():
		leg_lengths[i] = _leg_factor(i, leg_value)
	lift = target_lift(leg_value)
	bounce = 0.0
	squash = Vector3.ONE
	apply()


func reset() -> void:
	set_state(1.0, 1.0)


## Where the body has to ride so the feet land on the floor rather than through it.
func target_lift(leg_value: float) -> float:
	return (leg_value - 1.0) * _mean_vertical_reach * _rig.normal_scale()


## Leg chains differ in both raw length and angle. Tall needs equal *vertical* reach,
## not equal 3D segment length: a diagonal front chain otherwise grows less downward
## than a rear chain and leaves a tiger's front pair visibly shorter. Neutral remains
## exactly authored because target == 1 returns a factor of one for every leg.
func _leg_factor(index: int, target: float) -> float:
	if index >= _leg_vertical_reach.size() or _leg_vertical_reach[index] <= 0.0001:
		return target
	return 1.0 + (target - 1.0) * _mean_vertical_reach / _leg_vertical_reach[index]


## Push the bones into position. Cheap enough to run every frame of a tween: a few bone
## writes and a little arithmetic.
func apply() -> void:
	if _skeleton == null or _def == null:
		return

	for bone in _def.body_bones:
		var idx := _skeleton.find_bone(bone)
		if idx == -1:
			continue
		_skeleton.set_bone_pose_position(idx, _skeleton.get_bone_rest(idx).origin * body_length)
		_rig.mark_posed(idx)

	for i in _def.legs.size():
		var factor := leg_scale(i)
		for bone in _def.legs[i]["bones"] as PackedStringArray:
			var idx := _skeleton.find_bone(bone)
			if idx == -1:
				continue
			_skeleton.set_bone_pose_position(idx, _skeleton.get_bone_rest(idx).origin * factor)
			_rig.mark_posed(idx)

	_recentre()


## Final stance correction. Targets are extra vertical reach in normalised world units,
## calculated from explicit sole markers after every other adjective and idle pose.
## The same target is supplied to both members of a pair by CreatureRig.
func update_ground_extensions(targets: Array[float], delta: float, instant := false) -> bool:
	var limited := false
	var changed := false
	for i in _ground_extensions.size():
		var requested: float = maxf(targets[i], 0.0) if i < targets.size() else 0.0
		var max_extension: float = _leg_reach[i] * _rig.normal_scale() * 0.18
		if requested > max_extension:
			requested = max_extension
			limited = true
		var previous := _ground_extensions[i]
		_ground_extensions[i] = requested if instant else move_toward(previous, requested,
			_def.stand_height * 4.0 * delta)
		changed = changed or not is_equal_approx(previous, _ground_extensions[i])
	if changed:
		apply()
	return limited


func clear_ground_extensions(instant := true, delta := 0.0) -> void:
	var targets: Array[float] = []
	targets.resize(_ground_extensions.size())
	targets.fill(0.0)
	update_ground_extensions(targets, delta, instant)


func ground_extension(index: int) -> float:
	return _ground_extensions[index] if index >= 0 and index < _ground_extensions.size() else 0.0


## How far leg `index` is currently stretched, counting both the adjective and any ground
## extension. The single source of truth for it: apply() poses the bones by this, and the
## sole marker has to travel by exactly the same amount or the two disagree about where the
## foot is.
func leg_scale(index: int) -> float:
	var factor: float = leg_lengths[index] if index < leg_lengths.size() else 1.0
	if index < _ground_extensions.size() and index < _leg_vertical_reach.size():
		var response := _leg_vertical_reach[index] * _rig.normal_scale()
		if response > 0.0001:
			factor += _ground_extensions[index] / response
	return factor


func leg_vertical_response(index: int) -> float:
	return _leg_vertical_reach[index] if index >= 0 and index < _leg_vertical_reach.size() else 0.0


## A newly selected animal already sits on its authored sole plane. Do not recompute
## that neutral pose from approximate bone contact markers, or it visibly pops upward
## on the first frame after selection. Grounding is only needed once leg proportions
## actually change (or while a prior stance correction is being released).
func requires_grounding() -> bool:
	if _def != null and _def.ground_neutral:
		return true
	if not is_equal_approx(leg_target, 1.0):
		return true
	for extension in _ground_extensions:
		if absf(extension) > 0.00001:
			return true
	return false


## A lengthened body grows forward from the hips, which would walk the animal off its
## platform. Sliding the model back by half the gain keeps it centred.
func _recentre() -> void:
	if _body_tip == -1:
		return
	var delta := _skeleton.get_bone_global_pose(_body_tip).origin - _skeleton.get_bone_global_rest(_body_tip).origin
	_rig.set_model_offset(Vector3(-delta.x * 0.5, 0.0, -delta.z * 0.5) * _rig.normal_scale())


# --- Animated transitions -----------------------------------------------------

## Animate into a state. Falls back to snapping if the rig is not in the tree (the
## selftest builds rigs outside it), so callers never have to care.
func animate_to(body_value: float, leg_value: float) -> void:
	if _rig == null or not _rig.is_inside_tree():
		set_state(body_value, leg_value)
		return
	kill_tweens()
	if not is_equal_approx(body_value, body_length):
		_animate_body(body_value)
	if not leg_lengths.is_empty() and not is_equal_approx(leg_value, leg_target):
		_ground_extensions.fill(0.0)
		_animate_legs(leg_value)


## LONG pulls like taffy: ease in slowly, accelerate, overshoot the target, rebound
## past it, then settle. SHORT is an accordion: squeeze past the target and spring back.
func _animate_body(target: float) -> void:
	var from := body_length
	var stretching := target > from
	var tween := _rig.create_tween()
	_tweens.append(tween)

	if stretching:
		Audio.play("stretch")
		tween.tween_method(_set_body, from, lerpf(from, target, 0.28), 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_method(_set_body, lerpf(from, target, 0.28), lerpf(from, target, 0.92), 0.70) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_method(_set_body, lerpf(from, target, 0.92), target * LONG_OVERSHOOT, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_body, target * LONG_OVERSHOOT, target * LONG_REBOUND, 0.30) \
			.set_trans(Tween.TRANS_SINE)
		tween.tween_method(_set_body, target * LONG_REBOUND, target, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_squash_flourish(1.6, Vector3(0.93, 0.94, 0.93))
	else:
		Audio.play("squish")
		tween.tween_method(_set_body, from, target * SHORT_OVERSHOOT, 0.80) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_method(_set_body, target * SHORT_OVERSHOOT, target * SHORT_REBOUND, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_body, target * SHORT_REBOUND, target, 0.30) \
			.set_trans(Tween.TRANS_SINE)
		# Squashing shortens the body, so it bulges outward at maximum compression.
		_squash_flourish(0.8, Vector3(1.14, 1.10, 1.14))


## TALL: the body floats up to its final height, then each leg drops to the ground in
## turn, so the animal hangs there putting its landing gear down one leg at a time.
## SHORT: the legs pull in first and the body drops onto them with a thump.
func _animate_legs(target: float) -> void:
	var extending := target > leg_target
	leg_target = target
	var count := leg_lengths.size()
	var final_lift := target_lift(target)
	var stagger_start := 0.0

	if extending:
		Audio.play("charge", 1.25)
		var float_tween := _rig.create_tween()
		_tweens.append(float_tween)
		float_tween.tween_method(_set_lift, lift, final_lift * 1.04, FLOAT_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		float_tween.tween_method(_set_lift, final_lift * 1.04, final_lift, 0.28) \
			.set_trans(Tween.TRANS_SINE)
		# Legs start reaching down while the body is still settling, so it flows.
		stagger_start = FLOAT_TIME * 0.8

	for i in count:
		var from: float = leg_lengths[i]
		var to: float = _leg_factor(i, target)
		var overshoot: float = to * (LEG_POP if extending else LEG_UNDERSHOOT)
		var tween := _rig.create_tween()
		_tweens.append(tween)
		tween.tween_interval(stagger_start + i * LEG_STAGGER)
		tween.tween_callback(func() -> void: Audio.play("pop" if extending else "zip", 1.0 + i * 0.06))
		tween.tween_method(_set_leg.bind(i), from, overshoot, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_leg.bind(i), overshoot, to, 0.18) \
			.set_trans(Tween.TRANS_SINE)

	var settle := stagger_start + (count - 1) * LEG_STAGGER + 0.38

	if not extending:
		# Every leg is stubby now, so the body drops onto them and squashes on impact.
		var drop := _rig.create_tween()
		_tweens.append(drop)
		drop.tween_interval(settle)
		drop.tween_callback(func() -> void: Audio.play("thud", 0.85))
		drop.tween_method(_set_lift, lift, final_lift, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_squash_at(settle + 0.18, Vector3(1.12, 0.86, 1.12))
	else:
		# Landing on all fours kicks a little rebound through the body.
		var kick := _rig.create_tween()
		_tweens.append(kick)
		kick.tween_interval(settle)
		kick.tween_method(_set_bounce, 0.0, _mean_reach * _rig.normal_scale() * 0.18, 0.14) \
			.set_trans(Tween.TRANS_SINE)
		kick.tween_method(_set_bounce, _mean_reach * _rig.normal_scale() * 0.18, 0.0, 0.36) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A brief squash-and-stretch pass that always returns to neutral, so it never affects
## the persistent transformed state.
func _squash_flourish(peak_at: float, peak: Vector3) -> void:
	_squash_at(peak_at * 0.55, peak, peak_at * 0.30, peak_at * 0.55)


func _squash_at(delay: float, peak: Vector3, rise := 0.14, fall := 0.40) -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_method(_set_squash, Vector3.ONE, peak, rise).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_set_squash, peak, Vector3.ONE, fall) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func kill_tweens() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


func is_animating() -> bool:
	for t in _tweens:
		if t != null and t.is_valid() and t.is_running():
			return true
	return false


# --- Tween setters ------------------------------------------------------------

func _set_body(value: float) -> void:
	body_length = value
	apply()


func _set_leg(value: float, index: int) -> void:
	if index < leg_lengths.size():
		leg_lengths[index] = value
		apply()


func _set_lift(value: float) -> void:
	lift = value


func _set_bounce(value: float) -> void:
	bounce = value


func _set_squash(value: Vector3) -> void:
	squash = value
