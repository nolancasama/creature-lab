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

const PREVIEW_SPIN := 0.45
const RECORDING_FACING := -PI * 0.5 ## Godot forward (-Z) turned toward screen-right.
const DRAG_TURN_SPEED := 0.012
const SUCCESS_PAUSE := 1.1

const PLATFORM_POS := Vector3(-0.5, 0.0, 0.6)

## A long lens, further back. Anything off the optical axis shears under perspective, and
## the platform has to sit off-axis to be centred in the gap beside the panel - the disc
## came out visibly tilted at the original 48 degrees. Shear scales with tan(fov/2), so
## backing off to 22 degrees leaves about 44% of it while keeping the animal the same size
## on screen: distance and fov are traded against each other, not chosen independently.
const CAMERA_FOV := 22.0
const CAMERA_POS := Vector3(1.791, 4.271, 14.888)
const CAMERA_AIM := Vector3(-0.5, 0.95, 0.0)
## Looks lower than the picking camera, moving the animal/platform upward on screen and
## leaving a stable console region below without shrinking the animal.
const RECORDING_CAMERA_AIM := Vector3(-0.5, 0.22, 0.0)

## Picking and recording are overlays on one screen, so they share one panel rect: the
## Word Lab / Say It stack lands exactly where the animal grid was, and nothing resizes
## or jumps underneath the player at the moment of confirming.
const PANEL_LEFT := -680
const PANEL_RIGHT := -32
const HUD_TOP := 24 ## Top edge of the floating buttons, above the panel on both sub-states.
const PROGRESS_FONT := UiKit.SMALL * 3 ## Readable from the back of a classroom.
const HUD_BUTTON := 52 ## Back button size.
const GEAR_BUTTON_SIZE := HUD_BUTTON * 2 ## Doubled - settings is the one control every
## teacher needs to find without hunting, so it gets the HUD's largest touch target.
const GEAR_ICON := preload("res://ui/gear.svg")
const HUD_GAP := 24 ## Visible gap between the HUD row and the panel below it.
const PANEL_TOP := HUD_TOP + GEAR_BUTTON_SIZE + HUD_GAP ## Clears the gear, now the taller
                                                        ## of the two HUD buttons.
const PANEL_BOTTOM := -24 ## Tighter than the top margin: the height lost to the HUD row
                          ## above comes back here, so the Word Lab still shows every card.
const PANEL_WIDTH := -PANEL_LEFT + PANEL_RIGHT ## 648 - the rect's actual width.
## The centred present-tense panel. Tall enough on its own that SpeechPanel's internal
## centring expanders (see its _build()) already have real slack to work with here without
## any extra tuning.
const PRESENT_SIZE := Vector2(720, 360)
const CONSOLE_SIZE := Vector2(760, 300) ## Same footprint for words, colours and speech.
const CONSOLE_BOTTOM_MARGIN := 10
const SAY_IT_WIDTH := 620

## Content-hugging rather than the tall shared rect: three animal-button rows plus Start,
## no more. Hand-summed from the picking panel's own children (10 top pad + 3 rows of 62 +
## 2 row gaps of 10 + 14 vbox gap + 58 Start + 10 bottom pad) and checked against a render
## rather than trusted blind, since nothing here is a container that reports its own
## natural size back to the anchor math that positions it.
const PICKING_PANEL_HEIGHT := 298
const PROGRESS_SUB_FONT := UiKit.H2 ## The "(n of 3)" line beneath "Before" - present but
                                    ## secondary, not competing with PROGRESS_FONT's scale.
const PROGRESS_WIDTH := 420 ## Wide enough for "Before" at PROGRESS_FONT with room to spare.
const PROGRESS_HEIGHT := 100 ## Both lines plus the small gap between them.

## The animal sits centred in the gap beside the panel, which is always half the panel's
## span left of screen centre, whatever the window is doing. Applied as a lens shift - see
## _lens_shift() for why it is not simply a camera move.
const CAMERA_SHIFT := -PANEL_LEFT / 2.0

enum Mode { PICKING, RECORDING, PRESENT }

var _mode: Mode = Mode.PICKING

# Stage
var _preview_root: Node3D = null
var _rig: CreatureRig = null
var _platform: Node3D = null
var _camera: Camera3D = null

# Picking UI
var _picking_panel: Control = null
var _buttons := {}
var _selected := ""
var _rig_animal := "" ## Which animal the live rig was built for.

