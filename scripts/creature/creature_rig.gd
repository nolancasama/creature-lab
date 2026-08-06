class_name CreatureRig
extends Node3D
## A creature assembled at runtime from the primitives listed in its AnimalDefinition.
##
## No 3D model files exist for this project, and building bodies out of described parts
## is what makes the data-driven promise real: "Length Modifier -> trunk / ears / tail"
## is a field in JSON, not a switch statement. Each part is a pivot holding a mesh, so
## modifiers grow limbs away from where they attach instead of around their middle.

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
var body: Node3D = null
var fx_root: Node3D = null

var pivots := {} ## part id -> Node3D
var materials := {} ## role -> StandardMaterial3D
var sockets := {} ## socket name -> Node3D

var tempo := 1.0 ## Idle animation speed; the SPEED modifier drives this.
var moving := false ## Zoo creatures set this to swing their legs.

var _base_pivots := {} ## part id -> base position
var _clock := 0.0
var _last_swing := 0.0


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

	for spec in def.parts:
		var pivot := build_part_node(spec, _material(spec.role))
		body.add_child(pivot)
		pivots[spec.id] = pivot
		_base_pivots[spec.id] = spec.pivot

	for socket_name in def.sockets:
		var node := Node3D.new()
		node.name = "socket_%s" % socket_name
		node.position = def.sockets[socket_name]
		body.add_child(node)
		sockets[str(socket_name)] = node


## Build one pivot-plus-mesh pair. Shared with the fantasy part builder so add-on horns
## and wings are constructed exactly like body parts.
static func build_part_node(spec: BodyPartSpec, material: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = spec.id
	pivot.position = spec.pivot
	pivot.rotation_degrees = spec.rotation_deg

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _make_mesh(spec)
	mesh_instance.position = spec.offset
	# Round primitives take their depth from a node scale, since those mesh types only
	# expose a single radius.
	if spec.shape != "box" and not is_equal_approx(spec.size.x, spec.size.z) and spec.size.x > 0.0:
		mesh_instance.scale = Vector3(1.0, 1.0, spec.size.z / spec.size.x)
	mesh_instance.material_override = material
	pivot.add_child(mesh_instance)
	return pivot


func material_for(role: String) -> StandardMaterial3D:
	return _material(role)


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
			# CapsuleMesh height includes both hemispheres, so it can never be thinner
			# than it is wide.
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


func _material(role: String) -> StandardMaterial3D:
	if materials.has(role):
		return materials[role]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_role_color(role)
	mat.roughness = 0.85
	if role == "eye":
		mat.roughness = 0.25
	materials[role] = mat
	return mat


func base_role_color(role: String) -> Color:
	match role:
		"skin":
			return definition.skin_color
		"accent":
			return definition.accent_color
		"belly":
			return definition.belly_color
	if ROLE_FALLBACKS.has(role):
		return Content.role_color(role, ROLE_FALLBACKS[role])
	return definition.skin_color


# --- Modifier surface --------------------------------------------------------

## Return every part and material to the state described by the AnimalDefinition.
## Trait modifiers always recompute from this baseline, so applying them is idempotent
## and order-independent.
func reset_modifiers() -> void:
	for id in pivots:
		var pivot: Node3D = pivots[id]
		pivot.scale = Vector3.ONE
		pivot.position = _base_pivots[id]
	body.scale = Vector3.ONE
	body.position = Vector3.ZERO
	tempo = 1.0
	for role in materials:
		var mat: StandardMaterial3D = materials[role]
		mat.albedo_color = base_role_color(role)
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 1.0
		mat.metallic = 0.0
		mat.roughness = 0.25 if role == "eye" else 0.85
		mat.rim_enabled = false
	clear_fx()


func scale_body(factor: Vector3) -> void:
	body.scale *= factor


func set_role_color(role: String, color: Color) -> void:
	_material(role).albedo_color = color


func set_emission(role: String, color: Color, energy: float) -> void:
	var mat := _material(role)
	mat.emission_enabled = energy > 0.001
	mat.emission = color
	mat.emission_energy_multiplier = energy


func set_surface(role: String, roughness: float, metallic: float) -> void:
	var mat := _material(role)
	mat.roughness = roughness
	mat.metallic = metallic


func tint_role(role: String, color: Color, amount: float) -> void:
	var mat := _material(role)
	mat.albedo_color = mat.albedo_color.lerp(color, clampf(amount, 0.0, 1.0))


func scale_parts(ids: PackedStringArray, factor: Vector3) -> void:
	for id in ids:
		if pivots.has(id):
			var pivot: Node3D = pivots[id]
			pivot.scale *= factor


## Stretch the animal's signature feature (trunk, ears, tail, neck) along its own axis,
## then slide anything attached to its tip so the silhouette stays coherent.
func stretch_feature(factor: float) -> void:
	if definition.feature_parts.is_empty():
		return
	for spec in definition.parts:
		if not definition.feature_parts.has(spec.id):
			continue
		var pivot: Node3D = pivots[spec.id]
		var axis_scale := Vector3.ONE
		axis_scale[spec.axis_index()] = factor
		pivot.scale *= axis_scale
	var slide := definition.feature_dir.normalized() * definition.feature_length * (factor - 1.0)
	for id in definition.feature_followers:
		if pivots.has(id):
			var follower: Node3D = pivots[id]
			follower.position = _base_pivots[id] + slide


func attach_to_socket(socket_name: String, node: Node3D) -> void:
	var host: Node3D = sockets.get(socket_name, body)
	host.add_child(node)


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
	return definition.stand_height * body.scale.y


# --- Idle life ---------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta * tempo
	var breathe := sin(_clock * 1.8) * 0.02
	body.position.y = breathe + (sin(_clock * 1.1) * 0.05 * definition.hover)
	body.rotation.z = sin(_clock * 0.9) * 0.012
	if moving:
		_swing_limbs(sin(_clock * 6.0) * 0.42)
	elif not is_zero_approx(_last_swing):
		_swing_limbs(0.0)


func _swing_limbs(amount: float) -> void:
	_last_swing = amount
	var index := 0
	for spec in definition.parts:
		if not (spec.id.begins_with("leg") or spec.id.begins_with("arm")):
			continue
		var pivot: Node3D = pivots[spec.id]
		# Alternate the phase so opposite limbs move in opposite directions.
		var phase := 1.0 if index % 2 == 0 else -1.0
		pivot.rotation_degrees.x = spec.rotation_deg.x + rad_to_deg(amount) * phase * 0.35
		index += 1
