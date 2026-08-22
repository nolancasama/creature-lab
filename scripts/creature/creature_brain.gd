class_name CreatureBrain
extends Node3D
## Zoo behaviour: idle, walk, observe, do something a trait suggests, greet a neighbour.
##
## Deliberately not a NavigationAgent3D. The zoo is a flat, obstacle-free yard, so a
## navmesh would cost bake time and per-frame agent updates to solve a problem that does
## not exist. Steering lives behind this one class, so swapping in NavigationAgent3D
## later touches nothing else. No hunger, no breeding, no combat - just visible life.

signal clicked(brain: CreatureBrain)

enum State { IDLE, WALK, RUN, OBSERVE, TRAIT_ACTION, INTERACT }

## How each species divides its time, roughly. Not rolled per frame: a state is chosen, then
## committed to for a duration or until its destination is reached. The whole point is that
## the yard should read as calm and alive rather than as seven animals pacing in circles.
const TENDENCY := {
	"dog": {"idle": 0.30, "walk": 0.55, "run": 0.15},
	"cat": {"idle": 0.45, "walk": 0.45, "run": 0.10},
	"deer": {"idle": 0.30, "walk": 0.55, "run": 0.15},
	"horse": {"idle": 0.25, "walk": 0.60, "run": 0.15},
	"chicken": {"idle": 0.30, "walk": 0.60, "run": 0.10},
	"penguin": {"idle": 0.40, "walk": 0.55, "run": 0.05},
	"tiger": {"idle": 0.55, "walk": 0.40, "run": 0.05},
}
const DEFAULT_TENDENCY := {"idle": 0.35, "walk": 0.55, "run": 0.10}
## Species that settle rather than fidget. Their idles run half again as long.
const LINGERERS := ["tiger", "cat", "penguin"]
## Species happy to keep walking once they have started.
const RAMBLERS := ["horse", "deer", "chicken", "dog"]
const IDLE_TIME := Vector2(2.0, 7.0)
const LONG_IDLE_TIME := Vector2(8.0, 12.0)
const LONG_IDLE_CHANCE := 0.22 ## Occasionally settle properly rather than pausing.
const WALK_TIME := Vector2(4.0, 10.0)
const RAMBLE_BONUS := 4.0 ## Extra seconds a rambler may keep walking for.
const RUN_TIME := Vector2(1.5, 4.0)
## After a run, no more running for this long. Without it a creature ping-pongs
## walk-run-walk-run, which reads as a glitch rather than as a burst of energy.
const RUN_COOLDOWN := Vector2(9.0, 18.0)
const RUN_SPEED := 2.4 ## Multiplier on walk_speed. The animator matches the clip to it.
## Runs end in a walk, not a stop. An animal that sprints and then freezes looks switched
## off; one that slows to a walk looks like it finished doing something.
const WALK_AFTER_RUN := 0.82

## Usable grass inside the rectangular fence (ZooScene.YARD minus its inner margin).
const YARD_HALF_EXTENTS := Vector2(17.0, 11.3)
const ARRIVE_DISTANCE := 0.35
const NEIGHBOUR_GAP := 0.32
const SEPARATION_RANGE := 1.35

var state_data: CreatureState = null
var rig: CreatureRig = null

var _state: State = State.IDLE
var _timer := 0.0
var _target := Vector3.ZERO
var _speed := 1.2
var _hover := 0.0
var _rng := RandomNumberGenerator.new()
var _action_word := ""
var _area: Area3D = null
var _focused := false
var _spacing_radius := 1.0
var _base_speed := 1.2 ## Before the run multiplier and this individual's own variation.
var _run_block := 0.0 ## Seconds until this creature may run again.
var _pace := 1.0 ## Per-creature timing variation, so two dogs never move in lockstep.


static func create(state: CreatureState, spawn: Vector3) -> CreatureBrain:
	var brain := CreatureBrain.new()
	brain.state_data = state
	brain.position = spawn
	return brain