# Recording UI
var _root: Control = null
var _progress: Label = null
var _progress_count: Label = null
var _word_lab: DescriptorCarousel = null
var _speech: SpeechPanel = null
var _console: Control = null
var _colour_preview := "" ## Temporary live Before colour; never written to CreatureState.

var _pending := {}
var _attempts := 0
var _busy := false
var _dragging_view := false

# Present-tense pass (Settings.SAY_SPLIT)
var _present_index := 0
var _present_counter: Label = null


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


func _process(delta: float) -> void:
	if _preview_root != null and _mode == Mode.PICKING:
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
		get_viewport().set_input_as_handled()


# --- Stage ---------------------------------------------------------------------

func _build_stage() -> void:
	add_child(StageKit.environment(Color("#16243c"), Color("#2b4a72"), 0.5))
	add_child(StageKit.key_light())
	add_child(StageKit.fill_light(Color("#cfe6ff"), Vector3(-3.0, 3.2, 3.2), 1.1, 14.0))
	add_child(StageKit.ground(9.0, Color("#141d2c")))

	_platform = StageKit.platform(1.8, Color("#22304a"), UiKit.ACCENT)
	_platform.position = PLATFORM_POS
	add_child(_platform)

	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_root.position = PLATFORM_POS + Vector3(0, 0.28, 0)
	_preview_root.rotation.y = -0.7 ## Starting pose for the very first animal shown. Picking
	## a different one later must not repeat this - see _preview(), which deliberately
	## leaves rotation alone so the turntable keeps spinning through a switch instead of
	## snapping back to this angle every time.
	add_child(_preview_root)

	_camera = StageKit.camera(CAMERA_POS, CAMERA_AIM, CAMERA_FOV)
	add_child(_camera)
	_lens_shift(_camera, CAMERA_SHIFT)


## Picking reserves the right side for animal buttons. Recording removes that split and
## uses the optical centre for the animal/platform group. The world objects never move,
## so switching words, colours and speech cannot introduce geometry jumps.
func _set_recording_composition(recording: bool) -> void:
	if _camera == null:
		return
	_camera.set_perspective(CAMERA_FOV, _camera.near, _camera.far)
	_camera.look_at(RECORDING_CAMERA_AIM if recording else CAMERA_AIM)
	if not recording:
		_lens_shift(_camera, CAMERA_SHIFT)


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
	if _mode == Mode.PRESENT:
		return GrammarValidator.CLAUSE_PRESENT
	return GrammarValidator.CLAUSE_PAST if Settings.past_only() else GrammarValidator.CLAUSE_BOTH


## Left edge (in pixels from the screen's left edge) that centres a `width`-wide element
## within the free-space region beside the panel - the same region the camera centres the
## animal in. Reads the actual viewport rather than assuming a fixed window size, the same
## way _lens_shift() does, so the platform, the progress line, and the Say It dock all
## agree on where "centred above the platform" is regardless of how the window is sized.
func _center_left(width: float) -> float:
	var view_width := get_viewport().get_visible_rect().size.x
	var free_width: float = view_width + PANEL_LEFT ## PANEL_LEFT is negative.
	return maxf(0.0, (free_width - width) * 0.5)


func _build_root() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)


# --- Picking sub-state -----------------------------------------------------------

