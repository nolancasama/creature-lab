extends Node
## The only speech-related thing gameplay is allowed to talk to.
##
## Picks a backend at runtime, forwards its transcripts, and knows nothing about
## grammar - validation is a separate stage so recognisers can be swapped freely.

signal heard(alternatives: PackedStringArray, is_final: bool)
signal listening_changed(is_listening: bool)
signal backend_changed(backend_id: String)
signal failed(reason: String)

var backend: SpeechBackend = null


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
	backend_changed.emit(backend.backend_id())


func mode() -> String:
	return backend.backend_id() if backend != null else "none"


func uses_microphone() -> bool:
	return mode() == "web"


func prompt_label() -> String:
	return backend.display_name() if backend != null else "Unavailable"


func is_listening() -> bool:
	return backend != null and backend.listening


func start() -> void:
	if backend != null:
		backend.start()


func stop() -> void:
	if backend != null:
		backend.stop()


func submit_typed(text: String) -> void:
	if backend != null:
		backend.submit(text)


func _on_transcript(alternatives: PackedStringArray, is_final: bool) -> void:
	heard.emit(alternatives, is_final)


func _on_listening_changed(value: bool) -> void:
	listening_changed.emit(value)


func _on_failed(reason: String) -> void:
	failed.emit(reason)
	# A browser that denies the microphone must not dead-end the lesson.
	if reason in ["not-allowed", "service-not-allowed", "unsupported", "audio-capture"]:
		Settings.stt_enabled = false
		select_backend()