## A conservative horizontal footprint used by both spawn placement and live steering. The
## actual meshes vary, so this uses the animal's stand height plus its SIZE trait rather than
## pretending every resident is a unit sphere.
static func spacing_radius_for(state: CreatureState) -> float:
	if state == null:
		return 1.0
	var def := Content.animal(state.animal_id)
	if def == null:
		return 1.0
	var size_scale := 1.0
	var pair := Content.pair_for_category("SIZE")
	var traits := state.after_traits()
	var word := str(traits.get("SIZE", ""))
	if pair != null and pair.has_word(word):
		size_scale = pair.value_for(word)
	var length_scale := 1.0
	var length_pair := Content.pair_for_category("LENGTH")
	var length_word := str(traits.get("LENGTH", ""))
	if length_pair != null and length_pair.has_word(length_word):
		length_scale = maxf(length_pair.value_for(length_word), 1.0)
	# Spawn placement has no rig yet, so include the two traits that enlarge the horizontal
	# silhouette. _ready() replaces this estimate with the model's measured footprint.
	return maxf(0.95, def.stand_height * 0.50 * size_scale
		* lerpf(1.0, length_scale, 0.62))


func _ready() -> void:
	_rng.seed = state_data.fingerprint() + int(position.x * 100.0)
	rig = CreatureFactory.build_fantasy(state_data)
	if rig == null:
		queue_free()
		return
	add_child(rig)

	# The authored idle, walk and run clips, which exist only out here. Everywhere else an
	# animal is a specimen being measured and stretched, and a breathing idle would move the
	# feet the stance solver is trying to place.
	rig.enable_authored_animation()

	var def := Content.animal(state_data.animal_id)
	# The animation sets the pace, not the other way round - see natural_speed(). Falls back
	# to the authored walk_speed for anything without clips.
	var clip_speed := rig.animator.natural_speed() if rig.animator != null else 0.0
	_base_speed = (clip_speed if clip_speed > 0.01 else def.walk_speed) * _trait_speed_scale()
	# Individual variation, so two dogs in the same yard never pace in step: each creature
	# gets its own slightly different sense of time and its own slightly different speed.
	# Seeded from the creature's fingerprint, so it is stable across a reload.
	_pace = _rng.randf_range(0.82, 1.22)
	_base_speed *= _rng.randf_range(0.9, 1.12)
	_speed = _base_speed
	# Stagger the first decision too. Without this every resident spawns into idle on the
	# same frame and the whole yard starts walking at once.
	_run_block = _rng.randf_range(0.0, RUN_COOLDOWN.x)
	_hover = def.hover
	_spacing_radius = spacing_radius_for(state_data)
	_spacing_radius = maxf(_spacing_radius, rig.horizontal_footprint_radius())
	position.y = _hover * 0.6
	rotation.y = _rng.randf_range(0.0, TAU)
	_action_word = _pick_action_word()
	_build_click_target(def)
	_enter(State.IDLE)


## Clicking a creature has to work on a body made of dozens of loose primitives, so one
## capsule stands in for all of them.
func _build_click_target(def: AnimalDefinition) -> void:
	_area = Area3D.new()
	_area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(0.6, def.stand_height * 0.35)
	capsule.height = maxf(1.2, def.stand_height)
	shape.shape = capsule
	shape.position.y = def.stand_height * 0.5
	_area.add_child(shape)
	add_child(_area)
	_area.input_event.connect(_on_area_input)


func _on_area_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	# Annotated, not inferred: `pressed` on a base InputEvent has no static type, so `:=`
	# cannot work out that these are booleans and the script fails to compile - which on
	# this screen means a grey zoo rather than an error anyone would see.
	var tapped: bool = event is InputEventScreenTouch and event.pressed
	var clicked_mouse: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if tapped or clicked_mouse:
		clicked.emit(self)


## Hold the resident still while the zoo camera presents it. The yaw is calculated after the
## camera has moved, so the animal faces the actual camera rather than the old yard view.
func focus_on(camera: Camera3D) -> void:
	_focused = true
	_state = State.IDLE
	_timer = INF
	if rig != null:
		rig.moving = false
	var direction := camera.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(-direction.x, -direction.z)


func dismiss_focus() -> void:
	_focused = false
	_enter(State.IDLE)


func _trait_speed_scale() -> float:
	var pair := Content.pair_for_category("SPEED")
	if pair == null:
		return 1.0
	var word := str(state_data.after_traits().get("SPEED", ""))
	return clampf(pair.value_for(word), 0.4, 2.0) if pair.has_word(word) else 1.0


## Something the creature can act out that names one of its own traits.
func _pick_action_word() -> String:
	var words := state_data.after_traits().values()
	for preferred in ["fast", "hot", "cold", "big", "small", "strong", "soft", "hard"]:
		if words.has(preferred):
			return preferred
	return str(words[0]) if not words.is_empty() else ""


func _physics_process(delta: float) -> void:
	if _focused:
		return
	_timer -= delta
	_run_block = maxf(_run_block - delta, 0.0)
	match _state:
		State.WALK, State.RUN:
			_walk(delta)
		State.OBSERVE:
			rotation.y += delta * 0.6
	if _timer <= 0.0:
		_choose_next()


