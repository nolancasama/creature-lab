extends Node3D
## Pick the animal that will be programmed. One live 3D preview rather than ten small
## ones: it costs a tenth as much to render and it shows the child what they are choosing.

const PREVIEW_SPIN := 0.45

var _selected := ""
var _preview: CreatureRig = null
var _preview_root: Node3D = null
var _buttons := {}
var _name_label: Label = null


func _ready() -> void:
	_build_stage()
	_build_ui()
	var ids := Content.animal_ids()
	if not ids.is_empty():
		_select(ids[0])


func _process(delta: float) -> void:
	if _preview_root != null:
		_preview_root.rotation.y += delta * PREVIEW_SPIN


func _build_stage() -> void:
	add_child(StageKit.environment(Color("#16243c"), Color("#2b4a72"), 0.5))
	add_child(StageKit.key_light())
	add_child(StageKit.fill_light(UiKit.ACCENT, Vector3(-3.0, 3.2, 3.2), 2.4, 14.0))
	add_child(StageKit.ground(9.0, Color("#141d2c")))

	var platform := StageKit.platform(1.9, Color("#22304a"), UiKit.ACCENT)
	add_child(platform)

	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_root.position.y = 0.28
	add_child(_preview_root)

	add_child(StageKit.camera(Vector3(3.4, 2.6, 6.4), Vector3(0.9, 1.2, 0.0), 48.0))


func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var panel := UiKit.panel(Color(0.06, 0.1, 0.16, 0.92), 18, 2, UiKit.PANEL_HI)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -680
	panel.offset_right = -32
	panel.offset_top = 40
	panel.offset_bottom = -40
	root.add_child(panel)

	var column := UiKit.vbox(14)
	panel.add_child(column)
	column.add_child(UiKit.label("Choose an animal", UiKit.H2, UiKit.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)

	for def in Content.animals:
		var b := UiKit.button(def.display_name, UiKit.H3)
		b.custom_minimum_size = Vector2(196, 62)
		b.pressed.connect(_select.bind(def.id))
		grid.add_child(b)
		_buttons[def.id] = b

	column.add_child(UiKit.expander())

	_name_label = UiKit.label("", UiKit.H3, UiKit.GOLD)
	column.add_child(_name_label)

	var row := UiKit.hbox(10)
	column.add_child(row)

	var back := UiKit.button("Back", UiKit.H3)
	back.custom_minimum_size = Vector2(140, 58)
	back.pressed.connect(func() -> void:
		Audio.play("click")
		Game.set_phase(Game.Phase.TITLE))
	row.add_child(back)

	row.add_child(UiKit.expander())

	var go := UiKit.button("Take to the Lab  →", UiKit.H3, true)
	go.custom_minimum_size = Vector2(300, 58)
	go.pressed.connect(_confirm)
	row.add_child(go)


func _select(animal_id: String) -> void:
	if animal_id == _selected:
		return
	_selected = animal_id
	Audio.play("select")

	if _preview != null:
		_preview.queue_free()
	_preview = CreatureFactory.build_plain(animal_id)
	if _preview != null:
		_preview_root.add_child(_preview)
	_preview_root.rotation.y = -0.7

	var def := Content.animal(animal_id)
	if def != null and _name_label != null:
		_name_label.text = def.display_name
	for id in _buttons:
		var b: Button = _buttons[id]
		UiKit.style_button(b, UiKit.ACCENT if id == animal_id else UiKit.PANEL_HI, id == animal_id)


func _confirm() -> void:
	if _selected.is_empty():
		return
	Audio.play("charge")
	Game.begin_creature(_selected)
	Game.set_phase(Game.Phase.CREATURE_LAB)
