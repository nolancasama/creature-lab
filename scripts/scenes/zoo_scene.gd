extends Node3D
## The reward. Every creature here gets a quiet close-up when selected.

## Half-extents of the yard, X by Z. A rectangle rather than a disc: a zoo enclosure is a
## fenced field, and a round one with no corners read as an arena.
const YARD := Vector2(13.0, 9.0)
const FENCE_MARGIN := 1.0 ## How far the fence stands outside the grass.
const POST_SPACING := 1.7
const RAIL_HEIGHTS := [0.42, 0.82]
const ORBIT_SPEED := 0.006
const ZOOM_LIMITS := Vector2(9.0, 26.0)
const FOCUS_DISTANCE := 8.0
const YARD_CAMERA_TARGET := Vector3(0.0, 1.2, 0.0)
const TITLE_COLOR := Color("#17324d") ## Deep enough to stay legible against the pale sky.
const PINCH_ZOOM_SCALE := 0.018

var _camera: Camera3D = null
var _yaw := 0.4
var _pitch := 0.42
var _distance := 24.0 ## Far enough back that the whole rectangle is in frame at rest.
var _camera_target := YARD_CAMERA_TARGET
var _dragging := false
var _info: PanelContainer = null
var _info_body: VBoxContainer = null
var _creatures: Node3D = null
var _focused_brain: CreatureBrain = null
var _distance_before_focus := 24.0
var _touch_points := {}
var _pinching := false
var _pinch_distance := 0.0


func _ready() -> void:
	# Clicking a creature relies on Area3D picking, which the viewport does not do by
	# default.
	get_viewport().physics_object_picking = true
	_build_stage()
	_build_ui()
	_populate()
	Game.zoo_changed.connect(_populate)
	Audio.play_ambience(true)


func _build_stage() -> void:
	add_child(StageKit.environment(Color("#2c5a92"), Color("#8fc2d8"), 0.9))
	add_child(StageKit.key_light(Vector3(-45, -40, 0), 1.2))
	_build_grass()
	_build_fence()

	_creatures = Node3D.new()
	_creatures.name = "Creatures"
	add_child(_creatures)

	_camera = StageKit.camera(Vector3(0, 8, 17), Vector3.ZERO, 55.0)
	add_child(_camera)
	_update_camera()


## A rectangular field rather than StageKit's disc, which is built for the lab platform.
func _build_grass() -> void:
	var grass := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(YARD.x * 2.0 + FENCE_MARGIN * 2.4, 0.2, YARD.y * 2.0 + FENCE_MARGIN * 2.4)
	grass.mesh = mesh
	grass.position.y = -0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#4b7a45")
	mat.roughness = 0.95
	grass.material_override = mat
	add_child(grass)


## Posts with rails between them. Posts alone read as a row of sticks in a field; it is the
## horizontals that make it a fence.
func _build_fence() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#8a6a44")
	wood.roughness = 0.85
	var x: float = YARD.x + FENCE_MARGIN
	var z: float = YARD.y + FENCE_MARGIN
	var corners := [Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z), Vector3(-x, 0, z)]
	for i in corners.size():
		var from: Vector3 = corners[i]
		var to: Vector3 = corners[(i + 1) % corners.size()]
		_fence_run(from, to, wood)


func _fence_run(from: Vector3, to: Vector3, wood: StandardMaterial3D) -> void:
	var span := to - from
	var length := span.length()
	var count := maxi(int(round(length / POST_SPACING)), 1)
	# The last post of one run is the first of the next, so runs stop one short of their
	# end and the corners are not built twice.
	for i in count:
		var post := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.11
		mesh.height = 1.1
		post.mesh = mesh
		post.position = from + span * (float(i) / float(count))
		post.position.y = 0.55
		post.material_override = wood
		add_child(post)

	for height in RAIL_HEIGHTS:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(length, 0.09, 0.05)
		rail.mesh = rail_mesh
		rail.position = (from + to) * 0.5
		rail.position.y = float(height)
		rail.rotation.y = atan2(-span.z, span.x)
		rail.material_override = wood
		add_child(rail)


func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# No bar across the top. It was a strip of chrome carrying a count, a line of controls
	# and an instruction, sitting over the one thing the screen is for - the zoo itself.
	# The name and one button do the same work without covering the yard.
	var title := UiKit.label("Matsubara Zoo", UiKit.H1, TITLE_COLOR)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 26
	title.offset_bottom = 26 + UiKit.H1 + 8
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var again := UiKit.button("Start again", UiKit.BODY, true)
	again.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	again.custom_minimum_size = Vector2(180, 52)
	again.offset_left = -208
	again.offset_right = -28
	again.offset_top = 26
	again.offset_bottom = 78
	again.pressed.connect(func() -> void:
		Audio.play("select")
		Game.set_phase(Game.Phase.ANIMAL_SELECTION))
	root.add_child(again)

	_info = UiKit.panel(Color(0.05, 0.09, 0.15, 0.95), 16, 2, UiKit.GOLD)
	_info.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_info.offset_left = -230
	_info.offset_right = 230
	_info.offset_top = -150
	_info.offset_bottom = -28
	_info.visible = false
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_info)

	_info_body = UiKit.vbox(8)
	_info_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_info_body)


func _populate() -> void:
	for child in _creatures.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var occupied: Array[Dictionary] = []
	for state in Game.zoo:
		var radius := CreatureBrain.spacing_radius_for(state)
		var spot := _find_open_spot(rng, radius, occupied)
		occupied.append({"position": spot, "radius": radius})
		var brain := CreatureBrain.create(state, spot)
		brain.clicked.connect(_show_info)
		_creatures.add_child(brain)

	if Game.zoo.is_empty():
		_show_empty_hint()


