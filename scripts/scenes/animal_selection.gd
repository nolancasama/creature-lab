extends Node3D
## Pick an animal, then record its three sentences - all without ever leaving this
## screen. Picking and speaking are one continuous action, not two different places to
## be: the animal rotates while it is being previewed, then holds still while the
## player records its sentences.
##
## Two local UI sub-states, not global FSM phases (the FSM only sees one
## Phase.ANIMAL_SELECTION for all of it):
##   PICKING   - grid of animal buttons, live rotating preview, a confirm button.
##   RECORDING - animal and platform are centred; the descriptor carousel and Say It swap
##               inside one fixed console beneath them.

const PREVIEW_SPIN := 0.18 ## Slow enough that the animal remains readable as a profile.
const RECORDING_FACING := -PI * 0.5 ## Godot forward (-Z) turned toward screen-right.
const CONFIRM_TURN_SPEED := 8.0 ## Radians per second: quick, but still a visible transition.
const CONFIRM_TURN_MIN := 0.10
const CONFIRM_TURN_MAX := 0.38 ## Formerly as long as 0.9s while the reaction had begun.
const DRAG_TURN_SPEED := 0.012
const SUCCESS_PAUSE := 1.1
const PRE_TRANSFORM_PAUSE := 0.28
const UI_EXIT_TIME := 0.72

const PLATFORM_POS := Vector3(-0.5, 0.0, 0.6)

## A long lens, further back. Anything off the optical axis shears under perspective, and
## the platform has to sit off-axis to be centred in the gap beside the panel - the disc
## came out visibly tilted at the original 48 degrees. Shear scales with tan(fov/2), so
## backing off to 22 degrees leaves about 44% of it while keeping the animal the same size
## on screen: distance and fov are traded against each other, not chosen independently.
const CAMERA_FOV := 22.0
const CAMERA_POS := Vector3(1.791, 4.271, 14.888)
## Shared picker/Before aim: leaves a stable console region below without shrinking the animal.
const RECORDING_CAMERA_AIM := Vector3(-0.5, 0.22, 0.0)
const CAMERA_MOVE_TIME := 0.55 ## Long enough to read as a move, short enough not to wait.

const PANEL_RIGHT := -32
const HUD_TOP := 24 ## Top edge of the floating buttons, above the panel on both sub-states.
const PROGRESS_FONT := UiKit.SMALL * 3 ## Readable from the back of a classroom.
const HUD_BUTTON := 78 ## 50% taller than the former 52px back control.
const HUD_BACK_WIDTH := 138 ## Room for the chevron and the new Back label.
const GEAR_BUTTON_SIZE := 70 ## 33% smaller than the former 104px settings gear.
const GEAR_ICON := preload("res://ui/gear.svg")
const HUD_GAP := 24 ## Visible gap between the HUD row and the panel below it.
## Top edge for a HUD_BUTTON-sized control so its centre line matches the gear's. This is
## derived rather than typed so the two stay aligned when either control changes size.
const HUD_BUTTON_TOP := HUD_TOP + (GEAR_BUTTON_SIZE - HUD_BUTTON) / 2
const PANEL_TOP := HUD_TOP + GEAR_BUTTON_SIZE + HUD_GAP ## The centred back button still
                                                        ## clears this panel edge.
const PANEL_BOTTOM := -24 ## Tighter than the top margin: the height lost to the HUD row
                          ## above comes back here, so the Word Lab still shows every card.
## The centred present-tense panel. Tall enough on its own that SpeechPanel's internal
## centring expanders (see its _build()) already have real slack to work with here without
## any extra tuning.
const PRESENT_SIZE := Vector2(720, 360)
const CONSOLE_SIZE := Vector2(760, 300) ## Same footprint for words, colours and speech.
const CONSOLE_BOTTOM_MARGIN := 10
const SAY_IT_WIDTH := 620

## Keep the full adjective instruction inside a fixed, symmetric box.  The former 420 px
## width only fit the old one-word "Before" label; the longer instruction then expanded
## the VBox toward the right and no longer shared the platform's centreline.
const PROGRESS_WIDTH := 760
const PROGRESS_HEIGHT := 112 ## Heading, seven lesson dots and the one-time drag hint.
const APPEARANCE_HEADING := "へんしん前の見た目をえらぼう"
const NOW_COLOUR_HEADING := "今の色をえらぼう"

const CAMERA_SHIFT := 0.0 ## The picker has no side panel; the animal owns the screen centre.
const ANIMAL_CARD_SIZE := Vector2(112, 78)
const ANIMAL_CARD_GAP := 8
const ANIMAL_ARROW_GAP := 24
const ANIMAL_CAROUSEL_WIDTH := ANIMAL_CARD_SIZE.x * 5.0 + ANIMAL_CARD_GAP * 4.0
const ANIMAL_EDGE_FADE_WIDTH := ANIMAL_CARD_SIZE.x * 0.33
const SELECT_BUTTON_SIZE := Vector2(280, 58)

enum Mode { PICKING, RECORDING, PRESENT, PRE_TRANSFORMATION }
enum ColourSpeechStage { NONE, PAST, PRESENT }

var _mode: Mode = Mode.PICKING

# Stage
var _preview_root: Node3D = null
var _rig: CreatureRig = null
var _platform: Node3D = null
var _camera: Camera3D = null
var _camera_aim := RECORDING_CAMERA_AIM ## Shared by picker and Before screen.
var _camera_shift := CAMERA_SHIFT

# Picking UI
var _picking_panel: Control = null
var _animal_cards: Array[Button] = []
var _animal_carousel_host: Control = null
var _animal_carousel_track: HBoxContainer = null
var _animal_fade_shader: Shader = null
var _selected := ""
var _animal_carousel_center := "" ## Moves only with chevrons, never when a card is tapped.
var _rig_animal := "" ## Which animal the live rig was built for.

# Recording UI
var _root: Control = null
var _progress: Label = null
var _progress_group: Control = null
var _lesson_progress: HBoxContainer = null
var _drag_hint: Label = null
var _word_lab: DescriptorCarousel = null
var _speech: SpeechPanel = null
var _console: Control = null
var _colour_preview := "" ## Temporary live Before colour; never written to CreatureState.

var _pending := {}
var _attempts := 0
var _busy := false
var _dragging_view := false
var _colour_speech_stage := ColourSpeechStage.NONE
var _choosing_now_colour := false
var _colour_past_accepted := false
var _colour_past_assisted := false
var _pre_transforming := false
var _confirmation_serial := 0 ## Cancels a pending confirm if browsing changes the animal.
var _confirming_selection := false ## Stops the turntable while the chosen animal responds.
var _facing_tween: Tween = null

# Present-tense pass (Settings.SAY_SPLIT)
var _present_index := 0


