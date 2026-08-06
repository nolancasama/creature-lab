class_name SpeechBackend
extends RefCounted
## Interface every recognition source implements. Gameplay only ever sees this shape,
## so swapping typed input for Web Speech - or for a Whisper GDExtension later - touches
## nothing above SpeechService.

## Recognisers return ranked alternatives; all of them are forwarded so a young learner's
## accent gets more than one chance at a match.
signal transcript(alternatives: PackedStringArray, is_final: bool)
signal listening_changed(is_listening: bool)
signal failed(reason: String)

var listening := false


func backend_id() -> String:
	return "none"


## Human-readable label for the mic button.
func display_name() -> String:
	return "Unavailable"


func is_supported() -> bool:
	return false


func start() -> void:
	pass


func stop() -> void:
	pass


## Typed backends receive text from the UI; microphone backends ignore this.
func submit(_text: String) -> void:
	pass


func cleanup() -> void:
	pass
