class_name TransformationDirector
extends RefCounted
## Plays the one beat the whole design is built around: the "It was..." animal becomes the
## "Now it is..." creature.
##
## Everything up to this point has been the past tense; everything after it is the
## present. Split out of LabController because it is a sequence, not a rule - and because
## a teacher must be able to skip it without unpicking the state machine.
##
## It happens ON THE PLATFORM. The animal used to walk across the room into a glass
## chamber, which took the subject away from the spot the student had been watching all
## round and then put glass between them and it. Now the machine comes down to the animal
## and the transformation happens where it has been standing the whole time, which is the
## single thing that makes the sequence easy to follow.
##
## The three sentences drive it, in the student's own voice where there is one: Voice
## captures each accepted take, and the machine surges on the sentence the student
## actually said. Where there is not one - they typed their answers, or the microphone was
## refused, or the browser would not give Godot an input stream - the lab speaks the
## sentence instead and the beat is otherwise identical. The fallback is not a degraded
## path; for a typed classroom it is the only path, and it has to look deliberate.

## Roughly how long a spoken sentence needs before its surge lands. The whole sequence is
## three of these plus the peak and the reveal, and it is the payoff for a whole round -
## but it is also dead time for anyone watching it a second time, so each beat is trimmed
## to about as long as the sentence actually takes to say and no longer.
const BEAT_SPEAK := 1.9
const MAX_BEAT := 6.0 ## A runaway recording must not hold the whole sequence open.
## Long enough to actually look at what the sentence built. The reveal used to cut away
## almost as soon as it landed, which made the payoff of a whole round feel like a
## transition rather than the end of one.
const REVEAL_HOLD := 3.6

## The anticipation beat, immediately before the last sentence: everything stops, the lab
## holds its breath, and the machine sits charged over a silent animal. Costs a few seconds
## once per round, at the only point where the round is about to pay off.
const FINAL_PAUSE := 2.6
const PAUSE_PUSH := 0.55 ## How far the camera creeps in during it, as a fraction of _spread().
## The last word of the last sentence, thrown back by the chamber. Three repeats is where it
## stops reading as emphasis and starts reading as a room.
const ECHO_REPEATS := 3
const ECHO_GAP := 0.62

## The music, and the three levels it moves between.
##
## It starts on the LAST sentence rather than at a measured countdown, because there is no
## way to know in advance when the sequence will end: each beat waits for however long the
## student actually took to say their line. Starting on the final beat puts it roughly seven
## and a half seconds ahead of the finished creature - the last sentence, its surge, the
## trait settling, then the peak - and, more usefully, it always lands on the same BEAT
## whatever the pacing, which a stopwatch could not do.
##
## MUSIC_UNDER is deliberately far down. The student's own recorded voice plays over it, and
## a bed that competes with a six-year-old saying "It was small" has defeated the point of
## recording them.
const MUSIC_TRACK := "transformation"
const MUSIC_UNDER := 0.22 ## Beneath the speech, through the final sentence.
const MUSIC_PEAK := 1.0 ## The transformation itself.
const MUSIC_AFTER := 0.34 ## Under the before-and-after screen that follows.
const MUSIC_RISE := 1.2 ## Seconds to swell into the peak.
const MUSIC_SETTLE := 1.6 ## Seconds to come back down afterwards.
const FRONT_CAMERA_MOVE := 0.42 ## A quick orbit replaces the old instant animal swivel.
const FRONT_CAMERA_DISTANCE := 7.05 ## Matches the final pull-back shot's subject scale.
const FRONT_CAMERA_HEIGHT := 1.75
const THIRD_CAMERA_DISTANCE := 5.6 ## Front view with the animal and machine both readable.
const THIRD_CAMERA_HEIGHT := 1.5
const PEAK_CAMERA_DISTANCE := 3.8 ## A closer version of that same front-facing angle.
const PEAK_CAMERA_HEIGHT := 1.25
const PEAK_CAMERA_MOVE := 0.45
const REVEAL_PULL_DISTANCE := 8.45
const REVEAL_PULL_HEIGHT := 2.1
const TRAIT_SETTLE := 2.2 ## Let one trait finish visibly before the next sentence begins.
## Gap between the top of the animal and the lowest part of the machine. Enough to read as
## "hanging over it" rather than "resting on it", and enough that the bolts have somewhere
## to travel.
const HEAD_CLEARANCE := 0.55
const REFERENCE_TOP := 1.9 ## The creature height the framings were originally written for.
const GROW_TIME := 0.7
const CLEARANCE_ASCEND_TIME := 0.45 ## Move first; only then let BIG/TALL begin.
const GROWTH_ANIMATION_HEADROOM := 0.50 ## Covers TALL's landing bounce and shape overshoot.

