class_name CreatureRig
extends Node3D
## A skinned animal model from res://models/animals.glb, wired so the trait system can
## drive it.
##
## Traits used to transform primitive shapes; now they pose bones. Same public surface
## either way - TraitVisuals, CreatureFactory and CreatureBrain never learn the
## difference. What changed underneath:
##   long/short  -> push the torso bones apart (see CreatureDeformer)
##   tall/short  -> telescope the leg bones, one leg at a time
##   strong      -> scale authored muscle bones
##   weak        -> radially contract mesh vertices around neutral bone centerlines
##   colour      -> a shader that re-lights the target colour with the texture's own
##                  light/dark pattern (see shaders/creature.gdshader for why)
##
## Fantasy add-on parts are still primitives, so BodyPartSpec and build_part_node stay.

const MODEL_PATH := "res://models/animals.glb"
const SHADER_PATH := "res://shaders/creature.gdshader"
const GROUND_CLEARANCE := 0.0 ## Sole/hoof contacts sit exactly on the platform surface.
const DEFAULT_RIB_PROFILE := {
	"center": Vector3(0.5, 0.56, 0.5),
	"size": Vector3(0.82, 0.30, 0.76),
	"count": 4.0,
	"depth": 0.020,
}
const MAX_WEAK_REGIONS := 16
const WEAK_REGION_SCALE := {
	"chest": 0.65,
	"neck": 0.72,
	"shoulder": 0.60,
	"front_limb": 0.57,
	"rear_limb": 0.60,
	"lower_limb": 0.64,
}
const WEAK_REGION_RADIUS := {
	"chest": 0.27,
	"neck": 0.13,
	"shoulder": 0.16,
	"front_limb": 0.11,
	"rear_limb": 0.11,
	"lower_limb": 0.085,
}

const ROLE_FALLBACKS := {
	"eye": Color("#1a1a22"),
	"dark": Color("#26262e"),
	"ice": Color("#9fe4ff"),
	"fire": Color("#ff8a3c"),
	"horn": Color("#efe3c8"),
	"wing": Color("#cfe8ff"),
	"crystal": Color("#b48cff"),
	"glow": Color("#b7ffdf"),
	"leaf": Color("#7ed957"),
}

var definition: AnimalDefinition = null
var body: Node3D = null ## Trait scaling lives here.
var fx_root: Node3D = null
var skeleton: Skeleton3D = null
var mesh_instance: MeshInstance3D = null
var material: ShaderMaterial = null

var sockets := {} ## socket name -> Node3D
var part_materials := {} ## role -> StandardMaterial3D, for fantasy add-ons

var deformer: CreatureDeformer = null ## Body length and per-leg lengths.
var muscle: MuscleDeformer = null ## STRONG/WEAK bulk and posture.
var feel: FeelDeformer = null ## HARD/SOFT shine, puff, squash and jiggle.

var tempo := 1.0 ## Idle animation speed; the SPEED modifier drives this.

## COLD's shivering, written by ColdEffect and folded into the idle pass. It lives on
## the rig rather than on the effect node so that freeing the effect - which happens on
## every trait re-apply, via clear_fx() - restores the neutral stance by itself.
var shiver_offset := Vector3.ZERO
var shiver_roll := 0.0
var moving := false ## Zoo creatures set this to swing their legs.

var _model_root: Node3D = null
var _base_model_pos := Vector3.ZERO
var _normal_scale := 1.0
var _trait_scale := Vector3.ONE ## SIZE/AGE scaling, kept apart from transient squash.
var _clock := 0.0
var _posed_bones := {} ## bone index -> true, so reset only touches what we changed
var _swayed := false ## Whether appendages currently carry a sway, so it can be cleared
var _weak_region_groups: Array[String] = []
var _ground_warning_emitted := false


static func create(def: AnimalDefinition) -> CreatureRig:
	var rig := CreatureRig.new()
	rig.name = "CreatureRig"
	rig._build(def)
	return rig


