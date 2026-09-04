class_name SpeechPanel
extends PanelContainer
## Presentation for the current spoken target. Recognition, classification and scaffold
## counting live below and above this control respectively; this node only renders them.
##
## Hidden until there is something to say - show_idle() turns it off, show_target() turns
## it on - so it appears the moment a card is picked and disappears the moment the sentence
## is done, rather than sitting on screen empty between turns.

signal change_requested()

const MIC_ICON := preload("res://ui/mic.svg")
const SPEAKER_ICON := preload("res://ui/speaker.svg")
const MIC_IDLE := "タップして話す"
const MIC_STARTING := "マイクを準備しています… タップで停止"
const MIC_LISTENING := "聞いています… タップで停止"
const MIC_QUEUED := "次のマイクを準備しています…"
## No "tap to stop" on this one: the button is disabled while the answer is being checked.
const MIC_CHECKING := "チェック中…"
## Said in words, above the button, as well as shown on it.
##
## The button already changed colour and caption, but both live ON the control the student
## is about to press, which is the one place they are not looking while they think about
## the sentence. "Is it listening to me right now?" is the question the whole spoken half
## of this game rests on, and it deserves its own line rather than an inference from a
## button's shade.
const STATUS_IDLE := "マイクは とまっています"
const STATUS_STARTING := "マイクを じゅんびしています…"
const STATUS_LISTENING := "● ろくおん中… はなしてください"
const STATUS_QUEUED := "つぎの ろくおんを じゅんびしています…"
## The gap between the student finishing and Chrome answering. Without a line of its own it
## reads as the microphone having missed them, and the next thing they do is press again.
## The dots are appended by _process so the wait visibly moves; "checking", never
## "thinking", because the game is checking their English, not having a think about it.
const STATUS_CHECKING := "チェック中"
const CHECKING_DOT_CYCLE := 0.45 ## Seconds per dot.
const CHECKING_DOTS := 3
const LISTEN_TIMEOUT := 10.0 ## Seconds before an unanswered microphone closes itself.

var _sentence_label: RichTextLabel = null
var _step_counter: Label = null
var _feedback: Label = null
var _mic_button: Button = null
var _status: Label = null
var _entry: LineEdit = null
var _input_shell: Control = null
var _submit_button: Button = null
var _listen_button: Button = null
var _listen_timer: Timer = null
var _cancel_label: Button = null

var _before := ""
var _after := ""
var _category := ""
var _armed := false
var _checking := false
var _checking_clock := 0.0
var _clause := GrammarValidator.CLAUSE_BOTH


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.06, 0.1, 0.16, 0.94), 16, 2, UiKit.PANEL_HI))
	_build()
	Speech.session_state_changed.connect(_on_session_state_changed)
	Speech.backend_changed.connect(func(_id: String) -> void: _sync_input_mode())
	Settings.changed.connect(_on_settings_changed)
	show_idle()


