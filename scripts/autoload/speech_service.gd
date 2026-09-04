class_name SpeechService
extends Node
## Owns the current SpeechSession and converts browser callbacks into one classified
## attempt. Gameplay never reasons about callback order, and the classifier never sees
## browser state.

signal attempt_completed(result: Dictionary)
signal session_state_changed(session_id: int, state: int, restart_queued: bool)
signal session_capture_started(session_id: int)
signal session_capture_finished(session_id: int, tail_seconds: float, discard: bool)
signal transcript_observed(session_id: int, alternatives: PackedStringArray, is_final: bool)
signal backend_changed(backend_id: String)

const INTERIM_RECORDING_TAIL := 0.7
const FALLBACK_ERRORS := ["not-allowed", "service-not-allowed", "unsupported", "audio-capture"]

var backend: SpeechBackend = null
var active_session: SpeechSession = null

var _next_session_id := 0
var _target_before := ""
var _target_after := ""
var _target_tolerance := GrammarValidator.HEAR_LENIENT
var _target_clause := GrammarValidator.CLAUSE_BOTH
var _target_configured := false
var _fallback_after_session := false


func _ready() -> void:
	select_backend()


## Real recognition when the platform can do it and the teacher wants it; typed input
## otherwise. Typed mode is also the deterministic fallback for a refused microphone.
func select_backend() -> void:
	if active_session != null and active_session.is_active():
		cancel()
	if backend != null:
		backend.cleanup()

	var chosen: SpeechBackend = null
	if Settings.stt_enabled:
		var web := WebSpeechBackend.new()
		if web.is_supported():
			chosen = web
	if chosen == null:
		chosen = TypedSpeechBackend.new()
	_set_backend(chosen)


## The harness installs a passive backend and injects the same callbacks the browser uses.
## This tests ordering and stale IDs without pretending Chrome Web Speech exists on desktop.
func install_backend_for_test(candidate: SpeechBackend) -> void:
	if backend != null:
		backend.cleanup()
	active_session = null
	_fallback_after_session = false
	_set_backend(candidate)


func _set_backend(candidate: SpeechBackend) -> void:
	backend = candidate
	backend.browser_started.connect(_on_browser_started)
	backend.interim.connect(_on_interim)
	backend.final.connect(_on_final)
	backend.error.connect(_on_error)
	backend.no_match.connect(_on_no_match)
	backend.speech_ended.connect(_on_speech_ended)
	backend.browser_ended.connect(_on_browser_ended)
	backend_changed.emit(backend.backend_id())


func configure_attempt(before: String, after: String, tolerance: int, clause: int) -> void:
	_target_before = before
	_target_after = after
	_target_tolerance = tolerance
	_target_clause = clause
	_target_configured = true


func clear_attempt() -> void:
	cancel()
	_target_configured = false
	_target_before = ""
	_target_after = ""


func mode() -> String:
	return backend.backend_id() if backend != null else "none"


func uses_microphone() -> bool:
	return mode() == "web"


func prompt_label() -> String:
	return backend.display_name() if backend != null else "利用できません"


func session_state() -> int:
	return active_session.state if active_session != null else SpeechSession.State.IDLE


func is_listening() -> bool:
	return active_session != null and active_session.state == SpeechSession.State.LISTENING


func is_active() -> bool:
	return active_session != null and active_session.is_active()


func start() -> int:
	if active_session != null and active_session.state == SpeechSession.State.FINISHING:
		if active_session.queue_restart():
			_log_event(active_session.session_id, "restart_queued")
			_emit_state(active_session)
		return active_session.session_id
	if active_session != null and active_session.state in [
			SpeechSession.State.STARTING, SpeechSession.State.LISTENING,
			SpeechSession.State.CHECKING]:
		return active_session.session_id
	if not _target_configured or backend == null:
		Diagnostics.note("[speech]", "start refused: no active target or backend")
		return -1

	_next_session_id += 1
	active_session = SpeechSession.new(_next_session_id, _target_before, _target_after,
		_target_tolerance, _target_clause)
	active_session.request_start(Time.get_ticks_msec())
	_fallback_after_session = false
	# A modelled sentence can still be speaking when the retry button becomes available.
	# Stop it before either microphone consumer opens, or the game grades its own voice.
	Tts.stop()
	_log_event(active_session.session_id, "start_requested")
	_emit_state(active_session)
	session_capture_started.emit(active_session.session_id)
	backend.start(active_session.session_id)
	return active_session.session_id