func _ready() -> void:
	# This screen is quiet - no chamber hum until the player actually reaches the
	# chamber. Title's looping ambience would otherwise keep playing underneath it.
	Audio.play_ambience(false)

	_build_stage()
	_build_root()
	_build_picking_panel()

	var ids := Content.animal_ids()
	if Game.current == null and not ids.is_empty():
		_preview(ids[0])

	Speech.heard.connect(_on_heard)
	Game.debug_action.connect(_on_debug_action)

	# Re-entering with a creature already begun - a debug jump, or returning from
	# Teacher Settings mid-round - skips straight to recording with progress intact.
	if Game.current != null:
		_enter_recording()


func _exit_tree() -> void:
	Speech.stop()
	Audio.stop_animal_call()


func _process(delta: float) -> void:
	if _preview_root != null and _mode == Mode.PICKING and not _confirming_selection:
		_preview_root.rotation.y += delta * PREVIEW_SPIN


## During sentence recording, the player can inspect the still creature without
## restarting its automatic turntable rotation.
func _unhandled_input(event: InputEvent) -> void:
	if _mode != Mode.RECORDING or _preview_root == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_view = event.pressed
		return
	if event is InputEventMouseMotion and _dragging_view:
		_preview_root.rotation.y -= event.relative.x * DRAG_TURN_SPEED
		if _drag_hint != null:
			_drag_hint.visible = false
		get_viewport().set_input_as_handled()


# --- Stage ---------------------------------------------------------------------

func _build_stage() -> void:
	# The platform and directly lit animal are the subject; a mid-blue sky and gray floor
	# competed with both. Lights stay unchanged so only the surrounding stage falls back.
	add_child(StageKit.environment(Color("#09111f"), Color("#152a45"), 0.5))
	add_child(StageKit.key_light())
	add_child(StageKit.fill_light(Color("#cfe6ff"), Vector3(-3.0, 3.2, 3.2), 1.1, 14.0))
	add_child(StageKit.ground(9.0, Color("#080d16")))

	_platform = StageKit.platform(1.8, Color("#22304a"), UiKit.ACCENT)
	_platform.position = PLATFORM_POS
	add_child(_platform)

	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_root.position = PLATFORM_POS + Vector3(0, 0.28, 0)
	_preview_root.rotation.y = -1.0 ## Starting pose for the very first animal shown. Picking
	## a different one later must not repeat this - see _preview(), which deliberately
	## leaves rotation alone so the turntable keeps spinning through a switch instead of
	## snapping back to this angle every time.
	add_child(_preview_root)

	_camera = StageKit.camera(CAMERA_POS, RECORDING_CAMERA_AIM, CAMERA_FOV)
	add_child(_camera)
	_lens_shift(_camera, CAMERA_SHIFT)


## Both picker and recorder use the optical centre for the animal/platform group. The
## world objects never move, so confirming a choice cannot introduce a geometry jump.
func _set_recording_composition(recording: bool, animate := false) -> void:
	if _camera == null:
		return
	var target_aim := RECORDING_CAMERA_AIM
	var target_shift := 0.0 if recording else CAMERA_SHIFT
	if not animate or not is_inside_tree():
		_compose(target_aim, target_shift)
		return
	# Picking an animal used to cut straight to the recording framing. Moving instead keeps
	# the animal the student just chose continuously in view, so it reads as the lab
	# settling on their pick rather than as a different screen appearing.
	var from_aim := _camera_aim
	var from_shift := _camera_shift
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
			_compose(from_aim.lerp(target_aim, t), lerpf(from_shift, target_shift, t)),
		0.0, 1.0, CAMERA_MOVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Both halves of the framing move together: the aim, and how far the lens is shifted to
## leave room for the picking panel. Driven by one factor so they cannot disagree part way.
func _compose(aim: Vector3, shift: float) -> void:
	_camera_aim = aim
	_camera_shift = shift
	_camera.set_perspective(CAMERA_FOV, _camera.near, _camera.far)
	if not is_zero_approx(shift):
		_lens_shift(_camera, shift)
	_camera.look_at(aim)


## Shifts the rendered image sideways by a number of screen pixels, by offsetting the
## camera's frustum - the lens moves, the camera does not. Moving the camera itself
## (h_offset) changes the direction the animal is seen from, so it stopped reading as a
## profile and started looking turned away; a frustum offset keeps the framing identical
## and only slides where it lands on screen.
func _lens_shift(cam: Camera3D, pixels: float) -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var near_height := 2.0 * cam.near * tan(deg_to_rad(cam.fov) * 0.5)
	var near_width := near_height * view.x / view.y
	cam.set_frustum(near_height, Vector2(pixels / view.x * near_width, 0.0), cam.near, cam.far)


## The clause the student is currently being asked to produce. Split mode asks for the
## past card by card and gathers the present tense afterwards, so the answer depends on
## the sub-state as much as on the setting.
func _clause() -> int:
	if _colour_speech_stage == ColourSpeechStage.PAST:
		return GrammarValidator.CLAUSE_PAST
	if _colour_speech_stage == ColourSpeechStage.PRESENT:
		return GrammarValidator.CLAUSE_PRESENT
	if _mode == Mode.PRESENT:
		return GrammarValidator.CLAUSE_PRESENT
	return GrammarValidator.CLAUSE_PAST if Settings.past_only() else GrammarValidator.CLAUSE_BOTH


func _build_root() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)


# --- Picking sub-state -----------------------------------------------------------

