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
const SPEAKER_ICON := preload("res://ui/speaker.svg")
const MIC_IDLE := "タップして話す（スペース）"
const MIC_LISTENING := "聞いています… タップで停止"
const LISTEN_TIMEOUT := 10.0 ## Seconds before an unanswered microphone closes itself.

var _sentence_label: RichTextLabel = null
var _feedback: Label = null
var _mic_button: Button = null
var _entry: LineEdit = null
var _input_shell: Control = null
var _submit_button: Button = null
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

	# Two expanders, not a fixed spacer, so the sentence and input block remain centred
	# however much slack the panel actually has.
	column.add_child(UiKit.expander())

	var sentence_row := UiKit.hbox(8)
	sentence_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sentence_row.custom_minimum_size = Vector2(0, 38)
	column.add_child(sentence_row)

	_sentence_label = UiKit.rich("", UiKit.H2)
	_sentence_label.custom_minimum_size = Vector2(0, 38)
	# Hugs its own text so the speaker button sits beside the sentence rather than out at
	# the panel edge, and the pair centres in the row as one group.
	#
	# Wrapping has to be off for that. A RichTextLabel reports a minimum width of zero, so
	# with wrapping on it shrinks to nothing here and puts one letter per line - which then
	# stretches the row tall enough to turn the Listen button into a vertical bar. With
	# wrapping off its minimum is the width of the sentence, which is what shrink-to-fit
	# needs. These sentences are one short clause each and fit the console comfortably.
	_sentence_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sentence_label.fit_content = true
	_sentence_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sentence_row.add_child(_sentence_label)

	_listen_button = UiKit.button("", UiKit.SMALL)
	_listen_button.icon = SPEAKER_ICON
	_listen_button.tooltip_text = "文をきく"
	_listen_button.custom_minimum_size = Vector2(52, 52)
	UiKit.style_secondary(_listen_button)
	_listen_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER ## Never a full-height bar.
	# A theme constant on Button, not a property - assigning it directly fails at runtime
	# and leaves the icon at its full size.
	_listen_button.add_theme_constant_override("icon_max_width", 24)
	_listen_button.pressed.connect(func() -> void: Tts.speak(_target_sentence()))
	sentence_row.add_child(_listen_button)

	column.add_child(UiKit.expander())

	_input_shell = Control.new()
	_input_shell.custom_minimum_size = Vector2(0, 64)
	_input_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_input_shell)
	_entry = UiKit.line_edit("英語の文を入力")
	_entry.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_entry_for_embedded_submit()
	_entry.text_submitted.connect(func(text: String) -> void: _submit_typed(text))
	_entry.text_changed.connect(func(text: String) -> void:
		if _submit_button != null:
			_submit_button.disabled = not _armed or text.strip_edges().is_empty())
	_input_shell.add_child(_entry)
	_submit_button = UiKit.button("✓", UiKit.H3)
	_submit_button.name = "TypedSubmit"
	_submit_button.tooltip_text = "確認"
	_submit_button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_submit_button.offset_left = -58
	_submit_button.offset_right = -6
	_submit_button.offset_top = -26
	_submit_button.offset_bottom = 26
	_submit_button.custom_minimum_size = Vector2(52, 52)
	_style_embedded_submit()
	_submit_button.pressed.connect(func() -> void: _submit_typed(_entry.text))
	_input_shell.add_child(_submit_button)

	_feedback = UiKit.label("", UiKit.BODY, UiKit.MUTED)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(0, 36)
	column.add_child(_feedback)

	_mic_button = UiKit.button(MIC_IDLE, UiKit.H3, true)
	UiKit.style_primary(_mic_button) ## The call-to-action colour, not the
	## ambient ACCENT the "true" flag would otherwise apply - _on_listening_changed()
	## switches it to OK while actually listening and back to this otherwise.
	_mic_button.icon = MIC_ICON
	_mic_button.custom_minimum_size = Vector2(0, 60)
	_mic_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_button.add_theme_constant_override("h_separation", 10)
	_mic_button.pressed.connect(_on_mic_pressed)
	column.add_child(_mic_button)

	# A quiet outlined action: subordinate to Confirm/Talk, but visibly tappable and
	# keyboard-focusable rather than text that happens to react to a click.
	_cancel_label = UiKit.button("キャンセル", UiKit.H3)
	UiKit.style_secondary(_cancel_label)
	_cancel_label.custom_minimum_size = Vector2(170, 52)
	_cancel_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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

	_override_button = UiKit.button("正しく言えました － 先生が承認", UiKit.SMALL)
	_override_button.custom_minimum_size.y = 52
	UiKit.style_secondary(_override_button)
	_override_button.visible = false
	_override_button.pressed.connect(func() -> void:
		Audio.play("success")
		accepted_by_teacher.emit())
	column.add_child(_override_button)

	# Last child regardless of what is visible above it, so Cancel (or the override button,
	# on the rare round that reaches it) never sits flush against the panel's bottom edge.
	column.add_child(UiKit.spacer(16))

	_sync_input_mode()