func _find_open_spot(rng: RandomNumberGenerator, radius: float,
		occupied: Array[Dictionary]) -> Vector3:
	# Try many candidates so the initial frame is already separated; the brains' live
	# separation pass remains as a safeguard once they start walking.
	var x_limit := maxf(YARD.x - radius - 0.7, 1.0)
	var z_limit := maxf(YARD.y - radius - 0.7, 1.0)
	for _attempt in 80:
		var candidate := Vector3(rng.randf_range(-x_limit, x_limit), 0.0,
			rng.randf_range(-z_limit, z_limit))
		var clear := true
		for entry in occupied:
			var other: Vector3 = entry["position"]
			var required: float = radius + float(entry["radius"]) + CreatureBrain.NEIGHBOUR_GAP
			if candidate.distance_to(other) < required:
				clear = false
				break
		if clear:
			return candidate
	# At high zoo capacity, return the best-effort candidate and let live steering finish the
	# separation instead of stacking every late resident at one fixed fallback point.
	return Vector3(rng.randf_range(-x_limit, x_limit), 0.0,
		rng.randf_range(-z_limit, z_limit))


func _show_empty_hint() -> void:
	_info_body_reset()
	_info.offset_left = -230
	_info.offset_right = 230
	_info.offset_top = -150
	_info_body.add_child(UiKit.label("Your zoo is empty", UiKit.H3, UiKit.GOLD))
	_info_body.add_child(UiKit.label(
		"Make a creature and it will live here for the rest of the lesson.",
		UiKit.BODY, UiKit.MUTED))
	_info.visible = true


func _info_body_reset() -> void:
	for child in _info_body.get_children():
		child.queue_free()


func _show_info(brain: CreatureBrain) -> void:
	var state := brain.state_data
	if _focused_brain == brain:
		return
	Audio.play("pop")
	if _focused_brain == null:
		_distance_before_focus = _distance
	else:
		_focused_brain.dismiss_focus()
	_focused_brain = brain
	_camera_target = brain.global_position + Vector3(0.0, 1.0, 0.0)
	_distance = FOCUS_DISTANCE
	_update_camera()
	brain.focus_on(_camera)
	_info_body_reset()

	var head := Control.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiKit.label(state.display_name(), UiKit.H2, UiKit.GOLD)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	# Fit the panel to the name while reserving a clean corner for the close button.
	var head_width := maxf(name_label.get_combined_minimum_size().x + 52.0, 96.0)
	head.custom_minimum_size = Vector2(head_width, 44)
	var box_width := head_width + 28.0 ## The panel's horizontal content margins.
	_info.offset_left = -box_width * 0.5
	_info.offset_right = box_width * 0.5
	_info.offset_top = -96
	var close := UiKit.button("×", UiKit.SMALL)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -44
	close.offset_right = 0
	close.offset_top = 0
	close.offset_bottom = 44
	close.custom_minimum_size = Vector2(44, 44)
	close.pressed.connect(_dismiss_info)
	head.add_child(close)
	_info_body.add_child(head)
	_info.visible = true


func _dismiss_info() -> void:
	Audio.play("click")
	if _focused_brain != null:
		_focused_brain.dismiss_focus()
	_focused_brain = null
	_camera_target = YARD_CAMERA_TARGET
	_distance = _distance_before_focus
	_update_camera()
	_info.visible = false


# --- Camera ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _focused_brain != null:
		if event is InputEventScreenTouch and event.pressed:
			if _creature_at(event.position) != _focused_brain:
				_dismiss_info()
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			if _creature_at(event.position) != _focused_brain:
				_dismiss_info()
			return
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pick_creature_at(event.position)
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pick_creature_at(button.position)
			_dragging = button.pressed
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = clampf(_distance - 1.4, ZOOM_LIMITS.x, ZOOM_LIMITS.y)
			_update_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = clampf(_distance + 1.4, ZOOM_LIMITS.x, ZOOM_LIMITS.y)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		_yaw -= motion.relative.x * ORBIT_SPEED
		_pitch = clampf(_pitch - motion.relative.y * ORBIT_SPEED, 0.12, 1.25)
		_update_camera()


func _pick_creature_at(screen_position: Vector2) -> void:
	var creature := _creature_at(screen_position)
	if creature != null:
		_show_info(creature)


func _creature_at(screen_position: Vector2) -> CreatureBrain:
	if _camera == null or _creatures == null:
		return null
	var origin := _camera.project_ray_origin(screen_position)
	var endpoint := origin + _camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit.get("collider")
	while node != null and node != _creatures:
		if node is CreatureBrain:
			return node as CreatureBrain
		node = node.get_parent()
	return null


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 2:
			_pinching = true
			_pinch_distance = _touch_distance()
	else:
		_touch_points.erase(event.index)
		if _touch_points.size() < 2:
			_pinching = false
			_pinch_distance = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _pinching or not _touch_points.has(event.index):
		return
	_touch_points[event.index] = event.position
	var distance := _touch_distance()
	if _pinch_distance > 0.0 and distance > 0.0:
		_distance = clampf(_distance - (distance - _pinch_distance) * PINCH_ZOOM_SCALE,
			ZOOM_LIMITS.x, ZOOM_LIMITS.y)
		_update_camera()
	_pinch_distance = distance


func _touch_distance() -> float:
	if _touch_points.size() < 2:
		return 0.0
	var ids := _touch_points.keys()
	var first: Vector2 = _touch_points[ids[0]]
	var second: Vector2 = _touch_points[ids[1]]
	return first.distance_to(second)


func _update_camera() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	var target_shift := _camera_target - YARD_CAMERA_TARGET
	_camera.position = offset + Vector3(0, 0.8, 0) + target_shift
	_camera.look_at(_camera_target, Vector3.UP)
