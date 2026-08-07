class_name SpeechPanel
extends PanelContainer
## Where the student actually speaks, and where a student who is stuck gets help.
##
## The specs described only the success path. In a classroom the failure path is the one
## that decides whether a child keeps going, so this panel implements a scaffold ladder:
## retry, then tell them which half was heard, then model the sentence aloud, and finally
## let the teacher accept it. Nothing here can dead-end a lesson.

signal accepted_by_teacher()
signal change_requested()

const HELP_AFTER_MODEL := 2 ## Failed attempts before the sentence is read aloud.
const HELP_AFTER_OVERRIDE := 3 ## Failed attempts before the teacher override appears.

var _sentence_label: RichTextLabel = null
var _chips: HBoxContainer = null
var _feedback: Label = null
var _mic_button: Button = null
var _entry: LineEdit = null
var _listen_button: Button = null
var _change_button: Button = null
var _override_button: Button = null

var _before := ""
var _after := ""
var _armed := false


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.06, 0.1, 0.16, 0.94), 16, 2, UiKit.PANEL_HI))
	_build()
	Speech.listening_changed.connect(_on_listening_changed)
	Speech.backend_changed.connect(func(_id: String) -> void: _sync_input_mode())
	show_idle()


func _build() -> void:
	var column := UiKit.vbox(8)
	add_child(column)

	var header := UiKit.hbox(8)
	column.add_child(header)
	header.add_child(UiKit.label("SAY IT", UiKit.H3, UiKit.ACCENT))
	header.add_child(UiKit.expander())
	_listen_button = UiKit.button("Listen", UiKit.SMALL)
	_listen_button.pressed.connect(func() -> void: Tts.speak(_target_sentence()))
	header.add_child(_listen_button)
	_change_button = UiKit.button("Change card", UiKit.SMALL)
	_change_button.pressed.connect(func() -> void:
		Audio.play("click")
		change_requested.emit())
	header.add_child(_change_button)

	_sentence_label = UiKit.rich("", UiKit.H2)
	_sentence_label.custom_minimum_size = Vector2(0, 104)
	column.add_child(_sentence_label)

	_chips = UiKit.hbox(8)
	column.add_child(_chips)

	var input_row := UiKit.hbox(8)
	column.add_child(input_row)

	_entry = UiKit.line_edit("Type the sentence, then press Enter")
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.text_submitted.connect(func(text: String) -> void: _submit_typed(text))
	input_row.add_child(_entry)

	_mic_button = UiKit.button("", UiKit.H3, true)
	_mic_button.custom_minimum_size = Vector2(230, 52)
	_mic_button.button_down.connect(_on_mic_down)
	_mic_button.button_up.connect(_on_mic_up)
	input_row.add_child(_mic_button)

	_feedback = UiKit.label("", UiKit.BODY, UiKit.MUTED)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(0, 44)
	column.add_child(_feedback)

	_override_button = UiKit.button("That was right - accept it", UiKit.SMALL)
	_override_button.visible = false
	_override_button.pressed.connect(func() -> void:
		Audio.play("success")
		accepted_by_teacher.emit())
	column.add_child(_override_button)

	_sync_input_mode()


func _sync_input_mode() -> void:
	var mic := Speech.uses_microphone()
	_mic_button.visible = mic
	_entry.visible = not mic
	_mic_button.text = "Hold to speak  (Space)"


# --- Public API --------------------------------------------------------------

func show_idle(message := "") -> void:
	_armed = false
	_before = ""
	_after = ""
	_sentence_label.text = "[center][color=#93a6bf]Choose a word card.[/color][/center]"
	_set_chips([])
	_feedback.text = message
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_override_button.visible = false
	_change_button.visible = false
	_listen_button.visible = false
	_set_input_enabled(false)


func show_target(before: String, after: String) -> void:
	_before = before
	_after = after
	_armed = true
	_sentence_label.text = _prompt_text()
	_set_chips([before, after])
	_feedback.text = "Read it out loud." if Speech.uses_microphone() else "Type the whole sentence."
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_override_button.visible = false
	_change_button.visible = true
	_listen_button.visible = Tts.available() and Settings.prompt_mode != Settings.PROMPT_HIDDEN
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


func show_success() -> void:
	_armed = false
	_feedback.text = "Yes!  %s" % _target_sentence()
	_feedback.add_theme_color_override("font_color", UiKit.OK)
	_override_button.visible = false
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
	return CreatureState.sentence_for(_before, _after)


func _prompt_text() -> String:
	if Settings.prompt_mode == Settings.PROMPT_HIDDEN:
		return "[center][color=#93a6bf]Say your sentence.[/color][/center]"
	if Settings.prompt_mode == Settings.PROMPT_GAPPED:
		return _sentence_bbcode("It was ____ . Now it is ____ .")
	return _sentence_bbcode(_target_sentence())


func _sentence_bbcode(text: String) -> String:
	return "[center][b]%s[/b][/center]" % text


## The two words always stay visible as chips, even when the frame is hidden: the child
## needs to know which words they picked, not be tested on remembering them.
func _set_chips(words: Array) -> void:
	for child in _chips.get_children():
		child.queue_free()
	if words.is_empty():
		return
	_chips.add_child(_chip("was", str(words[0])))
	_chips.add_child(UiKit.label("->", UiKit.H3, UiKit.MUTED))
	_chips.add_child(_chip("now", str(words[1])))
	_chips.add_child(UiKit.expander())


func _chip(tag: String, word: String) -> Control:
	var tint := Content.color_of(word, UiKit.PANEL_HI) if Content.is_color_word(word) else UiKit.PANEL_HI
	var chip := UiKit.panel(tint, 10)
	var row := UiKit.hbox(6)
	chip.add_child(row)
	var text_color := UiKit.TEXT
	if Content.is_color_word(word):
		var def := Content.color_def(word)
		if def != null:
			text_color = def.label_color()
	row.add_child(UiKit.label(tag, UiKit.SMALL, text_color))
	row.add_child(UiKit.label(word, UiKit.H3, text_color))
	return chip


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


func _on_mic_down() -> void:
	if _armed:
		Speech.start()


func _on_mic_up() -> void:
	Speech.stop()


func _on_listening_changed(listening: bool) -> void:
	if not Speech.uses_microphone():
		return
	_mic_button.text = "Listening..." if listening else "Hold to speak  (Space)"
	UiKit.style_button(_mic_button, UiKit.OK if listening else UiKit.ACCENT, true)


func _unhandled_input(event: InputEvent) -> void:
	if not _armed or not Speech.uses_microphone():
		return
	if event.is_action_pressed("push_to_talk"):
		Speech.start()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("push_to_talk"):
		Speech.stop()
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
		"frame_before":
			return "Remember the whole frame: It was %s." % _before
		"frame_after":
			return "Remember the second half: Now it is %s." % _after
		"exact":
			return "So close! Say just the sentence: %s" % _target_sentence()
	return "Try again!"
