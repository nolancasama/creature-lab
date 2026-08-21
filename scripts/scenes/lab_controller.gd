extends Node3D
## The transformation chamber screen. By the time the player arrives here, all three
## "It was..." sentences are already recorded - on the previous screen, alongside the
## animal itself. There is nothing left to type or say: the animal enters carrying the
## combined "It was..." state, and the chamber executes one "Now it is..." instruction per
## sentence.

var stage: LabStage = null

var _banner: Label = null
var _flash: ColorRect = null
var _top_bar: Control = null
var _director: TransformationDirector = null
var _transformed := false


func _ready() -> void:
	stage = LabStage.new()
	add_child(stage)
	_build_ui()

	if Game.current != null:
		stage.set_rig(CreatureFactory.build_lab_animal(Game.current))
		stage.apply_before_view(Game.take_transformation_handoff())

	stage.array.flash_requested.connect(_flash_screen)
	_director = TransformationDirector.new(stage, _banner)
	Audio.play_ambience(true)
	Game.phase_changed.connect(_on_phase_changed)
	Game.debug_action.connect(_on_debug_action)

	if Game.phase == Game.Phase.TRANSFORMATION:
		_run_transformation()
	elif Game.phase == Game.Phase.CREATURE_LAB:
		Game.set_phase(Game.Phase.TRANSFORMATION)


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_top_bar = _build_top_bar()
	# The seamless handoff opens on a clean copy of the final Before frame. Cinematic
	# controls return only after the machine has begun entering that frame.
	_top_bar.visible = Game.phase != Game.Phase.CREATURE_LAB
	root.add_child(_top_bar)

	_banner = UiKit.label("D N A   C O M P L E T E", UiKit.H1, UiKit.ACCENT)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 150
	_banner.offset_bottom = 220
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	root.add_child(_banner)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)


func _build_top_bar() -> Control:
	var bar := UiKit.panel(Color(0.05, 0.09, 0.15, 0.9), 0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 62

	var row := UiKit.hbox(14)
	bar.add_child(row)

	var def: AnimalDefinition = null
	if Game.current != null:
		def = Content.animal(Game.current.animal_id)
	row.add_child(UiKit.label("CREATURE LAB", UiKit.H3, UiKit.ACCENT))
	row.add_child(UiKit.label("-", UiKit.H3, UiKit.MUTED))
	row.add_child(UiKit.label(def.display_name if def != null else "-", UiKit.H3, UiKit.TEXT))
	row.add_child(UiKit.expander())

	var skip := UiKit.button("Skip", UiKit.SMALL)
	skip.pressed.connect(func() -> void:
		if _director != null:
			_director.request_skip())
	row.add_child(skip)

	var quit := UiKit.button("Menu", UiKit.SMALL)
	quit.pressed.connect(func() -> void: Game.set_phase(Game.Phase.ANIMAL_SELECTION))
	row.add_child(quit)

	return bar


# --- Transformation --------------------------------------------------------------

func _on_phase_changed(next: int, _previous: int) -> void:
	if next == Game.Phase.TRANSFORMATION:
		_run_transformation()


func _on_debug_action(action: String) -> void:
	if action == "skip_transform" and _director != null:
		_director.request_skip()


## The sequence itself lives in TransformationDirector; this only decides when it runs
## and what happens after.
func _run_transformation() -> void:
	if _transformed or Game.current == null or _director == null:
		return
	_transformed = true
	_show_cinematic_controls_delayed()
	await _director.run(Game.current)
	# Leaving the lab mid-sequence is legal; only advance if we are still the live scene.
	if is_inside_tree() and Game.phase == Game.Phase.TRANSFORMATION:
		Game.set_phase(Game.Phase.NAMING)


func _show_cinematic_controls_delayed() -> void:
	if _top_bar == null or _top_bar.visible:
		return
	await get_tree().create_timer(1.9).timeout
	if not is_inside_tree() or _top_bar == null:
		return
	_top_bar.visible = true
	_top_bar.modulate.a = 0.0
	create_tween().tween_property(_top_bar, "modulate:a", 1.0, 0.25)


func _flash_screen(strength: float) -> void:
	_flash.color = Color(1, 1, 1, clampf(strength, 0.0, 1.0))
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.8)