func _build() -> void:
	var column := UiKit.vbox(8)
	add_child(column)

	# Overlay progress without adding another row to this fixed-height panel.
	var step_overlay := Control.new()
	step_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(step_overlay)
	_step_counter = UiKit.label("0 / 7", UiKit.H3, UiKit.ACCENT)
	_step_counter.name = "StepCounter"
	_step_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step_counter.z_index = 1
	# PanelContainer already insets children by its 14 px style margin.
	_step_counter.offset_left = 2
	_step_counter.offset_top = 2
	_step_counter.offset_right = 82
	_step_counter.offset_bottom = 34
	step_overlay.add_child(_step_counter)

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
	_entry = UiKit.line_edit(TargetLanguage.input_placeholder())
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

	_status = UiKit.label(STATUS_IDLE, UiKit.SMALL, UiKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	_mic_button = UiKit.button(MIC_IDLE, UiKit.H3, true)
	UiKit.style_primary(_mic_button) ## The call-to-action colour, not the
	## ambient ACCENT the "true" flag would otherwise apply - the session-state renderer
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


	# Last child regardless of what is visible above it, so the Cancel hint never sits
	# flush against the panel's bottom edge.
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
	# Set here as well as when listening changes: this runs when the panel is built, and a
	# typed round would otherwise show "the microphone is stopped" under its text box until
	# a recogniser it never uses happened to report something.
	if _status != null:
		_status.visible = mic
	if _armed and not mic and _entry != null:
		_entry.grab_focus()


# --- Public API --------------------------------------------------------------

## Hides the panel entirely: nothing to say means nothing to show.
func show_idle(message := "") -> void:
	# A result is on screen; the checking caption must not keep animating over it.
	_checking = false
	_armed = false
	_before = ""
	_after = ""
	_category = ""
	visible = false
	_sentence_label.text = "[center][color=#93a6bf]単語カードをえらぼう。[/color][/center]"
	_feedback.text = message
	_feedback.visible = not message.is_empty()
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_listen_button.visible = false
	_cancel_label.visible = false
	_set_input_enabled(false)


func show_target(before: String, after: String, clause := GrammarValidator.CLAUSE_BOTH,
		completed_steps := 0, category := "") -> void:
	_before = before
	_after = after
	_category = category
	_clause = clause
	_set_completed_steps(completed_steps)
	_armed = true
	visible = true
	_sentence_label.text = _prompt_text()
	# The field or microphone button already makes the required action clear. Keep this row
	# out of the layout until it has useful response feedback to show.
	_feedback.text = ""
	_feedback.visible = false
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_listen_button.visible = Tts.available() and Settings.prompt_mode != Settings.PROMPT_HIDDEN
	_cancel_label.visible = true
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


## The sound and pop begin together; callers await this before closing or advancing.
func show_success(completed_steps: int) -> void:
	# A result is on screen; the checking caption must not keep animating over it.
	_checking = false
	_armed = false
	visible = true
	_feedback.text = "できました！  %s" % _target_sentence()
	_feedback.visible = true
	_feedback.add_theme_color_override("font_color", UiKit.OK)
	_cancel_label.visible = false
	_set_input_enabled(false)
	_set_completed_steps(completed_steps)
	Audio.play("success")
	_step_counter.pivot_offset = _step_counter.size * 0.5
	_step_counter.add_theme_color_override("font_color", UiKit.GOLD)
	var tween := create_tween()
	tween.tween_property(_step_counter, "scale", Vector2.ONE * 1.4, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_step_counter, "scale", Vector2.ONE, 0.23) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	if not is_inside_tree():
		return
	_step_counter.add_theme_color_override("font_color", UiKit.ACCENT)


func _set_completed_steps(completed_steps: int) -> void:
	_step_counter.text = "%d / 7" % clampi(completed_steps, 0, 7)
	_step_counter.scale = Vector2.ONE
	_step_counter.add_theme_color_override("font_color", UiKit.ACCENT)


func show_failure(heard: String, model_sentence: bool) -> void:
	# A result is on screen; the checking caption must not keep animating over it.
	_checking = false
	# Japanese recognition forms may contain kanji the bundled display subset does not.
	# They are evidence for matching, never student-facing copy.
	var show_heard := not TargetLanguage.is_japanese() and not heard.is_empty()
	_feedback.text = "もう一度ためそう！" if not show_heard \
		else "もう一度ためそう。「%s」と聞こえました。" % heard
	_feedback.visible = true
	_feedback.add_theme_color_override("font_color", UiKit.GOLD if model_sentence else UiKit.BAD)
	Audio.play("fail")

	if model_sentence:
		# Stop asking and start showing: say the sentence for them.
		_sentence_label.text = _sentence_bbcode(_target_sentence())
		Tts.speak(_target_sentence(), 0.75)
	_entry.clear()
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


## Silence and inconclusive recognition are microphone uncertainty, not language failure.
## They do not play the fail sound or advance the scaffold ladder.
func show_uncertain() -> void:
	# A result is on screen; the checking caption must not keep animating over it.
	_checking = false
	_feedback.text = "もう一度言ってみよう！"
	_feedback.visible = true
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_entry.clear()
	_set_input_enabled(true)
	if not Speech.uses_microphone():
		_entry.grab_focus()


func show_technical_error(reason: String) -> void:
	# A result is on screen; the checking caption must not keep animating over it.
	_checking = false
	var message := "もう一度言ってみよう！"
	match reason:
		"not-allowed", "service-not-allowed":
			message = "マイクが使えません。ブラウザの設定をかくにんしてね。"
		"audio-capture":
			message = "マイクが見つかりません。せつぞくをかくにんしてね。"
	_feedback.text = message
	_feedback.visible = true
	_feedback.add_theme_color_override("font_color", UiKit.MUTED)
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
	return TargetLanguage.sentence(_category, _before, _after, _clause)


func _prompt_text() -> String:
	if Settings.prompt_mode == Settings.PROMPT_HIDDEN:
		return ""
	if Settings.prompt_mode == Settings.PROMPT_GAPPED:
		return _sentence_bbcode(TargetLanguage.gapped_sentence(_clause))
	return _sentence_bbcode(_target_sentence())


func _on_settings_changed() -> void:
	if _entry != null:
		_entry.placeholder_text = TargetLanguage.input_placeholder()
	if not _armed:
		return
	_sentence_label.text = _prompt_text()
	_listen_button.visible = Tts.available() \
		and Settings.prompt_mode != Settings.PROMPT_HIDDEN


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
	Speech.toggle()


func _on_listen_timeout() -> void:
	if Speech.session_state() not in [SpeechSession.State.STARTING, SpeechSession.State.LISTENING]:
		return
	Speech.timeout()


## Only ever appends to the checking caption, and only while that state is live. Plain
## text rather than a spinner or a shader on purpose: this waits on a network round trip,
## and the indicator must not be the thing that stutters while the browser is busy.
func _process(delta: float) -> void:
	if not _checking or _status == null:
		return
	_checking_clock += delta
	var shown := int(_checking_clock / CHECKING_DOT_CYCLE) % (CHECKING_DOTS + 1)
	_status.text = STATUS_CHECKING + ".".repeat(shown)


func _on_session_state_changed(_session_id: int, state: int, restart_queued: bool) -> void:
	if not Speech.uses_microphone():
		return
	if state in [SpeechSession.State.STARTING, SpeechSession.State.LISTENING]:
		_listen_timer.start()
	else:
		_listen_timer.stop()
	var armed := state in [SpeechSession.State.STARTING, SpeechSession.State.LISTENING] \
		or restart_queued
	if state == SpeechSession.State.CHECKING and not _checking:
		_checking_clock = 0.0
	_checking = state == SpeechSession.State.CHECKING
	# The one state that shuts the button rather than re-labelling it. A tap here would
	# race the result already on its way back, and a six-year-old who thinks nothing
	# happened will press again - which is exactly the case this state exists to prevent.
	_mic_button.disabled = _checking
	match state:
		SpeechSession.State.STARTING:
			_mic_button.text = MIC_STARTING
		SpeechSession.State.LISTENING:
			_mic_button.text = MIC_LISTENING
		SpeechSession.State.CHECKING:
			_mic_button.text = MIC_CHECKING
		SpeechSession.State.FINISHING:
			_mic_button.text = MIC_QUEUED if restart_queued else MIC_IDLE
		_:
			_mic_button.text = MIC_IDLE
	if _status != null:
		match state:
			SpeechSession.State.STARTING:
				_status.text = STATUS_STARTING
			SpeechSession.State.LISTENING:
				_status.text = STATUS_LISTENING
			SpeechSession.State.CHECKING:
				_status.text = STATUS_CHECKING
			SpeechSession.State.FINISHING:
				_status.text = STATUS_QUEUED if restart_queued else STATUS_IDLE
			_:
				_status.text = STATUS_IDLE
		var tone := UiKit.OK if armed else UiKit.MUTED
		_status.add_theme_color_override("font_color", UiKit.GOLD if _checking else tone)
		# Only meaningful when the microphone is the input; a typed round has no state to
		# report and the line would just be noise under the text field.
		_status.visible = Speech.uses_microphone()
	UiKit.style_button(_mic_button, UiKit.OK if armed else UiKit.CTA, true)


func _unhandled_input(event: InputEvent) -> void:
	if not _armed or not Speech.uses_microphone():
		return
	# Space used to open the microphone here. It is a confirm key everywhere else in the
	# game now, and a key that submits an answer on one screen and starts recording on
	# another is worse than a key that does nothing. The microphone is tapped.
	pass