func _build_picking_panel() -> void:
	var panel := UiKit.panel(Color(0.06, 0.1, 0.16, 0.92), 18, 2, UiKit.PANEL_HI)
	# Vertically centred and sized to its own content (PICKING_PANEL_HEIGHT), not stretched
	# to the shared PANEL_TOP/PANEL_BOTTOM rect the way Word Lab is - a grid of seven
	# buttons plus one Start does not need the picking screen to be as tall as the recording
	# screen's card board.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = PANEL_LEFT
	panel.offset_right = PANEL_RIGHT
	panel.offset_top = -PICKING_PANEL_HEIGHT * 0.5
	panel.offset_bottom = PICKING_PANEL_HEIGHT * 0.5
	_root.add_child(panel)
	_picking_panel = panel

	var column := UiKit.vbox(14)
	panel.add_child(column)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)

	for def in Content.animals:
		var b := UiKit.button(def.display_name, UiKit.H3)
		b.custom_minimum_size = Vector2(196, 62)
		b.pressed.connect(_preview.bind(def.id))
		grid.add_child(b)
		_buttons[def.id] = b

	# No expander: Start sits directly below the grid - below Chicken, the last animal -
	# rather than pinned to the foot of a much taller panel.
	#
	# One full-width action and nothing beside it: the selected animal is already named on
	# its own button and standing on the platform, so a separate name label repeated it,
	# and Back led to a title screen that no longer exists.
	var go := UiKit.button("Start", UiKit.H3, true)
	UiKit.style_button(go, UiKit.CTA, true) ## The one action that starts the round gets
	## the palette's call-to-action colour, not the ambient ACCENT every header already uses.
	go.custom_minimum_size = Vector2(0, 58)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_confirm)
	column.add_child(go)

	_add_gear_button()


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
	_progress_count = null
	_buttons.clear() ## Freed with the panel; _preview() would otherwise iterate corpses.


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
	gear.icon = GEAR_ICON
	gear.expand_icon = true
	# The gear alone, with no plate behind it. icon_button's panel-coloured box is right for
	# the back arrow, which sits on flat 2D chrome, but this one sits over the lit 3D stage
	# and read as a floating tile there. Feedback moves onto the icon itself so it still
	# answers a hover and a press without a box to draw them on.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		gear.add_theme_stylebox_override(state, StyleBoxEmpty.new())
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
	_selected = animal_id
	Audio.play("select")

	_build_rig(animal_id)
	# No rotation reset here: _preview_root is one persistent node the whole time the
	# picking grid is up, only the rig child underneath it gets swapped, so the turntable
	# is already exactly where it needs to be to continue uninterrupted.
	for id in _buttons:
		var b: Button = _buttons[id]
		UiKit.style_button(b, UiKit.ACCENT if id == animal_id else UiKit.PANEL_HI, id == animal_id)


func _confirm() -> void:
	if _selected.is_empty() or _mode != Mode.PICKING:
		return
	Audio.play("charge")
	Game.begin_creature(_selected)
	_enter_recording()


## The mirror of _enter_recording(), for the back button abandoning a half-finished
## round. It has to rebuild the picking overlay locally: both sub-states are one screen,
## so there is no phase to move to, and Game.set_phase(ANIMAL_SELECTION) from inside
## ANIMAL_SELECTION returns early without emitting anything - which is how the back
## button previously left the Word Lab on screen with Game.current already null, every
## adjective button silently dead against its own null guard.
func _enter_picking() -> void:
	Speech.stop()
	_mode = Mode.PICKING
	_set_recording_composition(false)
	_dragging_view = false
	_colour_preview = ""
	_pending = {}
	_attempts = 0
	_busy = false

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
	_clear_overlays()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP ## Swallows taps meant for the panel behind.
	_root.add_child(dim)

	var panel := UiKit.panel(Color(0.06, 0.1, 0.16, 0.98), 18, 2, UiKit.ACCENT)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -PRESENT_SIZE.x * 0.5
	panel.offset_right = PRESENT_SIZE.x * 0.5
	panel.offset_top = -PRESENT_SIZE.y * 0.5
	panel.offset_bottom = PRESENT_SIZE.y * 0.5
	_root.add_child(panel)

	var column := UiKit.vbox(10)
	panel.add_child(column)

	var heading := UiKit.label("Now say what it IS", UiKit.H2, UiKit.ACCENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	_present_counter = UiKit.label("", UiKit.H3, UiKit.GOLD)
	_present_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_present_counter)

	_speech = SpeechPanel.new()
	_speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_speech.accepted_by_teacher.connect(func() -> void: _present_advance())
	column.add_child(_speech)

	_add_gear_button() ## A teacher must still be able to reach the settings mid-pass.
	_present_step()


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
	_present_counter.text = "(%d of %d)" % [_present_index + 1, Game.current.entries.size()]
	_speech.show_target(str(entry["before"]), str(entry["after"]), GrammarValidator.CLAUSE_PRESENT)


## Nothing is recorded here - the entry already exists from the past pass, and the traits
## are applied by the chamber. This pass only gates the way there.
func _present_advance() -> void:
	if _busy:
		return
	_busy = true
	_pending = {}
	_speech.show_success()
	Audio.play("success")
	await get_tree().create_timer(SUCCESS_PAUSE).timeout
	if not is_inside_tree():
		return
	_busy = false
	_present_index += 1
	if Game.current == null or _present_index >= Game.current.entries.size():
		Game.set_phase(Game.Phase.CREATURE_LAB)
		return
	_present_step()


# --- Recording sub-state -----------------------------------------------------------

