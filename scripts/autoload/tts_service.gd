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
	var voices: Array = []
	for language in TargetLanguage.tts_voice_languages():
		voices = DisplayServer.tts_get_voices_for_language(language)
		if not voices.is_empty():
			break
	if voices.is_empty():
		voices = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return
	_voice_id = str(voices[0])
	_available = true


func reconfigure_language() -> void:
	stop()
	_voice_id = ""
	_available = false
	_pick_voice()


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


## Repeat one word as a decaying echo.
##
## Deliberately does NOT call tts_stop() first, unlike speak(): these are queued behind
## whatever is still being said rather than cutting it off. A real echo overlaps its source
## and the platform gives no way to mix two utterances, so this leans on the other two
## controls instead - each repeat is quieter, lower and slower than the last, which reads as
## an echo even though the repeats are strictly sequential.
func echo(text: String, repeats := 3) -> void:
	if not available() or text.strip_edges().is_empty():
		return
	for i in repeats:
		var falloff := pow(0.55, float(i))
		DisplayServer.tts_speak(text, _voice_id, int(clampf(46.0 * falloff, 4.0, 100.0)),
			clampf(0.9 - float(i) * 0.16, 0.1, 2.0),
			clampf(0.78 - float(i) * 0.11, 0.1, 2.0))


func stop() -> void:
	if _available:
		DisplayServer.tts_stop()
