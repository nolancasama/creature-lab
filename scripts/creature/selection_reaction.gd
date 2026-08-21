class_name SelectionReaction
extends RefCounted
## A tiny data-driven pose player for the animal picker.
##
## The source models contain no authored animations, so a reaction profile combines a
## smooth root flourish with optional additive bone tracks.  Profiles live with each
## AnimalDefinition; this class deliberately knows nothing about dogs, cats, or any other
## species.  Replaying interrupts and restores the previous pose immediately, which keeps
## fast carousel browsing responsive.

const DEFAULT_DURATION := 0.95

var _rig: CreatureRig = null
var _profile: Dictionary = {}
var _tracks: Array[Dictionary] = []
var _elapsed := 0.0
var _duration := DEFAULT_DURATION
var _active := false
var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _base_scale := Vector3.ONE


func _init(rig: CreatureRig) -> void:
	_rig = rig


func play(profile: Dictionary) -> float:
	cancel()
	if _rig == null or profile.is_empty():
		return 0.0
	_profile = profile.duplicate(true)
	_duration = clampf(float(_profile.get("duration", DEFAULT_DURATION)), 0.35, 2.0)
	_elapsed = 0.0
	_base_position = _rig.position
	_base_rotation = _rig.rotation
	_base_scale = _rig.scale
	_tracks.clear()
	_resolve_tracks()
	_active = true
	_apply_pose(0.0)
	return _duration


func cancel() -> void:
	if _rig != null and _active:
		_restore_pose()
	_active = false
	_profile = {}
	_tracks.clear()
	_elapsed = 0.0


func is_active() -> bool:
	return _active


func tick(delta: float) -> void:
	if not _active or _rig == null:
		return
	_elapsed = minf(_elapsed + delta, _duration)
	_apply_pose(_elapsed / _duration)
	if _elapsed >= _duration:
		# The final sample is exactly neutral. Restore once more to avoid leaving a bone at
		# its penultimate frame if the skeleton is updated between process callbacks.
		_restore_pose()
		_active = false


func _resolve_tracks() -> void:
	if _rig.skeleton == null:
		return
	var raw_tracks = _profile.get("bones", [])
	if not raw_tracks is Array:
		return
	for raw in raw_tracks:
		if not raw is Dictionary:
			continue
		var spec := raw as Dictionary
		var bone_name := str(spec.get("bone", ""))
		var index := _rig.skeleton.find_bone(bone_name)
		if index == -1:
			continue
		_tracks.append({
			"index": index,
			"base": _rig.skeleton.get_bone_pose_rotation(index),
			"axis": BodyPartSpec.to_v3(spec.get("axis", null), Vector3.RIGHT).normalized(),
			"angle": deg_to_rad(float(spec.get("angle_deg", 0.0))),
			"cycles": maxf(float(spec.get("cycles", 0.0)), 0.0),
			"phase": deg_to_rad(float(spec.get("phase_deg", 0.0))),
		})


func _apply_pose(t: float) -> void:
	var envelope := sin(PI * t)
	var rotation_cycles := maxf(float(_profile.get("rotation_cycles", 0.0)), 0.0)
	var rotation_weight := envelope
	if rotation_cycles > 0.0:
		rotation_weight = sin(TAU * rotation_cycles * t) * envelope

	var bounces := maxf(float(_profile.get("bounces", 1.0)), 1.0)
	var lift_weight := absf(sin(PI * bounces * t))
	# Later hops settle slightly, which makes two or three bounces feel intentional rather
	# than like a looping idle that was abruptly cut off.
	lift_weight *= lerpf(1.0, 0.68, t)
	var lift := float(_profile.get("lift", 0.0)) * lift_weight
	var forward := float(_profile.get("forward", 0.0)) * envelope
	var local_offset := Vector3(0.0, lift, forward)
	_rig.position = _base_position + Basis.from_euler(_base_rotation) * local_offset

	var flourish := Vector3(
		deg_to_rad(float(_profile.get("pitch_deg", 0.0))),
		deg_to_rad(float(_profile.get("yaw_deg", 0.0))),
		deg_to_rad(float(_profile.get("roll_deg", 0.0)))) * rotation_weight
	_rig.rotation = _base_rotation + flourish
	var scale_amount := float(_profile.get("scale", 0.0))
	_rig.scale = _base_scale * (1.0 + scale_amount * envelope)

	if _rig.skeleton == null:
		return
	for track in _tracks:
		var cycles := float(track["cycles"])
		var weight := envelope
		if cycles > 0.0:
			weight = sin(TAU * cycles * t + float(track["phase"])) * envelope
		var index := int(track["index"])
		var rotation := track["base"] as Quaternion
		rotation *= Quaternion(track["axis"] as Vector3, float(track["angle"]) * weight)
		_rig.skeleton.set_bone_pose_rotation(index, rotation)


func _restore_pose() -> void:
	if _rig == null:
		return
	_rig.position = _base_position
	_rig.rotation = _base_rotation
	_rig.scale = _base_scale
	if _rig.skeleton == null:
		return
	for track in _tracks:
		_rig.skeleton.set_bone_pose_rotation(int(track["index"]), track["base"] as Quaternion)
