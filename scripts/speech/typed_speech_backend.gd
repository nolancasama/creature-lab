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


func start(session_id: int) -> void:
	browser_started.emit(session_id)


func stop(session_id: int) -> void:
	browser_ended.emit(session_id)


func abort(_session_id: int) -> void:
	pass
