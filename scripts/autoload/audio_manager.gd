extends Node
## Every sound in the game is synthesised at startup, so the project ships with no audio
## files. Swap `_build_library()` for streamed assets later without touching callers.

const MIX_RATE := 22050
const VOICES := 8

var _library := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambience: AudioStreamPlayer = null
var _animal_player: AudioStreamPlayer = null ## Exclusive: rapid browsing never layers calls.


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Master"
	add_child(_ambience)
	_animal_player = AudioStreamPlayer.new()
	_animal_player.bus = "Master"
	add_child(_animal_player)
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


## Animal previews share one dedicated voice. A new focused animal always replaces the
## old call, so spinning through the carousel cannot build a wall of overlapping sounds.
func play_animal_call(sound: String, pitch := 1.0) -> void:
	if _animal_player == null:
		return
	_animal_player.stop()
	var stream: AudioStream = _library.get(sound, null)
	if stream == null or Settings.sfx_volume <= 0.001:
		return
	_animal_player.stream = stream
	_animal_player.pitch_scale = pitch
	_animal_player.volume_db = linear_to_db(clampf(Settings.sfx_volume, 0.0, 1.0))
	_animal_player.play()


func stop_animal_call() -> void:
	if _animal_player != null:
		_animal_player.stop()


func has_sound(sound: String) -> bool:
	return _library.has(sound)


## The old laboratory drone read as a persistent hum, so ambience is deliberately silent.
## Keep the API in place for existing scene calls; sound effects and speech are unaffected.
func play_ambience(_on: bool) -> void:
	if _ambience != null:
		_ambience.stop()


