extends Node3D
## Pick an animal, then record its three sentences - all without ever leaving this
## screen. Picking and speaking are one continuous action, not two different places to
## be: the animal rotates while it is being previewed, then holds still while the
## player records its sentences.
##
## Two local UI sub-states, not global FSM phases (the FSM only sees one
## Phase.ANIMAL_SELECTION for all of it):
##   PICKING   - grid of animal buttons, live rotating preview, a confirm button.
##   RECORDING - Word Lab + Say It stacked on the right, floating HUD, animal centred in
##               the free space on the left.

const PREVIEW_SPIN := 0.45
const RECORDING_FACING := -PI * 0.5 ## Godot forward (-Z) turned toward screen-right.
const DRAG_TURN_SPEED := 0.012
const SUCCESS_PAUSE := 1.1

const PLATFORM_POS := Vector3(-0.5, 0.0, 0.6)
const CAMERA_POS := Vector3(0.5, 2.4, 6.5)
const CAMERA_AIM := Vector3(-0.5, 0.95, 0.0)

## Picking and recording are overlays on one screen, so they share one panel rect: the
## Word Lab / Say It stack lands exactly where the animal grid was, and nothing resizes
## or jumps underneath the player at the moment of confirming.
const PANEL_LEFT := -680
const PANEL_RIGHT := -32
const HUD_TOP := 24 ## Top edge of the floating buttons, above the panel on both sub-states.
const HUD_BUTTON := 52
const PANEL_TOP := HUD_TOP + HUD_BUTTON + 12 ## Clears the gear rather than sitting under it.
const PANEL_BOTTOM := -24 ## Tighter than the top margin: the height lost to the gear row
                          ## above comes back here, so the Word Lab still shows every card.
const PANEL_WIDTH := -PANEL_LEFT + PANEL_RIGHT ## 648 - the rect's actual width.

## The animal sits centred in the gap beside the panel, which is always half the panel's
## span left of screen centre, whatever the window is doing. Applied as a lens shift - see
## _lens_shift() for why it is not simply a camera move.
const CAMERA_SHIFT := -PANEL_LEFT / 2.0

enum Mode { PICKING, RECORDING }

var _mode: Mode = Mode.PICKING

# Stage
var _preview_root: Node3D = null
var _rig: CreatureRig = null

# Picking UI
var _picking_panel: Control = null
var _buttons := {}
var _selected := ""
var _rig_animal := "" ## Which animal the live rig was built for.

# Recording UI
var _root: Control = null
var _progress: Label = null
var _word_lab: WordLab = null
var _speech: SpeechPanel = null

var _pending := {}
var _attempts := 0
var _busy := false
var _dragging_view := false


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

	var platform := StageKit.platform(1.8, Color("#22304a"), UiKit.ACCENT)
	platform.position = PLATFORM_POS
	add_child(platform)

	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_root.position = PLATFORM_POS + Vector3(0, 0.28, 0)
	add_child(_preview_root)

	var cam := StageKit.camera(CAMERA_POS, CAMERA_AIM, 48.0)
	add_child(cam)
	_lens_shift(cam, CAMERA_SHIFT)


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
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = PANEL_LEFT
	panel.offset_right = PANEL_RIGHT
	panel.offset_top = PANEL_TOP
	panel.offset_bottom = PANEL_BOTTOM
	_root.add_child(panel)
	_picking_panel = panel

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
		b.pressed.connect(_preview.bind(def.id))
		grid.add_child(b)
		_buttons[def.id] = b

	column.add_child(UiKit.expander())

	# One full-width action and nothing beside it: the selected animal is already named on
	# its own button and standing on the platform, so a separate name label repeated it,
	# and Back led to a title screen that no longer exists.
	var go := UiKit.button("Start", UiKit.H3, true)
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
	_progress = null
	_buttons.clear() ## Freed with the panel; _preview() would otherwise iterate corpses.


## Teacher Settings has to be reachable from both sub-states, and from the same corner in
## each - picking and recording are one screen, so a control that moved between them would
## read as a different screen.
##
## Both offsets are set explicitly: the preset derives them from the button's current size,
## so moving only one edge leaves a rect narrower than the button, which renders clipped
## off the screen edge.
func _add_gear_button() -> void:
	var gear := UiKit.icon_button("⚙", HUD_BUTTON)
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_right = PANEL_RIGHT
	gear.offset_left = PANEL_RIGHT - HUD_BUTTON
	gear.offset_top = HUD_TOP
	gear.offset_bottom = HUD_TOP + HUD_BUTTON
	gear.pressed.connect(func() -> void: Game.open_settings())
	_root.add_child(gear)