func _build(def: AnimalDefinition) -> void:
	definition = def
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)

	_model_root = _instantiate_model(def.model)
	if _model_root == null:
		push_error("Animal '%s': no node named '%s' in %s" % [def.id, def.model, MODEL_PATH])
		return
	body.add_child(_model_root)

	skeleton = _first_of_class(_model_root, "Skeleton3D")
	mesh_instance = _first_of_class(_model_root, "MeshInstance3D")
	if mesh_instance == null:
		push_error("Animal '%s': model has no MeshInstance3D" % def.id)
		return

	_normalise_height()
	_setup_material()
	_build_sockets()
	deformer = CreatureDeformer.new(self)
	muscle = MuscleDeformer.new(self)
	feel = FeelDeformer.new(self)


## Pull one animal out of the shared GLB and discard the other six. The PackedScene
## itself is cached by Godot's resource loader, so this stays cheap.
static func _instantiate_model(model_name: String) -> Node3D:
	var packed: PackedScene = load(MODEL_PATH)
	if packed == null:
		return null
	var scene := packed.instantiate()
	var wanted := scene.get_node_or_null(NodePath(model_name))
	if wanted == null:
		scene.free()
		return null
	scene.remove_child(wanted)
	scene.free()
	wanted.name = "Model"
	return wanted


## Source models range from 0.5 to 2.0 units tall. Scale every one to its declared
## stand_height and sit it on the floor, so trait maths and camera framing can assume
## a predictable size.
func _normalise_height() -> void:
	var box := mesh_instance.get_aabb()
	var height: float = maxf(box.size.y, 0.001)
	_normal_scale = definition.stand_height / height
	_model_root.scale = Vector3.ONE * _normal_scale
	_base_model_pos = Vector3(0.0, -box.position.y * _normal_scale, 0.0)
	_model_root.position = _base_model_pos


func _setup_material() -> void:
	var shader: Shader = load(SHADER_PATH)
	var base: BaseMaterial3D = mesh_instance.mesh.surface_get_material(0)
	material = ShaderMaterial.new()
	material.shader = shader
	if base != null and base.albedo_texture != null:
		material.set_shader_parameter("base_tex", base.albedo_texture)
	_configure_weak_regions()
	_configure_rib_profile()
	_reset_material()
	mesh_instance.material_override = material


func _reset_material() -> void:
	if material == null:
		return
	material.set_shader_parameter("tint", Color.WHITE)
	material.set_shader_parameter("tint_amount", 0.0)
	material.set_shader_parameter("wash", Color.WHITE)
	material.set_shader_parameter("wash_amount", 0.0)
	material.set_shader_parameter("emission_colour", Color.BLACK)
	material.set_shader_parameter("emission_energy", 0.0)
	material.set_shader_parameter("emission_flicker", 0.0)
	material.set_shader_parameter("roughness_value", 0.85)
	material.set_shader_parameter("metallic_value", 0.0)
	set_weak_mesh({})


## Build skinning-compatible radial deformation regions from neutral bone endpoints.
## No model axis is treated as limb length: every centerline comes from actual joints.
func _configure_weak_regions() -> void:
	if material == null or skeleton == null or mesh_instance == null:
		return
	var starts: Array[Vector3] = []
	var ends: Array[Vector3] = []
	var radii: Array[float] = []
	var scales: Array[float] = []
	_weak_region_groups.clear()
	var skeleton_to_mesh := _transform_to_ancestor(mesh_instance, _model_root).affine_inverse() \
		* _transform_to_ancestor(skeleton, _model_root)
	var mesh_span: float = maxf(mesh_instance.get_aabb().size.length(), 0.001)
	for group in MuscleDeformer.GROUPS:
		for bone_name in definition.bulk_bones_for(group):
			_append_weak_region(str(group), bone_name, skeleton_to_mesh, mesh_span,
				starts, ends, radii, scales)
	# The configured upper-limb muscle bones stop above the shin. Add each shin segment,
	# but deliberately exclude the last foot/hoof bone so extremities remain neutral.
	for leg in definition.legs:
		var bones: PackedStringArray = leg.get("bones", PackedStringArray())
		if not bones.is_empty():
			_append_weak_region("lower_limb", bones[0], skeleton_to_mesh, mesh_span,
				starts, ends, radii, scales)
	for i in range(starts.size(), MAX_WEAK_REGIONS):
		starts.append(Vector3.ZERO)
		ends.append(Vector3.UP)
		radii.append(0.001)
		scales.append(1.0)
	material.set_shader_parameter("weak_region_count", mini(_weak_region_groups.size(), MAX_WEAK_REGIONS))
	material.set_shader_parameter("weak_region_start", PackedVector3Array(starts))
	material.set_shader_parameter("weak_region_end", PackedVector3Array(ends))
	material.set_shader_parameter("weak_region_radius", PackedFloat32Array(radii))
	material.set_shader_parameter("weak_region_scale", PackedFloat32Array(scales))


