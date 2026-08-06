class_name LabStage
extends Node3D
## The 3D half of the laboratory: floor, platform, chamber, lights, camera.
##
## Kept apart from LabController so the Word Lab genuinely cannot touch the animal - the
## data path is Word Lab -> LabController -> CreatureState -> this.

const PLATFORM_POS := Vector3(-2.4, 0.0, 1.6)
const CHAMBER_POS := Vector3(3.2, 0.0, -2.4)
const CAMERA_POS := Vector3(1.6, 3.0, 10.4)
const CAMERA_AIM := Vector3(1.6, 0.3, 0.0)

var chamber: TransformationChamber = null
var mount: Node3D = null

var _rig: CreatureRig = null


func _ready() -> void:
	add_child(StageKit.environment(Color("#0c1524"), Color("#1b3050"), 0.35))
	add_child(StageKit.key_light(Vector3(-50, -26, 0), 1.5))
	add_child(StageKit.fill_light(UiKit.ACCENT, Vector3(-3.6, 4.2, 5.2), 2.4, 16.0))
	add_child(StageKit.fill_light(UiKit.GOLD, Vector3(5.0, 2.4, 4.5), 1.8, 12.0))

	var floor_disc := StageKit.ground(30.0, Color("#0f1726"))
	add_child(floor_disc)

	var platform := StageKit.platform(2.0, Color("#1d2a42"), UiKit.ACCENT)
	platform.position = PLATFORM_POS
	add_child(platform)

	chamber = TransformationChamber.new()
	chamber.position = CHAMBER_POS
	add_child(chamber)

	mount = Node3D.new()
	mount.name = "CreatureMount"
	mount.position = PLATFORM_POS + Vector3(0, 0.28, 0)
	add_child(mount)

	add_child(StageKit.camera(CAMERA_POS, CAMERA_AIM, 50.0))


func rig() -> CreatureRig:
	return _rig


## Swap in a freshly built rig. Building from scratch rather than mutating in place is
## what keeps "the animal shows the combined It-was state" true by construction.
func set_rig(new_rig: CreatureRig) -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.queue_free()
	_rig = new_rig
	if _rig != null:
		mount.add_child(_rig)
		# A three-quarter view: head-on, the head hides the body and the silhouette
		# stops reading as the animal it is supposed to be.
		_rig.rotation.y = -0.85


## A short pop so a newly applied "It was..." trait is felt, not just seen.
func punch() -> void:
	if _rig == null:
		return
	var tween := create_tween()
	tween.tween_property(_rig, "scale", Vector3.ONE * 1.07, 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_rig, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	Fx.burst(mount, Vector3(0, 0.3, 0), "sparkle", UiKit.ACCENT, 1.4)


func walk_into_chamber(duration := 1.9) -> void:
	if _rig == null:
		return
	_rig.moving = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mount, "position", CHAMBER_POS + Vector3(0, 0.42, 0), duration)
	tween.tween_property(_rig, "rotation:y", -PI * 0.5, 0.5)
	await tween.finished
	_rig.moving = false


func place_at_chamber() -> void:
	mount.position = CHAMBER_POS + Vector3(0, 0.42, 0)


func walk_out(duration := 1.6) -> void:
	if _rig == null:
		return
	_rig.moving = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mount, "position", PLATFORM_POS + Vector3(0, 0.28, 0), duration)
	tween.tween_property(_rig, "rotation:y", -0.85, duration)
	await tween.finished
	_rig.moving = false
