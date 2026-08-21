extends Node3D
## Name the creature, then send it to the zoo.
##
## The before-animal is shown here as a translucent ghost beside the finished creature.
## The spec put a scene change between the two, which hides exactly the comparison the
## grammar is about; standing them side by side while the three sentences are on screen
## is the moment the lesson lands.

## Closer to the centre line than they used to be. How square a platform looks depends on
## how far off-axis it sits, so pulling the pair in is what buys the camera room to come
## nearer without tipping either of them back onto its side.
const BEFORE_POS := Vector3(-3.7, 0.0, 0.0)
const NOW_POS := Vector3(3.7, 0.0, 0.0)
const FRONT_FACING := PI
const CAPTION_WIDTH := 300.0

var _candidates := PackedStringArray()
var _entry: LineEdit = null
var _before_root: Node3D = null
var _creature_root: Node3D = null
var _camera: Camera3D = null
var _before_caption: Label = null
var _now_caption: Label = null


func _ready() -> void:
	if Game.current == null:
		Game.set_phase(Game.Phase.ANIMAL_SELECTION)
		return
	_candidates = NameGenerator.candidates(Game.current)
	if Game.current.generated_name.is_empty() and not _candidates.is_empty():
		Game.current.generated_name = _candidates[0]
	_build_stage()
	_build_ui()
	Audio.play("reveal")


## Deliberately not turning. This screen exists to be compared, and a pair of turntables
## means the two are almost never facing the same way at the same moment - whenever one
## reads clearly the other is showing its back. They hold the front-facing pose instead.
func _process(_delta: float) -> void:
	pass


func _build_stage() -> void:
	# Contrast here is a lighting problem, not a background one. The colour of the creature
	# is itself one of the things the student chose - white and black are both on the
	# palette - so no single backdrop can be relied on to sit behind it. A rim light does
	# not care: it draws a bright edge along whatever shape is in front of it, which
	# separates a white creature from a pale background and a black one from a dark one.
	add_child(StageKit.environment(Color("#050b14"), Color("#0f2138"), 0.42))
	add_child(StageKit.key_light(Vector3(-50, -30, 0), 1.35))
	add_child(StageKit.fill_light(Color("#fff2d0"), Vector3(2.4, 3.4, 3.4), 1.1, 14.0))
	# One behind and above each platform, aimed through the creature towards the camera.
	for spot in [BEFORE_POS, NOW_POS]:
		add_child(StageKit.fill_light(Color("#cfe6ff"),
			spot + Vector3(0.0, 2.6, -3.0), 4.5, 9.0))
	add_child(_comparison_floor())

	var before_platform := StageKit.platform(1.55, Color("#1b2438"), UiKit.MUTED)
	before_platform.position = BEFORE_POS
	add_child(before_platform)

	var now_platform := StageKit.platform(1.9, Color("#243352"), UiKit.GOLD)
	now_platform.position = NOW_POS
	add_child(now_platform)

	var ghost := CreatureFactory.build_before_ghost(Game.current)
	var creature := CreatureFactory.build_fantasy(Game.current)

	# One shared scale for both, so a creature that grew to five times its old size still
	# fits on screen *and* still looks five times bigger than the ghost beside it. Fitting
	# them independently would throw away the comparison this screen exists to make.
	var tallest := 1.0
	if ghost != null:
		tallest = maxf(tallest, ghost.crown_height())
	if creature != null:
		tallest = maxf(tallest, creature.crown_height())
	var fit := clampf(2.9 / tallest, 0.3, 1.25)

	if ghost != null:
		ghost.position = BEFORE_POS + Vector3(0, 0.28, 0)
		ghost.rotation.y = FRONT_FACING
		ghost.scale = Vector3.ONE * fit
		_before_root = ghost
		add_child(ghost)

	_creature_root = Node3D.new()
	_creature_root.position = NOW_POS + Vector3(0, 0.3, 0)
	_creature_root.rotation.y = FRONT_FACING
	_creature_root.scale = Vector3.ONE * fit
	add_child(_creature_root)
	if creature != null:
		_creature_root.add_child(creature)

	# Far back with a narrow lens rather than close with a wide one. The two platforms sit
	# either side of the centre line, and a wide lens from close up sees each of them from
	# its own side - the further apart they are, the more each one is turned away. Pulling
	# back and narrowing flattens that out until both read as square to the camera. Level,
	# too: aiming at a point below the lens tipped the whole comparison forward.
	_camera = StageKit.camera(Vector3(0.0, 1.30, 13.2), Vector3(0.0, 1.30, 0.0), 34.0)
	add_child(_camera)


