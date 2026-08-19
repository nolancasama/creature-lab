extends Node
## Keeps the student's own voice so the transformation can play it back.
##
## The recogniser only ever hands back text, so the words the student said are gone the
## moment they are understood. This captures the audio alongside it: a second, silent
## consumer of the microphone that starts when the recogniser starts listening and stops
## when it stops, so it records exactly the take that was accepted and nothing else.
##
## It is deliberately incapable of breaking a lesson. Every entry point checks that input
## actually came up, `clip()` returns null when there is nothing, and the caller is
## expected to fall back - a student who typed their answers, or refused the microphone,
## or is on a browser that will not give Godot an input stream, still gets the whole
## sequence with the lab speaking the sentence instead. Nothing here is ever required.
##
## Clips live only for the round. They are never written to disk and never enter
## CreatureState: a save file is a record of what a child said, and a recording of a
## child's voice is a different kind of thing to be keeping.

const CAPTURE_BUS := "VoiceCapture"
const PLAYBACK_BUS := "VoiceLab"
const MAX_SECONDS := 9.0 ## A sentence is three seconds; this is only a runaway guard.
const TRIM_FLOOR := 0.02 ## Below this counts as silence when trimming the lead-in.

var _record: AudioEffectRecord = null
var _mic: AudioStreamPlayer = null
var _player: AudioStreamPlayer = null
var _clips := {} ## slot index -> AudioStreamWAV
var _last: AudioStreamWAV = null
var _armed := false
var _ready_to_record := false
var _stop_guard: SceneTreeTimer = null


func _ready() -> void:
	# Nothing is set up at all unless audio input is switched on for the whole engine, and
	# it is currently switched OFF. On the web export, enabling it makes Godot ask for the
	# microphone while it is still bringing the audio driver up; when that request is
	# pending or refused the output context never starts, and the entire game goes silent -
	# no effects, no speech, nothing - while the recogniser carries on working, because
	# Web Speech does not use Godot's audio at all. That shipped once. Until the capture
	# can be opened after a user gesture instead of during driver init, this stays off and
	# every sentence is spoken by the lab.
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		return
	_ready_to_record = _build_buses()
	if not _ready_to_record:
		push_warning("Voice: no audio input bus; the lab will speak the sentences instead.")
		return
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = CAPTURE_BUS
	# Not started here on purpose: opening the stream is what makes the browser ask for
	# the microphone, and that question belongs to the moment the student taps to speak.
	add_child(_mic)

	_player = AudioStreamPlayer.new()
	_player.bus = PLAYBACK_BUS
	add_child(_player)

	Speech.listening_changed.connect(_on_listening_changed)


## Two buses: one silent one to record from, one with reverb to play back through. The
## capture bus is muted because routing a live microphone to the speakers in a classroom
## of laptops is how you get feedback howl.
func _build_buses() -> bool:
	if AudioServer.get_bus_index(CAPTURE_BUS) == -1:
		AudioServer.add_bus()
		var capture := AudioServer.bus_count - 1
		AudioServer.set_bus_name(capture, CAPTURE_BUS)
		AudioServer.set_bus_mute(capture, true)
		_record = AudioEffectRecord.new()
		AudioServer.add_bus_effect(capture, _record)
	else:
		var existing := AudioServer.get_bus_index(CAPTURE_BUS)
		_record = AudioServer.get_bus_effect(existing, 0) as AudioEffectRecord

	if AudioServer.get_bus_index(PLAYBACK_BUS) == -1:
		AudioServer.add_bus()
		var lab := AudioServer.bus_count - 1
		AudioServer.set_bus_name(lab, PLAYBACK_BUS)
		# The lab-speaker treatment. Wet enough to sound like the room, dry enough that a
		# ten-year-old still hears themselves - the whole point is recognising your own
		# voice, and a heavy effect chain takes that away.
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.72
		reverb.wet = 0.34
		reverb.dry = 0.8
		reverb.spread = 0.6
		AudioServer.add_bus_effect(lab, reverb)
	return _record != null


func available() -> bool:
	return _ready_to_record and _record != null


# --- Capture -----------------------------------------------------------------

func _on_listening_changed(is_listening: bool) -> void:
	if is_listening:
		_start()
	else:
		_stop()


func _start() -> void:
	if not available() or _armed:
		return
	_armed = true
	_last = null
	if _mic != null and not _mic.playing:
		_mic.playing = true
	_record.set_recording_active(true)
	# The recogniser normally closes the session itself, but a browser that never fires
	# its end event would otherwise leave this recording for the rest of the lesson.
	_stop_guard = get_tree().create_timer(MAX_SECONDS)
	_stop_guard.timeout.connect(func() -> void:
		if _armed:
			_stop())


func _stop() -> void:
	if not available() or not _armed:
		return
	_armed = false
	_stop_guard = null
	if _record.is_recording_active():
		_last = _trim(_record.get_recording())
		_record.set_recording_active(false)
	if _mic != null:
		_mic.playing = false ## Let go of the microphone between turns.


## Drops the silence before the student actually started talking. Without this the clip
## begins with however long they spent deciding, and the surge it is meant to trigger
## lands on nothing.
func _trim(clip: AudioStreamWAV) -> AudioStreamWAV:
	if clip == null:
		return null
	var data := clip.data
	if data.is_empty():
		return null
	var stereo := clip.stereo
	var bytes_per_frame := 4 if stereo else 2 ## 16-bit samples.
	if clip.format != AudioStreamWAV.FORMAT_16_BITS:
		return clip ## Only the 16-bit case is worth hand-trimming; anything else plays as is.
	var frames := data.size() / bytes_per_frame
	var first := 0
	for i in frames:
		var sample := data.decode_s16(i * bytes_per_frame) / 32768.0
		if absf(sample) > TRIM_FLOOR:
			first = maxi(i - int(clip.mix_rate * 0.08), 0) ## Keep a breath of lead-in.
			break
	if first <= 0:
		return clip
	var trimmed := AudioStreamWAV.new()
	trimmed.format = clip.format
	trimmed.mix_rate = clip.mix_rate
	trimmed.stereo = stereo
	trimmed.data = data.slice(first * bytes_per_frame)
	return trimmed


# --- Storage -----------------------------------------------------------------

## Called when a sentence is accepted, so the clip that is kept is the take that passed
## rather than whatever was said last.
func keep_for(slot: int) -> void:
	if _last == null or slot < 0:
		return
	_clips[slot] = _last
	_last = null


func clip(slot: int) -> AudioStreamWAV:
	return _clips.get(slot, null)


func has_clip(slot: int) -> bool:
	return _clips.has(slot)


## True while the sentence is playing, so the sequence can wait for the student's own
## voice to finish rather than talking over it.
func playing() -> bool:
	return _player != null and _player.playing


## Returns the clip's length in seconds, or 0.0 when there is nothing to play - which is
## the caller's cue to speak the sentence instead.
func play(slot: int) -> float:
	var wav: AudioStreamWAV = clip(slot)
	if wav == null or _player == null:
		return 0.0
	_player.stream = wav
	_player.play()
	return wav.get_length()


func stop() -> void:
	if _player != null:
		_player.stop()


## A new creature starts with no voice. Called when a round begins or is abandoned, so
## one child's recording can never turn up in the next child's transformation.
func clear() -> void:
	_clips.clear()
	_last = null
	stop()