## Local-to-ancestor composition works both before and after the rig enters the tree;
## unlike global_transform it does not emit errors during factory construction.
func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result


func _append_weak_region(group: String, bone_name: String, skeleton_to_mesh: Transform3D,
		mesh_span: float, starts: Array[Vector3], ends: Array[Vector3],
		radii: Array[float], scales: Array[float]) -> void:
	if _weak_region_groups.size() >= MAX_WEAK_REGIONS:
		return
	var idx := skeleton.find_bone(bone_name)
	if idx == -1:
		return
	var end_idx := _continuing_child(idx)
	var start_source := skeleton.get_bone_global_rest(idx).origin
	var end_source := Vector3.ZERO
	if end_idx != -1:
		end_source = skeleton.get_bone_global_rest(end_idx).origin
	else:
		var parent := skeleton.get_bone_parent(idx)
		if parent == -1:
			return
		end_source = start_source
		start_source = skeleton.get_bone_global_rest(parent).origin
	var start: Vector3 = skeleton_to_mesh * start_source
	var end: Vector3 = skeleton_to_mesh * end_source
	if start.distance_squared_to(end) < 0.000001:
		return
	starts.append(start)
	ends.append(end)
	radii.append(mesh_span * float(WEAK_REGION_RADIUS.get(group, 0.10)))
	scales.append(float(WEAK_REGION_SCALE.get(group, 0.65)))
	_weak_region_groups.append(group)


## Pick the child that continues the neutral incoming bone direction. This avoids
## accidentally using a shoulder branch as the longitudinal axis of a spine region.
func _continuing_child(idx: int) -> int:
	var children := skeleton.get_bone_children(idx)
	if children.is_empty():
		return -1
	if children.size() == 1:
		return children[0]
	var origin := skeleton.get_bone_global_rest(idx).origin
	var parent := skeleton.get_bone_parent(idx)
	var incoming := Vector3.ZERO
	if parent != -1:
		incoming = (origin - skeleton.get_bone_global_rest(parent).origin).normalized()
	var best := children[0]
	var best_alignment := -1.0
	for child in children:
		var outgoing := (skeleton.get_bone_global_rest(child).origin - origin).normalized()
		var alignment := absf(incoming.dot(outgoing)) if not incoming.is_zero_approx() else 0.0
		if alignment > best_alignment:
			best_alignment = alignment
			best = child
	return best


## Convert a species' normalised chest profile into this mesh's local coordinates.
## A missing or malformed profile falls back to a conservative generic chest area.
func _configure_rib_profile() -> void:
	if material == null or mesh_instance == null or mesh_instance.mesh == null:
		return
	var profile: Dictionary = DEFAULT_RIB_PROFILE.duplicate()
	for key in definition.rib_profile:
		profile[key] = definition.rib_profile[key]
	var center_n := BodyPartSpec.to_v3(profile.get("center", null), DEFAULT_RIB_PROFILE.center)
	var size_n := BodyPartSpec.to_v3(profile.get("size", null), DEFAULT_RIB_PROFILE.size)
	var box := mesh_instance.get_aabb()
	var center := Vector3(
		box.position.x + box.size.x * center_n.x,
		box.position.y + box.size.y * center_n.y,
		box.position.z + box.size.z * center_n.z
	)
	var size := Vector3(
		maxf(box.size.x * size_n.x, 0.001),
		maxf(box.size.y * size_n.y, 0.001),
		maxf(box.size.z * size_n.z, 0.001)
	)
	material.set_shader_parameter("rib_center", center)
	material.set_shader_parameter("rib_size", size)
	material.set_shader_parameter("rib_count", clampf(float(profile.get("count", 4.0)), 3.0, 5.0))
	# The shader works in source-mesh units; express the desired normalised-world dent
	# in those units so each animal receives an equally subtle treatment.
	material.set_shader_parameter("rib_depth", maxf(float(profile.get("depth", 0.020)) / _normal_scale, 0.001))


