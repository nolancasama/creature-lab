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
## Everything is positioned in the same normalised space as the sockets: origin at the head
## bone, +Y up, distances as fractions of stand_height. Offsets are multiplied by the head
## scale, because the enlarged head has pushed its own surface out by exactly that much -
## without it the pacifier ends up buried inside a bigger muzzle.
##
## FORWARD is -Z, the glTF convention these models are authored in. Confirmed from the
## skeletons rather than assumed: every species' head bone sits at negative Z (the dog's at
## -0.91, the tiger's at -1.30, the horse's at -1.20) with the body trailing behind it
## toward +Z. Note the `face` socket's authored offset is +Z, which points *backward* into
## the skull - it is positioned for hanging fantasy parts off, so its magnitude is a useful
## measure of muzzle reach but its direction must not be followed.
const FORWARD := -1.0

const ROSY := Color("#ff9ec4")
const PACIFIER_GUARD := Color("#ffd166")
const PACIFIER_TEAT := Color("#ffe6b8")


## Build every baby feature onto `rig`, around a head sitting at `head` (normalised space)
## that has already been scaled up by `head_scale`.
static func apply(rig: CreatureRig, head: Vector3, head_scale: float) -> void:
	var def := rig.definition
	# The muzzle's real length, measured off the model - see CreatureRig.muzzle_reach().
	# Every default below is a fraction of it, so a tiger's long head and a chicken's
	# short one place their own features without either needing an override.
	var reach := rig.muzzle_reach()

	_paint_cheeks(rig, def, head, head_scale, reach)
	_add_pacifier(rig, def, head, head_scale, reach)


## Handed to the shader as two centres and a radius, in body space - CreatureRig.set_cheeks()
## converts. Because the patch is evaluated against the skinned vertex position, it stays
## on the cheek as the head scales up rather than needing to be moved with it.
static func _paint_cheeks(rig: CreatureRig, def: AnimalDefinition, head: Vector3,
		hs: float, reach: float) -> void:
	var size := def.young_value("cheek", "size", 0.40) * reach * hs
	var spacing := def.young_value("cheek", "spacing", 0.25) * reach * hs
	var forward := def.young_value("cheek", "forward", 0.69) * reach * hs * FORWARD
	var down := def.young_value("cheek", "down", 0.33) * reach * hs
	var at := head + Vector3(0.0, -down, forward)
	rig.set_cheeks(at + Vector3(-spacing, 0.0, 0.0), at + Vector3(spacing, 0.0, 0.0),
		size, ROSY, 1.0)


## Guard disc plus teat, on the centreline below the eyes.
##
## Both hang off one pivot so `tilt` turns them together - a pacifier is a rigid object, and
## rotating the guard while the teat stayed on the horizontal would pull it out through the
## disc. The tilt exists because almost no snout points straight ahead: muzzles and beaks
## angle downward, and a pacifier held dead level reads as stuck to the face rather than
## held in the mouth. Negative is nose-down (a rotation about X sends -Z upward).
static func _add_pacifier(rig: CreatureRig, def: AnimalDefinition, head: Vector3,
		hs: float, reach: float) -> void:
	var size := def.young_value("pacifier", "size", 0.46) * reach * hs
	var forward := def.young_value("pacifier", "forward", 1.10) * reach * hs * FORWARD
	var down := def.young_value("pacifier", "down", 0.19) * reach * hs
	var tilt := def.young_value("pacifier", "tilt", -20.0)

	var pivot := Node3D.new()
	pivot.name = "Pacifier"
	pivot.rotation_degrees = Vector3(tilt, 0.0, 0.0)

	var guard := _cylinder(size, size * 0.22, PACIFIER_GUARD, 0.22)
	guard.rotation_degrees = Vector3(90.0, 0.0, 0.0) ## Cylinders build along Y; face it out.
	pivot.add_child(guard)

	var teat := _sphere(size * 0.52, PACIFIER_TEAT, 0.12)
	teat.scale = Vector3(1.0, 1.0, 1.35) ## Drawn out into a soft nub.
	teat.position = Vector3(0.0, 0.0, size * 0.30 * FORWARD)
	pivot.add_child(teat)

	rig.add_accessory(pivot, head + Vector3(0.0, -down, forward))


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
