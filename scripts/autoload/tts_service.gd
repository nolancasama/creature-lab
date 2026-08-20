extends Node
## Text-to-speech via the platform voice (Windows SAPI, macOS, Android, and the Web
## Speech API on HTML5 exports). Used to model a sentence for a student who is stuck,
## and to read Word Lab cards aloud.

signal finished

var _voice_id := ""
var _available := false


func _ready() -> void:
	_pick_voice()


func _pick_voice() -> void:
	var voices: Array = DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		voices = DisplayServer.tts_get_voices_for_language("en_US")
	if voices.is_empty():
		voices = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return
	_voice_id = str(voices[0])
	_available = true


func available() -> bool:
	# Web speech voices are populated asynchronously. An empty list during _ready() is not
	# a permanent failure, so retry whenever UI or gameplay is about to use speech.
	if not _available:
		_pick_voice()
	return _available and Settings.tts_enabled


## `rate` below 1.0 is the classroom default: slow enough for a beginner to copy.
func speak(text: String, rate := 0.85) -> void:
	if not available() or text.strip_edges().is_empty():
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, _voice_id, 50, 1.0, clampf(rate, 0.1, 2.0))


func stop() -> void:
	if _available:
		DisplayServer.tts_stop()
