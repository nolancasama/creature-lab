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
const REVEAL_HOLD := 1.1
const TRAIT_SETTLE := 2.2 ## Let one trait finish visibly before the next sentence begins.
## Gap between the top of the animal and the lowest part of the machine. Enough to read as
## "hanging over it" rather than "resting on it", and enough that the bolts have somewhere
## to travel.
const HEAD_CLEARANCE := 0.55
const REFERENCE_TOP := 1.9 ## The creature height the framings were originally written for.
const GROW_TIME := 0.7

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
	_stage.lock_creature_movement()
	_banner_text = _banner.text
	_show_banner()

	if _skip:
		_stage.array.park(_work_height())
	else:
		# Begin from the lab's existing three-quarter view. The former one-second setup
		# moved directly in front of the animal and turned it head-on before anything
		# happened, creating a detached opening shot before the real sequence began.
		await _stage.array.descend(_work_height())

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
		_stage.array.settle_to(_work_height())
		creature.scale = Vector3.ONE * 0.72
		var grow := _stage.create_tween()
		grow.tween_property(creature, "scale", Vector3.ONE, GROW_TIME).set_trans(Tween.TRANS_BACK)
		await grow.finished

	if not _alive():
		return
	await _reveal()

	if _alive():
		_banner.text = _banner_text
		_banner.visible = false


## One sentence, one surge. The banner carries the words as well as the speaker, because
## a lab with its sound turned off is a real classroom and the beat still has to land.
func _beat(index: int, total: int, sentence: String, entry: Dictionary,
		staged_traits: Dictionary) -> void:
	var rising := float(index + 1) / float(total)
	_banner.text = sentence
	# The student's own voice if it was captured, the lab's if it was not. Either way the
	# words are on the banner, because a classroom with the sound off still gets the beat.
	Voice.report("beat %d" % index)
	var spoken := Voice.play_sentence(index)
	if spoken <= 0.0:
		Tts.speak(sentence, 0.95)
	_stage.array.set_charge(rising * 0.75)

	# Camera: push in, drop to a low angle, then swing round. One continuous move per
	# sentence rather than a cut, so the animal never leaves the frame.
	var eye := _hero_eye()
	match index:
		0: eye = _hero_eye() + Vector3(0.4, -0.6, -1.6) * _spread()
		1: eye = _stage.STAND + Vector3(3.4, 0.7, 4.4) * _spread()
		_: eye = _stage.STAND + Vector3(-3.6, 1.5, 4.0) * _spread()
	_stage.frame(eye, _machine_aim(), BEAT_SPEAK + 0.5)

	# Wait for the recording to actually finish rather than a fixed guess: a child who
	# says it slowly should still get their surge on the last word, not over it.
	await _wait(clampf(spoken, BEAT_SPEAK, MAX_BEAT) if spoken > 0.0 else BEAT_SPEAK)
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
	_stage.transform_to_traits(staged_traits)
	await _wait(TRAIT_SETTLE)


## The final machine flourish, and the only hard cut in the sequence - the trait changes
## have already happened one at a time, so this peak reads as the completed transformation.
func _peak() -> void:
	if _skip:
		_stage.vent_steam(1.0)
		return
	Audio.play("transform", 1.0)
	_stage.array.set_charge(1.0)
	_stage.array.flash(0.85) ## Not a full white-out: the silhouette has to stay findable.
	_stage.cut_to(_stage.STAND + Vector3(0.0, 1.2, 3.4) * _spread(), _machine_aim())
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
		_stage.reset_camera()
		_stage.face_rig_to_camera()
		return
	var pull := _stage.frame(_hero_eye() + Vector3(-0.8, 0.35, 1.4) * _spread(),
		_stage.STAND + Vector3(0, 0.45, 0), 1.6)
	await _stage.array.retract()
	if not _alive():
		return
	await pull.finished
	if not _alive():
		return
	# The camera has now reached its final reveal position; face the actual camera, not the
	# earlier pre-descent framing.
	_stage.face_rig_to_camera()
	await _wait(REVEAL_HOLD)
	if _alive():
		_stage.reset_camera()


## Where the machine hangs: clear of the tallest point of THIS animal, not at a height
## picked for an average one. A tall horse used to stand inside the prongs.
func _work_height() -> float:
	var clear: float = _stage.creature_top() + HEAD_CLEARANCE + TransformArray.DROP_BELOW
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
