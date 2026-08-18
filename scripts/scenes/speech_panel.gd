class_name SpeechPanel
extends PanelContainer
## Where the student actually speaks, and where a student who is stuck gets help.
##
## The specs described only the success path. In a classroom the failure path is the one
## that decides whether a child keeps going, so this panel implements a scaffold ladder:
## retry, then tell them which half was heard, then model the sentence aloud, and finally
## let the teacher accept it. Nothing here can dead-end a lesson.
##
## Hidden until there is something to say - show_idle() turns it off, show_target() turns
## it on - so it appears the moment a card is picked and disappears the moment the sentence
## is done, rather than sitting on screen empty between turns.

signal accepted_by_teacher()
signal change_requested()

const HELP_AFTER_MODEL := 2 ## Failed attempts before the sentence is read aloud.
const HELP_AFTER_OVERRIDE := 3 ## Failed attempts before the teacher override appears.
const MIC_ICON := preload("res://ui/mic.svg")
const MIC_IDLE := "Tap to speak  (Space)"
const MIC_LISTENING := "Listening...  tap to stop"
const LISTEN_TIMEOUT := 10.0 ## Seconds before an unanswered microphone closes itself.
const HEADER_HEIGHT := 34
const LISTEN_WIDTH := 96

var _sentence_label: RichTextLabel = null
var _feedback: Label = null
var _mic_button: Button = null
var _entry: LineEdit = null
var _listen_button: Button = null
var _listen_timer: Timer = null
var _override_button: Button = null
var _cancel_label: Button = null

var _before := ""
var _after := ""
var _armed := false
var _clause := GrammarValidator.CLAUSE_BOTH


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.06, 0.1, 0.16, 0.94), 16, 2, UiKit.PANEL_HI))
	_build()
	Speech.listening_changed.connect(_on_listening_changed)
	Speech.backend_changed.connect(func(_id: String) -> void: _sync_input_mode())
	show_idle()


func _build() -> void:
	var column := UiKit.vbox(8)
	add_child(column)

	# A plain hbox would centre the title only when Listen is hidden, and shift it every
	# time Listen appears. Anchoring both inside one Control keeps the title on the panel's
	# centre line whatever else is in the row.
	var header := Control.new()
	header.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	column.add_child(header)

	var title := UiKit.label("SAY IT", UiKit.H3, UiKit.ACCENT)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	_listen_button = UiKit.button("Listen", UiKit.SMALL)
	_listen_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_listen_button.offset_left = -LISTEN_WIDTH
	_listen_button.offset_right = 0
	_listen_button.offset_top = 0
	_listen_button.offset_bottom = HEADER_HEIGHT
	_listen_button.pressed.connect(func() -> void: Tts.speak(_target_sentence()))
	header.add_child(_listen_button)

	# No expander below the sentence any more: the panel is sized to hug its content now
	# (SAY_IT_HEIGHT in animal_selection.gd), so a flexible gap here would just be empty
	# space with nothing to fill. The vbox's own separation is the only gap left.
	_sentence_label = UiKit.rich("", UiKit.H2)
	_sentence_label.custom_minimum_size = Vector2(0, 60)
	column.add_child(_sentence_label)

	_entry = UiKit.line_edit("Type the sentence, then press Enter")
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.text_submitted.connect(func(text: String) -> void: _submit_typed(text))
	column.add_child(_entry)

	_feedback = UiKit.label("", UiKit.BODY, UiKit.MUTED)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(0, 36)
	column.add_child(_feedback)

	_mic_button = UiKit.button(MIC_IDLE, UiKit.H3, true)
	UiKit.style_button(_mic_button, UiKit.CTA, true) ## The call-to-action colour, not the
	## ambient ACCENT the "true" flag would otherwise apply - _on_listening_changed()
	## switches it to OK while actually listening and back to this otherwise.
	_mic_button.icon = MIC_ICON
	_mic_button.custom_minimum_size = Vector2(0, 60)
	_mic_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_button.add_theme_constant_override("h_separation", 10)
	_mic_button.pressed.connect(_on_mic_pressed)
	column.add_child(_mic_button)

	# Text, not a button: cancelling is a minor, low-stakes escape hatch, not an action
	# that deserves the mic button's visual weight. Still a real Button underneath (flat,
	# no stylebox override) so it keeps a normal click target and hover feedback without
	# looking like one.
	_cancel_label = Button.new()
	_cancel_label.text = "Cancel"
	_cancel_label.flat = true
	_cancel_label.focus_mode = Control.FOCUS_NONE
	_cancel_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel_label.add_theme_font_size_override("font_size", UiKit.SMALL)
	_cancel_label.add_theme_color_override("font_color", UiKit.MUTED)
	_cancel_label.add_theme_color_override("font_hover_color", UiKit.TEXT)
	_cancel_label.add_theme_color_override("font_pressed_color", UiKit.TEXT)
	_cancel_label.pressed.connect(func() -> void:
		Audio.play("click")
		change_requested.emit())
	column.add_child(_cancel_label)

	# An open microphone with no way out is the failure mode of tap-to-talk: a child who
	# taps and then says nothing would otherwise sit in front of a listening button for
	# ever. This closes the session and says so in words they can act on.
	_listen_timer = Timer.new()
	_listen_timer.one_shot = true
	_listen_timer.wait_time = LISTEN_TIMEOUT
	_listen_timer.timeout.connect(_on_listen_timeout)
	add_child(_listen_timer)

	_override_button = UiKit.button("That was right - accept it", UiKit.SMALL)
	_override_button.visible = false
	_override_button.pressed.connect(func() -> void:
		Audio.play("success")
		accepted_by_teacher.emit())
	column.add_child(_override_button)

	# Last child regardless of what is visible above it, so Cancel (or the override button,
	# on the rare round that reaches it) never sits flush against the panel's bottom edge.
	column.add_child(UiKit.spacer(16))

	_sync_input_mode()


