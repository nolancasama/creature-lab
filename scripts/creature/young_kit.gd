class_name YoungKit
extends RefCounted
## The baby-animal look for the YOUNG trait: rosy cheeks and a pacifier, over a head
## scaled up on its own bone.
##
## YOUNG deliberately does NOT touch the creature's overall size. That belongs to BIG and
## SMALL, and a young animal that was simply a shrunken one taught the student the wrong
## contrast - "young" and "small" became the same card. Everything here reads as *baby*
## instead: proportions and props, not scale.
##
## There are deliberately no cartoon eyes. None of the seven species has an eye bone or a
## separate eye surface - every model is one skinned mesh with its eyes painted into the
## texture - so the only way to change them was to lay stylised eyeballs over the muzzle,
## and at a size big enough to read across a classroom those dominated the face rather than
## flattering it.
##
## The cheeks are painted by the shader rather than built here (see set_cheeks() and
## creature.gdshader): a blush is a marking on the skin, and the same idea as geometry was
## a flattened ball of pink that read as something growing out of the face.
##
## Props hang off CreatureRig.face_anchors(), which measures the head from the mesh's own
## skin weights. An earlier version scaled offsets off a single "muzzle reach" number, and
## it could not be made to work: the same multipliers that sat a pacifier on a dog's snout
## buried it in the tiger's and left it in mid-air beside the penguin's beak, because a
## scalar says how LONG a head is and nothing about how high or how steeply it is carried.
##
## FORWARD is -Z, the glTF convention these models are authored in - every species' head
## bone sits at negative Z with the body trailing behind it.
const FORWARD := -1.0

const ROSY := Color("#ff9ec4")
const PACIFIER_GUARD := Color("#ffd166")
const PACIFIER_TEAT := Color("#ffe6b8")


## Build every baby feature onto `rig`. `hs` is the head scale already applied to the head
## bone, which the props are nudged outward by so they clear the enlarged skull.
static func apply(rig: CreatureRig, hs: float) -> void:
	var def := rig.definition
	var a := rig.face_anchors()

	_paint_cheeks(rig, def, a, hs)
	_add_pacifier(rig, def, a, hs)


## On the side of the face, not on the snout: placed further forward the patch lands on the
## nose and reads as a pink muzzle rather than as a blush.
static func _paint_cheeks(rig: CreatureRig, def: AnimalDefinition, a: Dictionary, hs: float) -> void:
	var cheek: Vector3 = a["cheek"]
	var size := def.young_value("cheek", "size", 0.42) * float(a["depth"]) * hs
	var at := Vector3(0.0, cheek.y, cheek.z) + Vector3(0.0,
		def.young_value("cheek", "down", 0.0) * float(a["span"]),
		def.young_value("cheek", "forward", 0.0) * float(a["depth"]) * FORWARD)
	var spacing := cheek.x * def.young_value("cheek", "spacing", 1.0) * hs
	rig.set_patches([
		{"at": at + Vector3(-spacing, 0.0, 0.0), "radius": size},
		{"at": at + Vector3(spacing, 0.0, 0.0), "radius": size},
	], ROSY, 1.0)


## Guard disc plus teat at the mouth, on one pivot so `tilt` turns them together - a
## pacifier is a rigid object, and rotating the guard alone pulled the teat out through the
## disc. It tilts because almost no snout points straight ahead; negative is nose-down.
static func _add_pacifier(rig: CreatureRig, def: AnimalDefinition, a: Dictionary, hs: float) -> void:
	var mouth: Vector3 = a["mouth"]
	var size := def.young_value("pacifier", "size", 0.52) * float(a["depth"]) * hs
	var tilt := def.young_value("pacifier", "tilt", -18.0)
	var at := mouth + Vector3(0.0,
		def.young_value("pacifier", "down", 0.0) * float(a["span"]),
		def.young_value("pacifier", "forward", 0.20) * float(a["depth"]) * FORWARD)

	var pivot := Node3D.new()
	pivot.name = "Pacifier"
	pivot.rotation_degrees = Vector3(tilt, 0.0, 0.0)

	var guard := _cylinder(size, size * 0.20, PACIFIER_GUARD, 0.22)
	guard.rotation_degrees = Vector3(90.0, 0.0, 0.0) ## Cylinders build along Y; face it out.
	pivot.add_child(guard)

	var teat := _sphere(size * 0.50, PACIFIER_TEAT, 0.12)
	teat.scale = Vector3(1.0, 1.0, 1.30)
	teat.position = Vector3(0.0, 0.0, size * 0.28 * FORWARD)
	pivot.add_child(teat)

	rig.add_accessory(pivot, at)


# --- Primitives --------------------------------------------------------------
#
# Built here rather than through BodyPartSpec/build_part_node: those describe *fantasy*
# add-ons authored in content files, and these are fixed parts of one trait's presentation
# with their own colours, which no content file should be able to repaint.

static func _sphere(diameter: float, color: Color, glow: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = maxf(diameter * 0.5, 0.001)
	mesh.height = maxf(diameter, 0.002)
	mesh.radial_segments = 16
	mesh.rings = 8
	return _instance(mesh, color, glow)


static func _cylinder(diameter: float, height: float, color: Color, glow: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = maxf(diameter * 0.5, 0.001)
	mesh.bottom_radius = mesh.top_radius
	mesh.height = maxf(height, 0.002)
	mesh.radial_segments = 16
	return _instance(mesh, color, glow)


## A little emission on every piece: these are small props seen from across a classroom,
## and pure albedo on the unlit side of the creature turned them into dark smudges.
static func _instance(mesh: Mesh, color: Color, glow: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
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
