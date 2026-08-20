extends Node3D
## The reward. Every creature here was built out of three sentences a student spoke, and
## clicking one shows exactly which three - the zoo is the score.

## Half-extents of the yard, X by Z. A rectangle rather than a disc: a zoo enclosure is a
## fenced field, and a round one with no corners read as an arena.
const YARD := Vector2(13.0, 9.0)
const FENCE_MARGIN := 1.0 ## How far the fence stands outside the grass.
const POST_SPACING := 1.7
const RAIL_HEIGHTS := [0.42, 0.82]
const ORBIT_SPEED := 0.006
const ZOOM_LIMITS := Vector2(9.0, 26.0)

var _camera: Camera3D = null
var _yaw := 0.4
var _pitch := 0.42
var _distance := 24.0 ## Far enough back that the whole rectangle is in frame at rest.
var _dragging := false
var _info: PanelContainer = null
var _info_body: VBoxContainer = null
var _creatures: Node3D = null


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
	var title := UiKit.label("Matsubara Zoo", UiKit.H1, UiKit.GOLD)
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
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_info.offset_left = 28
	_info.offset_right = 520
	_info.offset_top = -300
	_info.offset_bottom = -28
	_info.visible = false
	root.add_child(_info)

	_info_body = UiKit.vbox(8)
	_info.add_child(_info_body)


func _populate() -> void:
	for child in _creatures.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	for state in Game.zoo:
		# Scattered across the rectangle rather than around a circle, so the residents use
		# the corners instead of leaving them conspicuously empty.
		var spot := Vector3(rng.randf_range(-1.0, 1.0) * (YARD.x - 1.5), 0.0,
			rng.randf_range(-1.0, 1.0) * (YARD.y - 1.5))
		var brain := CreatureBrain.create(state, spot)
		brain.clicked.connect(_show_info)
		_creatures.add_child(brain)

	if Game.zoo.is_empty():
		_show_empty_hint()


func _show_empty_hint() -> void:
	_info_body_reset()
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
	var def := Content.animal(state.animal_id)
	Audio.play("pop")
	_info_body_reset()

	var head := UiKit.hbox(8)
	head.add_child(UiKit.label(state.display_name(), UiKit.H2, UiKit.GOLD))
	head.add_child(UiKit.expander())
	var close := UiKit.button("x", UiKit.SMALL)
	close.pressed.connect(func() -> void: _info.visible = false)
	head.add_child(close)
	_info_body.add_child(head)

	_info_body.add_child(UiKit.label(
		"Made from a %s" % (def.display_name.to_lower() if def != null else state.animal_id),
		UiKit.BODY, UiKit.MUTED))
	_info_body.add_child(UiKit.spacer(4))

	for sentence in state.sentences():
		var chip := UiKit.panel(Color("#101a2b"), 10)
		chip.add_child(UiKit.label(sentence, UiKit.BODY, UiKit.TEXT))
		_info_body.add_child(chip)

	if state.needed_help():
		_info_body.add_child(UiKit.label("A teacher accepted one of these.", UiKit.SMALL, UiKit.GOLD))

	if Tts.available():
		var listen := UiKit.button("Listen to my sentences", UiKit.SMALL)
		listen.pressed.connect(func() -> void: Tts.speak(" ".join(state.sentences())))
		_info_body.add_child(listen)

	_info.visible = true


# --- Camera ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
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


func _update_camera() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	_camera.position = offset + Vector3(0, 0.8, 0)
	_camera.look_at(Vector3(0, 1.2, 0), Vector3.UP)
