extends Node3D
## The reward. Every creature here was built out of three sentences a student spoke, and
## clicking one shows exactly which three - the zoo is the score.

const YARD_RADIUS := 10.0
const ORBIT_SPEED := 0.006
const ZOOM_LIMITS := Vector2(9.0, 26.0)

var _camera: Camera3D = null
var _yaw := 0.4
var _pitch := 0.42
var _distance := 17.0
var _dragging := false
var _info: PanelContainer = null
var _info_body: VBoxContainer = null
var _header: Label = null
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
	add_child(StageKit.ground(YARD_RADIUS + 1.5, Color("#4b7a45")))

	# A low fence so the yard reads as an enclosure rather than an empty plain.
	for i in 40:
		var post := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.11
		mesh.height = 1.1
		post.mesh = mesh
		var angle := TAU * float(i) / 40.0
		post.position = Vector3(cos(angle), 0.55, sin(angle)) * Vector3(YARD_RADIUS + 1.0, 1.0, YARD_RADIUS + 1.0)
		post.position.y = 0.55
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#8a6a44")
		post.material_override = mat
		add_child(post)

	_creatures = Node3D.new()
	_creatures.name = "Creatures"
	add_child(_creatures)

	_camera = StageKit.camera(Vector3(0, 8, 17), Vector3.ZERO, 55.0)
	add_child(_camera)
	_update_camera()


func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var bar := UiKit.panel(Color(0.05, 0.09, 0.15, 0.86), 0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 62
	root.add_child(bar)

	var row := UiKit.hbox(14)
	bar.add_child(row)
	_header = UiKit.label("", UiKit.H3, UiKit.ACCENT)
	row.add_child(_header)
	row.add_child(UiKit.label("Drag to look around  -  scroll to zoom  -  click a creature", UiKit.SMALL, UiKit.MUTED))
	row.add_child(UiKit.expander())

	var again := UiKit.button("Make another  ->", UiKit.SMALL, true)
	again.pressed.connect(func() -> void:
		Audio.play("select")
		Game.set_phase(Game.Phase.ANIMAL_SELECTION))
	row.add_child(again)

	var settings := UiKit.button("Teacher", UiKit.SMALL)
	settings.pressed.connect(func() -> void: Game.open_settings())
	row.add_child(settings)

	var menu := UiKit.button("Menu", UiKit.SMALL)
	menu.pressed.connect(func() -> void: Game.set_phase(Game.Phase.TITLE))
	row.add_child(menu)

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
	_header.text = "MY ZOO  -  %d creature%s" % [Game.zoo.size(), "" if Game.zoo.size() == 1 else "s"]

	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	for state in Game.zoo:
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * (YARD_RADIUS - 1.5)
		var brain := CreatureBrain.create(state, Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))
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