func _sync_input_mode() -> void:
	var mic := Speech.uses_microphone()
	_mic_button.visible = mic
	_entry.visible = not mic


# --- Public API --------------------------------------------------------------

## Hides the panel entirely: nothing to say means nothing to show.
func show_idle(message := "") -> void:
	_armed = false
	_before = ""
	_after = ""
	visible = false
	_sentence_label.text = "[center][color=#93a6bf]Choose a word card.[/color][/center]"
	_feedback.text = message
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_override_button.visible = false
	_listen_button.visible = false
	_cancel_label.visible = false
	_set_input_enabled(false)


func show_target(before: String, after: String, clause := GrammarValidator.CLAUSE_BOTH) -> void:
	_before = before
	_after = after
	_clause = clause
	_armed = true
	visible = true
	_sentence_label.text = _prompt_text()
	if Speech.uses_microphone():
		_feedback.text = "" ## The mic button carries the instruction now.
	else:
		_feedback.text = "Type the sentence." if Settings.past_only() else "Type the whole sentence."
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_override_button.visible = false
	_listen_button.visible = Tts.available() and Settings.prompt_mode != Settings.PROMPT_HIDDEN
	# The present-tense pass has nothing to cancel back to: the pairing was fixed during
	# the past pass that came before it, not a fresh choice made here.
	_cancel_label.visible = clause != GrammarValidator.CLAUSE_PRESENT
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


func show_success() -> void:
	_armed = false
	_feedback.text = "Yes!  %s" % _target_sentence()
	_feedback.add_theme_color_override("font_color", UiKit.OK)
	_override_button.visible = false
	_cancel_label.visible = false
	_set_input_enabled(false)


## The scaffold ladder. `attempts` is how many times this sentence has now failed.
func show_failure(result: Dictionary, attempts: int) -> void:
	_feedback.text = _message_for(result)
	_feedback.add_theme_color_override("font_color", UiKit.BAD if attempts < HELP_AFTER_MODEL else UiKit.GOLD)
	Audio.play("fail")

	if attempts >= HELP_AFTER_MODEL:
		# Stop asking and start showing: say the sentence for them.
		_sentence_label.text = _sentence_bbcode(_target_sentence())
		Tts.speak(_target_sentence(), 0.75)
	if attempts >= HELP_AFTER_OVERRIDE:
		_override_button.visible = true
		_feedback.text += "  A teacher can accept it below."

	_entry.clear()
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


