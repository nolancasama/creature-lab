extends Node3D
## The Creature Laboratory: the whole gameplay loop lives here, and nothing else does.
##
## The one rule everything below serves: the animal on the platform always shows the
## combined "It was..." state. Selecting a card applies the BEFORE word immediately;
## the AFTER word is only ever recorded, never rendered, until the chamber runs.

const SUCCESS_PAUSE := 1.1
const BANNER_TEXT := "D N A   C O M P L E T E"

var stage: LabStage = null

var _dna_log: DnaLog = null
var _word_lab: WordLab = null
var _speech: SpeechPanel = null
var _progress: Label = null
var _banner: Label = null
var _flash: ColorRect = null
var _skip_button: Button = null

var _director: TransformationDirector = null

var _pending := {}
var _attempts := 0
var _busy := false
var _transformed := false


func _ready() -> void:
	stage = LabStage.new()
	add_child(stage)
	_build_ui()
	_refresh_rig()
	_sync_ui()

	Speech.heard.connect(_on_heard)
	Game.phase_changed.connect(_on_phase_changed)
	Game.debug_action.connect(_on_debug_action)
	stage.chamber.flash_requested.connect(_flash_screen)
	_director = TransformationDirector.new(stage, _banner)
	Audio.play_ambience(true)

	# Re-entering the lab in the TRANSFORMATION phase (the debug jump) still plays out.
	if Game.phase == Game.Phase.TRANSFORMATION:
		_run_transformation()


func _exit_tree() -> void:
	Speech.stop()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	root.add_child(_build_top_bar())

	_dna_log = DnaLog.new()
	_dna_log.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_dna_log.offset_left = -424
	_dna_log.offset_right = -24
	_dna_log.offset_top = 78
	_dna_log.offset_bottom = 350
	root.add_child(_dna_log)

	_word_lab = WordLab.new()
	_word_lab.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_word_lab.offset_left = 24
	_word_lab.offset_right = 1128
	_word_lab.offset_top = -352
	_word_lab.offset_bottom = -24
	_word_lab.pair_selected.connect(_on_pair_selected)
	root.add_child(_word_lab)

	_speech = SpeechPanel.new()
	_speech.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speech.offset_left = -424
	_speech.offset_right = -24
	_speech.offset_top = -462
	_speech.offset_bottom = -24
	_speech.change_requested.connect(_cancel_pending)
	_speech.accepted_by_teacher.connect(func() -> void: _commit(true))
	root.add_child(_speech)

	_banner = UiKit.label(BANNER_TEXT, UiKit.H1, UiKit.ACCENT)
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
	row.add_child(UiKit.label("•", UiKit.H3, UiKit.MUTED))
	row.add_child(UiKit.label(def.display_name if def != null else "-", UiKit.H3, UiKit.TEXT))

	_progress = UiKit.label("", UiKit.BODY, UiKit.GOLD)
	row.add_child(_progress)
	row.add_child(UiKit.expander())

	_skip_button = UiKit.button("Skip", UiKit.SMALL)
	_skip_button.visible = false
	_skip_button.pressed.connect(func() -> void:
		if _director != null:
			_director.request_skip())
	row.add_child(_skip_button)

	var settings := UiKit.button("Teacher", UiKit.SMALL)
	settings.pressed.connect(func() -> void: Game.open_settings())
	row.add_child(settings)

	var quit := UiKit.button("Menu", UiKit.SMALL)
	quit.pressed.connect(func() -> void: Game.set_phase(Game.Phase.TITLE))
	row.add_child(quit)

	return bar


func _sync_ui() -> void:
	if Game.current == null:
		return
	var assigned := _assigned_category()
	var text := "Sentence %d of %d" % [mini(Game.current.slots_filled() + 1, CreatureState.SLOTS), CreatureState.SLOTS]
	if not assigned.is_empty():
		var pair := Content.pair_for_category(assigned)
		text += "  •  use %s" % ("colours" if pair == null else "%s ↔ %s" % [pair.word_a, pair.word_b])
	_progress.text = text

	_dna_log.sync(Game.current)
	_word_lab.set_used(Game.current.used_categories())
	_word_lab.set_restriction(assigned)
	_word_lab.set_locked(not _pending.is_empty() or _busy)
	stage.chamber.set_fill(float(Game.current.slots_filled()) / float(CreatureState.SLOTS), false)