## Apply independent group amounts derived from the current neutral/strong/weak state.
## Shader parameters are absolute, so repeated switching cannot accumulate deformation.
func set_weak_mesh(group_amounts: Dictionary) -> void:
	if material == null:
		return
	var amounts := PackedFloat32Array()
	for group in _weak_region_groups:
		amounts.append(clampf(float(group_amounts.get(group, 0.0)), 0.0, 1.0))
	for i in range(amounts.size(), MAX_WEAK_REGIONS):
		amounts.append(0.0)
	material.set_shader_parameter("weak_region_amount", amounts)
	material.set_shader_parameter("weak_rib_amount",
		clampf(float(group_amounts.get("chest", 0.0)), 0.0, 1.0))


## Sockets sit in normalised space under Body, so their offsets read the same on a
## chicken and a horse. They do not follow bone animation, which is fine - the idle
## motion is a gentle bob, not a gallop.
func _build_sockets() -> void:
	for socket_name in definition.sockets:
		var node := Node3D.new()
		node.name = "socket_%s" % socket_name
		node.position = _socket_position(str(socket_name))
		body.add_child(node)
		sockets[str(socket_name)] = node


func _socket_position(socket_name: String) -> Vector3:
	var offset := definition.socket_offset(socket_name)
	var bone := definition.socket_bone(socket_name)
	if skeleton == null or bone.is_empty():
		return Vector3(0, definition.stand_height, 0) + offset
	var idx := skeleton.find_bone(bone)
	if idx == -1:
		return Vector3(0, definition.stand_height, 0) + offset
	var rest := skeleton.get_bone_global_rest(idx).origin * _normal_scale
	rest.y += _model_root.position.y
	return rest + offset


# --- Modifier surface --------------------------------------------------------

## Return every bone and material to its authored state. Trait modifiers always
## recompute from this baseline, so applying them is idempotent and order-independent.
func reset_modifiers() -> void:
	if skeleton != null:
		for idx in _posed_bones:
			skeleton.set_bone_pose_scale(idx, Vector3.ONE)
			skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_rest(idx).basis.get_rotation_quaternion())
			skeleton.set_bone_pose_position(idx, skeleton.get_bone_rest(idx).origin)
		_posed_bones.clear()
	_trait_scale = Vector3.ONE
	body.scale = Vector3.ONE
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	_model_root.position = _base_model_pos
	tempo = 1.0
	shiver_offset = Vector3.ZERO
	shiver_roll = 0.0
	if deformer != null:
		deformer.reset()
	if muscle != null:
		muscle.reset()
	if feel != null:
		feel.reset()
	_reset_material()
	clear_fx()


func scale_body(factor: Vector3) -> void:
	_trait_scale *= factor
	body.scale = _trait_scale


## The colour trait. Repaints via the shader rather than multiplying, so dark animals
## still change colour legibly.
func recolor(color: Color) -> void:
	if material == null:
		return
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("tint_amount", 1.0)


func set_role_color(role: String, color: Color) -> void:
	# "skin" is the animal itself; other roles belong to fantasy add-on parts.
	if role == "skin":
		recolor(color)
	elif part_materials.has(role):
		part_materials[role].albedo_color = color


## A partial colour shift, used by hot/cold/old rather than a full repaint.
func tint_role(role: String, color: Color, amount: float) -> void:
	if role != "skin" or material == null:
		return
	material.set_shader_parameter("wash", color)
	material.set_shader_parameter("wash_amount", clampf(amount, 0.0, 1.0))


