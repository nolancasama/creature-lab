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
##   strong/weak -> morph the two existing front legs or wings into opposite arm forms
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
const MAX_WEAK_REGIONS := 20
const MAX_PATCHES := 6 ## Mirrors the shader's own cap on AGE skin markings.
const WEAK_REGION_SCALE := {
	"chest": 0.65,
	"neck": 0.72,
	"shoulder": 0.60,
	"front_limb": 0.57,
	"rear_limb": 0.60,
	"lower_limb": 0.64,
	# Above 1.0, so STRONG swells this region instead of slimming it. The animal's own
	# upper foreleg is what becomes the muscle, so it has to grow far past its authored
	# girth - anything subtle here just reads as a slightly chubby leg.
	"strong_forelimb_left": 3.2,
	"strong_forelimb_right": 3.2,
}
const WEAK_REGION_RADIUS := {
	"chest": 0.27,
	"neck": 0.13,
	"shoulder": 0.16,
	"front_limb": 0.11,
	"rear_limb": 0.11,
	"lower_limb": 0.085,
	# Tight, unlike the slimming regions: a swell pushes every vertex it catches outwards,
	# so a generous radius would balloon the chest and the far leg along with this one.
	"strong_forelimb_left": 0.085,
	"strong_forelimb_right": 0.085,
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
var accessory_root: Node3D = null ## Worn items (YOUNG's bib, pacifier); inherits body scale.
var fx_root: Node3D = null
var thermal_fx_root: Node3D = null ## HOT/COLD's particle systems - see thermal_applied.
var thermal_follows_body := false ## HOT moves with the creature; COLD's ground patch does not.
var skeleton: Skeleton3D = null
var mesh_instance: MeshInstance3D = null
var material: ShaderMaterial = null

var sockets := {} ## socket name -> Node3D
var part_materials := {} ## role -> StandardMaterial3D, for fantasy add-ons

var deformer: CreatureDeformer = null ## Body length and per-leg lengths.
var muscle: MuscleDeformer = null ## STRONG/WEAK one-for-one forelimb morphs.
var feel: FeelDeformer = null ## HARD/SOFT shine, puff, squash and jiggle.
var pace: PaceDeformer = null ## FAST/SLOW dashes, twitches and drawn-out actions.
var gait: Gait = null ## The species walk cycle.

## Written by Gait each frame and read below when the body transform is assembled. Kept as
## fields rather than returned, because the body transform is the sum of six contributors
## and the walk is only one of them - a creature can be big, cold, dashing and walking at
## once, and every one of those has a claim on this transform.
var gait_body_offset := Vector3.ZERO
var gait_body_roll := 0.0
var gait_body_pitch := 0.0
var selection_reaction: SelectionReaction = null ## Short picker-only, data-driven flourish.

var tempo := 1.0 ## Idle animation speed; the SPEED modifier drives this.
var movement_locked := false ## Transformation presentation keeps FAST on the platform.

## COLD's shivering, written by ColdEffect and folded into the idle pass. It lives on
## the rig rather than on the effect node so that freeing the effect - which happens on
## every trait re-apply, via clear_fx() - restores the neutral stance by itself.
var shiver_offset := Vector3.ZERO
var shiver_roll := 0.0

## The THERMAL value (see traits.json) that thermal_fx_root currently shows, or NAN if
## nothing has ever been built. Every card tap re-applies the WHOLE committed trait set
## - see TraitVisuals.apply_all - so without this, tapping an unrelated card would tear
## down and rebuild HOT/COLD's particle systems too. A freshly-built GPUParticles3D
## starts with zero active particles and takes up to its own `lifetime` (snow is 5s,
## mist 4s) to look full again, which is exactly the "takes a few seconds" a repeated,
## needless rebuild produces. TraitVisuals checks this before touching
## thermal_fx_root, so an unchanged HOT/COLD is left running untouched.
var thermal_applied := NAN
## Whether YOUNG's accessories are currently on. Survives reset_modifiers() for the same
## reason thermal_applied does: every card tap re-applies the whole committed trait set,
## and the baby sound must greet the student once when the creature becomes young - not
## again on every unrelated tap that happens afterwards.
var young_applied := false
var old_applied := false ## The same one-shot gate for OLD's elderly chuckle.
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
var _head_bounds := AABB()
var _head_bounds_ready := false
var _head_points := PackedVector3Array() ## Dominant head-family vertices, in body space.
var _bone_accessory_hosts: Array[BoneAttachment3D] = [] ## Native head-bone mounts for face props.


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
	# Deliberately under Body, unlike fx_root: accessories are worn, so they have to
	# inherit whatever scale SIZE gave the animal. A bib parented beside Body instead of
	# inside it would stay its own size while a BIG creature grew out from under it.
	accessory_root = Node3D.new()
	accessory_root.name = "Accessories"
	body.add_child(accessory_root)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	thermal_fx_root = Node3D.new()
	thermal_fx_root.name = "ThermalFx"
	add_child(thermal_fx_root)

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
	pace = PaceDeformer.new(self)
	gait = Gait.new(self, def)
	selection_reaction = SelectionReaction.new(self)


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
	material.set_shader_parameter("patch_count", 0)
	material.set_shader_parameter("patch_amount", 0.0)
	material.set_shader_parameter("grey_dark_amount", 0.0)
	material.set_shader_parameter("grey_coat_amount", 0.0)
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
	# One region per forelimb, so STRONG can swell whichever sides are actually wearing the
	# word. Taken from the authored forelimb chain rather than the muscle-group lists, so
	# the swell follows the same limb the WEAK replacement uses.
	for side in ["left", "right"]:
		var forelimb := definition.forelimb_config(side)
		var forelimb_chain: PackedStringArray = forelimb.chain
		if forelimb_chain.is_empty():
			continue
		# The second bone, not the first: a quadruped's humerus is buried inside its chest,
		# so swelling it puffs the ribs rather than the leg. The bone below it is the free
		# leg the child actually reads as the foreleg. Stopping short of the paw keeps the
		# muscle belly high on that leg, where an upper arm's would be.
		var segment := 1 if forelimb_chain.size() >= 2 else 0
		_append_weak_region("strong_forelimb_%s" % side, str(forelimb_chain[segment]),
			skeleton_to_mesh, mesh_span, starts, ends, radii, scales, 0.20, -0.10)
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


## `overshoot` lengthens the capsule past both joints, as a fraction of the segment. The
## shader deliberately pins the first and last sixth of every region so joints keep their
## shape, which is right for slimming a limb but leaves a full-width collar at each end -
## and STRONG's replacement arm has to sit exactly where that collar is. Pushing the
## capsule's ends outside the real segment puts the fully squeezed middle over all of it.
func _append_weak_region(group: String, bone_name: String, skeleton_to_mesh: Transform3D,
		mesh_span: float, starts: Array[Vector3], ends: Array[Vector3],
		radii: Array[float], scales: Array[float], overshoot_start := 0.0,
		overshoot_end := 0.0) -> void:
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
	if not is_zero_approx(overshoot_start) or not is_zero_approx(overshoot_end):
		# Asymmetric, and negative values pull an end inwards: the muscle belly needs to
		# stop short of the paw, which stays exactly as the animator authored it.
		var along := end - start
		start -= along * overshoot_start
		end += along * overshoot_end
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
	if pace != null:
		pace.reset()
	_reset_material()
	clear_fx()
	clear_accessories()


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


## Where a point in normalised body space lands in the mesh's own model space - the space
## the shader's VERTEX (and so its cheek centres) live in. Sockets, accessories and every
## trait offset are authored in body space, which is the model scaled by _normal_scale and
## lifted onto the floor, so anything handed to the shader has to come back out of it.
func to_model_space(body_point: Vector3) -> Vector3:
	if _model_root == null or is_zero_approx(_normal_scale):
		return body_point
	return (body_point - _model_root.position) / _normal_scale


## AGE's skin markings - YOUNG's blush, OLD's grey muzzle and brow. `spots` is a list of
## {"at": Vector3, "radius": float} in body space; both are converted here, so callers never
## have to know the model's internal scale. The shader caps the list at MAX_PATCHES.
func set_patches(spots: Array, color: Color, amount: float) -> void:
	if material == null:
		return
	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	for spot in spots:
		if centers.size() >= MAX_PATCHES:
			break
		centers.append(to_model_space(spot.get("at", Vector3.ZERO)))
		radii.append(maxf(float(spot.get("radius", 0.0)) / maxf(_normal_scale, 0.0001), 0.0001))
	material.set_shader_parameter("patch_count", centers.size())
	material.set_shader_parameter("patch_center", centers)
	material.set_shader_parameter("patch_radius", radii)
	material.set_shader_parameter("patch_colour", color)
	material.set_shader_parameter("patch_amount", clampf(amount, 0.0, 1.0) if centers.size() > 0 else 0.0)


## OLD's coat greying. `dark` greys only the texture's dark markings (a tiger's stripes),
## `coat` greys everything gently (a cat going silver). Both use the patch colour, so a
## species picks its greying style without picking a second colour.
func set_greying(dark: float, coat: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("grey_dark_amount", clampf(dark, 0.0, 1.0))
	material.set_shader_parameter("grey_coat_amount", clampf(coat, 0.0, 1.0))


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


## Worn accessories, in the same normalised space as the sockets. Cleared and rebuilt on
## every apply_all like the rest of the trait surface - these are a handful of static
## primitives, so unlike the thermal particle systems there is nothing expensive to
## preserve across a rebuild.
func add_accessory(node: Node3D, at := Vector3.ZERO) -> void:
	node.position = at
	accessory_root.add_child(node)


## Mount face props on Godot's native bone follower. The prop is authored in Body space,
## so preserve that fitted transform while reparenting it beneath the selected bone.
func add_bone_accessory(node: Node3D, at: Vector3, bone: String) -> void:
	if skeleton == null or bone.is_empty() or skeleton.find_bone(bone) == -1:
		add_accessory(node, at)
		return
	if skeleton.has_method("force_update_all_bone_transforms"):
		skeleton.force_update_all_bone_transforms()
	node.position = at
	var fitted_in_body := node.transform
	var bone_index := skeleton.find_bone(bone)
	# BoneAttachment3D does not reliably acquire a pose-scaled bone transform until it
	# enters the SceneTree. Comparison-screen creatures are assembled off-tree, so deriving
	# the child's local transform from the still-identity host made YOUNG's head scale apply
	# to the pacifier a second time on the first live frame. Use the skeleton's current pose
	# directly and initialise the host to that same transform; its native updates can then
	# take over without changing the fitted mouth contact.
	var bone_rest_in_body := _bone_rest_transform_in_body(bone)
	var host := BoneAttachment3D.new()
	host.name = "AccessoryBone_%s" % node.name
	skeleton.add_child(host)
	host.bone_idx = bone_index
	host.override_pose = false
	host.transform = skeleton.get_bone_global_pose(bone_index)
	# Face props are measured from the neutral mesh. Store that rest-bone-relative fit and
	# let the live bone apply SHORT/LONG and YOUNG head scale exactly once.
	node.transform = bone_rest_in_body.affine_inverse() * fitted_in_body
	host.add_child(node)
	_bone_accessory_hosts.append(host)


## Refresh native mounts immediately after a snapped deformation. During normal animation
## BoneAttachment3D receives skeleton updates itself; this method is for factory/test paths
## which can change a pose before the rig enters the SceneTree.
func sync_bone_accessories() -> void:
	if skeleton == null or _bone_accessory_hosts.is_empty():
		return
	if skeleton.has_method("force_update_all_bone_transforms"):
		skeleton.force_update_all_bone_transforms()
	for host in _bone_accessory_hosts:
		if is_instance_valid(host):
			if host.is_inside_tree():
				host.on_skeleton_update()
			elif host.bone_idx >= 0:
				# Match the transform BoneAttachment3D will receive on its first live frame.
				host.transform = skeleton.get_bone_global_pose(host.bone_idx)


func find_accessory(accessory_name: String) -> Node3D:
	if accessory_root != null:
		var loose := accessory_root.find_child(accessory_name, true, false)
		if loose is Node3D:
			return loose as Node3D
	for host in _bone_accessory_hosts:
		if not is_instance_valid(host):
			continue
		var mounted := host.find_child(accessory_name, true, false)
		if mounted is Node3D:
			return mounted as Node3D
	return null


func accessory_transform_in_body(node: Node3D) -> Transform3D:
	return _transform_to_ancestor(node, body)


func _bone_transform_in_body(bone: String) -> Transform3D:
	if skeleton == null:
		return Transform3D.IDENTITY
	var index := skeleton.find_bone(bone)
	if index == -1:
		return Transform3D.IDENTITY
	return _transform_to_ancestor(skeleton, body) * skeleton.get_bone_global_pose(index)


func _bone_rest_transform_in_body(bone: String) -> Transform3D:
	if skeleton == null:
		return Transform3D.IDENTITY
	var index := skeleton.find_bone(bone)
	if index == -1:
		return Transform3D.IDENTITY
	return _transform_to_ancestor(skeleton, body) * skeleton.get_bone_global_rest(index)


func _bone_origin_in_body(bone: String, _rest := false) -> Vector3:
	return _bone_transform_in_body(bone).origin


func clear_accessories() -> void:
	if accessory_root != null:
		for child in accessory_root.get_children():
			accessory_root.remove_child(child)
			child.queue_free()
	for host in _bone_accessory_hosts:
		if not is_instance_valid(host):
			continue
		var parent := host.get_parent()
		if parent != null:
			parent.remove_child(host)
		host.queue_free()
	_bone_accessory_hosts.clear()


## Pose-scale one named bone. YOUNG uses this for the head; keeping it public means
## TraitVisuals never reaches into the skeleton itself.
func scale_bone(bone: String, factor: Vector3) -> void:
	_scale_bones(PackedStringArray([bone]), factor)


func add_fx(node: Node3D, at := Vector3.ZERO) -> void:
	node.position = at
	fx_root.add_child(node)
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = true


## A translucent copy of the animal left behind at `at`, fading out within a fraction of
## a second. Drawn from the same mesh but with no skeleton attached, so it costs one
## unskinned draw and holds the bind pose - at this lifetime nobody reads the pose, only
## the silhouette. Parented to fx_root rather than body so the dash that spawned it does
## not drag it along; a ghost that follows the animal is not an afterimage.
func spawn_afterimage(at: Vector3, life: float) -> void:
	if mesh_instance == null or mesh_instance.mesh == null or not is_inside_tree():
		return
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh_instance.mesh
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.78, 0.90, 1.0, 0.26)
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost.material_override = ghost_mat
	fx_root.add_child(ghost)
	ghost.transform = Transform3D(Basis.IDENTITY, at) 		* (global_transform.affine_inverse() * mesh_instance.global_transform)
	var fade := create_tween()
	fade.tween_property(ghost_mat, "albedo_color:a", 0.0, life)
	fade.tween_callback(ghost.queue_free)


func clear_fx() -> void:
	for child in fx_root.get_children():
		child.queue_free()


## Same as add_fx, but for HOT/COLD's own root, which reset_modifiers() deliberately
## does not sweep - see thermal_applied. Persistent HOT particles use local coordinates
## so already-emitted flames travel with a dashing creature instead of trailing behind.
func add_thermal_fx(node: Node3D, at := Vector3.ZERO, follows_body := false) -> void:
	node.position = at
	thermal_fx_root.add_child(node)
	if follows_body:
		thermal_follows_body = true
		if node is GPUParticles3D:
			(node as GPUParticles3D).local_coords = true
		_sync_thermal_fx_to_body()
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = true


## Does not touch thermal_applied: TraitVisuals sets that itself, either to the value
## it is about to build (rebuilding) or to NAN (nothing left to show).
func clear_thermal_fx() -> void:
	for child in thermal_fx_root.get_children():
		child.queue_free()
	thermal_follows_body = false
	thermal_fx_root.transform = Transform3D.IDENTITY


## Follow the creature's translation, turning and persistent trait scale without inheriting
## transient squash. The scale matters: a shrunk animal must carry its flame anchors down with
## its body instead of leaving them floating at the neutral height.
func _sync_thermal_fx_to_body() -> void:
	if not thermal_follows_body or thermal_fx_root == null or body == null:
		return
	var body_basis := body.transform.basis.orthonormalized().scaled(_trait_scale)
	thermal_fx_root.transform = Transform3D(body_basis, body.position)


## Roughly where the top of the creature is right now, for labels and camera framing.
## The head's actual bounding box, in body space, found from the mesh's own skin weights:
## every vertex whose dominant bone is the head bone or one of its descendants. This is the
## one measurement that makes face props placeable without per-species guesswork - it gives
## the real nose tip, chin, crown and width of a chicken's head and a horse's alike, where
## a scalar "muzzle reach" only ever gave a length and left the height and angle to be
## guessed at. Computed once per rig and cached; the meshes are a few thousand vertices.
func head_bounds() -> AABB:
	if _head_bounds_ready:
		return _head_bounds
	_head_bounds_ready = true
	_head_points.clear()
	_head_bounds = AABB(Vector3(0, definition.stand_height * 0.8, 0), Vector3.ONE * 0.1)
	if skeleton == null or mesh_instance == null or mesh_instance.mesh == null:
		return _head_bounds

	var head_bone := definition.socket_bone("head_top")
	var root := skeleton.find_bone(head_bone)
	if root == -1:
		return _head_bounds

	# The head bone plus everything hanging off it - jaw, ears, horns.
	var family := {root: true}
	for b in skeleton.get_bone_count():
		var walk := skeleton.get_bone_parent(b)
		while walk != -1:
			if walk == root:
				family[b] = true
				break
			walk = skeleton.get_bone_parent(walk)

	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty() or bones.size() != verts.size() * 4:
		return _head_bounds

	var found := false
	var box := AABB()
	for v in verts.size():
		# Dominant influence only: a vertex half-owned by the neck belongs to the neck.
		var best := 0.0
		var best_bone := -1
		for j in 4:
			var w := weights[v * 4 + j]
			if w > best:
				best = w
				best_bone = bones[v * 4 + j]
		if best < 0.5 or not family.has(best_bone):
			continue
		var point := verts[v] * _normal_scale + _model_root.position
		_head_points.append(point)
		if not found:
			box = AABB(point, Vector3.ZERO)
			found = true
		else:
			box = box.expand(point)
	if found:
		_head_bounds = box
	return _head_bounds


## The foremost piece of actual mesh close to a requested face height. A whole-head AABB
## only knows the single furthest nose/beak vertex; using that Z at every height leaves a
## rigid mouth prop floating wherever the lips sit behind the nose tip.
func _head_front_at(target_y: float, span: float, half_w: float, fallback: float) -> float:
	var best_z := INF
	var found := false
	var band := maxf(span * 0.075, 0.002)
	var centre_limit := maxf(half_w * 0.72, 0.002)
	for point in _head_points:
		if absf(point.y - target_y) > band or absf(point.x) > centre_limit:
			continue
		best_z = minf(best_z, point.z)
		found = true
	if found:
		return best_z

	# Very low-poly mouths can have no vertex in a narrow horizontal band. Choose the
	# nearest central profile vertex rather than falling back to the unrelated nose tip.
	var best_distance := INF
	for point in _head_points:
		if absf(point.x) > centre_limit:
			continue
		var distance := absf(point.y - target_y)
		if distance < best_distance - 0.0001 or (is_equal_approx(distance, best_distance) and point.z < best_z):
			best_distance = distance
			best_z = point.z
			found = true
	return best_z if found else fallback


## Foremost piece of head mesh inside a small elliptical footprint. Spectacles cannot use
## the nose-tip plane: on a horse or bird that plane is far ahead of the eyes, while on a
## broad feline it can pass through the brow. Sampling the actual footprint of each lens
## and the bridge gives a contact plane which is outside the skin without leaving the
## glasses suspended in front of a long muzzle.
func head_front_in_patch(target_x: float, target_y: float, radius_x: float,
		radius_y: float, fallback: float) -> float:
	head_bounds() ## Populates the cached head-family points.
	var rx := maxf(radius_x, 0.002)
	var ry := maxf(radius_y, 0.002)
	var best_z := INF
	var found := false
	for point in _head_points:
		var dx := (point.x - target_x) / rx
		var dy := (point.y - target_y) / ry
		if dx * dx + dy * dy > 1.0:
			continue
		best_z = minf(best_z, point.z)
		found = true
	if found:
		return best_z

	# A few very low-poly heads have no vertex inside a lens-sized ellipse. Use the
	# nearest head vertex instead of reverting to the unrelated end of the nose or beak.
	var nearest_score := INF
	for point in _head_points:
		var dx := (point.x - target_x) / rx
		var dy := (point.y - target_y) / ry
		var score := dx * dx + dy * dy
		if score < nearest_score - 0.0001 \
				or (is_equal_approx(score, nearest_score) and point.z < best_z):
			nearest_score = score
			best_z = point.z
			found = true
	return best_z if found else fallback


## Move a rigid face prop's contact plane just beyond every head vertex beneath its
## footprint. Sampling only the centre of a curved muzzle is insufficient: the centre can
## touch while the rim of a pacifier or pair of glasses passes into the cheeks. `outward`
## is the prop's local +Z direction; the returned point keeps the same orientation and
## shifts only as far forward as the complete elliptical footprint requires.
func fit_head_accessory_plane(center: Vector3, outward: Vector3, radius_x: float,
		radius_tangent: float, clearance := 0.0) -> Vector3:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.FORWARD
	var protrusion := head_surface_protrusion(center, normal, radius_x, radius_tangent)
	return center + normal * maxf(protrusion + clearance, 0.0)


## Furthest head-surface distance through a candidate accessory plane. A positive value
## means part of the face still lies in front of the plane and the rigid prop would clip.
## The second footprint axis follows the face vertically, perpendicular to `outward` in
## the Y/Z plane, so this also works on the horse's sloping muzzle and upright bird beaks.
func head_surface_protrusion(center: Vector3, outward: Vector3, radius_x: float,
		radius_tangent: float) -> float:
	head_bounds() ## Populates the cached head-family points.
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.FORWARD
	var tangent := Vector3(0.0, normal.z, -normal.y).normalized()
	if tangent.length_squared() < 0.5:
		tangent = Vector3.UP
	var rx := maxf(radius_x, 0.002)
	var rt := maxf(radius_tangent, 0.002)
	var furthest := -INF
	var found := false
	for point in _head_points:
		var delta := point - center
		var across := delta.x / rx
		var along := delta.dot(tangent) / rt
		if across * across + along * along > 1.0:
			continue
		furthest = maxf(furthest, delta.dot(normal))
		found = true
	return furthest if found else 0.0


## Foremost central vertex of the head family. Birds can mount a rigid prop directly on
## the end of a beak instead of borrowing the generic lower-mouth band used by mammals.
func _head_tip(half_w: float, fallback: Vector3) -> Vector3:
	var tip := fallback
	var found := false
	var centre_limit := maxf(half_w * 0.72, 0.002)
	for point in _head_points:
		if absf(point.x) > centre_limit:
			continue
		if not found or point.z < tip.z:
			tip = Vector3(0.0, point.y, point.z)
			found = true
	return tip


## Foremost central vertex near mouth height. Unlike `_head_tip`, the vertical band keeps
## antlers and tall ears from winning, while still reaching the end of a beak or long nose.
func _snout_tip(mouth_y: float, span: float, half_w: float, fallback: Vector3) -> Vector3:
	var tip := fallback
	var found := false
	var centre_limit := maxf(half_w * 0.72, 0.002)
	var vertical_limit := maxf(span * 0.36, 0.003)
	for point in _head_points:
		if absf(point.x) > centre_limit or absf(point.y - mouth_y) > vertical_limit:
			continue
		if not found or point.z < tip.z:
			tip = Vector3(0.0, point.y, point.z)
			found = true
	return tip


## Named points on the face, derived from head_bounds(), in body space. Both AGE kits hang
## their props off these instead of off multiples of a scalar, which is what finally put a
## pacifier on a beak and a chicken's and on a horse's muzzle from the same numbers.
##
## Two clamps matter. The head box is measured from skin weights, so a deer's antlers and a
## tiger's ears are inside it: the raw width would set eye spacing from antler tip to antler
## tip, and the raw height would put the brow above the crown. Both are therefore limited
## against the head's DEPTH, which no species inflates.
func face_anchors() -> Dictionary:
	var box := head_bounds()
	var depth: float = maxf(box.size.z, 0.001)
	var span: float = minf(box.size.y, depth * 1.15) ## Usable head height.
	var half_w: float = minf(box.size.x, depth * 0.95) * 0.5
	var front: float = box.position.z ## Models face -Z, so this is the nose or beak.
	var base: float = box.position.y
	# Head scaling happens about the head bone, not about the centre of its AABB. AGE props
	# that must touch the enlarged head need that real pivot to follow the same transform.
	var head_pivot := box.get_center()
	if skeleton != null and definition != null:
		var head_idx := skeleton.find_bone(definition.socket_bone("head_top"))
		if head_idx != -1:
			head_pivot = skeleton.get_bone_global_rest(head_idx).origin * _normal_scale \
				+ _model_root.position
	var mouth_y := base + span * 0.30
	# A skin marking is centred over the whole muzzle, while a pacifier belongs at the
	# lower lip. Keeping separate heights prevents the rigid prop from reading as though
	# it were stuck to the animal's nose.
	var mouth_surface_y := base + span * 0.18
	var mouth_front := _head_front_at(mouth_surface_y, span, half_w, front)
	var mouth_surface := Vector3(0.0, mouth_surface_y, mouth_front)
	return {
		"front": front,
		"base": base,
		"span": span,
		"depth": depth,
		"half_w": half_w,
		"head_pivot": head_pivot,
		# Fractions chosen against the seven measured boxes, not one species.
		"mouth": Vector3(0.0, mouth_y, front + depth * 0.08),
		# Unlike the centre of a skin marking, a rigid prop cannot sit inside the mesh.
		# This point is on the front plane of the measured muzzle and is used as YOUNG's
		# no-penetration contact plane.
		"mouth_surface": mouth_surface,
		"face_tip": _head_tip(half_w, mouth_surface),
		"snout_tip": _snout_tip(mouth_surface_y, span, half_w, mouth_surface),
		"chin": Vector3(0.0, base + span * 0.08, front + depth * 0.26),
		"eye": Vector3(half_w * 0.62, base + span * 0.66, front + depth * 0.34),
		"brow": Vector3(half_w * 0.60, base + span * 0.86, front + depth * 0.30),
		"cheek": Vector3(half_w * 0.92, base + span * 0.48, front + depth * 0.52),
		"temple": Vector3(half_w * 0.80, base + span * 0.78, front + depth * 0.70),
	}


## The AGE beard can be tuned against the current persistent proportions. Always include
## NORMAL first, then overlay active size/length/height modes so a beard has a deliberate
## contact point in each presentation instead of inheriting one neutral guess.
func beard_modes() -> PackedStringArray:
	var modes := PackedStringArray(["normal"])
	if _trait_scale.x < 0.85:
		modes.append("small")
	elif _trait_scale.x > 1.15:
		modes.append("big")
	if deformer != null:
		if deformer.body_length < 0.90:
			modes.append("short")
		elif deformer.body_length > 1.10:
			modes.append("long")
		if deformer.leg_target < 0.90:
			if not modes.has("short"):
				modes.append("short")
		elif deformer.leg_target > 1.10:
			modes.append("tall")
	return modes


## How far the muzzle reaches in front of the head bone, measured from the model itself
## rather than inferred from an authored socket offset.
##
## The `face` socket's offset is a hand-tuned mounting point for fantasy parts; its
## magnitude happens to track head size on most species but is wildly wrong on some - the
## tiger's is 0.22 against a muzzle that actually runs 0.76 in front of its head bone, so
## accessories sized from it ended up buried inside the skull. The models all face -Z, so
## the front of the mesh AABB is the nose (or beak), and the gap between that and the head
## bone is the real measurement every species can be sized against.
func muzzle_reach() -> float:
	if mesh_instance == null or skeleton == null or definition == null:
		return definition.stand_height * 0.25 if definition != null else 0.25
	var head_bone := definition.socket_bone("head_top")
	var idx := skeleton.find_bone(head_bone)
	if idx == -1:
		return definition.stand_height * 0.25
	var head_z := skeleton.get_bone_global_rest(idx).origin.z * _normal_scale
	var front_z := mesh_instance.get_aabb().position.z * _normal_scale
	return maxf(head_z - front_z, definition.stand_height * 0.08)


func crown_height() -> float:
	var deform_lift: float = deformer.lift if deformer != null else 0.0
	return definition.stand_height * _trait_scale.y + deform_lift


## A rotation-independent horizontal footprint for zoo avoidance. Using the furthest
## source-mesh corners makes this a containing circle rather than a guess based only on
## height; LONG extends the fore/aft reach, and BIG/SMALL scales the whole result.
func horizontal_footprint_radius() -> float:
	if mesh_instance == null or definition == null:
		return 1.0
	var box := mesh_instance.get_aabb()
	var far_x := maxf(absf(box.position.x), absf(box.end.x)) * _normal_scale
	var far_z := maxf(absf(box.position.z), absf(box.end.z)) * _normal_scale
	var length_scale := maxf(deformer.body_length if deformer != null else 1.0, 1.0)
	far_z *= length_scale
	var size_scale := maxf(absf(_trait_scale.x), absf(_trait_scale.z))
	# A small skin around the containing circle keeps low-poly ears, tails, and worn face
	# props from merely touching even when the underlying mesh bounds are exact.
	return maxf(Vector2(far_x, far_z).length() * size_scale * 1.08,
		definition.stand_height * size_scale * 0.42)


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


## The picker supplies a profile from AnimalDefinition. Returning its duration lets the
## confirmation flow continue precisely when the flourish has settled, without blocking
## any input while it plays.
func play_selection_reaction(profile: Dictionary) -> float:
	if selection_reaction == null:
		return 0.0
	return selection_reaction.play(profile)


func stop_selection_reaction() -> void:
	if selection_reaction != null:
		selection_reaction.cancel()


## Public mainly for deterministic harness advancement; normal play advances from
## _process() below.
func advance_selection_reaction(delta: float) -> void:
	if selection_reaction != null:
		selection_reaction.tick(delta)


# --- Idle life ---------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta * tempo * (pace.playback if pace != null and not movement_locked else 1.0)
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
	# SPEED moves the whole animal around the platform, so its offset joins the others
	# here rather than replacing them: a fast animal still breathes, jiggles and shivers
	# while it dashes.
	if pace != null and not movement_locked:
		pace.tick(delta)
		offset += pace.offset
		twist += pace.yaw
	# The walk runs before the body transform is assembled, because it contributes to it:
	# the bob, roll and pitch of a walking animal belong in the same sum as the breathing
	# lift and the shiver, not layered on top afterwards where they would fight.
	if gait != null:
		gait.tick(delta, global_position, moving and not movement_locked, motion)
	body.position = offset + shiver_offset + gait_body_offset + Vector3(0.0, lift
		+ sin(_clock * 1.1) * 0.05 * definition.hover, 0.0)
	body.rotation.x = lean + gait_body_pitch
	body.rotation.y = twist
	body.rotation.z = sin(_clock * 0.9) * 0.01 * (1.0 - posture * 0.4) * motion \
		+ shiver_roll + gait_body_roll
	body.scale = _trait_scale * squash
	_sway_appendages(motion)
	_apply_grounding(delta)
	_sync_thermal_fx_to_body()
	# Apply this last: grounding keeps the neutral stance correct, while an intentional
	# selection hop is allowed to lift the whole already-grounded creature for a moment.
	advance_selection_reaction(delta)


## Explicit sole/hoof points after skinning, adjective proportions and the base idle
## animation. The result is in rig-local coordinates, where Y=0 is the platform plane.
func foot_contact_positions() -> Array[Vector3]:
	var contacts: Array[Vector3] = []
	if skeleton == null or definition == null or body == null:
		return contacts
	var skeleton_to_body := body.global_transform.affine_inverse() * skeleton.global_transform
	for leg in definition.legs:
		# A quadruped's front legs have become arms in STRONG/WEAK, so they are no longer
		# floor contacts. Rear feet continue to support the body; birds already list only
		# their two actual legs here, so their wing replacement needs no special case.
		if muscle != null and muscle.replaces_front_limbs() \
				and str(leg.get("id", "")).begins_with("front"):
			contacts.append(Vector3(INF, INF, INF))
			continue
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
		and (feel == null or not feel.is_animating()) \
		and (pace == null or not pace.is_animating())
	if not settled:
		deformer.clear_ground_extensions(false, delta)
		_support_lowest_contact()
		return

	_support_lowest_contact()
	var contacts := foot_contact_positions()
	var pair_targets := {"front": 0.0, "rear": 0.0}
	var pair_present := {"front": false, "rear": false}
	var scale_y := maxf(absf(body.scale.y), 0.001)
	for i in mini(contacts.size(), definition.legs.size()):
		if not is_finite(contacts[i].y):
			continue
		var pair := "front" if str(definition.legs[i].get("id", "")).begins_with("front") else "rear"
		pair_present[pair] = true
		# A positive Y means this sole floats above the plane and needs more reach.
		var needed := deformer.ground_extension(i) \
			+ maxf(contacts[i].y - GROUND_CLEARANCE, 0.0) / scale_y * 0.45
		pair_targets[pair] = maxf(float(pair_targets[pair]), needed)
	# Body translation handles the common vertical offset. Keeping a shared amount in
	# every leg creates a feedback loop: the body rises, the other pair then extends,
	# and the cycle repeats until the animal floats at the extension cap.
	if pair_present.front and pair_present.rear:
		var common_extension := minf(float(pair_targets.front), float(pair_targets.rear))
		pair_targets.front = maxf(float(pair_targets.front) - common_extension, 0.0)
		pair_targets.rear = maxf(float(pair_targets.rear) - common_extension, 0.0)
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
