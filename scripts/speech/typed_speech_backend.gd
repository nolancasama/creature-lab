class_name TypedSpeechBackend
extends SpeechBackend
## Keyboard input standing in for a microphone.
##
## Not a debug-only feature: classroom PCs often have no working mic, and a teacher may
## want a written round. It is also the fallback whenever real recognition is
## unavailable, which is why the whole game can be played without a microphone.


func backend_id() -> String:
	return "typed"


func display_name() -> String:
	return "文を入力"


func is_supported() -> bool:
	return true


func start() -> void:
	listening = true
	listening_changed.emit(true)


func stop() -> void:
	listening = false
	listening_changed.emit(false)


func submit(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	transcript.emit(PackedStringArray([text]), PackedFloat32Array([-1.0]), true)
	stop()