func _walk(delta: float) -> void:
	var flat_target := Vector3(_target.x, position.y, _target.z)
	var to_target := flat_target - position
	if to_target.length() < ARRIVE_DISTANCE:
		# Arrived. Stand here and look at things for a while; do NOT immediately pick
		# somewhere else to be. A run that reaches its destination hands over to a walk
		# first, for the same reason it does when it times out.
		_enter(State.WALK if _state == State.RUN and _rng.randf() < WALK_AFTER_RUN \
			else State.IDLE)
		return
	var direction := to_target.normalized()
	var separation := _neighbour_separation()
	if separation.length_squared() > 0.0001:
		direction = (direction + separation * 1.8).normalized()
	# Godot's forward axis is -Z. Turn first, then move along that forward axis, so a
	# creature never slides toward a target while its body is still facing backwards.
	var wanted := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, wanted, clampf(delta * 4.0, 0.0, 1.0))
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	if forward.dot(direction) > 0.0:
		position += forward * _speed * delta
	_keep_inside_yard()
	position.y = _hover * (0.6 + sin(Time.get_ticks_msec() * 0.002) * 0.12)


## Pick what to do next, weighted by species and constrained by what just happened.
##
## Two rules shape this more than the weights do. A run may only follow a walk - an animal
## that bolts from standing looks startled, and nothing startles it here. And a run is
## followed by a walk almost always, so the burst tails off instead of stopping dead.
func _choose_next() -> void:
	if _state == State.RUN:
		_enter(State.WALK if _rng.randf() < WALK_AFTER_RUN else State.IDLE)
		return

	var weights: Dictionary = TENDENCY.get(_animal_id(), DEFAULT_TENDENCY)
	var idle_weight := float(weights.get("idle", 0.35))
	var walk_weight := float(weights.get("walk", 0.55))
	var run_weight := float(weights.get("run", 0.10))
	# Running is only reachable from a walk, and only once the last one has worn off.
	if _state != State.WALK or _run_block > 0.0:
		walk_weight += run_weight
		run_weight = 0.0

	var roll := _rng.randf() * (idle_weight + walk_weight + run_weight)
	if roll < run_weight:
		_enter(State.RUN)
		return
	roll -= run_weight
	if roll < walk_weight:
		_enter(State.WALK)
		return
	# The idle share, spent standing still - but not always doing nothing. Observing, a
	# trait flourish and greeting a neighbour are all things done from a standstill, so
	# they come out of this budget rather than competing with it.
	var flavour := _rng.randf()
	if flavour < 0.62:
		_enter(State.IDLE)
	elif flavour < 0.78:
		_enter(State.OBSERVE)
	elif flavour < 0.92:
		_enter(State.TRAIT_ACTION)
	else:
		_enter(State.INTERACT)


func _animal_id() -> String:
	return str(state_data.animal_id) if state_data != null else ""


func _enter(next: State) -> void:
	_state = next
	var travelling := next == State.WALK or next == State.RUN
	if rig != null:
		rig.moving = travelling
		rig.motion_state = "run" if next == State.RUN \
			else ("walk" if next == State.WALK else "idle")
	_speed = _base_speed * (RUN_SPEED if next == State.RUN else 1.0)
	match next:
		State.IDLE:
			# Occasionally settle properly instead of just pausing, and let the animals that
			# should look unhurried hold it longer.
			var span: Vector2 = LONG_IDLE_TIME if _rng.randf() < LONG_IDLE_CHANCE \
				else IDLE_TIME
			_timer = _rng.randf_range(span.x, span.y) * _pace
			if _animal_id() in LINGERERS:
				_timer *= 1.5
		State.WALK:
			# A destination is chosen once, here, and kept until it is reached. Picking a new
			# one mid-walk is what makes a creature wander aimlessly on the spot.
			_target = _reachable_point()
			var walk_span := WALK_TIME.y + (RAMBLE_BONUS if _animal_id() in RAMBLERS else 0.0)
			_timer = _rng.randf_range(WALK_TIME.x, walk_span) * _pace
		State.RUN:
			_timer = _rng.randf_range(RUN_TIME.x, RUN_TIME.y) * _pace
			_run_block = _rng.randf_range(RUN_COOLDOWN.x, RUN_COOLDOWN.y)
		State.OBSERVE:
			_timer = _rng.randf_range(1.5, 3.0)
		State.TRAIT_ACTION:
			_timer = 1.4
			_perform_trait_action()
		State.INTERACT:
			_timer = 2.0
			_greet_neighbour()