var _stage: LabStage = null
var _banner: Label = null
var _skip := false
var _banner_text := ""


func _init(stage: LabStage, banner: Label) -> void:
	_stage = stage
	_banner = banner


## Skipping jumps each step to its end state rather than cancelling it, so the lab is
## left in exactly the same condition either way.
func request_skip() -> void:
	_skip = true


func run(state: CreatureState) -> void:
	if not _alive():
		return
	await Router.wait_until_revealed()
	if not _alive():
		return
	_stage.lock_creature_movement()
	_banner_text = _banner.text

	if _skip:
		_show_banner()
		_stage.array.park(_work_height())
	else:
		# Shot 1 is the exact final Before frame. The machine visibly enters that familiar
		# composition first; only after its descent is legible do the lens, camera and animal
		# orientation begin easing toward the chamber shot.
		var from_before := _stage.has_before_view()
		var descent := _stage.array.begin_descent(_work_height())
		if from_before:
			await _wait(0.35)
			if not _alive():
				return
			_show_banner()
			_stage.transition_from_before()
		else:
			_show_banner()
		await descent.finished

	# Each sentence: the lab says it, the machine answers it. Keep the before state as the
	# starting point and add exactly one after-trait after each sentence's zap.
	var entries := state.entries
	var staged_traits := state.before_traits()
	if not _skip:
		for i in entries.size():
			if not _alive():
				return
			await _beat(i, entries.size(), str(entries[i]["sentence"]), entries[i], staged_traits)

	if not _alive():
		return
	await _peak()

	# A skipped sequence still needs the finished state immediately. During the normal path the
	# live rig has already changed one trait at a time, so finish that same rig instead of
	# replacing it with an all-at-once build.
	if not _alive():
		return
	if _skip:
		_stage.set_rig(CreatureFactory.build_fantasy(state))
	else:
		CreatureFactory.finish_transformation(_stage.rig())
	var creature := _stage.rig()
	if creature != null and not _skip:
		# Measured now, at full size, before the grow tween shrinks it: the machine came
		# down over the "It was" animal, and a creature turning big or tall grows straight
		# into it. Done here rather than at the end because the clipping happens during the
		# growth, not after it - and the steam is at its thickest, so the machine lifting
		# clear is not something anyone sees happen.
		await _stage.get_tree().process_frame
		if not _alive():
			return
		# Never lower a machine that already rose to clear a growing trait. It retracts after
		# this reveal, and descending toward the animal while the reveal scale grows would
		# throw away the safe TALL headroom we established before the transformation.
		var final_work_height := _work_height()
		if final_work_height > _stage.array.position.y + 0.001:
			_stage.array.settle_to(final_work_height)
		creature.scale = Vector3.ONE * 0.72
		var grow := _stage.create_tween()
		grow.tween_property(creature, "scale", Vector3.ONE, GROW_TIME).set_trans(Tween.TRANS_BACK)
		await grow.finished

	if not _alive():
		return
	await _reveal()

	# Down, not off: the naming screen is the same moment continuing, and it stops the
	# music itself when the student leaves it.
	Audio.set_music_level(MUSIC_AFTER, MUSIC_SETTLE)
	if _alive():
		_banner.text = _banner_text
		_banner.visible = false


