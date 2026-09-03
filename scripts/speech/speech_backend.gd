class_name SpeechBackend
extends RefCounted
## Browser-recognition interface. Every callback carries the session that created the
## recogniser, so an old JavaScript object can never answer a new classroom prompt.

signal browser_started(session_id: int)
signal interim(session_id: int, alternatives: PackedStringArray, confidences: PackedFloat32Array)
signal final(session_id: int, alternatives: PackedStringArray, confidences: PackedFloat32Array)
signal error(session_id: int, reason: String)
signal no_match(session_id: int)
signal browser_ended(session_id: int)


func backend_id() -> String:
	return "none"


## Human-readable label for the mic button.
func display_name() -> String:
	return "利用できません"


func is_supported() -> bool:
	return false


func start(_session_id: int) -> void:
	pass


func stop(_session_id: int) -> void:
	pass


func abort(_session_id: int) -> void:
	pass


func cleanup() -> void:
	pass