func toggle() -> void:
	if active_session == null:
		start()
		return
	match active_session.state:
		SpeechSession.State.STARTING, SpeechSession.State.LISTENING:
			cancel()
		SpeechSession.State.CHECKING:
			# Ignored, not queued. The student's answer is already on its way to the
			# recogniser; starting another attempt here would race its own result, and
			# queuing one would fire an unwanted recording the moment it lands.
			pass
		SpeechSession.State.FINISHING:
			start() # Queues the tap; onend consumes it.
		_:
			start()


## Cancellation is not an attempt. abort() detaches the abandoned recogniser's handlers,
## while the state and session ID independently reject anything already queued by Chrome.
func cancel() -> void:
	if active_session == null or not active_session.cancel():
		return
	var id := active_session.session_id
	_log_event(id, "cancelled")
	if backend != null:
		backend.abort(id)
	_finish_capture(active_session, 0.0, true)
	_emit_state(active_session)


func stop() -> void:
	cancel()


## The presentation timer reports its intent here; it never paints a second result beside
## the session. A timeout and an onend-without-result are the same neutral uncertainty.
func timeout() -> void:
	if active_session == null or active_session.state not in [
			SpeechSession.State.STARTING, SpeechSession.State.LISTENING]:
		return
	var result := SpeechAttemptClassifier.classify(PackedStringArray(), active_session.before,
		active_session.after, active_session.tolerance, active_session.clause)
	_complete_attempt(active_session, result, "timeout", 0.0, true)
	if backend != null:
		backend.stop(active_session.session_id)


## Typed input shares the language classifier but never enters the microphone state machine.
func submit_typed(text: String) -> void:
	if not _target_configured:
		Diagnostics.note("[speech]", "typed answer refused: no active target")
		return
	var result := SpeechAttemptClassifier.classify(PackedStringArray([text]), _target_before,
		_target_after, _target_tolerance, _target_clause)
	result["session_id"] = 0
	result["source"] = "typed"
	_log_result(0, result)
	attempt_completed.emit(result)


func _on_browser_started(session_id: int) -> void:
	if not _is_current(session_id, "start"):
		return
	if not active_session.browser_started(Time.get_ticks_msec()):
		_log_ignored(session_id, "start")
		return
	_log_event(session_id, "browser_started")
	if Settings.speech_log:
		Diagnostics.note("[speech]", "session=%d timing tap_to_start_ms=%d" % [
			session_id, active_session.browser_start_msec - active_session.tap_msec])
	_emit_state(active_session)


func _on_interim(session_id: int, alternatives: PackedStringArray,
		_confidences: PackedFloat32Array) -> void:
	if not _is_current(session_id, "interim"):
		return
	if active_session.result_produced or active_session.state not in [
			SpeechSession.State.STARTING, SpeechSession.State.LISTENING,
			SpeechSession.State.CHECKING]:
		_log_ignored(session_id, "interim")
		return
	transcript_observed.emit(session_id, alternatives, false)
	var strong_pass := SpeechAttemptClassifier.is_strong_pass(alternatives,
		active_session.before, active_session.after, active_session.tolerance,
		active_session.clause)
	if Settings.speech_log:
		Diagnostics.note("[speech]", "session=%d interim strong_pass=%s alts=%s" % [
			session_id, strong_pass, alternatives])
	if not strong_pass:
		return
	var result := SpeechAttemptClassifier.classify(alternatives, active_session.before,
		active_session.after, active_session.tolerance, active_session.clause)
	_complete_attempt(active_session, result, "interim", INTERIM_RECORDING_TAIL, false)
	if backend != null:
		backend.stop(session_id)


func _on_final(session_id: int, alternatives: PackedStringArray,
		_confidences: PackedFloat32Array) -> void:
	if not _is_current(session_id, "final"):
		return
	if active_session.result_produced or active_session.state not in [
			SpeechSession.State.STARTING, SpeechSession.State.LISTENING,
			SpeechSession.State.CHECKING]:
		_log_ignored(session_id, "final")
		return
	transcript_observed.emit(session_id, alternatives, true)
	if Settings.speech_log:
		Diagnostics.note("[speech]", "session=%d final alts=%s" % [session_id, alternatives])
	var result := SpeechAttemptClassifier.classify(alternatives, active_session.before,
		active_session.after, active_session.tolerance, active_session.clause)
	_complete_attempt(active_session, result, "final", 0.0,
		int(result["outcome"]) in [SpeechAttemptClassifier.Outcome.UNCERTAIN,
			SpeechAttemptClassifier.Outcome.TECHNICAL_ERROR])
	if backend != null:
		backend.stop(session_id)