func _build_picking_panel() -> void:
	# No menu wall: this full-screen, transparent owner only positions controls around the
	# live animal. The platform and creature remain the largest objects on the screen.
	var picker := Control.new()
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(picker)
	_picking_panel = picker
	var heading_group := UiKit.vbox(6)
	heading_group.anchor_left = 0.5
	heading_group.anchor_right = 0.5
	heading_group.offset_left = -360
	heading_group.offset_right = 360
	heading_group.offset_top = 24
	heading_group.offset_bottom = 24 + PROGRESS_HEIGHT
	picker.add_child(heading_group)
	var heading := UiKit.label("どうぶつをえらぼう", PROGRESS_FONT, UiKit.GOLD)
	heading.name = "AnimalSelectionHeading"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_group.add_child(heading)
	_lesson_progress = UiKit.lesson_progress(0, 0)
	heading_group.add_child(_lesson_progress)

	# Exact footprint used by the adjective carousel on the Before screen. Five English
	# names stay readable at their normal card size; browsing merely changes which five
	# data-backed animals occupy the window.
	var selection_console := Control.new()
	selection_console.name = "AnimalSelectionConsole"
	selection_console.anchor_left = 0.5
	selection_console.anchor_right = 0.5
	selection_console.anchor_top = 1.0
	selection_console.anchor_bottom = 1.0
	selection_console.offset_left = -CONSOLE_SIZE.x * 0.5
	selection_console.offset_right = CONSOLE_SIZE.x * 0.5
	selection_console.offset_top = -(CONSOLE_SIZE.y + CONSOLE_BOTTOM_MARGIN)
	selection_console.offset_bottom = -CONSOLE_BOTTOM_MARGIN
	picker.add_child(selection_console)

	var column := UiKit.vbox(26)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	selection_console.add_child(column)
	var carousel := UiKit.hbox(0)
	carousel.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(carousel)
	carousel.add_child(_animal_carousel_arrow("<", -1))
	carousel.add_child(UiKit.spacer(ANIMAL_ARROW_GAP))
	_animal_carousel_host = Control.new()
	_animal_carousel_host.name = "AnimalCarouselViewport"
	_animal_carousel_host.custom_minimum_size = Vector2(
		ANIMAL_CAROUSEL_WIDTH, ANIMAL_CARD_SIZE.y)
	_animal_carousel_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_animal_carousel_host.clip_contents = true
	carousel.add_child(_animal_carousel_host)
	_animal_carousel_track = UiKit.hbox(ANIMAL_CARD_GAP)
	_animal_carousel_track.name = "AnimalCarouselCards"
	_animal_carousel_track.custom_minimum_size = Vector2(
		ANIMAL_CAROUSEL_WIDTH, ANIMAL_CARD_SIZE.y)
	_animal_carousel_host.add_child(_animal_carousel_track)
	for slot in 5:
		var card := _animal_name_card()
		_animal_carousel_track.add_child(card)
		_animal_cards.append(card)
		_apply_animal_edge_fade(card, slot)
	carousel.add_child(UiKit.spacer(ANIMAL_ARROW_GAP))
	carousel.add_child(_animal_carousel_arrow(">", 1))

	var choose := UiKit.button("このどうぶつにする", UiKit.H3, true)
	UiKit.style_primary(choose)
	choose.name = "SelectAnimal"
	choose.custom_minimum_size = SELECT_BUTTON_SIZE
	choose.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose.pressed.connect(_confirm)
	column.add_child(choose)

	_add_gear_button()
	_add_zoo_button()


## A way back into the zoo without playing a whole round first.
##
## Only appears once there is something in it. On a fresh install the zoo is an empty field,
## and a button that leads a six-year-old to an empty field is a dead end that makes the
## game look broken - so it stays hidden until the first creature has been sent there, at
## which point it turns up on its own and explains itself.
##
## Deliberately NOT beside the gear. The gear is the teacher's control and it opens a modal
## a young student cannot easily get out of; putting a button they ARE meant to press right
## next to it invites exactly the mis-tap that strands them in Teacher Settings. The
## opposite corner is empty, mirrors the gear, and keeps a hand's width between the two.
func _add_zoo_button() -> void:
	if Game.zoo.is_empty():
		return
	var zoo := UiKit.button("どうぶつえん", UiKit.BODY)
	zoo.name = "OpenZoo"
	zoo.custom_minimum_size = Vector2(0, GEAR_BUTTON_SIZE)
	zoo.focus_mode = Control.FOCUS_NONE
	# The navigation palette, which exists for exactly this. Not CTA orange: the picker
	# already has one orange button and it is the one that starts the lesson, so a second
	# would compete with it and a child would tap whichever was nearer. Not OK green either
	# - green already means "already used" on the adjective cards, and that meaning is
	# carrying instructional weight.
	UiKit.style_navigation(zoo)
	zoo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	zoo.offset_left = -PANEL_RIGHT ## The gear's margin, mirrored.
	zoo.offset_top = HUD_TOP
	zoo.offset_bottom = HUD_TOP + GEAR_BUTTON_SIZE
	zoo.offset_right = zoo.offset_left + 210
	zoo.pressed.connect(func() -> void:
		Audio.play("click")
		Game.set_phase(Game.Phase.ZOO))
	_root.add_child(zoo)


func _browse_animal(direction: int) -> void:
	if _confirming_selection:
		return ## See _confirm(): the flourish is part of committing, not a chance to browse.
	var ids := Content.animal_ids()
	if ids.is_empty():
		return
	var index := ids.find(_animal_carousel_center)
	if index < 0:
		index = maxi(0, ids.find(_selected))
	_animal_carousel_center = ids[wrapi(index + direction, 0, ids.size())]
	_preview(_animal_carousel_center)
	# _preview() intentionally returns early when the centred animal was already selected,
	# but the chevron must still be allowed to reposition the carousel.
	_refresh_animal_cards()


func _animal_carousel_arrow(glyph: String, direction: int) -> Button:
	var arrow := UiKit.button(glyph, 38)
	# Named so the harness can press the real control rather than a caption: "<" and ">"
	# also appear on the adjective carousel.
	arrow.name = "PreviousAnimal" if direction < 0 else "NextAnimal"
	arrow.custom_minimum_size = Vector2(55, 55)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_navigation(arrow)
	arrow.pressed.connect(_browse_animal.bind(direction))
	return arrow


func _animal_name_card() -> Button:
	var card := Button.new()
	card.custom_minimum_size = ANIMAL_CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_font_size_override("font_size", UiKit.BODY)
	card.pressed.connect(func() -> void:
		if _confirming_selection:
			return ## As with the chevrons - see _confirm().
		var animal_id := str(card.get_meta("animal_id", ""))
		if not animal_id.is_empty():
			_preview(animal_id))
	var check_badge := PanelContainer.new()
	check_badge.name = "SelectedCheck"
	check_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	check_badge.offset_left = -32
	check_badge.offset_right = -6
	check_badge.offset_top = 6
	check_badge.offset_bottom = 32
	check_badge.add_theme_stylebox_override("panel",
		UiKit.stylebox(UiKit.ACCENT, 13, 2, UiKit.TEXT, 1))
	var check := UiKit.label("✓", UiKit.SMALL, UiKit.INK)
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check_badge.add_child(check)
	check_badge.visible = false
	card.add_child(check_badge)
	_style_animal_card(card, false)
	return card


## Use the same real-alpha edge dissolve as the adjective and colour carousels. The animal
## strip itself never moves when a card is selected, so each card's origin is fixed by its
## slot. The selected badge and its check glyph draw separately from the Button and need
## their own correctly offset material or they would remain floating at a faded edge.
func _apply_animal_edge_fade(card: Button, slot: int) -> void:
	var card_origin := float(slot) * (ANIMAL_CARD_SIZE.x + ANIMAL_CARD_GAP)
	card.material = _animal_edge_fade_material(card_origin)
	var badge := card.get_node_or_null("SelectedCheck") as Control
	if badge == null:
		return
	var badge_origin := card_origin + ANIMAL_CARD_SIZE.x + badge.offset_left
	badge.material = _animal_edge_fade_material(badge_origin)
	for child in badge.get_children():
		if child is CanvasItem:
			(child as CanvasItem).material = _animal_edge_fade_material(badge_origin)


