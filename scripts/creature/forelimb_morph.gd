class_name ForelimbMorph
extends Node3D
## Two opposite treatments sharing one data-driven forelimb map.
##
## STRONG swells the animal's OWN upper foreleg into a huge muscle. Nothing is added and
## nothing is replaced: the shader pushes that one limb segment's vertices outwards from
## their own bone, so the fur, the markings and the colour the child chose all stretch over
## the muscle, and every joint, paw and wing tip stays exactly where it was authored.
## WEAK performs the one-for-one skinny-arm replacement requested for that opposite.

enum Mode { NEUTRAL, STRONG, WEAK }

const HUMAN_SKIN := Color("#e5a071")
const HUMAN_LIGHT := Color("#f3b486")
const HUMAN_SHADOW := Color("#bd7454")
const HIDDEN_LIMB_SCALE := 0.015

var mode := Mode.NEUTRAL
var amount := 0.0
var flex := 0.0
var left_weak_arm: Node3D = null
var right_weak_arm: Node3D = null

var _rig: CreatureRig = null
var _sides := {} ## side -> holder/config/weak/animated parts
var _clock := 0.0


static func create(rig: CreatureRig) -> ForelimbMorph:
	var morph := ForelimbMorph.new()
	morph.name = "ForelimbMorph"
	morph._rig = rig
	morph._build()
	return morph


func _build() -> void:
	var weak_skin := _material(HUMAN_SKIN)
	var weak_light := _material(HUMAN_LIGHT)
	var weak_shadow := _material(HUMAN_SHADOW)
	_build_side("left", -1.0, weak_skin, weak_light, weak_shadow)
	_build_side("right", 1.0, weak_skin, weak_light, weak_shadow)
	left_weak_arm = (_sides.left as Dictionary).weak
	right_weak_arm = (_sides.right as Dictionary).weak
	visible = false
	set_process(true)


func _build_side(side_name: String, sign_x: float,
		weak_skin: Material, weak_light: Material, weak_shadow: Material) -> Dictionary:
	var cfg := _rig.definition.forelimb_config(side_name)
	var holder := Node3D.new()
	holder.name = "%sForelimbReplacement" % side_name.capitalize()
	holder.rotation_degrees = cfg.rotation
	add_child(holder)

	var weak := _build_weak_arm(sign_x, weak_skin, weak_light, weak_shadow)
	weak.name = "WeakArm"
	holder.add_child(weak)

	var data := {
		"holder": holder,
		"bone": str(cfg.bone),
		"original_root": str(cfg.original_root),
		"chain": cfg.chain,
		"kind": str(cfg.kind),
		"offset": cfg.offset,
		"scale": float(cfg.scale),
		"weak": weak,
		"weak_biceps": weak.get_node("TinyBiceps"),
		"weak_biceps_scale": (weak.get_node("TinyBiceps") as Node3D).scale,
		"weak_hand": weak.get_node("LimpHand"),
		"enabled": true,
		"sign": sign_x,
	}
	_sides[side_name] = data
	return data


func _build_weak_arm(sign_x: float, skin: Material, light: Material,
		shadow: Material) -> Node3D:
	var root := Node3D.new()
	var unit := _rig.definition.stand_height * 0.22
	var shoulder := Vector3.ZERO
	var elbow := Vector3(sign_x * unit * 0.60, -unit * 0.76, sign_x * unit * 0.28)
	var wrist := Vector3(sign_x * unit * 0.76, -unit * 1.48, sign_x * unit * 0.38)

	_add_sphere(root, "SmallDeltoid", shoulder + Vector3(sign_x * unit * 0.10, -unit * 0.03, 0.0),
		Vector3(unit * 0.25, unit * 0.28, unit * 0.25), skin)
	_add_capsule(root, "ThinUpperArm", shoulder, elbow, unit * 0.095, skin)
	_add_sphere(root, "TinyBiceps", shoulder.lerp(elbow, 0.52) + Vector3(0.0, unit * 0.055, 0.0),
		Vector3(unit * 0.16, unit * 0.22, unit * 0.16), light)
	_add_sphere(root, "SkinnyElbow", elbow, Vector3.ONE * unit * 0.15, shadow)
	_add_capsule(root, "NarrowForearm", elbow, wrist, unit * 0.073, skin)
	_add_weak_hand(root, wrist, sign_x, unit, skin, light)
	return root


func _add_weak_hand(parent: Node3D, at: Vector3, sign_x: float, unit: float,
		skin: Material, light: Material) -> void:
	var hand := Node3D.new()
	hand.name = "LimpHand"
	hand.position = at
	parent.add_child(hand)
	_add_sphere(hand, "Palm", Vector3.ZERO,
		Vector3(unit * 0.31, unit * 0.38, unit * 0.24), skin)
	for finger in 4:
		var z := (float(finger) - 1.5) * unit * 0.075
		var start := Vector3(sign_x * unit * 0.04, -unit * 0.21, z)
		var finish := start + Vector3(sign_x * unit * 0.03, -unit * (0.27 + finger * 0.015), 0.0)
		_add_capsule(hand, "Finger%d" % finger, start, finish, unit * 0.038, light)
	_add_sphere(hand, "Thumb", Vector3(-sign_x * unit * 0.15, -unit * 0.06, -sign_x * unit * 0.10),
		Vector3(unit * 0.11, unit * 0.20, unit * 0.10), skin)