## One sentence, one surge. The banner carries the words as well as the speaker, because
## a lab with its sound turned off is a real classroom and the beat still has to land.
func _beat(index: int, total: int, sentence: String, entry: Dictionary,
		staged_traits: Dictionary) -> void:
	var rising := float(index + 1) / float(total)
	var final_beat := index == total - 1
	# The last sentence is where the music comes in, under the speech - and under the pause
	# before it, so the silence has a bed rather than being a dead spot.
	if final_beat:
		Audio.play_music(MUSIC_TRACK, MUSIC_UNDER)
		await _hold_breath()
		if not _alive():
			return
	_banner.text = sentence
	# The student's own voice if it was captured, the lab's if it was not. Either way the
	# words are on the banner, because a classroom with the sound off still gets the beat.
	Voice.report("beat %d" % index)
	var spoken := Voice.play_sentence(index)
	if spoken <= 0.0:
		Tts.speak(sentence, 0.95)
	_stage.array.set_charge(rising * 0.75)

	# Camera: push in, drop to a low angle, then orbit to the animal's own front. One
	# continuous move per sentence rather than a cut, so the animal never leaves the frame.
	var eye := _hero_eye()
	match index:
		0: eye = _hero_eye() + Vector3(0.4, -0.6, -1.6) * _spread()
		1: eye = _stage.STAND + Vector3(3.4, 0.7, 4.4) * _spread()
		_: eye = _third_eye()
	_stage.frame(eye, _machine_aim(), BEAT_SPEAK + 0.5)

	# Wait for the recording to actually finish rather than a fixed guess: a child who
	# says it slowly should still get their surge on the last word, not over it.
	await _wait(clampf(spoken, BEAT_SPEAK, MAX_BEAT) if spoken > 0.0 else BEAT_SPEAK)
	if not _alive():
		return

	# The last word comes back off the walls before the machine does anything with it.
	if final_beat:
		await _echo_last_word(sentence)
		if not _alive():
			return

	# The surge itself: bolts converge, the platform vents, the machine spins up a notch.
	Audio.play("zip", 1.0 + rising * 0.2)
	_stage.array.set_charge(rising)
	for i in 3 + index * 2:
		if not _alive():
			return
		_stage.array.fire_bolt(_bolt_target(), UiKit.ACCENT if index % 2 == 0 else UiKit.GOLD)
		if i % 2 == 0:
			_stage.vent_steam(rising * 0.5)
		await _wait(0.06)
	Fx.burst(_stage.mount, Vector3(0, 0.5, 0), "sparkle", UiKit.GOLD, 1.2 + rising)
	await _wait(0.2)

	# This is the one transformation belonging to this sentence. The cumulative dictionary
	# preserves earlier changes, while the newly added category is the only new trait this
	# zap can introduce.
	staged_traits[str(entry["category"])] = str(entry["after"])
	# The machine descended around the Before animal. Preview the cumulative target before
	# changing the live rig, and visibly lift the machine first whenever the next trait will
	# make the animal taller. Recalculating after TALL settles is too late: the head has
	# already passed through the prongs by then.
	var predicted_top := _stage.predicted_creature_top(staged_traits)
	var safe_height := _work_height_for_top(predicted_top)
	if predicted_top > _stage.creature_top() + 0.001:
		safe_height += GROWTH_ANIMATION_HEADROOM
	if safe_height > _stage.array.position.y + 0.001:
		var ascent := _stage.array.settle_to(safe_height, CLEARANCE_ASCEND_TIME)
		await ascent.finished
		if not _alive():
			return
	_stage.transform_to_traits(staged_traits)
	await _wait(TRAIT_SETTLE)


## Everything stops. No words on the banner, no bolts, just the charged machine hanging
## over the animal and the camera creeping in. The music is already running underneath.
func _hold_breath() -> void:
	_banner.text = ""
	Audio.play("charge", 0.72)
	_stage.array.set_charge(0.55)
	# A slow creep rather than a move: the framing barely changes, but it is not still, which
	# is what stops the pause reading as the game having frozen.
	_stage.frame(_third_eye() + Vector3(0.0, -0.15, -PAUSE_PUSH) * _spread(),
		_machine_aim(), FINAL_PAUSE + 0.4)
	await _wait(FINAL_PAUSE)