func _build_library() -> void:
	_library["click"] = _blip(660.0, 660.0, 0.05, 0.6)
	_library["select"] = _blip(520.0, 780.0, 0.12, 0.5)
	_library["success"] = _arpeggio([523.25, 659.25, 783.99], 0.11)
	_library["fail"] = _blip(300.0, 190.0, 0.28, 0.45)
	_library["charge"] = _blip(180.0, 900.0, 0.55, 0.35)
	_library["transform"] = _noise_sweep(1.4)
	_library["reveal"] = _arpeggio([392.0, 523.25, 659.25, 1046.5], 0.16)
	_library["pop"] = _blip(880.0, 440.0, 0.09, 0.5)
	# Cartoon transformation sounds: a rising glide for taffy stretch, a falling one
	# for the accordion squish, a quick zip for a retracting leg, a soft thud for
	# landing on stubby ones.
	_library["stretch"] = _blip(210.0, 760.0, 1.10, 0.30)
	_library["squish"] = _blip(700.0, 170.0, 0.55, 0.34)
	_library["zip"] = _blip(880.0, 330.0, 0.14, 0.42)
	_library["thud"] = _blip(150.0, 62.0, 0.26, 0.55)
	# A long airy sag for muscles deflating - the "pffft" the design asks for.
	_library["deflate"] = _blip(540.0, 85.0, 0.72, 0.30)
	# A tiny, deliberately unimpressive squeak for WEAK's failed arm flex.
	_library["weak"] = _blip(520.0, 690.0, 0.16, 0.20)
	_library["clang"] = _clang()
	_library["boing"] = _boing()
	_library["puff"] = _blip(340.0, 620.0, 0.34, 0.18)
	# FAST's arc run. Short and airy on purpose: the dashes already fire "zip" often, and
	# anything heavier turns an energetic animal into an annoying one.
	_library["whoosh"] = _noise_sweep(0.28)
	_library["baby"] = _coo()
	_library["elder"] = _chuckle()

	# Friendly, deliberately stylised animal voices. They are short vocal gestures rather
	# than realistic field recordings, which keeps the picker playful and classroom-safe.
	_library["dog_call"] = _animal_voice([
		{"from": 330.0, "to": 190.0, "seconds": 0.18, "gap": 0.03}], 0.34, 0.20)
	_library["dog_confirm"] = _animal_voice([
		{"from": 350.0, "to": 185.0, "seconds": 0.19, "gap": 0.07},
		{"from": 390.0, "to": 220.0, "seconds": 0.16, "gap": 0.02}], 0.37, 0.20)
	_library["cat_call"] = _animal_voice([
		{"from": 520.0, "to": 760.0, "seconds": 0.20, "gap": 0.0},
		{"from": 760.0, "to": 430.0, "seconds": 0.27, "gap": 0.02}], 0.27, 0.04)
	_library["cat_confirm"] = _animal_voice([
		{"from": 480.0, "to": 820.0, "seconds": 0.24, "gap": 0.0},
		{"from": 820.0, "to": 390.0, "seconds": 0.34, "gap": 0.02}], 0.30, 0.04)
	_library["tiger_call"] = _animal_voice([
		{"from": 155.0, "to": 94.0, "seconds": 0.56, "gap": 0.02}], 0.30, 0.34)
	_library["tiger_confirm"] = _animal_voice([
		{"from": 170.0, "to": 82.0, "seconds": 0.78, "gap": 0.03}], 0.35, 0.38)
	_library["horse_call"] = _animal_voice([
		{"from": 360.0, "to": 710.0, "seconds": 0.25, "gap": 0.0},
		{"from": 700.0, "to": 330.0, "seconds": 0.28, "gap": 0.02}], 0.29, 0.11)
	_library["horse_confirm"] = _animal_voice([
		{"from": 330.0, "to": 790.0, "seconds": 0.31, "gap": 0.0},
		{"from": 780.0, "to": 300.0, "seconds": 0.38, "gap": 0.02}], 0.32, 0.12)
	_library["deer_call"] = _animal_voice([
		{"from": 510.0, "to": 680.0, "seconds": 0.17, "gap": 0.02}], 0.18, 0.03)
	_library["deer_confirm"] = _animal_voice([
		{"from": 500.0, "to": 710.0, "seconds": 0.19, "gap": 0.06},
		{"from": 620.0, "to": 760.0, "seconds": 0.14, "gap": 0.02}], 0.20, 0.03)
	_library["penguin_call"] = _animal_voice([
		{"from": 720.0, "to": 980.0, "seconds": 0.12, "gap": 0.04},
		{"from": 850.0, "to": 1080.0, "seconds": 0.11, "gap": 0.02}], 0.24, 0.05)
	_library["penguin_confirm"] = _animal_voice([
		{"from": 690.0, "to": 1030.0, "seconds": 0.13, "gap": 0.04},
		{"from": 780.0, "to": 1160.0, "seconds": 0.13, "gap": 0.04},
		{"from": 900.0, "to": 1080.0, "seconds": 0.11, "gap": 0.02}], 0.27, 0.05)
	_library["chicken_call"] = _animal_voice([
		{"from": 520.0, "to": 310.0, "seconds": 0.10, "gap": 0.05},
		{"from": 480.0, "to": 280.0, "seconds": 0.10, "gap": 0.02}], 0.25, 0.14)
	_library["chicken_confirm"] = _animal_voice([
		{"from": 560.0, "to": 300.0, "seconds": 0.11, "gap": 0.045},
		{"from": 520.0, "to": 270.0, "seconds": 0.11, "gap": 0.045},
		{"from": 600.0, "to": 330.0, "seconds": 0.13, "gap": 0.02}], 0.29, 0.15)


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