func _animal_edge_fade_material(origin: float) -> ShaderMaterial:
	if _animal_fade_shader == null:
		_animal_fade_shader = Shader.new()
		_animal_fade_shader.code = DescriptorCarousel.EDGE_FADE_SHADER
	var material := ShaderMaterial.new()
	material.shader = _animal_fade_shader
	material.set_shader_parameter("viewport_width", ANIMAL_CAROUSEL_WIDTH)
	material.set_shader_parameter("fade_width", ANIMAL_EDGE_FADE_WIDTH)
	material.set_shader_parameter("card_origin", origin)
	return material


func _style_animal_card(card: Button, selected: bool) -> void:
	var face := Color("#173047") if selected else Color("#101a2b")
	var edge := UiKit.ACCENT if selected else UiKit.LINE
	var width := 3 if selected else 1
	card.add_theme_stylebox_override("normal", UiKit.stylebox(face, 12, width, edge, 5))
	card.add_theme_stylebox_override("hover",
		UiKit.stylebox(face.lightened(0.12), 12, maxi(width, 2), UiKit.ACCENT, 5))
	card.add_theme_stylebox_override("pressed",
		UiKit.stylebox(face.darkened(0.16), 12, maxi(width, 2), UiKit.ACCENT, 5))
	card.add_theme_stylebox_override("focus",
		UiKit.stylebox(face, 12, 3, UiKit.GOLD, 5))
	card.add_theme_color_override("font_color", UiKit.GOLD if selected else UiKit.TEXT)
	card.add_theme_color_override("font_hover_color", UiKit.GOLD if selected else UiKit.TEXT)
	var check_badge := card.get_node_or_null("SelectedCheck") as Control
	if check_badge != null:
		check_badge.visible = selected


func _refresh_animal_cards() -> void:
	var ids := Content.animal_ids()
	if ids.is_empty() or _animal_cards.is_empty():
		return
	var center_index := ids.find(_animal_carousel_center)
	if center_index < 0:
		center_index = maxi(0, ids.find(_selected))
	for slot in _animal_cards.size():
		var offset := slot - 2
		var animal_id := str(ids[wrapi(center_index + offset, 0, ids.size())])
		var def := Content.animal(animal_id)
		var card := _animal_cards[slot]
		card.visible = true
		var label := def.display_name if def != null else animal_id.capitalize()
		card.text = label
		card.set_meta("animal_id", animal_id)
		_style_animal_card(card, animal_id == _selected)


## Each sub-state owns the whole of _root, so entering either clears all of it instead of
## tracking individual pieces. The gear is built by both and would otherwise stack up one
## invisible copy per transition.
func _clear_overlays() -> void:
	for child in _root.get_children():
		child.queue_free()
	_picking_panel = null
	_word_lab = null
	_speech = null
	_console = null
	_progress = null
	_progress_group = null
	_lesson_progress = null
	_drag_hint = null
	_animal_cards.clear()


## Teacher Settings has to be reachable from both sub-states, and from the same corner in
## each - picking and recording are one screen, so a control that moved between them would
## read as a different screen.
##
## Both offsets are set explicitly: the preset derives them from the button's current size,
## so moving only one edge leaves a rect narrower than the button, which renders clipped
## off the screen edge.
func _add_gear_button() -> void:
	# A drawn gear, not the "⚙" character: the export bundles only Godot's default font,
	# which has no U+2699, and the web build has no system font to fall back on the way
	# the desktop editor silently did - so the glyph arrived as a tofu box of hex digits.
	# Same trap the pair separator hit; see the note in word_lab.gd.
	var gear := UiKit.icon_button("", GEAR_BUTTON_SIZE)
	gear.name = "SettingsGear"
	gear.icon = GEAR_ICON
	gear.expand_icon = true
	# The gear alone, with no plate behind it. icon_button's panel-coloured box is right for
	# the back arrow, which sits on flat 2D chrome, but this one sits over the lit 3D stage
	# and read as a floating tile there. Feedback moves onto the icon itself so it still
	# answers a hover and a press without a box to draw them on.
	for state in ["normal", "hover", "pressed", "disabled"]:
		gear.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	gear.add_theme_stylebox_override("focus",
		UiKit.stylebox(Color.TRANSPARENT, 12, 3, UiKit.GOLD, 2))
	gear.tooltip_text = "先生用設定"
	gear.add_theme_color_override("icon_normal_color", UiKit.TEXT)
	gear.add_theme_color_override("icon_hover_color", UiKit.ACCENT)
	gear.add_theme_color_override("icon_pressed_color", UiKit.ACCENT)
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_right = PANEL_RIGHT
	gear.offset_left = PANEL_RIGHT - GEAR_BUTTON_SIZE
	gear.offset_top = HUD_TOP
	gear.offset_bottom = HUD_TOP + GEAR_BUTTON_SIZE
	gear.pressed.connect(func() -> void: Game.open_settings())
	_root.add_child(gear)


func _preview(animal_id: String) -> void:
	if animal_id == _selected:
		return
	_confirmation_serial += 1
	_confirming_selection = false
	if _facing_tween != null and _facing_tween.is_valid():
		_facing_tween.kill()
	_facing_tween = null
	Audio.stop_animal_call()
	_selected = animal_id
	if _animal_carousel_center.is_empty():
		_animal_carousel_center = animal_id

	_build_rig(animal_id)
	# No rotation reset here: _preview_root is one persistent node the whole time the
	# picking grid is up, only the rig child underneath it gets swapped, so the turntable
	# is already exactly where it needs to be to continue uninterrupted.
	_refresh_animal_cards()


func _confirm() -> void:
	if _selected.is_empty() or _mode != Mode.PICKING:
		return
	# SELECT commits. The flourish that follows it - the turn, the animal's reaction - is
	# part of confirming, not a window to change your mind in, so browsing is refused while
	# it plays rather than quietly cancelling it.
	#
	# It used to work the other way: an arrow press during the flourish moved _selected, the
	# check below then saw a different animal and abandoned the whole confirmation. Tapping
	# SELECT and then a chevron therefore did nothing at all - no next screen, no message,
	# and SELECT looking broken. Silently discarding the one irreversible action on the
	# screen is the worst of the available behaviours; the serial guard stays for the paths
	# that really do invalidate a confirmation, like leaving the picker.
	_confirmation_serial += 1
	var serial := _confirmation_serial
	var chosen := _selected
	var def := Content.animal(chosen)
	_confirming_selection = true
	var turn_time := _turn_selected_right()
	if turn_time > 0.0:
		await get_tree().create_timer(turn_time).timeout
	if not is_inside_tree() or _mode != Mode.PICKING \
			or serial != _confirmation_serial or chosen != _selected:
		return
	# Finish on one canonical angle before any root or bone response begins. Equivalent
	# wrapped angles look the same, but normalising here makes the ordering unambiguous.
	if _preview_root != null:
		_preview_root.rotation.y = RECORDING_FACING

	var duration := 0.0
	if def != null and _rig != null:
		duration = _rig.play_selection_reaction(def.confirm_selection_animation)
		Audio.play_animal_call(def.confirm_selection_sound, def.voice_pitch)
		Fx.burst(_preview_root, Vector3(0, 0.38, 0), "sparkle", UiKit.GOLD, 1.25)
	else:
		Audio.play("charge")
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
	if not is_inside_tree() or _mode != Mode.PICKING \
			or serial != _confirmation_serial or chosen != _selected:
		return
	Game.begin_creature(chosen)
	_enter_recording()


