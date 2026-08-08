class_name MuscleDeformer
extends RefCounted
## STRONG / WEAK: cartoon muscle bulk, veins, posture, and the power-up that gets there.
##
## Five bulk controls are driven independently - chest, shoulder, front limb, rear limb,
## neck - which is what lets the power-up stage them one after another instead of
## inflating everything at once.
##
## Bone scale propagates to every descendant, so naively scaling the chest also inflates
## the neck, the legs, the feet and the skull: the animal just gets BIGGER, which is
## indistinguishable from the big/small trait. Instead each bone is given a *desired*
## thickness and its local scale is set to desired/inherited, walking the skeleton
## parents-first. Bones in no muscle group get a desired of 1.0, which actively cancels
## whatever they would otherwise inherit - so the skull, shins and feet stay their
## normal size while the muscles around them swell.
##
## Three systems write to this skeleton and they deliberately do not overlap:
##   CreatureDeformer -> bone POSITION (body length, telescoping legs)
##   MuscleDeformer   -> bone SCALE    (muscle bulk)
##   CreatureRig      -> bone ROTATION (walk cycle, posture)
## Keeping one component each is what lets a creature be long, tall, strong and walking
## all at the same time without any of them clobbering the others.
##
## Muscles are shown as bulges through the existing fur or feathers rather than as
## sculpted anatomy - the animal keeps its own shape and simply swells.

const GROUPS: Array[String] = ["chest", "shoulder", "front_limb", "rear_limb", "neck"]

const STRONG_OVERSHOOT := 1.16
const WEAK_UNDERSHOOT := 0.90
const VEIN_COLOR := Color("#8c1d2c")

## How much of the overall level each group takes. A powerful animal is mostly chest and
## haunches; the neck only thickens "somewhat", per the design.
const GROUP_WEIGHT := {
	"chest": 1.0,
	"shoulder": 0.92,
	"front_limb": 0.80,
	"rear_limb": 0.88,
	"neck": 0.45,
}

## Current bulk per group. 1.0 is the animal's natural build.
var bulk := {}
var posture := 0.0 ## +1 proud and lifted, -1 drooping and tired.
var vein_visibility := 0.0
var shake := Vector3.ZERO ## Power-up vibration.
var squash := Vector3.ONE
var pitch := 0.0 ## Rearing / head-up flourishes.
var yaw := 0.0 ## Flex twist.
var lift := 0.0 ## Posture height, on top of the leg deformer's lift.

var _rig: CreatureRig = null
var _skeleton: Skeleton3D = null
var _def: AnimalDefinition = null
var _vein_nodes: Array[Node3D] = []
var _tweens: Array[Tween] = []
var _target := 1.0 ## Last requested bulk level, so transitions know their direction.
var _order: Array = [] ## Bone indices, shallowest first.
var _posed_scale := {} ## Bones currently carrying a non-1 scale, so they get cleared.
var _was_bulked := false


func _init(rig: CreatureRig) -> void:
	_rig = rig
	_skeleton = rig.skeleton
	_def = rig.definition
	for group in GROUPS:
		bulk[group] = 1.0
	_build_veins()


# --- Veins --------------------------------------------------------------------

## Veins are little primitive clusters parked on the muscle they belong to, hidden until
## the animal turns strong. A handful of bold shapes reads far better to a child at
## screen distance than any attempt at real anatomy - and per the design, too many veins
## would make the animal look ill rather than powerful.
func _build_veins() -> void:
	if _skeleton == null or _def == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = VEIN_COLOR
	material.roughness = 0.55
	material.emission_enabled = true
	material.emission = VEIN_COLOR.lightened(0.15)
	material.emission_energy_multiplier = 0.22

	for vein in _def.veins:
		var cluster := Node3D.new()
		cluster.name = "vein"
		cluster.position = _vein_position(vein)
		cluster.scale = Vector3.ZERO
		cluster.visible = false
		# A stubby trunk with two branches: the simplest shape that still reads as a vein.
		var size: float = vein["size"]
		var thick: float = size * 0.20
		_add_branch(cluster, material, Vector3.ZERO, Vector3(0, 0, 12), size, thick)
		_add_branch(cluster, material, Vector3(0, size * 0.34, 0), Vector3(0, 0, 46), size * 0.60, thick * 0.8)
		_add_branch(cluster, material, Vector3(0, size * 0.30, 0), Vector3(0, 0, -52), size * 0.52, thick * 0.8)
		_rig.body.add_child(cluster)
		_vein_nodes.append(cluster)