## Build a compact voiced call from pitch gestures. A small filtered-noise component
## distinguishes a bark/roar/cluck from the clean musical UI blips, while rounded syllable
## envelopes and conservative gain keep every call friendly rather than startling.
func _animal_voice(syllables: Array, gain: float, roughness: float) -> AudioStreamWAV:
	var total := 0
	for syllable in syllables:
		total += int(MIX_RATE * (float(syllable.get("seconds", 0.1))
			+ float(syllable.get("gap", 0.0))))
	var samples := PackedFloat32Array()
	samples.resize(maxi(total, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260821 + syllables.size() * 97 + int(gain * 1000.0)
	var index := 0
	var filtered_noise := 0.0
	for syllable in syllables:
		var count := maxi(int(MIX_RATE * float(syllable.get("seconds", 0.1))), 1)
		var phase := 0.0
		for i in count:
			var t := float(i) / float(count)
			var hz := lerpf(float(syllable.get("from", 440.0)),
				float(syllable.get("to", 440.0)), smoothstep(0.0, 1.0, t))
			hz *= 1.0 + sin(TAU * 7.0 * t) * 0.018
			phase += TAU * hz / float(MIX_RATE)
			filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.22)
			var voiced := sin(phase) * 0.72 + sin(phase * 2.0) * 0.20 \
				+ sin(phase * 3.0) * 0.08
			var envelope := pow(sin(PI * t), 0.72)
			samples[index] = (voiced * (1.0 - roughness)
				+ filtered_noise * roughness) * envelope * gain
			index += 1
		index += int(MIX_RATE * float(syllable.get("gap", 0.0)))
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


## The YOUNG cue: two short rising chirps, the second a little higher than the first, with
## a light vibrato. Deliberately a playful squeak rather than anything resembling an infant
## crying - this fires every time a student turns a creature young, so it has to stay
## welcome on the twentieth hearing in a classroom. Kept brief and quiet for the same
## reason: it greets the change, it does not announce it.
func _coo() -> AudioStreamWAV:
	var syllables := [
		{"from": 620.0, "to": 880.0, "seconds": 0.11},
		{"from": 780.0, "to": 1080.0, "seconds": 0.13},
	]
	var gap := int(MIX_RATE * 0.035)
	var total := gap
	for s in syllables:
		total += int(MIX_RATE * float(s["seconds"])) + gap
	var samples := PackedFloat32Array()
	samples.resize(total)
	var index := gap ## A beat of silence first, so it never clips the tap that caused it.
	for s in syllables:
		var count := int(MIX_RATE * float(s["seconds"]))
		var phase := 0.0
		for i in count:
			var t := float(i) / float(count)
			# Vibrato is what makes it read as a voice rather than a UI beep.
			var hz: float = lerpf(float(s["from"]), float(s["to"]), sqrt(t)) \
				* (1.0 + sin(t * TAU * 7.0) * 0.035)
			phase += TAU * hz / float(MIX_RATE)
			# Rounded in and out: a hard attack on a high sine is what stings the ear.
			var envelope: float = sin(PI * t)
			# A quiet second harmonic softens the tone without muddying it.
			samples[index] = (sin(phase) * 0.82 + sin(phase * 2.0) * 0.18) * envelope * 0.30
			index += 1
		index += gap
	return _to_wav(samples)


## The OLD cue: three short low notes, each a touch lower than the last - a contented
## "heh heh heh" rather than a word. Deliberately warm and low: the brief asks for old and
## wise, not sick, so there is no rasp, no wobble at the end and no falling sigh, all of
## which read as unwell rather than amused.
func _chuckle() -> AudioStreamWAV:
	var notes := [196.0, 185.0, 174.0]
	var per := int(MIX_RATE * 0.095)
	var gap := int(MIX_RATE * 0.045)
	var samples := PackedFloat32Array()
	samples.resize((per + gap) * notes.size())
	var index := 0
	for n in notes:
		var phase := 0.0
		for i in per:
			var t := float(i) / float(per)
			phase += TAU * float(n) / float(MIX_RATE)
			# Rounded either side so each note is a soft "heh" rather than a click, and a
			# little third harmonic for a chesty rather than a thin tone.
			var envelope: float = sin(PI * t)
			samples[index] = (sin(phase) * 0.75 + sin(phase * 3.0) * 0.25) * envelope * 0.26
			index += 1
		index += gap
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