func set_emission(role: String, color: Color, energy: float) -> void:
	if role != "skin" or material == null:
		return
	material.set_shader_parameter("emission_colour", color)
	material.set_shader_parameter("emission_energy", maxf(energy, 0.0))


## 0 holds emission at a flat brightness; >0 lets the shader's cheap sine flicker gut
## and flare it, which is what makes a hot creature look lit by fire rather than paint.
func set_emission_flicker(amount: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("emission_flicker", clampf(amount, 0.0, 1.0))


## A quick brighten-then-settle on the emission energy - the "whoosh" of catching
## alight - without disturbing whatever steady-state energy the trait already set.
func pulse_emission(peak: float, settle: float, duration: float) -> void:
	if material == null:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("emission_energy", v),
		settle, peak, duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("emission_energy", v),
		peak, settle, duration * 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func set_surface(role: String, roughness: float, metallic: float) -> void:
	if role != "skin" or material == null:
		return
	material.set_shader_parameter("roughness_value", clampf(roughness, 0.0, 1.0))
	material.set_shader_parameter("metallic_value", clampf(metallic, 0.0, 1.0))


func _scale_bones(bones: PackedStringArray, factor: Vector3) -> void:
	if skeleton == null:
		return
	for bone in bones:
		var idx := skeleton.find_bone(bone)
		if idx == -1:
			continue
		skeleton.set_bone_pose_scale(idx, factor)
		_posed_bones[idx] = true


func mark_posed(bone_index: int) -> void:
	_posed_bones[bone_index] = true


func normal_scale() -> float:
	return _normal_scale


## Where the model sits after height normalisation, so overlays can be placed in the
## same space as the sockets.
func model_base_y() -> float:
	return _base_model_pos.y


## The deformer slides the model to keep a lengthened body centred on its platform.
func set_model_offset(offset: Vector3) -> void:
	if _model_root != null:
		_model_root.position = _base_model_pos + offset


func attach_to_socket(socket_name: String, node: Node3D) -> void:
	var host: Node3D = sockets.get(socket_name, body)
	host.add_child(node)


func material_for(role: String) -> StandardMaterial3D:
	if part_materials.has(role):
		return part_materials[role]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Content.role_color(role, ROLE_FALLBACKS.get(role, definition.skin_color))
	mat.roughness = 0.8
	part_materials[role] = mat
	return mat


func add_fx(node: Node3D, at := Vector3.ZERO) -> void:
	node.position = at
	fx_root.add_child(node)
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = true


func clear_fx() -> void:
	for child in fx_root.get_children():
		child.queue_free()


## Roughly where the top of the creature is right now, for labels and camera framing.
func crown_height() -> float:
	var deform_lift: float = deformer.lift if deformer != null else 0.0
	return definition.stand_height * _trait_scale.y + deform_lift


## Used by the naming screen's ghost: a flat translucent silhouette instead of the
## textured model.
func make_ghost(color: Color, alpha := 0.3) -> void:
	if mesh_instance == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mesh_instance.material_override = mat
	clear_fx()


# --- Idle life ---------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta * tempo
	# Idle motion is added on top of the deformation, never in place of it, so a
	# transformed creature keeps its new proportions while it breathes and walks.
	# Both deformers contribute to the body transform, so their effects compose rather
	# than overwrite: a creature can be long, tall, strong and walking all at once.
	var lift := 0.0
	var squash := Vector3.ONE
	var offset := Vector3.ZERO
	var lean := 0.0
	var twist := 0.0
	var posture := 0.0
	if deformer != null:
		lift += deformer.lift + deformer.bounce
		squash *= deformer.squash
	if muscle != null:
		lift += muscle.lift_total()
		squash *= muscle.squash
		offset = muscle.shake
		lean = muscle.pitch
		twist = muscle.yaw
		posture = muscle.posture

	# How freely anything is allowed to move: a hard animal is stiff, a soft one loose.
	var motion := 1.0
	if feel != null:
		feel.tick(delta, moving)
		squash *= feel.scale_multiplier
		offset += feel.offset
		motion = feel.motion_scale()

	# Grounded animals must not translate vertically during neutral idle. A newly built
	# preview starts at clock zero, so the old sine bob made every selected animal rise
	# during its first half-second. Only explicitly hovering species retain vertical bob.
	# COLD's shiver is horizontal only, deliberately: a vertical component would fight
	# the grounding pass below and lift the feet off the platform.
	body.position = offset + shiver_offset + Vector3(0.0, lift
		+ sin(_clock * 1.1) * 0.05 * definition.hover, 0.0)
	body.rotation.x = lean
	body.rotation.y = twist
	body.rotation.z = sin(_clock * 0.9) * 0.01 * (1.0 - posture * 0.4) * motion + shiver_roll
	body.scale = _trait_scale * squash
	_swing_legs((sin(_clock * 5.0) * 0.5 if moving else 0.0) * motion)
	_sway_appendages(motion)
	_apply_grounding(delta)


## Explicit sole/hoof points after skinning, adjective proportions and the base idle
## animation. The result is in rig-local coordinates, where Y=0 is the platform plane.
func foot_contact_positions() -> Array[Vector3]:
	var contacts: Array[Vector3] = []
	if skeleton == null or definition == null or body == null:
		return contacts
	var skeleton_to_body := body.global_transform.affine_inverse() * skeleton.global_transform
	for leg in definition.legs:
		var bones: PackedStringArray = leg.get("bones", PackedStringArray())
		if bones.is_empty():
			contacts.append(Vector3(INF, INF, INF))
			continue
		var foot := skeleton.find_bone(bones[bones.size() - 1])
		if foot == -1:
			contacts.append(Vector3(INF, INF, INF))
			continue
		var point: Vector3 = skeleton_to_body * skeleton.get_bone_global_pose(foot).origin
		point += definition.foot_contact_for(str(leg.get("id", "")))
		contacts.append(body.transform * point)
	return contacts


## Final idle stance pass. It first supports the body on the longest-reaching foot,
## then gives each shorter front/rear pair only the extra reach it needs. Longer legs
## are never shortened. There is no IK rig in these assets, so minimum local joint
## translation along the already-authored chain is the least invasive available fallback.
func _apply_grounding(delta: float, instant := false) -> void:
	if deformer == null or definition == null or definition.legs.is_empty():
		return
	# Leave the factory-authored neutral stance alone. This prevents the slight upward
	# pop that occurred when an unmodified selected animal first entered the scene tree.
	if not deformer.requires_grounding():
		return
	var settled := not moving and not deformer.is_animating() \
		and (muscle == null or not muscle.is_animating()) \
		and (feel == null or not feel.is_animating())
	if not settled:
		deformer.clear_ground_extensions(false, delta)
		_support_lowest_contact()
		return

	_support_lowest_contact()
	var contacts := foot_contact_positions()
	var pair_targets := {"front": 0.0, "rear": 0.0}
	var scale_y := maxf(absf(body.scale.y), 0.001)
	for i in mini(contacts.size(), definition.legs.size()):
		if not is_finite(contacts[i].y):
			continue
		var pair := "front" if str(definition.legs[i].get("id", "")).begins_with("front") else "rear"
		# A positive Y means this sole floats above the plane and needs more reach.
		var needed := deformer.ground_extension(i) \
			+ maxf(contacts[i].y - GROUND_CLEARANCE, 0.0) / scale_y
		pair_targets[pair] = maxf(float(pair_targets[pair]), needed)
	var targets: Array[float] = []
	for leg in definition.legs:
		var pair := "front" if str(leg.get("id", "")).begins_with("front") else "rear"
		targets.append(maxf(float(pair_targets[pair]), 0.0))
	var limited := deformer.update_ground_extensions(targets, delta, instant)
	if skeleton.has_method("force_update_all_bone_transforms"):
		skeleton.force_update_all_bone_transforms()
	_support_lowest_contact()
	if limited and not _ground_warning_emitted:
		_ground_warning_emitted = true
		push_warning("Animal '%s': stance correction reached the 18%% leg-extension limit" % definition.id)


## Translate the body only enough for the lowest explicit sole point to touch. This
## prevents penetration without using tails, fur or whole-mesh bounds as contacts.
func _support_lowest_contact() -> void:
	var contacts := foot_contact_positions()
	var lowest := INF
	for contact in contacts:
		if is_finite(contact.y):
			lowest = minf(lowest, contact.y)
	if not is_finite(lowest):
		return
	var correction := GROUND_CLEARANCE - lowest
	var max_adjust := definition.stand_height * 0.25
	var applied := clampf(correction, -max_adjust, max_adjust)
	body.position.y += applied
	if not is_equal_approx(applied, correction) and not _ground_warning_emitted:
		_ground_warning_emitted = true
		push_warning("Animal '%s': stance correction reached the 25%% body-height limit" % definition.id)


## Test/diagnostic entry point; normal gameplay uses the same pass from _process().
func solve_idle_grounding_immediately() -> void:
	_apply_grounding(1.0, true)


## No walk cycles ship with these models, so the legs are posed procedurally: opposite
## legs swing out of phase around the bone's rest pose.
## Ears, tails and wings hang loose on a soft animal and lock up on a hard one. Rotation
## is this class's component to write, which is why the floppiness lives here rather than
## in FeelDeformer.
func _sway_appendages(motion: float) -> void:
	if skeleton == null or definition.floppy_bones.is_empty() or feel == null:
		return
	var floppy := feel.floppiness()
	var amount: float = (0.05 + floppy * 0.22) * motion
	if amount < 0.008 and not _swayed:
		return
	_swayed = amount >= 0.008
	var index := 0
	for bone in definition.floppy_bones:
		var idx := skeleton.find_bone(bone)
		index += 1
		if idx == -1:
			continue
		var phase := _clock * (2.2 + floppy * 1.4) + float(index) * 1.3
		var rest := skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.RIGHT, sin(phase) * amount))
		_posed_bones[idx] = true


