extends Node3D
## Name the creature, then send it to the zoo.
##
## The before-animal is shown here as a translucent ghost beside the finished creature.
## The spec put a scene change between the two, which hides exactly the comparison the
## grammar is about; standing them side by side while the three sentences are on screen
## is the moment the lesson lands.

const GHOST_POS := Vector3(-2.4, 0.0, 0.0)
const CREATURE_POS := Vector3(1.7, 0.0, 0.0)

var _candidates := PackedStringArray()
var _index := 0
var _entry: LineEdit = null
var _creature_root: Node3D = null


func _ready() -> void:
	if Game.current == null:
		Game.set_phase(Game.Phase.TITLE)
		return
	_candidates = NameGenerator.candidates(Game.current)
	if Game.current.generated_name.is_empty() and not _candidates.is_empty():
		Game.current.generated_name = _candidates[0]
	_build_stage()
	_build_ui()
	Audio.play("reveal")


func _process(delta: float) -> void:
	if _creature_root != null:
		_creature_root.rotation.y += delta * 0.35


func _build_stage() -> void:
	add_child(StageKit.environment(Color("#152238"), Color("#31527d"), 0.55))
	add_child(StageKit.key_light(Vector3(-50, -30, 0), 1.0))
	add_child(StageKit.fill_light(UiKit.GOLD, Vector3(2.4, 3.4, 3.4), 2.6, 14.0))
	add_child(StageKit.ground(11.0, Color("#111a2a")))

	var ghost_platform := StageKit.platform(1.5, Color("#1b2438"), UiKit.MUTED)
	ghost_platform.position = GHOST_POS
	add_child(ghost_platform)

	var creature_platform := StageKit.platform(1.9, Color("#243352"), UiKit.GOLD)
	creature_platform.position = CREATURE_POS
	add_child(creature_platform)

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
		ghost.position = GHOST_POS + Vector3(0, 0.28, 0)
		ghost.rotation.y = -0.7
		ghost.scale = Vector3.ONE * fit
		add_child(ghost)

	_creature_root = Node3D.new()
	_creature_root.position = CREATURE_POS + Vector3(0, 0.3, 0)
	_creature_root.scale = Vector3.ONE * fit
	add_child(_creature_root)
	if creature != null:
		_creature_root.add_child(creature)

	add_child(StageKit.camera(Vector3(-0.3, 3.5, 11.4), Vector3(-0.3, 0.8, 0.0), 50.0))


func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	root.add_child(_build_captions())

	var panel := UiKit.panel(Color(0.05, 0.09, 0.15, 0.94), 18, 2, UiKit.PANEL_HI)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = -300
	panel.offset_bottom = -28
	root.add_child(panel)

	var column := UiKit.vbox(10)
	panel.add_child(column)
	column.add_child(UiKit.title("You created…", UiKit.H3, UiKit.MUTED))

	_entry = UiKit.line_edit("Name your creature")
	_entry.text = Game.current.generated_name
	_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_entry.add_theme_font_size_override("font_size", UiKit.H2)
	_entry.custom_minimum_size = Vector2(0, 62)
	column.add_child(_entry)

	var sentences := UiKit.hbox(10)
	sentences.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(sentences)
	for sentence in Game.current.sentences():
		var chip := UiKit.panel(Color("#101a2b"), 10)
		chip.add_child(UiKit.label(sentence, UiKit.SMALL, UiKit.TEXT))
		sentences.add_child(chip)

	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	var another := UiKit.button("Another name", UiKit.H3)
	another.custom_minimum_size = Vector2(240, 54)
	another.pressed.connect(_next_name)
	row.add_child(another)

	if Tts.available():
		var listen := UiKit.button("Listen", UiKit.H3)
		listen.custom_minimum_size = Vector2(150, 54)
		listen.pressed.connect(func() -> void:
			Tts.speak("%s. %s" % [_current_name(), " ".join(Game.current.sentences())]))
		row.add_child(listen)

	var send := UiKit.button("Send to my Zoo  →", UiKit.H3, true)
	send.custom_minimum_size = Vector2(300, 54)
	send.pressed.connect(_send_to_zoo)
	row.add_child(send)


## Labels the two platforms, so the ghost is unmistakably the "It was" version.
func _build_captions() -> Control:
	var bar := UiKit.hbox(0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 22
	bar.offset_bottom = 70
	bar.offset_left = 60
	bar.offset_right = -60

	var was := UiKit.title("It was…", UiKit.H2, UiKit.MUTED)
	was.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(was)

	var now := UiKit.title("Now it is…", UiKit.H2, UiKit.GOLD)
	now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(now)
	return bar


func _current_name() -> String:
	var typed := _entry.text.strip_edges()
	return typed if not typed.is_empty() else Game.current.generated_name


func _next_name() -> void:
	if _candidates.is_empty():
		return
	Audio.play("click")
	_index = (_index + 1) % _candidates.size()
	Game.current.generated_name = _candidates[_index]
	_entry.text = _candidates[_index]


func _send_to_zoo() -> void:
	Audio.play("success")
	Game.finish_creature(_current_name())
	Game.set_phase(Game.Phase.ZOO)