func _comparison_floor() -> Node3D:
	var root := Node3D.new()
	root.name = "ComparisonFloor"
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	# The rear edge sits just behind the display platforms, producing a straight horizon
	# through their centre line instead of the curved edge of a circular stage disc.
	mesh.size = Vector3(30.0, 0.2, 23.0)
	floor.mesh = mesh
	floor.position = Vector3(0.0, -0.1, 11.15)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#080d16")
	material.roughness = 0.95
	floor.material_override = material
	root.add_child(floor)
	return root


func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	root.add_child(_build_captions())

	var panel := UiKit.panel(Color(0.05, 0.09, 0.15, 0.94), 18, 2, UiKit.PANEL_HI)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -292
	panel.offset_bottom = -28
	root.add_child(panel)

	var column := UiKit.vbox(8)
	panel.add_child(column)
	column.add_child(UiKit.title("できあがり！", UiKit.H3, UiKit.MUTED))

	_entry = UiKit.line_edit("クリーチャーの名前")
	_entry.text = Game.current.generated_name
	_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_entry.add_theme_font_size_override("font_size", UiKit.H2)
	_entry.custom_minimum_size = Vector2(0, 62)
	column.add_child(_entry)

	var send := UiKit.button("どうぶつえんへ送る", UiKit.H3, true)
	send.custom_minimum_size = Vector2(360, 54)
	send.pressed.connect(_send_to_zoo)
	column.add_child(send)

	var start_again := UiKit.button("もう一度つくる", UiKit.H3)
	start_again.custom_minimum_size = Vector2(360, 54)
	start_again.pressed.connect(_start_again)
	column.add_child(start_again)


## Labels the two platforms with the before/now comparison.
func _build_captions() -> Control:
	var bar := Control.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 22
	bar.offset_bottom = 70
	bar.offset_left = 0
	bar.offset_right = 0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_before_caption = UiKit.title("へんしん前", UiKit.H2, UiKit.MUTED)
	bar.add_child(_before_caption)

	_now_caption = UiKit.title("へんしん後", UiKit.H2, UiKit.GOLD)
	bar.add_child(_now_caption)
	_position_captions()
	get_viewport().size_changed.connect(_position_captions)
	return bar


## The platforms are perspective-projected, so their centres are not exactly at the
## quarter points of the viewport. Project their real 3D origins and use those pixels as
## the caption centres; repeat after a resize so the alignment remains exact.
func _position_captions() -> void:
	if _camera == null or _before_caption == null or _now_caption == null:
		return
	_position_caption(_before_caption, _camera.unproject_position(BEFORE_POS).x)
	_position_caption(_now_caption, _camera.unproject_position(NOW_POS).x)


func _position_caption(caption: Label, center_x: float) -> void:
	caption.offset_left = center_x - CAPTION_WIDTH * 0.5
	caption.offset_right = center_x + CAPTION_WIDTH * 0.5
	caption.offset_top = 0.0
	caption.offset_bottom = 48.0


func _current_name() -> String:
	var typed := _entry.text.strip_edges()
	return typed if not typed.is_empty() else Game.current.generated_name


func _send_to_zoo() -> void:
	Audio.play("success")
	Game.finish_creature(_current_name())
	Game.set_phase(Game.Phase.ZOO)


func _start_again() -> void:
	Audio.play("click")
	Game.abandon_creature()
	Game.set_phase(Game.Phase.ANIMAL_SELECTION)
