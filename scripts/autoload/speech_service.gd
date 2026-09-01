extends Node
## The only speech-related thing gameplay is allowed to talk to.
##
## Picks a backend at runtime, forwards its transcripts, and knows nothing about
## grammar - validation is a separate stage so recognisers can be swapped freely.

signal heard(alternatives: PackedStringArray, confidences: PackedFloat32Array, is_final: bool)
signal listening_changed(is_listening: bool)
signal backend_changed(backend_id: String)
signal failed(reason: String)

var backend: SpeechBackend = null
var _cancelled := false ## Drops the transcript from a session the student called off.
var _context_phrases := PackedStringArray()


func _ready() -> void:
	select_backend()


## Real recognition when the platform can do it and the teacher wants it; typed input
## otherwise. Typed is never merely a fallback - see TypedSpeechBackend.
func select_backend() -> void:
	if backend != null:
		backend.cleanup()
		backend = null

	var chosen: SpeechBackend = null
	if Settings.stt_enabled:
		var web := WebSpeechBackend.new()
		if web.is_supported():
			chosen = web
	if chosen == null:
		chosen = TypedSpeechBackend.new()

	backend = chosen
	backend.transcript.connect(_on_transcript)
	backend.listening_changed.connect(_on_listening_changed)
	backend.failed.connect(_on_failed)
	backend.set_context(_context_phrases)
	backend_changed.emit(backend.backend_id())


func mode() -> String:
	return backend.backend_id() if backend != null else "none"


func uses_microphone() -> bool:
	return mode() == "web"


func prompt_label() -> String:
	return backend.display_name() if backend != null else "利用できません"


func is_listening() -> bool:
	return backend != null and backend.listening


func start() -> void:
	if backend != null:
		_cancelled = false
		backend.start()


func stop() -> void:
	if backend != null:
		backend.stop()


func set_context(phrases: PackedStringArray) -> void:
	_context_phrases = phrases.duplicate()
	if backend != null:
		backend.set_context(_context_phrases)


func biasing_status() -> Dictionary:
	return backend.biasing_status() if backend != null else {"available": false, "applied": false}


## Stop listening and throw away whatever this session was about to report. A student who
## taps the button a second time has changed their mind, not answered wrongly, so the
## transcript must not reach the validator and be counted as a failed attempt - a
## recogniser will still deliver a final result after being told to stop.
func cancel() -> void:
	if backend == null:
		return
	_cancelled = true
	backend.stop()


func submit_typed(text: String) -> void:
	if backend != null:
		_cancelled = false ## Typing is its own answer; an earlier cancel must not eat it.
		backend.submit(text)


func _on_transcript(alternatives: PackedStringArray, confidences: PackedFloat32Array,
		is_final: bool) -> void:
	# Printed because the spoken path cannot be observed anywhere but a browser, and this is
	# the first place it can silently end: a transcript arriving after a cancel is dropped
	# here and the student sees nothing happen at all. Godot's print reaches the browser
	# console in a web export.
	Diagnostics.note("[speech]", "transcript final=%s cancelled=%s alts=%s confidence=%s"
		% [is_final, _cancelled, alternatives, confidences])
	if _cancelled:
		return
	heard.emit(alternatives, confidences, is_final)


func _on_listening_changed(value: bool) -> void:
	listening_changed.emit(value)


func _on_failed(reason: String) -> void:
	failed.emit(reason)
	# A recogniser-side silence is an uncertain attempt, not a language failure. Route an
	# empty final through the same evaluation path so the scene can show its neutral retry.
	if reason == "no-speech" and not _cancelled:
		heard.emit(PackedStringArray(), PackedFloat32Array(), true)
	# A browser that denies the microphone must not dead-end the lesson.
	if reason in ["not-allowed", "service-not-allowed", "unsupported", "audio-capture"]:
		Settings.stt_enabled = false
		select_backend()