## Somewhere this animal can plausibly get to, not just anywhere in the yard.
##
## The yard is large and these walks are short and slow, so a destination chosen uniformly
## across the grass is one the creature will almost never reach - it walks for its allotted
## few seconds, stops a fifth of the way there, and the arrival behaviour never happens.
## Picking within reach of one walk means animals actually arrive somewhere and settle,
## which is the whole shape the behaviour brief asks for.
func _reachable_point() -> Vector3:
	var reach: float = _base_speed * WALK_TIME.y * _pace
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(reach * 0.35, reach)
	var wanted := position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	var x_limit := maxf(YARD_HALF_EXTENTS.x - _spacing_radius, 1.0)
	var z_limit := maxf(YARD_HALF_EXTENTS.y - _spacing_radius, 1.0)
	return Vector3(clampf(wanted.x, -x_limit, x_limit), position.y,
		clampf(wanted.z, -z_limit, z_limit))


func _random_point() -> Vector3:
	var x_limit := maxf(YARD_HALF_EXTENTS.x - _spacing_radius, 1.0)
	var z_limit := maxf(YARD_HALF_EXTENTS.y - _spacing_radius, 1.0)
	return Vector3(_rng.randf_range(-x_limit, x_limit), position.y,
		_rng.randf_range(-z_limit, z_limit))


func spacing_radius() -> float:
	return _spacing_radius


## Resolve the zoo as one system after every resident has moved. Pairwise corrections are
## split simultaneously (except around a focused animal), then repeated to settle chains.
## This avoids the order-dependent boundary jams caused by thirty independent solvers.
static func resolve_group_overlaps(parent: Node, passes := 8) -> float:
	if parent == null:
		return 0.0
	var residents: Array[CreatureBrain] = []
	for child in parent.get_children():
		if child is CreatureBrain:
			residents.append(child as CreatureBrain)
	for _pass in maxi(passes, 1):
		var moved := false
		for i in residents.size():
			for j in range(i + 1, residents.size()):
				var first := residents[i]
				var second := residents[j]
				var delta := Vector3(first.position.x - second.position.x, 0.0,
					first.position.z - second.position.z)
				var distance := delta.length()
				var required := first.spacing_radius() + second.spacing_radius() + NEIGHBOUR_GAP
				if distance >= required:
					continue
				var away := delta / distance if distance > 0.0001 \
					else first._overlap_direction(second)
				var correction := required - distance
				if first._focused:
					second.position -= away * correction
				elif second._focused:
					first.position += away * correction
				else:
					first.position += away * correction * 0.5
					second.position -= away * correction * 0.5
				first._keep_inside_yard()
				second._keep_inside_yard()
				moved = true
		if not moved:
			break
	var maximum_penetration := 0.0
	for i in residents.size():
		for j in range(i + 1, residents.size()):
			var first := residents[i]
			var second := residents[j]
			var distance := Vector2(first.position.x - second.position.x,
				first.position.z - second.position.z).length()
			maximum_penetration = maxf(maximum_penetration,
				first.spacing_radius() + second.spacing_radius() + NEIGHBOUR_GAP - distance)
	return maxf(maximum_penetration, 0.0)


func _neighbour_separation() -> Vector3:
	var result := Vector3.ZERO
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is CreatureBrain):
			continue
		var other := sibling as CreatureBrain
		var delta := Vector3(position.x - other.position.x, 0.0, position.z - other.position.z)
		var distance := delta.length()
		var required := _spacing_radius + other.spacing_radius() + NEIGHBOUR_GAP
		if distance < required * SEPARATION_RANGE:
			var away := delta / distance if distance > 0.0001 else _overlap_direction(other)
			result += away * clampf((required * SEPARATION_RANGE - distance) / required, 0.0, 1.0)
	return result


func _overlap_direction(other: CreatureBrain) -> Vector3:
	# Both directions for the same pair must be exact opposites. Otherwise two creatures
	# spawned at one coordinate can choose nearly the same escape direction and stay piled.
	var mine := int(get_instance_id())
	var theirs := int(other.get_instance_id())
	var low := mini(mine, theirs)
	var high := maxi(mine, theirs)
	var seed := low * 31 + high * 17
	var angle := fposmod(float(seed), 628.0) * 0.01
	var base := Vector3(cos(angle), 0.0, sin(angle)).normalized()
	return base if mine < theirs else -base