## Ease from whatever angle the turntable had reached to the established right-facing
## recording pose. A wrapped angular delta chooses the nearest equivalent rotation, so it
## never spins almost a full revolution merely because it was just past the target.
func _turn_selected_right() -> float:
	if _preview_root == null:
		return 0.0
	if _facing_tween != null and _facing_tween.is_valid():
		_facing_tween.kill()
	var start_angle := _preview_root.rotation.y
	var turn := wrapf(RECORDING_FACING - start_angle, -PI, PI)
	if absf(turn) < 0.001:
		_preview_root.rotation.y = RECORDING_FACING
		return 0.0
	var target_angle := start_angle + turn
	var turn_time := clampf(absf(turn) / CONFIRM_TURN_SPEED,
		CONFIRM_TURN_MIN, CONFIRM_TURN_MAX)
	_facing_tween = create_tween()
	_facing_tween.tween_method(func(angle: float) -> void:
			if _preview_root != null:
				_preview_root.rotation.y = angle,
		start_angle, target_angle, turn_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return turn_time


## The mirror of _enter_recording(), for the back button abandoning a half-finished
## round. It has to rebuild the picking overlay locally: both sub-states are one screen,
## so there is no phase to move to, and Game.set_phase(ANIMAL_SELECTION) from inside
## ANIMAL_SELECTION returns early without emitting anything - which is how the back
## button previously left the Word Lab on screen with Game.current already null, every
## adjective button silently dead against its own null guard.
func _enter_picking() -> void:
	Speech.stop()
	_mode = Mode.PICKING
	_confirming_selection = false
	if _facing_tween != null and _facing_tween.is_valid():
		_facing_tween.kill()
	_facing_tween = null
	_set_recording_composition(false)
	_dragging_view = false
	_colour_preview = ""
	_pending = {}
	_attempts = 0
	_busy = false
	_colour_speech_stage = ColourSpeechStage.NONE
	_choosing_now_colour = false
	_colour_past_accepted = false
	_colour_past_assisted = false

	_clear_overlays()
	_build_picking_panel()

	# The rig still wears the abandoned round's BEFORE traits, so it must be rebuilt
	# rather than left standing. _preview() early-returns on an unchanged id, hence the
	# clear first - otherwise the stale rig survives and no button looks selected.
	#
	# _selected is empty when the round was entered without picking (a --phase=lab jump,
	# or returning from Teacher Settings), and something must end up selected regardless
	# or Start Creating comes back dead - the same trap this whole function exists to fix.
	var previous := _selected
	if previous.is_empty():
		previous = _rig_animal
	if previous.is_empty():
		var ids := Content.animal_ids()
		previous = str(ids[0]) if not ids.is_empty() else ""
	_selected = ""
	if not previous.is_empty():
		_preview(previous)


# --- Present-tense pass ------------------------------------------------------------

## Settings.SAY_SPLIT collects the three "Now it is ___" sentences here, after every past
## sentence is recorded and before the chamber runs. The creature is still in its BEFORE
## state throughout - it transforms once, on all three traits at once, exactly as it does
## without this pass. This is a modal over that creature rather than another side panel:
## the three sentences are one task, and nothing else on screen is actionable during it.
func _enter_present() -> void:
	_mode = Mode.PRESENT
	_dragging_view = false
	_present_index = 0
	_attempts = 0
	_busy = false
	_pending = {}
	_colour_speech_stage = ColourSpeechStage.NONE
	_choosing_now_colour = false
	_colour_past_accepted = false
	_colour_past_assisted = false
	_clear_overlays()

	var dim := ColorRect.new()
	dim.name = "PresentDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP ## Swallows taps meant for the panel behind.
	_root.add_child(dim)

	var panel := UiKit.panel(Color(0.06, 0.1, 0.16, 0.98), 18, 2, UiKit.ACCENT)
	panel.name = "PresentPanel"
	# Keep the transformed subject visible above the task instead of leaving only its ears
	# peeking awkwardly from behind a centred modal.
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -PRESENT_SIZE.x * 0.5
	panel.offset_right = PRESENT_SIZE.x * 0.5
	panel.offset_top = -(PRESENT_SIZE.y + 24.0)
	panel.offset_bottom = -24.0
	_root.add_child(panel)

	var column := UiKit.vbox(10)
	panel.add_child(column)

	_speech = SpeechPanel.new()
	_speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_speech.accepted_by_teacher.connect(func() -> void: _present_advance())
	_speech.change_requested.connect(_cancel_present)
	column.add_child(_speech)

	_build_progress_display(false)
	_add_gear_button() ## A teacher must still be able to reach the settings mid-pass.
	_present_step()


func _cancel_present() -> void:
	if _busy:
		return
	Game.abandon_creature()
	_enter_picking()


func _present_step() -> void:
	if Game.current == null or _present_index >= Game.current.entries.size():
		return
	var entry: Dictionary = Game.current.entries[_present_index]
	_pending = {
		"category": str(entry["category"]),
		"before": str(entry["before"]),
		"after": str(entry["after"]),
	}
	_attempts = 0
	_update_lesson_progress()
	_speech.show_target(str(entry["before"]), str(entry["after"]), GrammarValidator.CLAUSE_PRESENT)


## Nothing is recorded here - the entry already exists from the past pass, and the traits
## are applied by the chamber. This pass only gates the way there.
func _present_advance() -> void:
	if _busy:
		return
	_busy = true
	_pending = {}
	# The present half is a take of its own, minutes after its past half, and has to be
	# filed here - _commit() only ever sees the past pass, so without this the whole
	# "Now it is..." side of a split round was recorded and then dropped.
	Voice.keep_present_for(_present_index)
	_speech.show_success()
	Audio.play("success")
	_update_lesson_progress(5 + _present_index)
	var is_last := Game.current == null or _present_index + 1 >= Game.current.entries.size()
	await get_tree().create_timer(PRE_TRANSFORM_PAUSE if is_last else SUCCESS_PAUSE).timeout
	if not is_inside_tree():
		return
	_busy = false
	_present_index += 1
	if Game.current == null or _present_index >= Game.current.entries.size():
		await _begin_pre_transformation()
		return
	_present_step()


# --- Recording sub-state -----------------------------------------------------------

## Swaps the picking panel for the Word Lab / Say It layout in place - the screen never
## changes, only what is shown on top of it.
func _enter_recording() -> void:
	_mode = Mode.RECORDING
	_confirming_selection = false
	_set_recording_composition(true, true)
	_dragging_view = false
	_colour_preview = ""
	_colour_speech_stage = ColourSpeechStage.NONE
	_choosing_now_colour = false
	_colour_past_accepted = false
	_colour_past_assisted = false
	if _preview_root != null:
		_preview_root.rotation.y = RECORDING_FACING
	_clear_overlays()
	_build_recording_ui()
	# A freshly confirmed animal is already the correct neutral live rig. Reapplying an
	# empty trait set calls reset_modifiers(), which snaps body.position to zero and made
	# the entire animal visibly rise from its current preview pose at selection time.
	# Restored/debug rounds still need their saved traits rebuilt here.
	var needs_restore := _rig == null or Game.current == null \
		or _rig_animal != Game.current.animal_id or not Game.current.entries.is_empty()
	if needs_restore:
		_apply_traits(false)
	_sync_ui()


func _build_recording_ui() -> void:
	# One fixed bottom console. Descriptor, sequential colour choice and Say It all occupy
	# this exact rectangle, so no selection can push the platform or animal sideways.
	_console = Control.new()
	_console.name = "SelectionConsole"
	_console.anchor_left = 0.5
	_console.anchor_right = 0.5
	_console.anchor_top = 1.0
	_console.anchor_bottom = 1.0
	_console.offset_left = -CONSOLE_SIZE.x * 0.5
	_console.offset_right = CONSOLE_SIZE.x * 0.5
	_console.offset_top = -(CONSOLE_SIZE.y + CONSOLE_BOTTOM_MARGIN)
	_console.offset_bottom = -CONSOLE_BOTTOM_MARGIN
	_root.add_child(_console)

	_word_lab = DescriptorCarousel.new()
	_word_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_word_lab.pair_selected.connect(_on_pair_selected)
	_word_lab.before_colour_previewed.connect(_on_before_colour_previewed)
	_word_lab.before_colour_selected.connect(_on_before_colour_selected)
	_word_lab.colour_selection_cancelled.connect(_on_colour_selection_cancelled)
	_word_lab.colour_step_changed.connect(_on_colour_step_changed)
	_console.add_child(_word_lab)
	var animal := Content.animal(Game.current.animal_id) if Game.current != null else null
	_word_lab.set_disabled_categories(animal.disabled_categories if animal != null else PackedStringArray())

	_build_say_it_dock()

	# Floating HUD
	var back_btn := UiKit.icon_button("< もどる", HUD_BUTTON)
	# Keep a stable name for the harness and for navigation code; the visible caption can
	# now describe the action without becoming an implicit selector.
	back_btn.name = "BackToPicking"
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back_btn.offset_left = 24
	back_btn.offset_right = 24 + HUD_BACK_WIDTH
	back_btn.offset_top = HUD_BUTTON_TOP
	back_btn.offset_bottom = HUD_BUTTON_TOP + HUD_BUTTON
	back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		Game.abandon_creature()
		_enter_picking())
	_root.add_child(back_btn)

	_add_gear_button()
	_build_progress_display()


