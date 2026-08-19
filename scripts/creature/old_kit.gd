class_name OldKit
extends RefCounted
## The elderly look for the OLD half of the AGE trait: round spectacles, grey at the
## muzzle and temples, and a pointed beard.
##
## OLD means *biologically old*, and is deliberately built from none of the things that
## would collide with a neighbouring card. It used to grey the whole body, stoop it and
## slow it down, which read as other adjectives at once:
##   0.94 vertical squash -> SMALL
##   tempo * 0.75         -> SLOW
##   whole-body grey wash -> a worn, dirty object rather than an elderly animal
##   dust cloud           -> the same
## All of it is gone. What is left is a face a child reads as elderly - props and grey
## hair - with the body itself untouched, so OLD can be combined with BIG or FAST without
## either of them cancelling it out.
##
## The grey is painted by the shader as skin markings (CreatureRig.set_patches) rather
## than washed over the whole animal, which is what lets it sit on top of the COLOUR card:
## a blue creature goes blue with a grey muzzle, not grey.
##
## The beard is a custom low-poly silhouette rather than a capsule stuck to the jaw. Two
## crossed copies keep its pointed outline readable in both the normal profile view and
## the front view reached by dragging the creature.
##
## Everything hangs off CreatureRig.face_anchors(), which measures the head from the mesh's
## own skin weights. See YoungKit for why a single "muzzle reach" scalar could not place
## these on seven differently-carried heads.

const FORWARD := -1.0 ## -Z, as in YoungKit - see its note for why this is not the `face` socket.

const GREY := Color("#b9bec6") ## The aging markings on the skin.
const FRAME := Color("#3d4450") ## Spectacle wire.
const LENS := Color("#cfe6ff")

## Authored in Blender-style coordinates: X across the face, Y depth, Z vertical. The
## source Y is constant, so mapping (X, Z, Y) produces a vertical Godot mesh while keeping
## the supplied silhouette exactly intact.
static var BEARD_OUTLINE := PackedVector3Array([
	Vector3(-0.30, -0.09, 0.10),
	Vector3(-0.48, -0.09, -0.05),
	Vector3(-0.58, -0.09, -0.32),
	Vector3(-0.52, -0.09, -0.58),
	Vector3(-0.42, -0.09, -0.68),
	Vector3(-0.36, -0.09, -1.05),
	Vector3(-0.18, -0.09, -0.88),
	Vector3(0.00, -0.09, -1.30),
	Vector3(0.18, -0.09, -0.88),
	Vector3(0.36, -0.09, -1.05),
	Vector3(0.42, -0.09, -0.68),
	Vector3(0.52, -0.09, -0.58),
	Vector3(0.58, -0.09, -0.32),
	Vector3(0.48, -0.09, -0.05),
	Vector3(0.30, -0.09, 0.10),
])


## Everything is placed from measured face anchors; OLD does not scale the head, so unlike
## YoungKit there is no head-scale factor to fold in.
static func apply(rig: CreatureRig) -> void:
	var def := rig.definition
	var a := rig.face_anchors()

	_paint_grey(rig, def, a)
	_add_spectacles(rig, def, a)
	_add_beard(rig, def, a)


## Grey at the muzzle and both temples - where an animal actually goes grey first, and
## between them enough of the face to read without touching the body's own colour.
static func _paint_grey(rig: CreatureRig, def: AnimalDefinition, a: Dictionary) -> void:
	var depth := float(a["depth"])
	var mouth: Vector3 = a["mouth"]
	var temple: Vector3 = a["temple"]
	var muzzle_size := def.old_value("grey", "muzzle_size", 0.46) * depth
	var temple_size := def.old_value("grey", "temple_size", 0.34) * depth
	rig.set_patches([
		{"at": Vector3(0.0, mouth.y, mouth.z), "radius": muzzle_size},
		{"at": Vector3(-temple.x, temple.y, temple.z), "radius": temple_size},
		{"at": Vector3(temple.x, temple.y, temple.z), "radius": temple_size},
	], def.old_tint(), 1.0)


