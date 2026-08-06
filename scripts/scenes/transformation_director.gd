class_name TransformationDirector
extends RefCounted
## Plays the one beat the whole design is built around: the "It was..." animal walks into
## the chamber, and the "Now it is..." creature walks out.
##
## Everything up to this point has been the past tense; everything after it is the
## present. Split out of LabController because it is a sequence, not a rule - and because
## a teacher must be able to skip it without unpicking the state machine.

const GROW_TIME := 0.7
const SETTLE_TIME := 0.7

var _stage: LabStage = null
var _banner: Label = null
var _skip := false


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
	_show_banner()

	if _skip:
		_stage.place_at_chamber()
	else:
		await _stage.walk_into_chamber()

	if not _alive():
		return
	if _skip:
		_stage.chamber.seal()
	else:
		await _stage.chamber.run_transformation()

	# The same CreatureState, read the other way round.
	if not _alive():
		return
	var creature := CreatureFactory.build_fantasy(state)
	_stage.set_rig(creature)
	_stage.place_at_chamber()
	if creature != null:
		creature.scale = Vector3.ONE * 0.2
		var grow := _stage.create_tween()
		grow.tween_property(creature, "scale", Vector3.ONE, GROW_TIME).set_trans(Tween.TRANS_BACK)
		if not _skip:
			await grow.finished

	if not _alive():
		return
	_stage.chamber.unseal()
	Audio.play("reveal")
	Fx.burst(_stage.mount, Vector3(0, 0.6, 0), "sparkle", UiKit.GOLD, 1.8)

	if not _skip:
		await _stage.walk_out()
		if not _alive():
			return
		await _stage.get_tree().create_timer(SETTLE_TIME).timeout

	if _alive():
		_banner.visible = false


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