func _add_branch(parent: Node3D, material: StandardMaterial3D, offset: Vector3,
		rotation_deg: Vector3, length: float, thickness: float) -> void:
	var spec := BodyPartSpec.new()
	spec.id = "vein_branch"
	spec.shape = "capsule"
	spec.size = Vector3(thickness, maxf(length, thickness * 1.05), thickness)
	spec.pivot = offset
	spec.rotation_deg = rotation_deg
	spec.offset = Vector3(0, length * 0.5, 0)
	parent.add_child(CreatureRig.build_part_node(spec, material))


func _vein_position(vein: Dictionary) -> Vector3:
	var idx := _skeleton.find_bone(str(vein["bone"]))
	if idx == -1:
		return Vector3(0, _def.stand_height * 0.6, 0)
	var pos: Vector3 = _skeleton.get_bone_global_rest(idx).origin * _rig.normal_scale()
	pos.y += _rig.model_base_y()
	return pos + (vein["off"] as Vector3)


# --- Applying the state -------------------------------------------------------

## Snap straight to a build, no animation. Used for zoo residents, ghosts and the
## finished creature, which are all born already transformed.
func set_state(level: float) -> void:
	kill_tweens()
	_target = level
	for group in GROUPS:
		bulk[group] = level
	posture = _posture_for(level)
	vein_visibility = 1.0 if level > 1.02 else 0.0
	shake = Vector3.ZERO
	squash = Vector3.ONE
	pitch = 0.0
	yaw = 0.0
	apply()


func reset() -> void:
	set_state(1.0)


## Strong stands proud and a little lifted; weak sags. Scaled off how far the bulk went,
## so it never contradicts the body.
func _posture_for(level: float) -> float:
	return clampf((level - 1.0) * 2.2, -1.0, 1.0)


func apply() -> void:
	if _skeleton == null or _def == null:
		return

	# What thickness each bone should end up at. Anything unlisted wants 1.0, which is
	# what keeps heads and feet out of the transformation.
	var desired := {}
	var touched := false
	for group in GROUPS:
		var factor: float = 1.0 + (bulk.get(group, 1.0) - 1.0) * float(GROUP_WEIGHT.get(group, 1.0))
		if not is_equal_approx(factor, 1.0):
			touched = true
		for bone in _def.bulk_bones_for(group):
			var idx := _skeleton.find_bone(bone)
			if idx != -1:
				desired[idx] = factor

	if touched or _was_bulked:
		# Parents before children, so a bone always knows what it is inheriting.
		var accumulated := {}
		for idx in _bone_order():
			var parent := _skeleton.get_bone_parent(idx)
			var inherited: float = accumulated.get(parent, 1.0)
			var want: float = desired.get(idx, 1.0)
			var local: float = want / inherited if absf(inherited) > 0.0001 else want
			accumulated[idx] = want
			if not is_equal_approx(local, 1.0) or _posed_scale.has(idx):
				_skeleton.set_bone_pose_scale(idx, Vector3(local, 1.0, local))
				_rig.mark_posed(idx)
				if is_equal_approx(local, 1.0):
					_posed_scale.erase(idx)
				else:
					_posed_scale[idx] = true
	_was_bulked = touched

	lift = posture * _def.stand_height * 0.035
	for node in _vein_nodes:
		node.scale = Vector3.ONE * vein_visibility
		node.visible = vein_visibility > 0.01


## Bone indices sorted shallowest-first. Godot usually stores them that way already, but
## the compensation maths breaks silently if a child is ever processed before its parent.
func _bone_order() -> Array:
	if not _order.is_empty():
		return _order
	var depths := []
	for idx in _skeleton.get_bone_count():
		var depth := 0
		var walk := idx
		while _skeleton.get_bone_parent(walk) != -1:
			walk = _skeleton.get_bone_parent(walk)
			depth += 1
		depths.append([depth, idx])
	depths.sort_custom(func(a, b): return a[0] < b[0])
	for entry in depths:
		_order.append(entry[1])
	return _order


