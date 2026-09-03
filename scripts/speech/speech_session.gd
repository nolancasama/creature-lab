class_name SpeechSession
extends RefCounted
## One microphone press, from the tap until the browser recogniser has ended.
##
## Browser callbacks are deliberately not treated as state. They are inputs to this
## machine, and only legal transitions are accepted. That distinction is what prevents a
## late final or duplicate onend from turning into a second classroom attempt.

enum State {
	IDLE,
	STARTING,
	LISTENING,
	FINISHING,
	COMPLETE,
	CANCELLED,
}

var session_id: int
var state := State.IDLE
var result_produced := false
var queued_restart := false
var capture_finished := false
var saw_final := false
var accepted_interim := false
var explicit_error := false
var tap_msec := 0
var browser_start_msec := 0
var final_msec := 0

var before: String
var after: String
var tolerance: int
var clause: int


func _init(id: int, target_before: String, target_after: String,
		target_tolerance: int, target_clause: int) -> void:
	session_id = id
	before = target_before
	after = target_after
	tolerance = target_tolerance
	clause = target_clause


func request_start(now_msec: int) -> bool:
	if state != State.IDLE:
		return false
	state = State.STARTING
	tap_msec = now_msec
	return true


func browser_started(now_msec: int) -> bool:
	if state != State.STARTING:
		return false
	state = State.LISTENING
	browser_start_msec = now_msec
	return true


func begin_result(source: String, now_msec: int) -> bool:
	if result_produced or state not in [State.STARTING, State.LISTENING]:
		return false
	result_produced = true
	saw_final = source == "final"
	accepted_interim = source == "interim"
	explicit_error = source == "error"
	if saw_final:
		final_msec = now_msec
	state = State.FINISHING
	return true


func queue_restart() -> bool:
	if state != State.FINISHING:
		return false
	queued_restart = true
	return true


func browser_ended() -> bool:
	if state not in [State.STARTING, State.LISTENING, State.FINISHING]:
		return false
	state = State.COMPLETE
	return true


func cancel() -> bool:
	if state not in [State.STARTING, State.LISTENING]:
		return false
	state = State.CANCELLED
	queued_restart = false
	return true


func is_active() -> bool:
	return state in [State.STARTING, State.LISTENING, State.FINISHING]
