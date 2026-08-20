class_name TransformArray
extends Node3D
## The machine that comes down out of the ceiling to do the transformation.
##
## Built from primitives for the same reason everything else in this lab is: the project
## carries no modelled props, and a ring plus a prong plus a glowing core reads as
## "transformation apparatus" to a eleven-year-old without costing an asset pipeline.
##
## It replaces the glass chamber the animal used to walk into. The chamber moved the
## subject away from the platform the student had been watching for the whole round and
## then hid it behind glass; this comes to the animal instead and leaves it exactly where
## it has been standing, which is the one thing that makes the sequence easy to follow.
##
## Nothing here knows what a trait is. The director drives it: descend, charge, fire,
## retract. That keeps the machine a prop rather than a second copy of the rules.

## The whole-screen white flash at the moment the energy peaks. Owned by the machine that
## causes it rather than by the lab, so the lab only has to know it should flash.
signal flash_requested(strength: float)

const PARK_HEIGHT := 7.2 ## Out of frame above the platform.
const WORK_HEIGHT := 3.05 ## Fallback only; the director sizes this to the actual creature.
## How far the machine reaches below its own origin - the prong tips plus their bulbs.
## Whatever height it is asked to work at, this much of it hangs underneath, so the caller
## has something concrete to clear the animal by.
const DROP_BELOW := 1.16
const RING_COUNT := 3
const PRONG_COUNT := 4
const PRONG_REACH := 1.5
const BOLT_SEGMENTS := 3 ## Enough of a kink to read as lightning, cheap enough to spam.

var charge := 0.0 ## 0 idle, 1 fully spun up. Drives spin rate and glow.

var _rings: Array[Node3D] = []
var _prong_tips: Array[Node3D] = []
var _core: MeshInstance3D = null
var _core_material: StandardMaterial3D = null
var _emitter_materials: Array[StandardMaterial3D] = []
var _spin := 0.0


static func create() -> TransformArray:
	var array := TransformArray.new()
	array.name = "TransformArray"
	return array


func _ready() -> void:
	position.y = PARK_HEIGHT
	_build_column()
	_build_core()
	_build_rings()
	_build_prongs()
	visible = false


func _process(delta: float) -> void:
	# Everything idles slowly and speeds up with charge, so the machine looks alive before
	# it looks dangerous.
	_spin += delta * (0.6 + charge * 7.0)
	for i in _rings.size():
		var ring := _rings[i]
		var direction := 1.0 if i % 2 == 0 else -1.0
		ring.rotation.y = _spin * direction * (0.7 + 0.3 * i)
		ring.rotation.x = deg_to_rad(24.0 * i) + sin(_spin * 0.4) * 0.12 * charge
	if _core_material != null:
		var pulse := 1.0 + sin(_spin * 6.0) * 0.35 * charge
		_core_material.emission_energy_multiplier = (0.8 + charge * 6.0) * pulse
	for mat in _emitter_materials:
		mat.emission_energy_multiplier = 0.4 + charge * 5.5


# --- Construction ------------------------------------------------------------

## A telescoping column, so the machine reads as having come from somewhere rather than
## having faded in above the platform.
func _build_column() -> void:
	for i in 3:
		var segment := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.30 - i * 0.06
		mesh.bottom_radius = 0.26 - i * 0.06
		mesh.height = 2.2
		segment.mesh = mesh
		segment.material_override = _metal(Color("#3a4a63"))
		segment.position.y = 1.5 + i * 1.9
		add_child(segment)


func _build_core() -> void:
	_core = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 0.84
	_core.mesh = mesh
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = UiKit.ACCENT
	_core_material.emission_enabled = true
	_core_material.emission = UiKit.ACCENT
	_core_material.emission_energy_multiplier = 0.8
	_core.material_override = _core_material
	add_child(_core)

	# A hub the prongs and rings visibly hang off, so the parts read as one machine.
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.72
	hub_mesh.bottom_radius = 0.92
	hub_mesh.height = 0.44
	hub.mesh = hub_mesh
	hub.material_override = _metal(Color("#2b3a52"))
	hub.position.y = 0.42
	add_child(hub)