## "Before" shares the actual screen centre with the optical centre of the animal and
## platform, rather than the old free-space centre left of a descriptor panel.
func _build_progress_display(show_heading := true) -> void:
	var box := UiKit.vbox(2)
	box.name = "BeforeHeadingGroup"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = -PROGRESS_WIDTH * 0.5
	box.offset_right = PROGRESS_WIDTH * 0.5
	box.offset_top = 24
	box.offset_bottom = 24 + (PROGRESS_HEIGHT if show_heading else 30)
	_root.add_child(box)
	_progress_group = box

	if show_heading:
		_progress = UiKit.label("", UiKit.BODY, UiKit.GOLD)
		_progress.add_theme_font_size_override("font_size", PROGRESS_FONT)
		_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_progress)
	_lesson_progress = UiKit.lesson_progress()
	box.add_child(_lesson_progress)
	if show_heading:
		_drag_hint = UiKit.label("ドラッグでどうぶつの向きを変えられます", UiKit.SMALL, UiKit.MUTED)
		_drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_drag_hint)
	_update_lesson_progress()


func _update_lesson_progress(completed_override := -1) -> void:
	if _lesson_progress == null:
		return
	var completed := 0
	var active := 0
	match _mode:
		Mode.PICKING:
			completed = 0
			active = 0
		Mode.RECORDING:
			completed = 1 + (Game.current.slots_filled() if Game.current != null else 0)
			active = mini(completed, 4)
		Mode.PRESENT:
			completed = 4 + _present_index
			active = mini(completed, 6)
		Mode.PRE_TRANSFORMATION:
			completed = UiKit.LESSON_STEPS
			active = -1
	if completed_override >= 0:
		completed = clampi(completed_override, 0, UiKit.LESSON_STEPS)
		active = -1 if completed >= UiKit.LESSON_STEPS else mini(completed, 6)
	UiKit.set_lesson_progress(_lesson_progress, completed, active)


## Say It replaces the carousel inside SelectionConsole instead of introducing another
## panel elsewhere on screen. Its width is narrower, but its centre and vertical region
## are identical to the carousel's.
func _build_say_it_dock() -> void:
	_speech = SpeechPanel.new()
	_speech.anchor_left = 0.5
	_speech.anchor_right = 0.5
	_speech.anchor_top = 0.0
	_speech.anchor_bottom = 1.0
	_speech.offset_left = -SAY_IT_WIDTH * 0.5
	_speech.offset_right = SAY_IT_WIDTH * 0.5
	_speech.offset_top = 0.0
	_speech.offset_bottom = 0.0
	_speech.accepted_by_teacher.connect(func() -> void: _commit(true))
	_speech.change_requested.connect(_cancel_pending)
	_console.add_child(_speech)


func _sync_ui() -> void:
	if Game.current == null:
		return
	var assigned := _assigned_category()
	if _progress != null:
		_progress.text = NOW_COLOUR_HEADING if _choosing_now_colour else APPEARANCE_HEADING
	_update_lesson_progress()

	_word_lab.set_used(Game.current.used_categories())
	_word_lab.set_restriction(assigned)
	_word_lab.set_locked(not _pending.is_empty() or _busy)
	_word_lab.visible = _pending.is_empty() and not _busy


## Guided mode hands the student one pair per sentence instead of the whole board. The
## choice is fixed for the round (seeded from this creature) so it does not shuffle
## under the student between redraws.
func _assigned_category() -> String:
	if Settings.choice_mode != Settings.CHOICE_GUIDED or Game.current == null:
		return ""
	var remaining := PackedStringArray()
	var used := Game.current.used_categories()
	var animal := Content.animal(Game.current.animal_id)
	for pair in Content.enabled_pairs():
		if not used.has(pair.category) and (animal == null or not animal.disabled_categories.has(pair.category)):
			remaining.append(pair.category)
	if not Content.enabled_colors().is_empty() and not used.has(Content.COLOR_CATEGORY):
		remaining.append(Content.COLOR_CATEGORY)
	if remaining.is_empty():
		return ""
	var round_seed: int = absi(("%s%d" % [Game.current.animal_id, Game.current.created_unix]).hash())
	return remaining[(round_seed + Game.current.slots_filled() * 7) % remaining.size()]