## The last word of the sentence, repeated back by the chamber and dying away.
##
## The word is taken from the sentence TEXT, not from the audio, because the audio may be
## the student's own recording played back by the browser - out of reach of anything here,
## and not sliceable into words in any case. So the lab echoes the word rather than the
## voice, which is also the reading that makes sense: it is the machine answering.
##
## The banner pulses in step whether or not any of this is audible. Speech can be switched
## off in Teacher Settings, and the beat still has to land in a silent classroom.
func _echo_last_word(sentence: String) -> void:
	var word := _last_word(sentence)
	if word.is_empty():
		return
	_banner.text = word
	Tts.echo(word, ECHO_REPEATS)
	for i in ECHO_REPEATS:
		if not _alive():
			return
		var falloff := pow(0.6, float(i))
		Audio.play("whoosh", 0.85 - float(i) * 0.12)
		var pulse := _stage.create_tween()
		pulse.tween_property(_banner, "modulate:a", 1.0, 0.12)
		pulse.tween_property(_banner, "modulate:a", maxf(0.25 * falloff, 0.08), ECHO_GAP)
		_stage.array.set_charge(0.55 + 0.15 * float(i))
		await _wait(ECHO_GAP + 0.12)
	if _alive():
		_banner.modulate.a = 1.0


## Trailing punctuation removed, so "big." echoes as "big" rather than as a word with a full
## stop welded to it - which the speech synthesiser reads as a pause and the banner shows.
static func _last_word(sentence: String) -> String:
	var cleaned := sentence.strip_edges()
	while not cleaned.is_empty() and not cleaned[cleaned.length() - 1].is_valid_identifier():
		var tail := cleaned[cleaned.length() - 1]
		if tail == "." or tail == "!" or tail == "?" or tail == "," or tail == "\u3002":
			cleaned = cleaned.substr(0, cleaned.length() - 1).strip_edges()
		else:
			break
	var parts := cleaned.split(" ", false)
	return str(parts[parts.size() - 1]) if not parts.is_empty() else ""


## The final machine flourish. Ease closer along the third shot's front-facing line so the
## impact grows without teleporting the camera or suddenly exposing the animal's backside.
func _peak() -> void:
	# Covers the skipped path too, where no beat ran to start it: a teacher who skips still
	# gets the reveal and the screen after it, so they should still get the music.
	Audio.play_music(MUSIC_TRACK, MUSIC_UNDER)
	Audio.set_music_level(MUSIC_PEAK, MUSIC_RISE)
	if _skip:
		_stage.vent_steam(1.0)
		return
	Audio.play("transform", 1.0)
	_stage.array.set_charge(1.0)
	_stage.array.flash(0.85) ## Not a full white-out: the silhouette has to stay findable.
	_stage.frame(_peak_eye(), _machine_aim(), PEAK_CAMERA_MOVE, Tween.TRANS_CUBIC)
	for i in 10:
		if not _alive():
			return
		_stage.array.fire_bolt(_bolt_target(), UiKit.GOLD if i % 2 == 0 else UiKit.ACCENT)
		if i % 3 == 0:
			_stage.vent_steam(0.9)
		await _wait(0.05)
	# Thickest here, and only here: the swap happens behind this. Two vents, not a wall -
	# the silhouette has to stay readable through it.
	_stage.vent_steam(1.0)
	await _wait(0.45)


