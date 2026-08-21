class_name CreatureBrain
extends Node3D
## Zoo behaviour: idle, walk, observe, do something a trait suggests, greet a neighbour.
##
## Deliberately not a NavigationAgent3D. The zoo is a flat, obstacle-free yard, so a
## navmesh would cost bake time and per-frame agent updates to solve a problem that does
## not exist. Steering lives behind this one class, so swapping in NavigationAgent3D
## later touches nothing else. No hunger, no breeding, no combat - just visible life.

signal clicked(brain: CreatureBrain)

enum State { IDLE, WALK, OBSERVE, TRAIT_ACTION, INTERACT }

const YARD_RADIUS := 9.0
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
	var word := str(state.after_traits().get("SIZE", ""))
	if pair != null and pair.has_word(word):
		size_scale = pair.value_for(word)
	return maxf(0.95, def.stand_height * 0.42 * size_scale)


func _ready() -> void:
	_rng.seed = state_data.fingerprint() + int(position.x * 100.0)
	rig = CreatureFactory.build_fantasy(state_data)
	if rig == null:
		queue_free()
		return
	add_child(rig)

	var def := Content.animal(state_data.animal_id)
	_speed = def.walk_speed * _trait_speed_scale()
	_hover = def.hover
	_spacing_radius = spacing_radius_for(state_data)
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
	_resolve_neighbour_overlap()
	_timer -= delta
	match _state:
		State.WALK:
			_walk(delta)
		State.OBSERVE:
			rotation.y += delta * 0.6
	if _timer <= 0.0:
		_choose_next()


func _walk(delta: float) -> void:
	var flat_target := Vector3(_target.x, position.y, _target.z)
	var to_target := flat_target - position
	if to_target.length() < ARRIVE_DISTANCE:
		_enter(State.IDLE)
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
	_resolve_neighbour_overlap()
	position.y = _hover * (0.6 + sin(Time.get_ticks_msec() * 0.002) * 0.12)


func _choose_next() -> void:
	var roll := _rng.randf()
	if roll < 0.42:
		_enter(State.WALK)
	elif roll < 0.6:
		_enter(State.OBSERVE)
	elif roll < 0.78:
		_enter(State.TRAIT_ACTION)
	elif roll < 0.88:
		_enter(State.INTERACT)
	else:
		_enter(State.IDLE)


func _enter(next: State) -> void:
	_state = next
	if rig != null:
		rig.moving = next == State.WALK
	match next:
		State.IDLE:
			_timer = _rng.randf_range(1.2, 3.4)
		State.WALK:
			_target = _random_point()
			_timer = _rng.randf_range(3.0, 6.5)
		State.OBSERVE:
			_timer = _rng.randf_range(1.5, 3.0)
		State.TRAIT_ACTION:
			_timer = 1.4
			_perform_trait_action()
		State.INTERACT:
			_timer = 2.0
			_greet_neighbour()


func _random_point() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * YARD_RADIUS
	return Vector3(cos(angle) * distance, position.y, sin(angle) * distance)


func spacing_radius() -> float:
	return _spacing_radius


## Push apart overlapping horizontal footprints. Both residents normally share the correction
## so they do not jitter; a focused resident is stationary, so a moving neighbor takes the
## whole correction instead.
func _resolve_neighbour_overlap() -> void:
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is CreatureBrain):
			continue
		var other := sibling as CreatureBrain
		var delta := Vector3(position.x - other.position.x, 0.0, position.z - other.position.z)
		var distance := delta.length()
		var required := _spacing_radius + other.spacing_radius() + NEIGHBOUR_GAP
		if distance >= required:
			continue
		var away := delta / distance if distance > 0.0001 else _overlap_direction(other)
		var share := 1.0 if other._focused else 0.5
		position += away * (required - distance) * share


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
	var seed := int(get_instance_id()) * 31 + int(other.get_instance_id())
	var angle := fposmod(float(seed), 628.0) * 0.01
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()


## A short, readable flourish tied to one of the creature's own "Now it is..." words.
func _perform_trait_action() -> void:
	if rig == null:
		return
	var tween := create_tween()
	match _action_word:
		"fast":
			var origin := position
			var dash_target := _safe_target(origin - global_transform.basis.z * 1.6)
			var return_target := _safe_target(origin)
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