func _keep_inside_yard() -> void:
	var x_limit := maxf(YARD_HALF_EXTENTS.x - _spacing_radius, 1.0)
	var z_limit := maxf(YARD_HALF_EXTENTS.y - _spacing_radius, 1.0)
	position.x = clampf(position.x, -x_limit, x_limit)
	position.z = clampf(position.z, -z_limit, z_limit)


## A short, readable flourish tied to one of the creature's own "Now it is..." words.
func _perform_trait_action() -> void:
	if rig == null:
		return
	var tween := create_tween()
	match _action_word:
		"fast":
			var origin := position
			var dash_target := _safe_target(origin - global_transform.basis.z * 1.6)
			# Endpoint clearance is not enough: a straight tween can still pass through a
			# neighbour on its way there. Keep the visual burst but skip displacement when
			# the swept footprint is occupied.
			if not _path_is_clear(origin, dash_target):
				dash_target = origin
			var return_target := _safe_target(origin)
			tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tween.tween_property(self, "position", dash_target, 0.28)
			tween.tween_property(self, "position", return_target, 0.5)
			Fx.burst(self, Vector3(0, 0.4, 0.6), "motion", Color("#bfe9ff"), 0.4)
		"hot":
			Fx.burst(self, Vector3(0, 1.0, 0), "flame", TraitVisuals.HOT, 0.5)
			Fx.burst(self, Vector3(0, 1.0, 0), "embers", TraitVisuals.HOT, 0.7)
			tween.tween_property(rig, "scale", Vector3.ONE * 1.08, 0.18)
			tween.tween_property(rig, "scale", Vector3.ONE, 0.4)
		"cold":
			# A big visible breath and a hard shudder - the two things that read as
			# "freezing" rather than "blue".
			var face: Node3D = rig.sockets.get("face", rig) if rig != null else self
			Fx.burst(face, Vector3.ZERO, "breath", Color(1, 1, 1, 0.9), 0.09)
			tween.tween_property(rig, "rotation:z", 0.08, 0.08)
			tween.tween_property(rig, "rotation:z", -0.08, 0.12)
			tween.tween_property(rig, "rotation:z", 0.05, 0.08)
			tween.tween_property(rig, "rotation:z", 0.0, 0.1)
		"big", "strong":
			tween.tween_property(self, "position:y", position.y + 0.5, 0.22)
			tween.tween_property(self, "position:y", position.y, 0.3)
			tween.tween_callback(func() -> void: Fx.burst(self, Vector3.ZERO, "dust", Color("#cbbfa6"), 1.0))
		_:
			tween.tween_property(rig, "scale", Vector3(1.0, 0.88, 1.0), 0.2)
			tween.tween_property(rig, "scale", Vector3.ONE, 0.35)


func _safe_target(target: Vector3) -> Vector3:
	var safe := target
	for _pass in 3:
		for sibling in get_parent().get_children():
			if sibling == self or not (sibling is CreatureBrain):
				continue
			var other := sibling as CreatureBrain
			var delta := Vector3(safe.x - other.position.x, 0.0, safe.z - other.position.z)
			var distance := delta.length()
			var required := _spacing_radius + other.spacing_radius() + NEIGHBOUR_GAP
			if distance < required:
				var away := delta / distance if distance > 0.0001 else _overlap_direction(other)
				safe += away * (required - distance)
	return safe


func _path_is_clear(from: Vector3, to: Vector3) -> bool:
	if get_parent() == null:
		return true
	var start := Vector2(from.x, from.z)
	var finish := Vector2(to.x, to.z)
	var segment := finish - start
	var length_squared := segment.length_squared()
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is CreatureBrain):
			continue
		var other := sibling as CreatureBrain
		var point := Vector2(other.position.x, other.position.z)
		var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0) \
			if length_squared > 0.0001 else 0.0
		var closest := start + segment * t
		var required := _spacing_radius + other.spacing_radius() + NEIGHBOUR_GAP
		if closest.distance_to(point) < required:
			return false
	return true


## Turn to face the closest neighbour - cheap, but it makes the yard feel populated.
func _greet_neighbour() -> void:
	var closest: Node3D = null
	var best := 6.0
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is CreatureBrain):
			continue
		var other: Node3D = sibling
		var distance := position.distance_to(other.position)
		if distance < best:
			best = distance
			closest = other
	if closest == null:
		_enter(State.IDLE)
		return
	var direction := (closest.position - position).normalized()
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", atan2(-direction.x, -direction.z), 0.4)
