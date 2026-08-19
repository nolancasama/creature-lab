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
## The three sentences drive it. Each one is spoken back by the lab, and each one lands a
## surge - so the student's own English is visibly the thing operating the machine. It is
## spoken rather than replayed: this game never records audio (the Web Speech backend
## returns transcripts, and half the class types its answers instead), so a "replay your
## own voice" beat would be silent for every student who typed. Speaking it works the
## same way for all of them.

## Roughly how long a spoken sentence needs before its surge lands. The whole sequence is
## three of these plus the peak and the reveal, and it is the payoff for a whole round -
## but it is also dead time for anyone watching it a second time, so each beat is trimmed
## to about as long as the sentence actually takes to say and no longer.
const BEAT_SPEAK := 1.9
const REVEAL_HOLD := 1.1
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
	_banner_text = _banner.text
	_show_banner()

	if _skip:
		_stage.array.park()
	else:
		await _stage.frame(_hero_eye(), _machine_aim(), 1.0).finished
		if not _alive():
			return
		await _stage.array.descend()

	# Each sentence: the lab says it, the machine answers it. Three of them, each one
	# harder than the last, so the sequence builds instead of just repeating.
	var sentences := state.sentences()
	if not _skip:
		for i in sentences.size():
			if not _alive():
				return
			await _beat(i, sentences.size(), str(sentences[i]))

	if not _alive():
		return
	await _peak()

	# The same CreatureState, read the other way round - swapped while the steam is at its
	# thickest, so the change happens inside the cloud rather than as a visible pop.
	if not _alive():
		return
	var creature := CreatureFactory.build_fantasy(state)
	_stage.set_rig(creature)
	if creature != null and not _skip:
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
func _beat(index: int, total: int, sentence: String) -> void:
	var rising := float(index + 1) / float(total)
	_banner.text = sentence
	Tts.speak(sentence, 0.95)
	_stage.array.set_charge(rising * 0.75)

	# Camera: push in, drop to a low angle, then swing round. One continuous move per
	# sentence rather than a cut, so the animal never leaves the frame.
	var eye := _hero_eye()
	match index:
		0: eye = _hero_eye() + Vector3(0.4, -0.6, -1.6)
		1: eye = _stage.STAND + Vector3(3.4, 0.7, 4.4)
		_: eye = _stage.STAND + Vector3(-3.6, 1.5, 4.0)
	_stage.frame(eye, _machine_aim(), BEAT_SPEAK + 0.5)

	await _wait(BEAT_SPEAK)
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
	await _wait(0.35)


## Everything at once, and the only hard cut in the sequence - on the frame where the
## energy peaks, a cut reads as impact rather than as losing the subject.
func _peak() -> void:
	if _skip:
		_stage.vent_steam(1.0)
		return
	Audio.play("transform", 1.0)
	_stage.array.set_charge(1.0)
	_stage.array.flash(0.85) ## Not a full white-out: the silhouette has to stay findable.
	_stage.cut_to(_stage.STAND + Vector3(0.0, 1.2, 3.4), _machine_aim())
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
		return
	var pull := _stage.frame(_hero_eye() + Vector3(-0.8, 0.35, 1.4),
		_stage.STAND + Vector3(0, 0.45, 0), 1.6)
	await _stage.array.retract()
	if not _alive():
		return
	await pull.finished
	if not _alive():
		return
	await _wait(REVEAL_HOLD)
	if _alive():
		_stage.reset_camera()


## Slightly off-axis and above standing height: head-on hides the body behind the head,
## which is the same reason set_rig turns the creature three-quarters on.
func _hero_eye() -> Vector3:
	return _stage.STAND + Vector3(2.2, 1.4, 5.6)


## Between the animal's back and the machine's prongs. Aimed at the animal alone, the
## apparatus sits above the top of the frame and the student never sees the thing that is
## supposedly doing the transformation.
func _machine_aim() -> Vector3:
	return _stage.STAND + Vector3(0.0, 1.35, 0.0)


## Chest height rather than the feet, so the bolts land on the animal and not the floor.
func _bolt_target() -> Vector3:
	var stand: Vector3 = _stage.STAND
	var local := stand - _stage.array.position
	return local + Vector3(randf_range(-0.35, 0.35), randf_range(0.45, 1.1),
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