## Show the committed "It was" traits plus whatever card is currently selected but not
## yet spoken.
##
## The rig is deliberately NOT rebuilt here. Rebuilding would reset the deformer every
## time a card is tapped, so a body could never be seen stretching - it would only ever
## pop into its new shape. Keeping one rig alive lets the transition animate from
## wherever the creature currently is, and lets the finished shape persist afterwards.
func _apply_traits(animate: bool) -> void:
	if Game.current == null:
		return
	if _rig == null or _rig_animal != Game.current.animal_id:
		_build_rig(Game.current.animal_id)
	if _rig == null:
		return
	var traits := Game.current.before_traits()
	if not _colour_preview.is_empty():
		traits[Content.COLOR_CATEGORY] = _colour_preview
	if not _pending.is_empty():
		traits[str(_pending["category"])] = str(_pending["before"])
	TraitVisuals.apply_all(_rig, traits, animate)


func _build_rig(animal_id: String) -> void:
	if _rig != null:
		_rig.queue_free()
	_rig = CreatureFactory.build_plain(animal_id)
	_rig_animal = animal_id
	if _rig != null:
		_preview_root.add_child(_rig)
		# The authored idle, so the animal on the platform breathes and looks around instead
		# of standing frozen while the student decides. Only on this screen and in the zoo:
		# the recording and transformation screens measure this creature's height and solve
		# its stance against the platform, and an idle that moves its feet moves the thing
		# they are solving for.
		_rig.enable_authored_animation()
		_rig.motion_state = "idle" 


func _is_deform_category(category: String) -> bool:
	var pair := Content.pair_for_category(category)
	return pair != null and (pair.modifier == "BODY_LENGTH" or pair.modifier == "LEG_LENGTH")