## Two rings and a bridge. TorusMesh is the one primitive that gives a real lens hole -
## anything else would be a disc, and a filled disc over the eye reads as a blindfold.
static func _add_spectacles(rig: CreatureRig, def: AnimalDefinition, a: Dictionary) -> void:
	var depth := float(a["depth"])
	var eye: Vector3 = a["eye"]
	var size := def.old_value("specs", "size", 0.46) * depth
	var wire := def.old_value("specs", "wire", 0.08) * depth
	var spacing := eye.x * def.old_value("specs", "spacing", 1.0)
	var at := Vector3(0.0, eye.y, eye.z) + Vector3(0.0,
		def.old_value("specs", "up", 0.0) * float(a["span"]),
		def.old_value("specs", "forward", 0.0) * depth * FORWARD)

	for side in [-1.0, 1.0]:
		var ring := _torus(size, wire, FRAME, 0.10)
		# Facing OUTWARD along X, not forward along Z. Every one of these species has its
		# eyes on the sides of its head, and the creature is seen in profile for the whole
		# of the recording screen - a forward-facing ring is edge-on from there, which is
		# how the first version turned a pair of round spectacles into two dark bars.
		# TorusMesh's axis is Y, so a turn about Z points it along X.
		ring.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		rig.add_accessory(ring, at + Vector3(spacing * side, 0.0, 0.0))

		var glass := _sphere(size * 0.90, LENS, 0.05)
		glass.scale = Vector3(0.08, 1.0, 1.0) ## Flattened on X to match the lens plane.
		var mat: StandardMaterial3D = glass.material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(LENS.r, LENS.g, LENS.b, 0.20)
		rig.add_accessory(glass, at + Vector3(spacing * side, 0.0, 0.0))

	rig.add_accessory(_box(Vector3(maxf(spacing * 2.0 - size * 0.8, wire), wire, wire), FRAME, 0.10), at)


## Fill the supplied concave outline, then cross two copies at right angles. A single
## face-forward card would disappear edge-on in the recording screen's profile view.
static func _add_beard(rig: CreatureRig, def: AnimalDefinition, a: Dictionary) -> void:
	var depth := float(a["depth"])
	var chin: Vector3 = a["chin"]
	var size := def.old_value("beard", "size", 0.48) * depth
	var length := def.old_value("beard", "length", 1.0)
	var down := def.old_value("beard", "down", 0.0) * depth
	var forward := def.old_value("beard", "forward", 0.0) * depth * FORWARD
	var mesh := _beard_mesh(length)
	var mat := _beard_material(def.old_tint())

	var beard := Node3D.new()
	beard.name = "OldBeard"
	# The outline's top is +0.10, so this offset joins that edge to the measured chin.
	var at := Vector3(0.0, chin.y - size * 0.10 - down,
		float(a["front"]) + depth * 0.10 + forward)
	beard.scale = Vector3.ONE * size

	var front := MeshInstance3D.new()
	front.name = "FrontSilhouette"
	front.mesh = mesh
	front.material_override = mat
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beard.add_child(front)

	var side := MeshInstance3D.new()
	side.name = "SideSilhouette"
	side.mesh = mesh
	side.material_override = mat
	side.rotation_degrees.y = 90.0
	# Keep the profile readable without making the beard as deep as it is wide.
	side.scale.x = 0.68
	side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beard.add_child(side)
	rig.add_accessory(beard, at)


static func _beard_mesh(length: float) -> ArrayMesh:
	var polygon := PackedVector2Array()
	for source in BEARD_OUTLINE:
		polygon.append(Vector2(source.x, source.z * length))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		var source := BEARD_OUTLINE[index]
		surface.set_normal(Vector3(0.0, 0.0, -1.0))
		surface.add_vertex(Vector3(source.x, source.z * length, source.y))
	return surface.commit()


static func _beard_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.06
	return mat


# --- Primitives --------------------------------------------------------------

static func _sphere(diameter: float, color: Color, glow: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = maxf(diameter * 0.5, 0.001)
	mesh.height = maxf(diameter, 0.002)
	mesh.radial_segments = 16
	mesh.rings = 8
	return _instance(mesh, color, glow)


static func _torus(outer_diameter: float, wire: float, color: Color, glow: float) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.outer_radius = maxf(outer_diameter * 0.5, 0.002)
	mesh.inner_radius = maxf(mesh.outer_radius - wire, 0.001)
	mesh.rings = 20
	mesh.ring_segments = 8
	return _instance(mesh, color, glow)


static func _box(size: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
	return _instance(mesh, color, glow)


## A little emission on every piece, as in YoungKit: small props seen from across a
## classroom, and pure albedo on the unlit side of the creature turns them into smudges.
static func _instance(mesh: Mesh, color: Color, glow: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.0
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