## Guided mode hands the student one pair per sentence instead of the whole board. The
## choice is fixed for the round (seeded from this creature) so it does not shuffle under
## the student between redraws.
func _assigned_category() -> String:
	if Settings.choice_mode != Settings.CHOICE_GUIDED or Game.current == null:
		return ""
	var remaining := PackedStringArray()
	var used := Game.current.used_categories()
	for pair in Content.enabled_pairs():
		if not used.has(pair.category):
			remaining.append(pair.category)
	if not Content.enabled_colors().is_empty() and not used.has(Content.COLOR_CATEGORY):
		remaining.append(Content.COLOR_CATEGORY)
	if remaining.is_empty():
		return ""
	var round_seed: int = absi(("%s%d" % [Game.current.animal_id, Game.current.created_unix]).hash())
	return remaining[(round_seed + Game.current.slots_filled() * 7) % remaining.size()]


## Rebuild the platform animal from the committed "It was" traits plus whatever card is
## currently selected but not yet spoken.
func _refresh_rig() -> void:
	if Game.current == null:
		return
	var pending_traits := {}
	if not _pending.is_empty():
		pending_traits[str(_pending["category"])] = str(_pending["before"])
	stage.set_rig(CreatureFactory.build_lab_animal(Game.current, pending_traits))


# --- Sentence flow -----------------------------------------------------------

func _on_pair_selected(category: String, before: String, after: String) -> void:
	if _busy or not _pending.is_empty() or Game.current == null or Game.current.is_complete():
		return
	_pending = {"category": category, "before": before, "after": after}
	_attempts = 0
	_refresh_rig()
	stage.punch()
	_word_lab.set_locked(true)
	_speech.show_target(before, after)


func _cancel_pending() -> void:
	if _busy or _pending.is_empty():
		return
	_pending = {}
	_attempts = 0
	_refresh_rig()
	_word_lab.set_locked(false)
	_speech.show_idle("Pick another card.")


func _on_heard(alternatives: PackedStringArray, is_final: bool) -> void:
	if not is_final or _busy or _pending.is_empty() or not _speech.is_armed():
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
	var index := Game.current.slots_filled() - 1
	_dna_log.set_slot(index, str(Game.current.entries[index]["sentence"]))
	stage.chamber.set_fill(float(Game.current.slots_filled()) / float(CreatureState.SLOTS))
	Audio.play("success")
	Fx.burst(stage.mount, Vector3(0, 0.4, 0), "sparkle", UiKit.OK, 1.6)
	_speech.show_success()
	# The rig is NOT rebuilt here: the BEFORE word is already applied, and the AFTER word
	# must not appear until the chamber runs.
	_finish_sentence()


func _finish_sentence() -> void:
	await get_tree().create_timer(SUCCESS_PAUSE).timeout
	_busy = false
	if Game.current != null and Game.current.is_complete():
		Game.set_phase(Game.Phase.TRANSFORMATION)
	else:
		_word_lab.set_locked(false)
		_speech.show_idle("Choose your next card.")
		_sync_ui()


# --- Transformation ----------------------------------------------------------

func _on_phase_changed(next: int, _previous: int) -> void:
	if next == Game.Phase.TRANSFORMATION:
		_run_transformation()


func _on_debug_action(action: String) -> void:
	match action:
		"skip_transform":
			if _director != null:
				_director.request_skip()
		"auto_answer":
			if not _pending.is_empty():
				Speech.submit_typed(GrammarValidator.expected_sentence(
					str(_pending["before"]), str(_pending["after"])))


## The chamber executes all three "Now it is..." instructions at once. The sequence
## itself lives in TransformationDirector; this only decides when it runs and what
## happens after.
func _run_transformation() -> void:
	if _transformed or Game.current == null or _director == null:
		return
	_transformed = true
	_busy = true
	_word_lab.set_locked(true)
	_speech.show_idle("")
	_skip_button.visible = true
	await _director.run(Game.current)
	# Leaving the lab mid-sequence is legal; only advance if we are still the live scene.
	if is_inside_tree() and Game.phase == Game.Phase.TRANSFORMATION:
		Game.set_phase(Game.Phase.NAMING)


func _flash_screen(strength: float) -> void:
	_flash.color = Color(1, 1, 1, clampf(strength, 0.0, 1.0))
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.8)
