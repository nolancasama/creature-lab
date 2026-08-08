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
##   strong/weak -> scale the bulk bones on X/Z
##   colour      -> a shader that re-lights the target colour with the texture's own
##                  light/dark pattern (see shaders/creature.gdshader for why)
##
## Fantasy add-on parts are still primitives, so BodyPartSpec and build_part_node stay.

const MODEL_PATH := "res://models/animals.glb"
const SHADER_PATH := "res://shaders/creature.gdshader"

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
var muscle: MuscleDeformer = null ## STRONG/WEAK bulk, veins and posture.

var tempo := 1.0 ## Idle animation speed; the SPEED modifier drives this.
var moving := false ## Zoo creatures set this to swing their legs.

var _model_root: Node3D = null
var _base_model_pos := Vector3.ZERO
var _normal_scale := 1.0
var _trait_scale := Vector3.ONE ## SIZE/AGE scaling, kept apart from transient squash.
var _clock := 0.0
var _posed_bones := {} ## bone index -> true, so reset only touches what we changed


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
	material.set_shader_parameter("roughness_value", 0.85)
	material.set_shader_parameter("metallic_value", 0.0)


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
	if deformer != null:
		deformer.reset()
	if muscle != null:
		muscle.reset()
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

	# A strong animal idles heavier and slower; a weak one droops and dawdles.
	var idle_rate: float = 1.0 + posture * 0.18
	body.position = offset + Vector3(0.0, lift
		+ sin(_clock * 1.8 * idle_rate) * 0.02
		+ sin(_clock * 1.1) * 0.05 * definition.hover, 0.0)
	body.rotation.x = lean
	body.rotation.y = twist
	body.rotation.z = sin(_clock * 0.9) * 0.01 * (1.0 - posture * 0.4)
	body.scale = _trait_scale * squash
	_swing_legs(sin(_clock * 5.0) * 0.5 if moving else 0.0)


## No walk cycles ship with these models, so the legs are posed procedurally: opposite
## legs swing out of phase around the bone's rest pose.
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