func _on_error(session_id: int, reason: String) -> void:
	if not _is_current(session_id, "error"):
		return
	if active_session.result_produced:
		_log_ignored(session_id, "error")
		return
	Diagnostics.note("[speech]", "session=%d browser_error=%s" % [session_id, reason])
	_fallback_after_session = reason in FALLBACK_ERRORS
	_complete_attempt(active_session, SpeechAttemptClassifier.technical_error(reason),
		"error", 0.0, true)
	if backend != null:
		backend.stop(session_id)


func _on_no_match(session_id: int) -> void:
	if not _is_current(session_id, "nomatch") or active_session.result_produced:
		return
	var result := SpeechAttemptClassifier.classify(PackedStringArray(), active_session.before,
		active_session.after, active_session.tolerance, active_session.clause)
	_complete_attempt(active_session, result, "nomatch", 0.0, true)
	if backend != null:
		backend.stop(session_id)


## Chrome heard the student stop talking; the transcript is still in flight. Nothing about
## the attempt has been decided, so this only moves the state - which is what shuts the
## microphone to taps and puts "checking" on screen for the length of the round trip.
func _on_speech_ended(session_id: int) -> void:
	if not _is_current(session_id, "speechend"):
		return
	if not active_session.speech_ended():
		return
	_log_event(session_id, "speech_end")
	_emit_state(active_session)


func _on_browser_ended(session_id: int) -> void:
	if not _is_current(session_id, "end"):
		return
	_log_event(session_id, "browser_end")
	if not active_session.result_produced and active_session.state in [
			SpeechSession.State.STARTING, SpeechSession.State.LISTENING,
			SpeechSession.State.CHECKING]:
		var result := SpeechAttemptClassifier.classify(PackedStringArray(), active_session.before,
			active_session.after, active_session.tolerance, active_session.clause)
		_complete_attempt(active_session, result, "end", 0.0, true)
	var restart := active_session.queued_restart
	if not active_session.browser_ended():
		_log_ignored(session_id, "end")
		return
	_emit_state(active_session)
	if _fallback_after_session:
		Settings.stt_enabled = false
		select_backend()
		return
	if restart and _target_configured:
		start()


func _complete_attempt(session: SpeechSession, result: Dictionary, source: String,
		tail_seconds: float, discard: bool) -> void:
	var now := Time.get_ticks_msec()
	if not session.begin_result(source, now):
		_log_ignored(session.session_id, source)
		return
	result["session_id"] = session.session_id
	result["source"] = source
	_emit_state(session)
	_finish_capture(session, tail_seconds, discard)
	_log_result(session.session_id, result)
	attempt_completed.emit(result)
	if source == "final" and Settings.speech_log:
		var start_to_final := session.final_msec - session.browser_start_msec \
			if session.browser_start_msec > 0 else -1
		Diagnostics.note("[speech]", "session=%d timing start_to_final_ms=%d final_to_ui_ms=%d" % [
			session.session_id, start_to_final, Time.get_ticks_msec() - session.final_msec])


func _finish_capture(session: SpeechSession, tail_seconds: float, discard: bool) -> void:
	if session.capture_finished:
		return
	session.capture_finished = true
	session_capture_finished.emit(session.session_id, tail_seconds, discard)


func _is_current(session_id: int, kind: String) -> bool:
	if active_session != null and active_session.session_id == session_id:
		return true
	var active_id := active_session.session_id if active_session != null else -1
	Diagnostics.note("[speech]", "session=%d ignored_stale_callback=%s active=%d" % [
		session_id, kind, active_id])
	return false


func _log_ignored(session_id: int, kind: String) -> void:
	if Settings.speech_log:
		Diagnostics.note("[speech]", "session=%d ignored_callback=%s state=%s" % [
			session_id, kind, SpeechSession.State.keys()[active_session.state]])


func _log_event(session_id: int, event: String) -> void:
	Diagnostics.note("[speech]", "session=%d %s" % [session_id, event])


func _log_result(session_id: int, result: Dictionary) -> void:
	Diagnostics.note("[speech]", "session=%d result=%s" % [session_id,
		SpeechAttemptClassifier.outcome_name(int(result["outcome"]))])
	if Settings.speech_log and result.has("candidates"):
		Diagnostics.note("[speech]", "session=%d candidates=%s" % [
			session_id, result["candidates"]])


func _emit_state(session: SpeechSession) -> void:
	session_state_changed.emit(session.session_id, session.state, session.queued_restart)