func _style_entry_for_embedded_submit() -> void:
	# Reserve the right side of the field for the check button so typed text and the caret
	# can never run underneath it.
	var normal := UiKit.stylebox(Color("#0b1220"), 10, 2, UiKit.PANEL_HI, 12)
	normal.content_margin_right = 72
	var focus := UiKit.stylebox(Color("#0b1220"), 10, 3, UiKit.GOLD, 12)
	focus.content_margin_right = 72
	var read_only := UiKit.stylebox(Color("#0b1220").darkened(0.16), 10, 2,
		UiKit.LINE, 12)
	read_only.content_margin_right = 72
	_entry.add_theme_stylebox_override("normal", normal)
	_entry.add_theme_stylebox_override("focus", focus)
	_entry.add_theme_stylebox_override("read_only", read_only)


func _style_embedded_submit() -> void:
	# Radius equals half the touch target: every state remains a true circle.
	_submit_button.add_theme_stylebox_override("normal",
		UiKit.stylebox(UiKit.CTA, 26))
	_submit_button.add_theme_stylebox_override("hover",
		UiKit.stylebox(UiKit.CTA.lightened(0.12), 26))
	_submit_button.add_theme_stylebox_override("pressed",
		UiKit.stylebox(UiKit.CTA.darkened(0.16), 26))
	_submit_button.add_theme_stylebox_override("focus",
		UiKit.stylebox(UiKit.CTA, 26, 3, UiKit.GOLD))
	_submit_button.add_theme_stylebox_override("disabled",
		UiKit.stylebox(UiKit.CTA.darkened(0.45), 26))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_submit_button.add_theme_color_override(state, UiKit.INK)
	_submit_button.add_theme_color_override("font_disabled_color", UiKit.MUTED.darkened(0.3))


func _sync_input_mode() -> void:
	var mic := Speech.uses_microphone()
	_mic_button.visible = mic
	_input_shell.visible = not mic


# --- Public API --------------------------------------------------------------

## Hides the panel entirely: nothing to say means nothing to show.
func show_idle(message := "") -> void:
	_armed = false
	_before = ""
	_after = ""
	visible = false
	_sentence_label.text = "[center][color=#93a6bf]単語カードをえらぼう。[/color][/center]"
	_feedback.text = message
	_feedback.visible = not message.is_empty()
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
	# The field or microphone button already makes the required action clear. Keep this row
	# out of the layout until it has useful response feedback to show.
	_feedback.text = ""
	_feedback.visible = false
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_override_button.visible = false
	_listen_button.visible = Tts.available() and Settings.prompt_mode != Settings.PROMPT_HIDDEN
	_cancel_label.visible = true
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


func show_success() -> void:
	_armed = false
	_feedback.text = "できました！  %s" % _target_sentence()
	_feedback.visible = true
	_feedback.add_theme_color_override("font_color", UiKit.OK)
	_override_button.visible = false
	_cancel_label.visible = false
	_set_input_enabled(false)


## The scaffold ladder. `attempts` is how many times this sentence has now failed.
func show_failure(result: Dictionary, attempts: int) -> void:
	_feedback.text = _message_for(result)
	_feedback.visible = true
	_feedback.add_theme_color_override("font_color", UiKit.BAD if attempts < HELP_AFTER_MODEL else UiKit.GOLD)
	Audio.play("fail")

	if attempts >= HELP_AFTER_MODEL:
		# Stop asking and start showing: say the sentence for them.
		_sentence_label.text = _sentence_bbcode(_target_sentence())
		Tts.speak(_target_sentence(), 0.75)
	if attempts >= HELP_AFTER_OVERRIDE:
		_override_button.visible = true
		_feedback.text += "  下のボタンから先生が承認できます。"

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
		return ""
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
	_submit_button.disabled = not enabled or _entry.text.strip_edges().is_empty()


## Typed answers go through SpeechService like everything else, so there is exactly one
## path from "the student produced words" to "the grammar was judged".
func _submit_typed(text: String) -> void:
	if not _armed or text.strip_edges().is_empty():
		return
	_entry.clear()
	_submit_button.disabled = true
	Speech.submit_typed(text)


## One tap starts listening, a second calls it off. Holding a button down while speaking
## is a lot to ask of a six-year-old who is also trying to remember a sentence.
func _on_mic_pressed() -> void:
	if not _armed:
		return
	if Speech.is_listening():
		Speech.cancel()
		_feedback.text = ""
		_feedback.visible = false
		_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	else:
		Speech.start()


func _on_listen_timeout() -> void:
	if not Speech.is_listening():
		return
	Speech.cancel()
	_feedback.text = "声が聞こえませんでした。ボタンをタップして、もう一度ためそう。"
	_feedback.visible = true
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
			return "声が聞こえませんでした。もう一度ためそう！"
		"nothing":
			return "もう一度ためそう。「%s」と聞こえました。" % heard
		"no_after":
			return "いいスタート！「It was %s」と聞こえました。つぎに「Now it is %s」と言おう。" % [_before, _after]
		"no_before":
			return "おしい！「It was %s」からはじめよう。" % _before
		"swapped":
			return "おしい！前の単語から言おう：It was %s. Now it is %s." % [_before, _after]
		"said_before", "frame_before":
			return "文の形をぜんぶ言おう：It was %s." % _before
		"said_after":
			return "文の形をぜんぶ言おう：Now it is %s." % _after
		"frame_after":
			return "後半を言おう：Now it is %s." % _after
		"exact":
			return "あと少し！この文だけを言おう：%s" % _target_sentence()
	return "もう一度ためそう！"