## Swaps the picking panel for the Word Lab / Say It layout in place - the screen never
## changes, only what is shown on top of it.
func _enter_recording() -> void:
	_mode = Mode.RECORDING
	_set_recording_composition(true)
	_dragging_view = false
	_colour_preview = ""
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
	_word_lab.colour_selection_cancelled.connect(_on_colour_selection_cancelled)
	_console.add_child(_word_lab)
	var animal := Content.animal(Game.current.animal_id) if Game.current != null else null
	_word_lab.set_disabled_categories(animal.disabled_categories if animal != null else PackedStringArray())

	_build_say_it_dock()

	# Floating HUD
	var back_btn := UiKit.icon_button("<", HUD_BUTTON)
	# Named, because "<" is no longer a unique caption on this screen - the carousel uses
	# it for its own left arrow, and a harness looking the button up by its text found the
	# wrong one and quietly stopped abandoning the round.
	back_btn.name = "BackToPicking"
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back_btn.offset_left = 24
	back_btn.offset_right = 24 + HUD_BUTTON
	back_btn.offset_top = 24
	back_btn.offset_bottom = 24 + HUD_BUTTON
	back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		Game.abandon_creature()
		_enter_picking())
	_root.add_child(back_btn)

	_add_gear_button()
	_build_progress_display()


## "Before" and its count share the actual screen centre with the optical centre of the
## animal and platform, rather than the old free-space centre left of a descriptor panel.
func _build_progress_display() -> void:
	var box := UiKit.vbox(2)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = -PROGRESS_WIDTH * 0.5
	box.offset_right = PROGRESS_WIDTH * 0.5
	box.offset_top = 24
	box.offset_bottom = 24 + PROGRESS_HEIGHT
	_root.add_child(box)

	_progress = UiKit.label("", UiKit.BODY, UiKit.GOLD)
	_progress.add_theme_font_size_override("font_size", PROGRESS_FONT)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_progress)

	_progress_count = UiKit.label("", UiKit.BODY, UiKit.GOLD)
	_progress_count.add_theme_font_size_override("font_size", PROGRESS_SUB_FONT)
	_progress_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_progress_count)


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
		_progress.text = "Before"
	if _progress_count != null:
		_progress_count.text = "(%d of %d)" % [mini(Game.current.slots_filled() + 1, CreatureState.SLOTS), CreatureState.SLOTS]

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
	_apply_traits(true)
	# Body and leg changes stage their own cartoon transition; a scale punch on top
	# would just fight it.
	if not _is_deform_category(category):
		_punch()
	_word_lab.set_locked(true)
	_word_lab.visible = false
	_speech.show_target(before, after, _clause())


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
	_apply_traits(true)


func _cancel_pending() -> void:
	if _busy or _pending.is_empty():
		return
	_pending = {}
	_colour_preview = ""
	_attempts = 0
	_apply_traits(true)
	_word_lab.set_locked(false)
	_word_lab.visible = true
	_speech.show_idle()


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
	_busy = true
	var category := str(_pending["category"])
	var before := str(_pending["before"])
	var after := str(_pending["after"])
	_pending = {}
	_colour_preview = ""

	Game.record_sentence(category, before, after, assisted)
	# Keep the take that was actually accepted, indexed by the slot it filled, so the
	# transformation can play the three sentences back in the order they were said.
	Voice.keep_for(Game.current.slots_filled() - 1)
	Audio.play("success")
	Fx.burst(_preview_root, Vector3(0, 0.4, 0), "sparkle", UiKit.OK, 1.6)
	_speech.show_success()
	# The rig is NOT rebuilt here: the BEFORE word is already applied, and the AFTER
	# word must not appear until the chamber runs on the next screen.
	_finish_sentence()


func _finish_sentence() -> void:
	await get_tree().create_timer(SUCCESS_PAUSE).timeout
	if not is_inside_tree():
		return
	_busy = false
	if Game.current != null and Game.current.is_complete():
		if Settings.split_pass():
			_enter_present()
		else:
			Game.set_phase(Game.Phase.CREATURE_LAB)
	else:
		_word_lab.set_locked(false)
		_word_lab.visible = true
		_speech.show_idle("Choose your next card.")
		_sync_ui()


func _on_debug_action(action: String) -> void:
	if action == "auto_answer" and not _pending.is_empty():
		Speech.submit_typed(GrammarValidator.expected_sentence(
			str(_pending["before"]), str(_pending["after"])))