func is_armed() -> bool:
	return _armed


# --- Internals ---------------------------------------------------------------

func _target_sentence() -> String:
	if _before.is_empty():
		return ""
	match _clause:
		GrammarValidator.CLAUSE_PAST:
			return CreatureState.past_sentence_for(_before)
		GrammarValidator.CLAUSE_PRESENT:
			return CreatureState.present_sentence_for(_after)
	return CreatureState.sentence_for(_before, _after)


func _prompt_text() -> String:
	if Settings.prompt_mode == Settings.PROMPT_HIDDEN:
		return "[center][color=#93a6bf]Say your sentence.[/color][/center]"
	if Settings.prompt_mode == Settings.PROMPT_GAPPED:
		match _clause:
			GrammarValidator.CLAUSE_PAST:
				return _sentence_bbcode("It was ____ .")
			GrammarValidator.CLAUSE_PRESENT:
				return _sentence_bbcode("Now it is ____ .")
		return _sentence_bbcode("It was ____ . Now it is ____ .")
	return _sentence_bbcode(_target_sentence())


func _sentence_bbcode(text: String) -> String:
	return "[center][b]%s[/b][/center]" % text


func _set_input_enabled(enabled: bool) -> void:
	_mic_button.disabled = not enabled
	_entry.editable = enabled


## Typed answers go through SpeechService like everything else, so there is exactly one
## path from "the student produced words" to "the grammar was judged".
func _submit_typed(text: String) -> void:
	if not _armed or text.strip_edges().is_empty():
		return
	_entry.clear()
	Speech.submit_typed(text)


## One tap starts listening, a second calls it off. Holding a button down while speaking
## is a lot to ask of a six-year-old who is also trying to remember a sentence.
func _on_mic_pressed() -> void:
	if not _armed:
		return
	if Speech.is_listening():
		Speech.cancel()
		_feedback.text = ""
		_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	else:
		Speech.start()


func _on_listen_timeout() -> void:
	if not Speech.is_listening():
		return
	Speech.cancel()
	_feedback.text = "I didn't hear anything. Tap the button and try again."
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)


func _on_listening_changed(listening: bool) -> void:
	if not Speech.uses_microphone():
		return
	if listening:
		_listen_timer.start()
	else:
		_listen_timer.stop()
	_mic_button.text = MIC_LISTENING if listening else MIC_IDLE
	UiKit.style_button(_mic_button, UiKit.OK if listening else UiKit.CTA, true)


func _unhandled_input(event: InputEvent) -> void:
	if not _armed or not Speech.uses_microphone():
		return
	if event.is_action_pressed("push_to_talk"):
		_on_mic_pressed()
		get_viewport().set_input_as_handled()


## Child-facing wording for each validator reason. The validator returns codes; the
## classroom voice lives here.
func _message_for(result: Dictionary) -> String:
	var heard := str(result.get("normalized", ""))
	match str(result.get("reason", "")):
		"empty":
			return "I didn't hear anything. Try again!"
		"nothing":
			return "Try again - I heard \"%s\"." % heard
		"no_after":
			return "Good start! I heard \"It was %s\". Now say: Now it is %s." % [_before, _after]
		"no_before":
			return "Almost! Start with: It was %s..." % _before
		"swapped":
			return "Nearly - say the OLD word first: It was %s. Now it is %s." % [_before, _after]
		"said_before", "frame_before":
			return "Remember the whole frame: It was %s." % _before
		"said_after":
			return "Remember the whole frame: Now it is %s." % _after
		"frame_after":
			return "Remember the second half: Now it is %s." % _after
		"exact":
			return "So close! Say just the sentence: %s" % _target_sentence()
	return "Try again!"
