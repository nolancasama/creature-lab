class_name LabStage
extends Node3D
## The 3D half of the laboratory: floor, platform, transform array, lights, camera.
##
## Kept apart from LabController so the Word Lab genuinely cannot touch the animal - the
## data path is Word Lab -> LabController -> CreatureState -> this.

const PLATFORM_POS := Vector3(-2.4, 0.0, 1.6)
const CAMERA_POS := Vector3(1.6, 3.0, 10.4)
const CAMERA_AIM := Vector3(1.6, 0.3, 0.0)
const CAMERA_FOV := 50.0
const TRANSFORMATION_FACING := -0.85
## Where the creature actually stands. Every cinematic framing is written relative to this
## rather than to the world, so moving the platform cannot silently break the shots.
const STAND := PLATFORM_POS + Vector3(0.0, 0.28, 0.0)

var array: TransformArray = null
var mount: Node3D = null
var camera: Camera3D = null

var _rig: CreatureRig = null
var _cam_from := Vector3.ZERO
var _aim_from := Vector3.ZERO
var _cam_to := Vector3.ZERO
var _aim_to := Vector3.ZERO
var _has_before_view := false


func _ready() -> void:
	add_child(StageKit.environment(Color("#050a12"), Color("#0e1d32"), 0.35))
	add_child(StageKit.key_light(Vector3(-50, -26, 0), 1.5))
	add_child(StageKit.fill_light(UiKit.ACCENT, Vector3(-3.6, 4.2, 5.2), 2.4, 16.0))
	add_child(StageKit.fill_light(UiKit.GOLD, Vector3(5.0, 2.4, 4.5), 1.8, 12.0))

	var floor_disc := StageKit.ground(30.0, Color("#070b13"))
	add_child(floor_disc)

	# Pixel-for-pixel continuation of Animal Selection's Before platform. The room lighting
	# may become cinematic after the seamless swap; the surface under the animal must not.
	var platform := StageKit.platform(1.8, Color("#22304a"), UiKit.ACCENT)
	platform.position = PLATFORM_POS
	add_child(platform)

	# Parked out of sight above the platform until the final sequence calls it down.
	array = TransformArray.create()
	array.position = Vector3(PLATFORM_POS.x, 0.0, PLATFORM_POS.z)
	add_child(array)

	mount = Node3D.new()
	mount.name = "CreatureMount"
	mount.position = STAND
	add_child(mount)

	camera = StageKit.camera(CAMERA_POS, CAMERA_AIM, CAMERA_FOV)
	add_child(camera)
	_cam_to = CAMERA_POS
	_aim_to = CAMERA_AIM


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
		_rig.rotation.y = TRANSFORMATION_FACING


## Rebuild the camera in the same subject-relative place and lens used by the final Before
## screen. The router's fade reveals this matching frame before transition_from_before()
## begins moving it into the chamber shot.
func apply_before_view(handoff: Dictionary) -> void:
	_has_before_view = not handoff.is_empty() and _rig != null
	if not _has_before_view:
		return
	var eye := STAND + Vector3(handoff.get("camera_offset", CAMERA_POS - STAND))
	var aim := STAND + Vector3(handoff.get("aim_offset", CAMERA_AIM - STAND))
	var fov := float(handoff.get("camera_fov", CAMERA_FOV))
	camera.set_perspective(fov, camera.near, camera.far)
	cut_to(eye, aim)
	_rig.rotation.y = float(handoff.get("creature_rotation_y", TRANSFORMATION_FACING))


func has_before_view() -> bool:
	return _has_before_view


## Camera position, aim, lens and creature orientation all share one easing factor, so no
## component arrives early and makes the animal appear to snap or swivel independently.
func transition_from_before(duration := 1.25) -> Tween:
	_has_before_view = false
	var from_fov := camera.fov
	var from_rotation := _rig.rotation.y if _rig != null else TRANSFORMATION_FACING
	_cam_from = camera.position
	_aim_from = _aim_to
	_cam_to = CAMERA_POS
	_aim_to = CAMERA_AIM
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
			_apply_frame(t)
			camera.set_perspective(lerpf(from_fov, CAMERA_FOV, t), camera.near, camera.far)
			if _rig != null:
				_rig.rotation.y = lerp_angle(from_rotation, TRANSFORMATION_FACING, t),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


func lock_creature_movement() -> void:
	if _rig == null:
		return
	_rig.movement_locked = true
	_rig.moving = false
	if _rig.pace != null:
		_rig.pace.reset()


## Apply the traits reached so far during the chamber sequence. The dictionary is
## cumulative, so TraitVisuals can rebuild from a clean baseline while only the newly added
## sentence trait animates from the current pose.
func transform_to_traits(traits: Dictionary) -> void:
	if _rig == null:
		return
	TraitVisuals.apply_all(_rig, traits, true)