## A short pop so a newly applied "It was..." trait is felt, not just seen.
func _punch() -> void:
	if _rig == null:
		return
	var tween := create_tween()
	tween.tween_property(_rig, "scale", Vector3.ONE * 1.07, 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_rig, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	Fx.burst(_preview_root, Vector3(0, 0.3, 0), "sparkle", UiKit.ACCENT, 1.4)


func _on_pair_selected(category: String, before: String, after: String) -> void:
	if _busy or not _pending.is_empty() or Game.current == null or Game.current.is_complete():
		return
	_colour_preview = ""
	_pending = {"category": category, "before": before, "after": after}
	_attempts = 0
	# A colour's past clause was already accepted before the Now wheel appeared. Full
	# sentence mode still needs the present clause here; the split/past modes either gather
	# it in their normal later pass or intentionally ask for past only.
	if category == Content.COLOR_CATEGORY and _colour_past_accepted:
		_word_lab.set_locked(true)
		_word_lab.visible = false
		if Settings.say_mode == Settings.SAY_FULL:
			_colour_speech_stage = ColourSpeechStage.PRESENT
			_speech.show_target(before, after, GrammarValidator.CLAUSE_PRESENT)
		else:
			_complete_colour_without_present()
		return
	_apply_traits(true)
	# Body and leg changes stage their own cartoon transition; a scale punch on top
	# would just fight it.
	if not _is_deform_category(category):
		_punch()
	_word_lab.set_locked(true)
	_word_lab.visible = false
	_speech.show_target(before, after, _clause())


## Choosing a Before colour has enough information for the past clause, but not enough to
## create the transformation entry. Ask for "It was ..." now, then retain that accepted
## half while the student chooses Now.
func _on_before_colour_selected(word: String) -> void:
	if _busy or not _pending.is_empty() or Game.current == null:
		return
	_colour_preview = word
	_colour_speech_stage = ColourSpeechStage.PAST
	_colour_past_accepted = false
	_colour_past_assisted = false
	_pending = {"category": Content.COLOR_CATEGORY, "before": word, "after": ""}
	_attempts = 0
	_word_lab.set_locked(true)
	_word_lab.visible = false
	_speech.show_target(word, "", GrammarValidator.CLAUSE_PAST)


## Before-colour browsing is visual only. It deliberately bypasses `_pending`, because a
## pending pair means the student has already chosen an After value and should be in Say
## It. The preview vanishes without touching CreatureState when the colour menu is cancelled.
func _on_before_colour_previewed(word: String) -> void:
	if _busy or not _pending.is_empty() or Game.current == null:
		return
	_colour_preview = word
	_apply_traits(true)


func _on_colour_selection_cancelled() -> void:
	if _busy or not _pending.is_empty():
		return
	_colour_preview = ""
	_colour_speech_stage = ColourSpeechStage.NONE
	_colour_past_accepted = false
	_colour_past_assisted = false
	_apply_traits(true)


func _on_colour_step_changed(choosing_now: bool) -> void:
	_choosing_now_colour = choosing_now
	if _progress != null:
		_progress.text = NOW_COLOUR_HEADING if choosing_now else APPEARANCE_HEADING


func _cancel_pending() -> void:
	if _busy or _pending.is_empty():
		return
	var cancelled_stage := _colour_speech_stage
	_pending = {}
	_attempts = 0
	_colour_speech_stage = ColourSpeechStage.NONE
	_word_lab.set_locked(false)
	_word_lab.visible = true
	_speech.show_idle()
	if cancelled_stage == ColourSpeechStage.PRESENT:
		# The past answer is still valid; return to Now so only the present colour is changed.
		_word_lab.continue_colour_after_past()
		return
	_colour_preview = ""
	_colour_past_accepted = false
	_colour_past_assisted = false
	_apply_traits(true)


func _on_heard(alternatives: PackedStringArray, is_final: bool) -> void:
	var speaking := _mode == Mode.RECORDING or _mode == Mode.PRESENT
	if not speaking or not is_final or _busy or _pending.is_empty() or not _speech.is_armed():
		return
	_evaluate(alternatives)


## Every alternative the recogniser offered gets a chance; the first that passes wins,
## otherwise the best-diagnosed failure is what the student is shown.
func _evaluate(alternatives: PackedStringArray) -> void:
	var before := str(_pending["before"])
	var after := str(_pending["after"])
	var best := {}
	for alternative in alternatives:
		var result := GrammarValidator.validate(alternative, before, after, Settings.strictness, _clause())
		if bool(result["ok"]):
			if _mode == Mode.PRESENT:
				_present_advance()
			else:
				_commit(false)
			return
		if best.is_empty() or _score(result) > _score(best):
			best = result
	if best.is_empty():
		best = GrammarValidator.validate("", before, after, Settings.strictness, _clause())
	_attempts += 1
	_speech.show_failure(best, _attempts)


## How close a failed attempt got, so the most useful diagnosis is the one shown.
static func _score(result: Dictionary) -> int:
	var value := 0
	if bool(result.get("said_before", false)):
		value += 1
	if bool(result.get("said_after", false)):
		value += 1
	if bool(result.get("frame_before", false)):
		value += 2
	if bool(result.get("frame_after", false)):
		value += 2
	return value


func _commit(assisted: bool) -> void:
	if _pending.is_empty() or _busy:
		return
	if _colour_speech_stage == ColourSpeechStage.PAST:
		_accept_colour_past(assisted)
		return
	_busy = true
	var category := str(_pending["category"])
	var before := str(_pending["before"])
	var after := str(_pending["after"])
	var completing_colour_present := _colour_speech_stage == ColourSpeechStage.PRESENT
	_pending = {}
	_colour_preview = ""

	Game.record_sentence(category, before, after, assisted or _colour_past_assisted)
	_update_lesson_progress()
	# Keep the take that was actually accepted, indexed by the slot it filled, so the
	# transformation can play the three sentences back in the order they were said.
	if completing_colour_present:
		Voice.keep_present_for(Game.current.slots_filled() - 1)
	else:
		Voice.keep_for(Game.current.slots_filled() - 1)
	_colour_speech_stage = ColourSpeechStage.NONE
	_colour_past_accepted = false
	_colour_past_assisted = false
	Audio.play("success")
	Fx.burst(_preview_root, Vector3(0, 0.4, 0), "sparkle", UiKit.OK, 1.6)
	_speech.show_success()
	# The rig is NOT rebuilt here: the BEFORE word is already applied, and the AFTER
	# word must not appear until the chamber runs on the next screen.
	_finish_sentence()


func _accept_colour_past(assisted: bool) -> void:
	_busy = true
	_colour_past_assisted = assisted
	_colour_past_accepted = true
	# The eventual colour entry will occupy the current empty slot.
	Voice.keep_for(Game.current.slots_filled())
	_pending = {}
	Audio.play("success")
	Fx.burst(_preview_root, Vector3(0, 0.4, 0), "sparkle", UiKit.OK, 1.6)
	_speech.show_success()
	await get_tree().create_timer(SUCCESS_PAUSE).timeout
	if not is_inside_tree() or Game.current == null:
		return
	_busy = false
	_colour_speech_stage = ColourSpeechStage.NONE
	_word_lab.set_locked(false)
	_word_lab.continue_colour_after_past()
	_word_lab.visible = true
	_speech.show_idle()


func _complete_colour_without_present() -> void:
	if _pending.is_empty() or Game.current == null:
		return
	_busy = true
	var before := str(_pending["before"])
	var after := str(_pending["after"])
	_pending = {}
	_colour_preview = ""
	Game.record_sentence(Content.COLOR_CATEGORY, before, after, _colour_past_assisted)
	_update_lesson_progress()
	_colour_speech_stage = ColourSpeechStage.NONE
	_colour_past_accepted = false
	_colour_past_assisted = false
	Audio.play("success")
	Fx.burst(_preview_root, Vector3(0, 0.4, 0), "sparkle", UiKit.OK, 1.6)
	_speech.show_idle()
	_finish_sentence()


func _finish_sentence() -> void:
	var ready_for_cinematic := Game.current != null and Game.current.is_complete() \
		and not Settings.needs_present_pass(Speech.uses_microphone())
	await get_tree().create_timer(
		PRE_TRANSFORM_PAUSE if ready_for_cinematic else SUCCESS_PAUSE).timeout
	if not is_inside_tree():
		return
	_busy = false
	if Game.current != null and Game.current.is_complete():
		if Settings.needs_present_pass(Speech.uses_microphone()):
			_enter_present()
		else:
			await _begin_pre_transformation()
	else:
		_word_lab.set_locked(false)
		_word_lab.visible = true
		_speech.show_idle("つぎのカードをえらぼう。")
		_sync_ui()


## A dedicated bridge between gameplay and cinema. It owns input lockout and every UI
## exit, while deliberately touching no camera, animal, platform or trait transform.
func _begin_pre_transformation() -> void:
	if _pre_transforming or Game.current == null:
		return
	_pre_transforming = true
	_mode = Mode.PRE_TRANSFORMATION
	_update_lesson_progress()
	_busy = true
	_dragging_view = false
	Speech.stop()
	Audio.play("whoosh", 0.82)
	var blocker := Control.new()
	blocker.name = "PreTransformationInputBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(blocker)

	var view := get_viewport().get_visible_rect().size
	var tween := create_tween().set_parallel(true)
	var back := _root.get_node_or_null("BackToPicking") as Control
	var gear := _root.get_node_or_null("SettingsGear") as Control
	var present_panel := _root.get_node_or_null("PresentPanel") as Control
	var present_dim := _root.get_node_or_null("PresentDim") as Control
	if back != null:
		tween.tween_property(back, "position:x", -back.size.x - 28.0, UI_EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(back, "modulate:a", 0.0, UI_EXIT_TIME)
	if gear != null:
		tween.tween_property(gear, "position:x", view.x + 28.0, UI_EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(gear, "modulate:a", 0.0, UI_EXIT_TIME)
	if _progress_group != null:
		tween.tween_property(_progress_group, "position:y", -_progress_group.size.y - 28.0,
			UI_EXIT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(_progress_group, "modulate:a", 0.0, UI_EXIT_TIME)
	if _console != null:
		tween.tween_property(_console, "position:y", view.y + 20.0, UI_EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(_console, "modulate:a", 0.0, UI_EXIT_TIME)
	if present_panel != null:
		tween.tween_property(present_panel, "position:y", view.y + 20.0, UI_EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(present_panel, "modulate:a", 0.0, UI_EXIT_TIME)
	if present_dim != null:
		tween.tween_property(present_dim, "modulate:a", 0.0, UI_EXIT_TIME)
	await tween.finished
	if not is_inside_tree() or Game.current == null:
		return
	_handoff_to_transformation()


## Preserve the view the learner has been watching. Offsets are relative to the animal's
## stand point so the chamber can recreate the shot even though its platform lives at a
## different world coordinate.
func _handoff_to_transformation() -> void:
	if _preview_root != null and _camera != null:
		var stand := _preview_root.global_position
		Game.set_transformation_handoff(
			_camera.global_position - stand,
			_camera_aim - stand,
			_camera.fov,
			_preview_root.global_rotation.y)
	Router.request_seamless_next_swap()
	Game.set_phase(Game.Phase.CREATURE_LAB)


func _on_debug_action(action: String) -> void:
	if action == "auto_answer" and not _pending.is_empty():
		Speech.submit_typed(GrammarValidator.expected_sentence(
			str(_pending["before"]), str(_pending["after"])))
