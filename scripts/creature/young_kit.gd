class_name YoungKit
extends RefCounted
## The baby-animal look for the YOUNG trait: rosy cheeks, a pacifier and a bib, over a
## head scaled up on its own bone.
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
## flattering it. The enlarged head plus cheeks, pacifier and bib carry "baby" on their own.
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
const BIB_CLOTH := Color("#7ad7ff")
const BIB_TRIM := Color("#fff4d6")


## Build every baby feature onto `rig`, around a head sitting at `head` (normalised space)
## that has already been scaled up by `head_scale`.
static func apply(rig: CreatureRig, head: Vector3, head_scale: float) -> void:
	var def := rig.definition
	# The muzzle's real length, measured off the model - see CreatureRig.muzzle_reach().
	# Every default below is a fraction of it, so a tiger's long head and a chicken's
	# short one place their own features without either needing an override.
	var reach := rig.muzzle_reach()

	_add_cheeks(rig, def, head, head_scale, reach)
	_add_pacifier(rig, def, head, head_scale, reach)
	_add_bib(rig, def, head, head_scale, reach)


## Flattened, not spherical: a rosy cheek is a marking on the face, and a ball of pink
## stuck to the muzzle reads as a growth rather than a blush.
static func _add_cheeks(rig: CreatureRig, def: AnimalDefinition, head: Vector3,
		hs: float, reach: float) -> void:
	var size := def.young_value("cheek", "size", 0.40) * reach * hs
	var spacing := def.young_value("cheek", "spacing", 0.25) * reach * hs
	var forward := def.young_value("cheek", "forward", 0.69) * reach * hs * FORWARD
	var down := def.young_value("cheek", "down", 0.33) * reach * hs

	for side in [-1.0, 1.0]:
		var cheek := _sphere(size, ROSY, 0.30)
		cheek.scale = Vector3(1.0, 0.72, 0.42) ## Pressed flat against the cheek.
		rig.add_accessory(cheek, head + Vector3(spacing * side, -down, forward))


## Guard disc plus teat, on the centreline below the eyes.
static func _add_pacifier(rig: CreatureRig, def: AnimalDefinition, head: Vector3,
		hs: float, reach: float) -> void:
	var size := def.young_value("pacifier", "size", 0.46) * reach * hs
	var forward := def.young_value("pacifier", "forward", 1.10) * reach * hs * FORWARD
	var down := def.young_value("pacifier", "down", 0.19) * reach * hs
	var at := head + Vector3(0.0, -down, forward)

	var guard := _cylinder(size, size * 0.22, PACIFIER_GUARD, 0.22)
	guard.rotation_degrees = Vector3(90.0, 0.0, 0.0) ## Cylinders build along Y; face it out.
	rig.add_accessory(guard, at)

	var teat := _sphere(size * 0.52, PACIFIER_TEAT, 0.12)
	teat.scale = Vector3(1.0, 1.0, 1.35) ## Drawn out into a soft nub.
	rig.add_accessory(teat, at + Vector3(0.0, 0.0, size * 0.30 * FORWARD))


## Hangs at the throat, below the head and slightly forward of it, so it reads across
## quadrupeds and upright birds alike without either wearing it as a hat or a belt.
static func _add_bib(rig: CreatureRig, def: AnimalDefinition, head: Vector3,
		hs: float, reach: float) -> void:
	# Sized and placed from `reach` but NOT multiplied by the head scale: the bib hangs on
	# the neck, which YOUNG leaves alone, so growing it with the head would float it off.
	var size := def.young_size("bib", "size", Vector3(0.89, 0.83, 0.29)) * reach
	# Under the chin, not back at the chest. Probing the throat and chest of a quadruped
	# found solid body at every depth - the neck meets the shoulders inside the silhouette,
	# so anything placed there is swallowed. A bib hanging below the jaw is both visible in
	# profile and where a bib actually goes on a baby.
	var forward := def.young_value("bib", "forward", 0.17) * reach * FORWARD
	var down := def.young_value("bib", "down", 0.83) * reach
	var at := head + Vector3(0.0, -down, forward)

	# A band right around the neck, not just a strip across the front. The creature is seen
	# in profile for the whole of the recording screen, and a flat forward-facing panel is
	# edge-on from there - it read as a thin sliver of colour rather than as a bib. A ring
	# has a silhouette from every angle the turntable can present.
	var collar := _cylinder(size.x * 1.05, size.y * 0.26, BIB_TRIM, 0.20)
	rig.add_accessory(collar, at + Vector3(0.0, size.y * 0.46, 0.0))

	# The cloth itself is deliberately a slab rather than a plane, for the same reason:
	# some depth means it still has a shape when viewed along its face.
	var cloth := _rounded_slab(Vector3(size.x, size.y, size.z), BIB_CLOTH, 0.14)
	cloth.rotation_degrees = Vector3(-22.0, 0.0, 0.0) ## Hangs down the chest, not straight out.
	rig.add_accessory(cloth, at + Vector3(0.0, -size.y * 0.30, size.z * 0.55 * FORWARD))


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


static func _rounded_slab(size: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
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