## A short pop so a newly applied "It was..." trait is felt, not just seen.
func punch() -> void:
	if _rig == null:
		return
	var tween := create_tween()
	tween.tween_property(_rig, "scale", Vector3.ONE * 1.07, 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_rig, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	Fx.burst(mount, Vector3(0, 0.3, 0), "sparkle", UiKit.ACCENT, 1.4)


## Moves the camera and what it is pointing at together. Both ends are interpolated by
## one factor rather than tweened separately, so the aim can never lag the position and
## swing the subject out of frame mid-move.
func frame(to: Vector3, aim: Vector3, duration: float,
		trans := Tween.TRANS_SINE) -> Tween:
	_cam_from = camera.position
	_aim_from = _aim_to
	_cam_to = to
	_aim_to = aim
	var tween := create_tween()
	tween.tween_method(_apply_frame, 0.0, 1.0, duration) 		.set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	return tween


## A hard cut. Used once, on the energy peak, where an instant change of angle reads as
## impact - everywhere else the camera moves, because cutting around a small subject is
## how a sequence stops being followable.
func cut_to(to: Vector3, aim: Vector3) -> void:
	_cam_from = to
	_aim_from = aim
	_cam_to = to
	_aim_to = aim
	_apply_frame(1.0)


func reset_camera() -> void:
	cut_to(CAMERA_POS, CAMERA_AIM)


## Put the camera in front of the animal without changing the animal's pose. `distance`
## and `height` are stage-space offsets from the live rig origin. The direction is the
## inverse of the yaw calculation formerly used to rotate the rig toward the camera.
func front_camera_position(distance: float, height: float) -> Vector3:
	if _rig == null:
		return camera.position if camera != null else CAMERA_POS
	var yaw := _rig.rotation.y
	var toward_camera := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rig_origin := mount.position + _rig.position
	return rig_origin + toward_camera * distance + Vector3.UP * height


func _apply_frame(t: float) -> void:
	if camera == null:
		return
	var eye: Vector3 = _cam_from.lerp(_cam_to, t)
	var look: Vector3 = _aim_from.lerp(_aim_to, t)
	if eye.distance_to(look) < 0.05:
		return
	camera.look_at_from_position(eye, look, Vector3.UP)


## How high the creature currently reaches, in stage space. Read off the mesh through the
## live transform chain, so it already accounts for the platform, BIG's body scale and
## TALL's lift rather than assuming the animal is the size it was authored at. A horse
## grown tall is more than twice a chicken, and a machine placed at one fixed height either
## speared the tall one or hovered uselessly far above the short one.
func creature_top() -> float:
	if _rig == null or not is_instance_valid(_rig) or _rig.mesh_instance == null:
		return STAND.y
	var box := _rig.mesh_instance.get_aabb()
	var to_stage := global_transform.affine_inverse() * _rig.mesh_instance.global_transform
	var top := -INF
	for i in 8:
		top = maxf(top, (to_stage * box.get_endpoint(i)).y)
	return top if is_finite(top) else STAND.y


## How high the animal will reach after `traits` settle, without disturbing the live rig
## or starting its animation early. The director uses this before each transformation
## beat so the ceiling array can rise clear of BIG/TALL before the animal grows into it.
func predicted_creature_top(traits: Dictionary) -> float:
	if _rig == null or not is_instance_valid(_rig) or _rig.definition == null:
		return creature_top()
	var probe := CreatureFactory.build_plain(_rig.definition.id)
	if probe == null or probe.mesh_instance == null:
		if probe != null:
			probe.free()
		return creature_top()
	TraitVisuals.apply_all(probe, traits)
	var box := probe.mesh_instance.get_aabb()
	# The probe deliberately remains outside the SceneTree; compose its local chain directly
	# rather than asking Node3D for a global transform it cannot provide off-tree.
	var to_probe := probe._transform_to_ancestor(probe.mesh_instance, probe)
	var local_top := -INF
	for i in 8:
		local_top = maxf(local_top, (to_probe * box.get_endpoint(i)).y)
	# An off-tree probe does not receive _process(), where the live rig copies the TALL
	# deformer lift onto Body.position. Include that target lift explicitly or a SHORT ->
	# TALL preview underestimates the crown by the entire leg-extension gain.
	if probe.deformer != null:
		local_top += probe.deformer.lift
	probe.free()
	return STAND.y + local_top if is_finite(local_top) else creature_top()


## Vents around the rim, so the steam belongs to the platform the student has been
## watching rather than appearing from nowhere underneath the animal.
func vent_steam(amount: float) -> void:
	# Two vents at full tilt, not five. The brief is that the animal stays findable inside
	# the cloud - the first build stacked enough emitters to white out the whole frame, and
	# a transformation you cannot see happening is just a loading screen.
	var count := 1 if amount < 0.6 else 2
	for i in count:
		var angle := randf() * TAU
		var at := Vector3(cos(angle), 0.06, sin(angle)) * randf_range(0.8, 1.5)
		Fx.burst(mount, at, "steam", Color("#dbe7f2"), 0.3 + amount * 0.28,
			0.7 + amount * 0.5, Vector3.UP)
