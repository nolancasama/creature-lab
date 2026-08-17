extends Node
## Every sound in the game is synthesised at startup, so the project ships with no audio
## files. Swap `_build_library()` for streamed assets later without touching callers.

const MIX_RATE := 22050
const VOICES := 8

var _library := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambience: AudioStreamPlayer = null


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Master"
	add_child(_ambience)
	_build_library()


func play(sound: String, pitch := 1.0) -> void:
	var stream: AudioStream = _library.get(sound, null)
	if stream == null or Settings.sfx_volume <= 0.001:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = linear_to_db(clampf(Settings.sfx_volume, 0.0, 1.0))
	player.play()


func play_ambience(on: bool) -> void:
	if not on or Settings.music_volume <= 0.001:
		_ambience.stop()
		return
	_ambience.stream = _library.get("ambience", null)
	_ambience.volume_db = linear_to_db(clampf(Settings.music_volume * 0.5, 0.001, 1.0))
	_ambience.play()


func _build_library() -> void:
	_library["click"] = _blip(660.0, 660.0, 0.05, 0.6)
	_library["select"] = _blip(520.0, 780.0, 0.12, 0.5)
	_library["success"] = _arpeggio([523.25, 659.25, 783.99], 0.11)
	_library["fail"] = _blip(300.0, 190.0, 0.28, 0.45)
	_library["charge"] = _blip(180.0, 900.0, 0.55, 0.35)
	_library["transform"] = _noise_sweep(1.4)
	_library["reveal"] = _arpeggio([392.0, 523.25, 659.25, 1046.5], 0.16)
	_library["pop"] = _blip(880.0, 440.0, 0.09, 0.5)
	_library["ambience"] = _drone([110.0, 164.81, 220.0], 4.0)
	# Cartoon transformation sounds: a rising glide for taffy stretch, a falling one
	# for the accordion squish, a quick zip for a retracting leg, a soft thud for
	# landing on stubby ones.
	_library["stretch"] = _blip(210.0, 760.0, 1.10, 0.30)
	_library["squish"] = _blip(700.0, 170.0, 0.55, 0.34)
	_library["zip"] = _blip(880.0, 330.0, 0.14, 0.42)
	_library["thud"] = _blip(150.0, 62.0, 0.26, 0.55)
	# A long airy sag for muscles deflating - the "pffft" the design asks for.
	_library["deflate"] = _blip(540.0, 85.0, 0.72, 0.30)
	_library["clang"] = _clang()
	_library["boing"] = _boing()
	_library["puff"] = _blip(340.0, 620.0, 0.34, 0.18)


## A decaying sine that glides from one pitch to another - the workhorse UI sound.
func _blip(from_hz: float, to_hz: float, seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var hz: float = lerpf(from_hz, to_hz, t)
		phase += TAU * hz / float(MIX_RATE)
		var envelope: float = pow(1.0 - t, 2.2)
		samples[i] = sin(phase) * envelope * gain
	return _to_wav(samples)


func _arpeggio(notes: Array, note_seconds: float) -> AudioStreamWAV:
	var per := int(MIX_RATE * note_seconds)
	var samples := PackedFloat32Array()
	samples.resize(per * notes.size())
	var index := 0
	for n in notes:
		var phase := 0.0
		for i in per:
			var t := float(i) / float(per)
			phase += TAU * float(n) / float(MIX_RATE)
			# Slight overlap-free decay keeps the notes distinct without clicks.
			samples[index] = sin(phase) * pow(1.0 - t, 1.6) * 0.42
			index += 1
	return _to_wav(samples)


func _noise_sweep(seconds: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var phase := 0.0
	var filtered := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(90.0, 620.0, t * t) / float(MIX_RATE)
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.25)
		var envelope: float = sin(PI * t)
		samples[i] = (sin(phase) * 0.55 + filtered * 0.45) * envelope * 0.5
	return _to_wav(samples)


## A soft looping chord for the laboratory. Loop points make it seamless.
func _drone(notes: Array, seconds: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var value := 0.0
		for n in notes:
			value += sin(TAU * float(n) * t)
		# Gentle tremolo so the pad breathes instead of buzzing.
		samples[i] = value / float(notes.size()) * 0.3 * (0.85 + 0.15 * sin(TAU * 0.12 * t))
	var wav := _to_wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count - 1
	return wav


## A metallic hit: inharmonic partials, so it rings rather than sounding like a note.
func _clang() -> AudioStreamWAV:
	var count := int(MIX_RATE * 0.85)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var partials := [1.0, 2.76, 5.40, 8.93, 13.34]
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var progress := float(i) / float(count)
		var value := 0.0
		for p_index in partials.size():
			var ratio: float = partials[p_index]
			# Higher partials die away first, which is what makes metal sound like metal.
			var decay: float = exp(-t * (5.0 + ratio * 2.2))
			value += sin(TAU * 320.0 * ratio * t) * decay / float(p_index + 2)
		samples[i] = clampf(value, -1.0, 1.0) * 0.55 * pow(1.0 - progress, 0.4)
	return _to_wav(samples)


## A springy rebound: pitch wobbles as it decays.
func _boing() -> AudioStreamWAV:
	var count := int(MIX_RATE * 0.55)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var hz: float = lerpf(520.0, 190.0, t) * (1.0 + sin(t * TAU * 5.0) * 0.22)
		phase += TAU * hz / float(MIX_RATE)
		samples[i] = sin(phase) * pow(1.0 - t, 1.8) * 0.45
	return _to_wav(samples)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