## The steam thins, the machine backs off, and the camera pulls out to hand the creature
## the frame. Held for a beat afterwards - a reveal that cuts away immediately does not
## feel like a prize.
func _reveal() -> void:
	Audio.play("reveal")
	Fx.burst(_stage.mount, Vector3(0, 0.6, 0), "sparkle", UiKit.GOLD, 1.8)
	_stage.array.set_charge(0.0)
	if _skip:
		_stage.array.visible = false
		var skipped_front := _stage.frame(_front_eye(), _front_aim(), FRONT_CAMERA_MOVE,
			Tween.TRANS_CUBIC)
		await skipped_front.finished
		return
	var pull := _stage.frame(_reveal_pull_eye(),
		_stage.STAND + Vector3(0, 0.45, 0), 1.6)
	await _stage.array.retract()
	if not _alive():
		return
	await pull.finished
	if not _alive():
		return
	# Preserve the animal's transformation pose. Orbit the camera around to the animal's
	# existing front instead of swivelling the animal suddenly toward the lens.
	var front := _stage.frame(_front_eye(), _front_aim(), FRONT_CAMERA_MOVE,
		Tween.TRANS_CUBIC)
	await front.finished
	if not _alive():
		return
	await _wait(REVEAL_HOLD)


func _front_eye() -> Vector3:
	return _stage.front_camera_position(
		FRONT_CAMERA_DISTANCE * _spread(), FRONT_CAMERA_HEIGHT * _spread())


func _third_eye() -> Vector3:
	return _stage.front_camera_position(
		THIRD_CAMERA_DISTANCE * _spread(), THIRD_CAMERA_HEIGHT * _spread())


func _peak_eye() -> Vector3:
	return _stage.front_camera_position(
		PEAK_CAMERA_DISTANCE * _spread(), PEAK_CAMERA_HEIGHT * _spread())


func _reveal_pull_eye() -> Vector3:
	return _stage.front_camera_position(
		REVEAL_PULL_DISTANCE * _spread(), REVEAL_PULL_HEIGHT * _spread())


func _front_aim() -> Vector3:
	return _stage.STAND + Vector3(0, 0.45, 0)


## Where the machine hangs: clear of the tallest point of THIS animal, not at a height
## picked for an average one. A tall horse used to stand inside the prongs.
func _work_height() -> float:
	return _work_height_for_top(_stage.creature_top())


func _work_height_for_top(creature_top: float) -> float:
	var clear: float = creature_top + HEAD_CLEARANCE + TransformArray.DROP_BELOW
	return maxf(clear, TransformArray.WORK_HEIGHT)


## How much further out everything has to sit for a creature taller than the one these
## framings were written around. Never below 1.0: a chicken does not need the camera pushed
## closer than the shot was designed for, it just needs the machine lower.
func _spread() -> float:
	return maxf(_stage.creature_top() / REFERENCE_TOP, 1.0)


## Centered directly in front of the platform and above standing height as the base for the
## moving transformation framings. Scaled outward for a tall animal so the machine above it
## stays in frame instead of being cropped.
func _hero_eye() -> Vector3:
	return _stage.STAND + Vector3(0.0, 1.4, 5.6) * _spread()


## Between the animal's back and the machine's prongs. Aimed at the animal alone, the
## apparatus sits above the top of the frame and the student never sees the thing that is
## supposedly doing the transformation.
func _machine_aim() -> Vector3:
	return _stage.STAND + Vector3(0.0, maxf(_stage.creature_top() * 0.72, 1.35), 0.0)


## Chest height rather than the feet, so the bolts land on the animal and not the floor.
func _bolt_target() -> Vector3:
	var stand: Vector3 = _stage.STAND
	var local := stand - _stage.array.position
	# Spread over the animal's own height, so bolts land on a horse's back rather than
	# somewhere around its knees.
	var reach: float = maxf(_stage.creature_top() - stand.y, 0.6)
	return local + Vector3(randf_range(-0.35, 0.35), randf_range(reach * 0.35, reach * 0.9),
		randf_range(-0.35, 0.35))


func _wait(seconds: float) -> void:
	if not _alive():
		return
	await _stage.get_tree().create_timer(seconds).timeout


## A student can hit Menu mid-sequence, which frees the lab out from under the awaits.
func _alive() -> bool:
	return is_instance_valid(_stage) and is_instance_valid(_banner) and _stage.is_inside_tree()


func _show_banner() -> void:
	_banner.visible = true
	_banner.modulate.a = 0.0
	var tween := _stage.create_tween()
	tween.set_loops(0)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tween.tween_property(_banner, "modulate:a", 0.65, 0.6)