func _preview(animal_id: String) -> void:
	if animal_id == _selected:
		return
	_selected = animal_id
	Audio.play("select")

	_build_rig(animal_id)
	_preview_root.rotation.y = -0.7

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
	_dragging_view = false
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


# --- Recording sub-state -----------------------------------------------------------

## Swaps the picking panel for the Word Lab / Say It layout in place - the screen never
## changes, only what is shown on top of it.
func _enter_recording() -> void:
	_mode = Mode.RECORDING
	_dragging_view = false
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
	var right := UiKit.vbox(12)
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = PANEL_LEFT
	right.offset_right = PANEL_RIGHT
	right.offset_top = PANEL_TOP
	right.offset_bottom = PANEL_BOTTOM
	right.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_root.add_child(right)

	# Word Lab has more content than a narrow column can always guarantee height for;
	# it scrolls if needed so Say It below it never gets squeezed off-screen.
	var word_scroll := ScrollContainer.new()
	word_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	word_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(word_scroll)

	_word_lab = WordLab.new()
	_word_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_word_lab.pair_selected.connect(_on_pair_selected)
	word_scroll.add_child(_word_lab)
	var animal := Content.animal(Game.current.animal_id) if Game.current != null else null
	_word_lab.set_disabled_categories(animal.disabled_categories if animal != null else PackedStringArray())

	_speech = SpeechPanel.new()
	_speech.custom_minimum_size = Vector2(0, 340)
	_speech.change_requested.connect(_cancel_pending)
	_speech.accepted_by_teacher.connect(func() -> void: _commit(true))
	right.add_child(_speech)

	# Floating HUD
	var back_btn := UiKit.icon_button("<", HUD_BUTTON)
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

	# Spans the gap to the left of the panel rather than the whole screen, so the progress
	# line reads as a caption over the animal instead of drifting toward the Word Lab.
	_progress = UiKit.label("", UiKit.BODY, UiKit.GOLD)
	_progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_progress.offset_left = 0
	_progress.offset_right = PANEL_LEFT
	_progress.add_theme_font_size_override("font_size", UiKit.SMALL)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.offset_top = 32
	_root.add_child(_progress)


func _sync_ui() -> void:
	if Game.current == null:
		return
	var assigned := _assigned_category()
	var text := "Before / %d of %d" % [mini(Game.current.slots_filled() + 1, CreatureState.SLOTS), CreatureState.SLOTS]
	if _progress != null:
		_progress.text = text

	_word_lab.set_used(Game.current.used_categories())
	_word_lab.set_restriction(assigned)
	_word_lab.set_locked(not _pending.is_empty() or _busy)


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
	_pending = {"category": category, "before": before, "after": after}
	_attempts = 0
	_apply_traits(true)
	# Body and leg changes stage their own cartoon transition; a scale punch on top
	# would just fight it.
	if not _is_deform_category(category):
		_punch()
	_word_lab.set_locked(true)
	_speech.show_target(before, after)


func _cancel_pending() -> void:
	if _busy or _pending.is_empty():
		return
	_pending = {}
	_attempts = 0
	_apply_traits(true)
	_word_lab.set_locked(false)
	_speech.show_idle("Pick another card.")


func _on_heard(alternatives: PackedStringArray, is_final: bool) -> void:
	if _mode != Mode.RECORDING or not is_final or _busy or _pending.is_empty() or not _speech.is_armed():
		return
	_evaluate(alternatives)


## Every alternative the recogniser offered gets a chance; the first that passes wins,
## otherwise the best-diagnosed failure is what the student is shown.
func _evaluate(alternatives: PackedStringArray) -> void:
	var before := str(_pending["before"])
	var after := str(_pending["after"])
	var best := {}
	for alternative in alternatives:
		var result := GrammarValidator.validate(alternative, before, after, Settings.strictness)
		if bool(result["ok"]):
			_commit(false)
			return
		if best.is_empty() or _score(result) > _score(best):
			best = result
	if best.is_empty():
		best = GrammarValidator.validate("", before, after, Settings.strictness)
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

	Game.record_sentence(category, before, after, assisted)
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
		Game.set_phase(Game.Phase.CREATURE_LAB)
	else:
		_word_lab.set_locked(false)
		_speech.show_idle("Choose your next card.")
		_sync_ui()


func _on_debug_action(action: String) -> void:
	if action == "auto_answer" and not _pending.is_empty():
		Speech.submit_typed(GrammarValidator.expected_sentence(
			str(_pending["before"]), str(_pending["after"])))