# --- Animated transitions -----------------------------------------------------

func animate_to(level: float) -> void:
	if _rig == null or not _rig.is_inside_tree():
		set_state(level)
		return
	if is_equal_approx(level, _target):
		return
	kill_tweens()
	if level > _target:
		_power_up(level)
	else:
		_deflate(level)
	_target = level


## Brace, shudder, then swell one muscle group at a time, overshoot into something
## ridiculous, rebound, pop the veins, and land in the species' own finishing pose.
func _power_up(level: float) -> void:
	Audio.play("charge", 0.9)

	# 1. Brace: crouch and tense.
	_squash_between(0.0, 0.22, Vector3.ONE, Vector3(1.06, 0.90, 1.06))
	_lift_dip(0.0, 0.22)

	# 2. Power-up shudder while the energy builds.
	_shudder(0.22, 0.30, _def.stand_height * 0.012)

	# 3-6. Chest, then shoulders and front limbs, then haunches, then neck.
	_swell("chest", level, 0.50, 0.38)
	_swell("shoulder", level, 0.74, 0.36)
	_swell("front_limb", level, 0.80, 0.36)
	_swell("rear_limb", level, 1.02, 0.36)
	_swell("neck", level, 1.24, 0.34)

	# 7-8. Everything overshoots into an absurd shape, then recoils back.
	var settle := _rig.create_tween()
	_tweens.append(settle)
	settle.tween_interval(1.46)
	settle.tween_callback(func() -> void: Audio.play("pop", 0.75))
	settle.tween_method(_set_all.bind(level), 1.0, STRONG_OVERSHOOT, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle.tween_method(_set_all.bind(level), STRONG_OVERSHOOT, 1.0, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_squash_between(1.46, 0.24, Vector3.ONE, Vector3(1.10, 1.06, 1.10))

	# 9. Veins pop in with a single pulse and then stay put.
	var veins := _rig.create_tween()
	_tweens.append(veins)
	veins.tween_interval(1.86)
	veins.tween_callback(func() -> void: Audio.play("pop", 1.35))
	veins.tween_method(_set_veins, 0.0, 1.35, 0.16).set_trans(Tween.TRANS_SINE)
	veins.tween_method(_set_veins, 1.35, 1.0, 0.26).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# Posture rises through the whole sequence.
	var stance := _rig.create_tween()
	_tweens.append(stance)
	stance.tween_interval(0.5)
	stance.tween_method(_set_posture, posture, _posture_for(level), 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# 10. Species finishing pose.
	_flourish(2.02)


## The reverse energy: veins vanish, then everything deflates from the chest outward,
## and the animal sags into a tired stance.
func _deflate(level: float) -> void:
	Audio.play("deflate")

	var veins := _rig.create_tween()
	_tweens.append(veins)
	veins.tween_method(_set_veins, vein_visibility, 0.0, 0.28).set_trans(Tween.TRANS_SINE)

	_swell("chest", level, 0.20, 0.42)
	_swell("shoulder", level, 0.45, 0.40)
	_swell("front_limb", level, 0.52, 0.40)
	_swell("rear_limb", level, 0.72, 0.40)
	_swell("neck", level, 0.96, 0.38)

	# A slack undershoot and a tired little wobble back.
	var sag := _rig.create_tween()
	_tweens.append(sag)
	sag.tween_interval(1.20)
	sag.tween_method(_set_all.bind(level), 1.0, WEAK_UNDERSHOOT, 0.24) \
		.set_trans(Tween.TRANS_SINE)
	sag.tween_method(_set_all.bind(level), WEAK_UNDERSHOOT, 1.0, 0.34) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_squash_between(1.18, 0.30, Vector3.ONE, Vector3(1.05, 0.92, 1.05))

	var stance := _rig.create_tween()
	_tweens.append(stance)
	stance.tween_interval(0.3)
	stance.tween_method(_set_posture, posture, _posture_for(level), 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var thud := _rig.create_tween()
	_tweens.append(thud)
	thud.tween_interval(1.44)
	thud.tween_callback(func() -> void: Audio.play("thud", 1.1))


## Grow or shrink one muscle group, with a small overshoot so it lands with weight.
func _swell(group: String, level: float, delay: float, duration: float) -> void:
	var from: float = bulk.get(group, 1.0)
	var over: float = level + (level - from) * 0.18
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_method(_set_group.bind(group), from, over, duration * 0.65) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_group.bind(group), over, level, duration * 0.45) \
		.set_trans(Tween.TRANS_SINE)


## A quick vibration, as if energy is building up inside the animal.
func _shudder(delay: float, duration: float, amount: float) -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(delay)
	var steps := 8
	for i in steps:
		var sign_x := 1.0 if i % 2 == 0 else -1.0
		var sign_y := 1.0 if i % 3 == 0 else -1.0
		tween.tween_method(_set_shake, shake, Vector3(amount * sign_x, amount * 0.5 * sign_y, 0.0),
			duration / float(steps)).set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(_set_shake, shake, Vector3.ZERO, 0.06)


## Species personality, layered on top of the shared sequence rather than replacing it.
func _flourish(delay: float) -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(delay)
	match _def.flourish:
		"stomp":
			# Front foot slams down and the body drops with it.
			tween.tween_callback(func() -> void: Audio.play("thud", 0.95))
			tween.tween_method(_set_lift_bias, 0.0, -_def.stand_height * 0.05, 0.10).set_trans(Tween.TRANS_SINE)
			tween.tween_method(_set_lift_bias, -_def.stand_height * 0.05, 0.0, 0.34) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"rear":
			# Front end lifts, like a horse half-rearing.
			tween.tween_callback(func() -> void: Audio.play("pop", 0.7))
			tween.tween_method(_set_pitch, 0.0, -0.22, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_method(_set_pitch, -0.22, 0.0, 0.42).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"flex":
			# A shoulder flex with a twist through the body.
			tween.tween_callback(func() -> void: Audio.play("pop", 1.1))
			tween.tween_method(_set_yaw, 0.0, 0.20, 0.18).set_trans(Tween.TRANS_SINE)
			tween.tween_method(_set_yaw, 0.20, -0.12, 0.20).set_trans(Tween.TRANS_SINE)
			tween.tween_method(_set_yaw, -0.12, 0.0, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_:
			# "puff": chest thrust, for the birds.
			tween.tween_callback(func() -> void: Audio.play("pop", 0.9))
			tween.tween_method(_set_group.bind("chest"), bulk.get("chest", 1.0),
				bulk.get("chest", 1.0) * 1.12, 0.16).set_trans(Tween.TRANS_SINE)
			tween.tween_method(_set_group.bind("chest"), bulk.get("chest", 1.0) * 1.12,
				bulk.get("chest", 1.0), 0.30).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _squash_between(delay: float, duration: float, from: Vector3, to: Vector3) -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_method(_set_squash, from, to, duration * 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_set_squash, to, Vector3.ONE, duration * 0.75) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _lift_dip(delay: float, duration: float) -> void:
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_method(_set_lift_bias, 0.0, -_def.stand_height * 0.03, duration * 0.5) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_method(_set_lift_bias, -_def.stand_height * 0.03, 0.0, duration * 0.6) \
		.set_trans(Tween.TRANS_SINE)


func kill_tweens() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


# --- Tween setters ------------------------------------------------------------

func _set_group(value: float, group: String) -> void:
	bulk[group] = value
	apply()


## Scales every group together, for the shared overshoot and rebound at the end.
func _set_all(value: float, level: float) -> void:
	for group in GROUPS:
		bulk[group] = level * value
	apply()


func _set_veins(value: float) -> void:
	vein_visibility = maxf(value, 0.0)
	apply()


func _set_posture(value: float) -> void:
	posture = value
	apply()


func _set_shake(value: Vector3) -> void:
	shake = value


func _set_squash(value: Vector3) -> void:
	squash = value


func _set_pitch(value: float) -> void:
	pitch = value


func _set_yaw(value: float) -> void:
	yaw = value


var _lift_bias := 0.0

func _set_lift_bias(value: float) -> void:
	_lift_bias = value
	apply()


func lift_total() -> float:
	return lift + _lift_bias