func _build_rings() -> void:
	for i in RING_COUNT:
		var pivot := Node3D.new()
		add_child(pivot)
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.85 + i * 0.34
		mesh.outer_radius = 0.95 + i * 0.34
		ring.mesh = mesh
		var tint := UiKit.ACCENT if i % 2 == 0 else UiKit.GOLD
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#48607f")
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.4
		ring.material_override = mat
		_emitter_materials.append(mat)
		pivot.add_child(ring)
		_rings.append(pivot)


## Prongs angle down and inward, so the machine points at the animal from several sides
## at once and the energy has somewhere obvious to come from.
func _build_prongs() -> void:
	for i in PRONG_COUNT:
		var angle := TAU * float(i) / float(PRONG_COUNT)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var arm := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.06
		mesh.height = PRONG_REACH
		arm.mesh = mesh
		arm.material_override = _metal(Color("#33465f"))
		arm.position = out * 0.95 + Vector3(0.0, -0.45, 0.0)
		arm.rotation.z = -out.x * 0.85
		arm.rotation.x = out.z * 0.85
		add_child(arm)

		var tip := Node3D.new()
		tip.position = out * 1.35 + Vector3(0.0, -1.0, 0.0)
		add_child(tip)
		var bulb := MeshInstance3D.new()
		var bulb_mesh := SphereMesh.new()
		bulb_mesh.radius = 0.16
		bulb_mesh.height = 0.32
		bulb.mesh = bulb_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = UiKit.GOLD
		mat.emission_enabled = true
		mat.emission = UiKit.GOLD
		mat.emission_energy_multiplier = 0.4
		bulb.material_override = mat
		_emitter_materials.append(mat)
		tip.add_child(bulb)
		_prong_tips.append(tip)


func _metal(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.75
	mat.roughness = 0.35
	return mat


# --- Performance -------------------------------------------------------------

## Comes down under its own weight and settles, rather than easing politely into place -
## it should land like something heavy arriving.
func descend(to_y := WORK_HEIGHT, duration := 1.7) -> void:
	visible = true
	position.y = maxf(to_y, PARK_HEIGHT)
	Audio.play("charge", 0.7)
	var tween := create_tween()
	tween.tween_property(self, "position:y", to_y, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	Audio.play("thud", 0.9)


func park(to_y := WORK_HEIGHT) -> void:
	visible = true
	position.y = to_y


func retract(duration := 1.4) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", PARK_HEIGHT, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false


func flash(strength := 1.0) -> void:
	flash_requested.emit(strength)


func set_charge(value: float) -> void:
	charge = clampf(value, 0.0, 1.0)


## One stylised bolt from a prong tip to a point near the animal. Deliberately built from
## a few straight segments with the middle ones kicked sideways: a clean straight beam
## reads as a laser, and a kinked one reads as electricity, which is the friendlier idea.
func fire_bolt(target: Vector3, tint := UiKit.ACCENT) -> void:
	if _prong_tips.is_empty():
		return
	var tip: Node3D = _prong_tips[randi() % _prong_tips.size()]
	var from: Vector3 = tip.position
	var bolt := Node3D.new()
	add_child(bolt)

	var previous := from
	for i in BOLT_SEGMENTS:
		var t := float(i + 1) / float(BOLT_SEGMENTS)
		var point: Vector3 = from.lerp(target, t)
		if i < BOLT_SEGMENTS - 1:
			# Kink sideways, but never on the last segment: the bolt has to actually land
			# on the animal or it looks like it missed.
			point += Vector3(randf_range(-0.28, 0.28), randf_range(-0.2, 0.2),
				randf_range(-0.28, 0.28))
		bolt.add_child(_segment(previous, point, tint))
		previous = point

	# Gone within a couple of frames. A bolt that lingers stops being a discharge and
	# becomes scenery.
	var life := create_tween()
	life.tween_interval(randf_range(0.06, 0.13))
	life.tween_callback(func() -> void:
		if is_instance_valid(bolt):
			bolt.queue_free())


func _segment(from: Vector3, to: Vector3, tint: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var length := from.distance_to(to)
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = maxf(length, 0.01)
	piece.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.9)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 7.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	piece.material_override = mat
	piece.position = (from + to) * 0.5
	# CylinderMesh runs along its own Y, so aim that axis down the segment.
	var along := (to - from).normalized()
	var hint := Vector3.RIGHT if absf(along.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var side := hint.cross(along).normalized()
	piece.basis = Basis(side, along, side.cross(along).normalized())
	return piece