func _add_capsule(parent: Node3D, node_name: String, start: Vector3, finish: Vector3,
		radius: float, mat: Material) -> MeshInstance3D:
	var direction := finish - start
	var mesh := CapsuleMesh.new()
	mesh.radius = maxf(radius, 0.002)
	mesh.height = maxf(direction.length(), radius * 2.05)
	mesh.radial_segments = 14
	mesh.rings = 6
	var node := _instance(node_name, mesh, mat)
	node.position = start.lerp(finish, 0.5)
	if direction.length_squared() > 0.000001:
		node.quaternion = Quaternion(Vector3.UP, direction.normalized())
	parent.add_child(node)
	return node


func _add_sphere(parent: Node3D, node_name: String, at: Vector3, dimensions: Vector3,
		mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var node := _instance(node_name, mesh, mat)
	node.position = at
	node.scale = dimensions
	parent.add_child(node)
	return node


func _instance(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.76
	mat.metallic = 0.0
	return mat


func set_state(new_mode: int, value: float) -> void:
	mode = new_mode
	amount = clampf(value, 0.0, 1.18)
	_apply_state()


func set_mode(new_mode: int) -> void:
	mode = new_mode
	_apply_state()


func set_amount(value: float) -> void:
	amount = clampf(value, 0.0, 1.18)
	_apply_state()


func set_flex(value: float) -> void:
	flex = value


func set_side_enabled(side: String, enabled: bool) -> void:
	if not _sides.has(side):
		return
	(_sides[side] as Dictionary).enabled = enabled
	_apply_state()


func side_enabled(side: String) -> bool:
	return bool((_sides.get(side, {}) as Dictionary).get("enabled", false))


func replaces_front_limbs() -> bool:
	# STRONG keeps paws/wings and their floor contacts; only WEAK replaces the limb.
	return mode == Mode.WEAK and amount > 0.45


func original_root_bones() -> PackedStringArray:
	var result := PackedStringArray()
	for side in ["left", "right"]:
		result.append(str((_sides[side] as Dictionary).original_root))
	return result


func _apply_state() -> void:
	visible = mode != Mode.NEUTRAL and amount > 0.002
	var replacement_scale := maxf(amount, 0.001)
	var hidden_amount := clampf(amount, 0.0, 1.0)
	for side in _sides:
		var data: Dictionary = _sides[side]
		var enabled: bool = data.enabled
		var weak: Node3D = data.weak
		weak.visible = visible and enabled and mode == Mode.WEAK
		weak.scale = Vector3.ONE * replacement_scale * float(data.scale)
		var bone_index := _rig.skeleton.find_bone(str(data.original_root))
		if bone_index != -1:
			# STRONG leaves the appendage in place and swells it. Only WEAK performs the
			# one-for-one visual replacement that collapses the authored limb.
			var limb_scale := lerpf(1.0, HIDDEN_LIMB_SCALE,
				hidden_amount if enabled and mode == Mode.WEAK else 0.0)
			_rig.skeleton.set_bone_pose_scale(bone_index, Vector3.ONE * limb_scale)
			_rig.mark_posed(bone_index)
	_apply_strong_swell()


## STRONG grows the forelimb without touching a single bone: the shader pushes that one
## segment's vertices out from their own bone axis, which leaves every joint, the lower leg
## and the paw exactly where the animator put them. Scaling the bone instead would drag the
## paw outwards with it and lift the animal off its own feet.
func _apply_strong_swell() -> void:
	var amounts := {}
	for side in _sides:
		amounts["strong_forelimb_%s" % side] = strong_swell(str(side))
	_rig.set_weak_mesh(amounts)


## How swollen this side's forelimb currently is, 0.0 to 1.0.
func strong_swell(side: String) -> float:
	var data: Dictionary = _sides.get(side, {})
	if data.is_empty() or mode != Mode.STRONG or not bool(data.enabled):
		return 0.0
	return clampf(amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if not visible or _rig == null or _rig.skeleton == null:
		return
	_clock += delta
	_update_attachments()
	for side in _sides:
		var data: Dictionary = _sides[side]
		if mode == Mode.STRONG:
			continue # The swell lives in the creature's own shader; there is nothing to pose.
		# A tiny periodic failed flex: the biceps barely changes and the arm droops again.
		var sign_x: float = float(data.sign)
		var cycle := fmod(_clock, 4.8)
		var attempt := sin(clampf((cycle - 2.7) / 0.75, 0.0, 1.0) * PI)
		var weak_effort := maxf(attempt, flex)
		(data.weak_biceps as Node3D).scale = (data.weak_biceps_scale as Vector3) * (1.0 + weak_effort * 0.07)
		(data.weak_hand as Node3D).rotation.z = sign_x * (0.12 + weak_effort * 0.10)
		(data.weak as Node3D).rotation.z = sign_x * (0.035 + sin(_clock * 13.0) * 0.008 * amount)


func _update_attachments() -> void:
	var skeleton_to_body := _rig.body.global_transform.affine_inverse() * _rig.skeleton.global_transform
	for side in _sides:
		var data: Dictionary = _sides[side]
		var bone_index := _rig.skeleton.find_bone(str(data.bone))
		if bone_index == -1:
			continue
		var point: Vector3 = skeleton_to_body * _rig.skeleton.get_bone_global_pose(bone_index).origin
		(data.holder as Node3D).position = point + (data.offset as Vector3)