func _swing_legs(amount: float) -> void:
	if skeleton == null or definition.leg_bones.is_empty():
		return
	var index := 0
	for bone in definition.leg_bones:
		var idx := skeleton.find_bone(bone)
		index += 1
		if idx == -1:
			continue
		var phase := 1.0 if index % 2 == 0 else -1.0
		var rest := skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.RIGHT, amount * phase))
		_posed_bones[idx] = true


# --- Fantasy add-on parts (still primitives) ---------------------------------

## Build one pivot-plus-mesh pair for a fantasy add-on (horns, wings, crystals).
static func build_part_node(spec: BodyPartSpec, mat: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = spec.id
	pivot.position = spec.pivot
	pivot.rotation_degrees = spec.rotation_deg

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _make_mesh(spec)
	mi.position = spec.offset
	if spec.shape != "box" and not is_equal_approx(spec.size.x, spec.size.z) and spec.size.x > 0.0:
		mi.scale = Vector3(1.0, 1.0, spec.size.z / spec.size.x)
	mi.material_override = mat
	pivot.add_child(mi)
	return pivot


static func _make_mesh(spec: BodyPartSpec) -> Mesh:
	match spec.shape:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = maxf(spec.size.x * 0.5, 0.001)
			sphere.height = maxf(spec.size.y, 0.002)
			sphere.radial_segments = 18
			sphere.rings = 9
			return sphere
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = maxf(spec.size.x * 0.5, 0.001)
			capsule.height = maxf(spec.size.y, spec.size.x * 1.02)
			capsule.radial_segments = 14
			capsule.rings = 4
			return capsule
		"cylinder", "cone":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.0 if spec.shape == "cone" else maxf(spec.size.x * 0.5, 0.001)
			cylinder.bottom_radius = maxf(spec.size.x * 0.5, 0.001)
			cylinder.height = maxf(spec.size.y, 0.002)
			cylinder.radial_segments = 14
			return cylinder
		_:
			var box := BoxMesh.new()
			box.size = spec.size
			return box


func _first_of_class(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var found := _first_of_class(c, cls)
		if found != null:
			return found
	return null
