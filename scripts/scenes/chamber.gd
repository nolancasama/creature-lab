class_name TransformationChamber
extends Node3D
## The glass chamber in the middle of the laboratory. It fills a third at a time as
## sentences are completed, then executes all three "Now it is..." instructions at once.

signal flash_requested(strength: float)

const HEIGHT := 3.6
const RADIUS := 1.55
const RING_COUNT := 3

var fill_level := 0.0

var _energy: MeshInstance3D = null
var _energy_material: StandardMaterial3D = null
var _glass: StandardMaterial3D = null
var _lid: Node3D = null
var _rings: Array[Node3D] = []
var _ring_speed := 0.35
var _sparks: GPUParticles3D = null


func _ready() -> void:
	_build_base()
	_build_energy()
	_build_glass()
	_build_rings()
	_build_lid()
	set_fill(0.0, false)


func _process(delta: float) -> void:
	for i in _rings.size():
		_rings[i].rotation.y += delta * _ring_speed * (1.0 if i % 2 == 0 else -1.4)
	if _energy_material != null:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.25
		_energy_material.emission_energy_multiplier = 1.6 * pulse * maxf(fill_level, 0.05)


func _build_base() -> void:
	var base := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS + 0.25
	mesh.bottom_radius = RADIUS + 0.42
	mesh.height = 0.42
	mesh.radial_segments = 36
	base.mesh = mesh
	base.position.y = 0.21
	base.material_override = _metal(Color("#27354d"))
	add_child(base)

	# Three struts so the chamber reads as machinery rather than a jar.
	for i in 3:
		var strut := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22, HEIGHT + 0.4, 0.22)
		strut.mesh = box
		var angle := TAU * float(i) / 3.0 + 0.4
		strut.position = Vector3(cos(angle) * (RADIUS + 0.2), (HEIGHT + 0.4) * 0.5, sin(angle) * (RADIUS + 0.2))
		strut.material_override = _metal(Color("#1d2941"))
		add_child(strut)


func _build_energy() -> void:
	# The energy column is pivoted at the floor so scaling it upward reads as filling.
	var pivot := Node3D.new()
	pivot.name = "EnergyPivot"
	pivot.position.y = 0.42
	add_child(pivot)

	_energy = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS - 0.12
	mesh.bottom_radius = RADIUS - 0.12
	mesh.height = HEIGHT
	mesh.radial_segments = 32
	_energy.mesh = mesh
	_energy.position.y = HEIGHT * 0.5

	_energy_material = StandardMaterial3D.new()
	_energy_material.albedo_color = Color(0.31, 0.82, 1.0, 0.34)
	_energy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_energy_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_energy_material.emission_enabled = true
	_energy_material.emission = UiKit.ACCENT
	_energy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_energy.material_override = _energy_material
	pivot.add_child(_energy)

	_sparks = Fx.make("sparkle", UiKit.ACCENT, RADIUS - 0.3)
	_sparks.position = Vector3(0, HEIGHT * 0.4, 0)
	_sparks.emitting = false
	add_child(_sparks)


func _build_glass() -> void:
	var glass := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = HEIGHT
	mesh.radial_segments = 40
	glass.mesh = mesh
	glass.position.y = 0.42 + HEIGHT * 0.5

	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.6, 0.85, 1.0, 0.13)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass.metallic = 0.4
	_glass.roughness = 0.08
	glass.material_override = _glass
	add_child(glass)


func _build_rings() -> void:
	for i in RING_COUNT:
		var pivot := Node3D.new()
		pivot.position.y = 0.7 + float(i) * (HEIGHT - 0.9) / float(RING_COUNT - 1)
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = RADIUS + 0.12
		mesh.outer_radius = RADIUS + 0.26
		mesh.rings = 12
		ring.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#3d5c8a")
		mat.metallic = 0.7
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = UiKit.ACCENT
		mat.emission_energy_multiplier = 0.35
		ring.material_override = mat
		pivot.add_child(ring)
		add_child(pivot)
		_rings.append(pivot)


func _build_lid() -> void:
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position.y = HEIGHT + 0.42
	add_child(_lid)

	var cap := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS * 0.6
	mesh.bottom_radius = RADIUS + 0.35
	mesh.height = 0.5
	mesh.radial_segments = 36
	cap.mesh = mesh
	cap.position.y = 0.25
	cap.material_override = _metal(Color("#27354d"))
	_lid.add_child(cap)


func _metal(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.4
	return mat


# --- Behaviour ---------------------------------------------------------------

## `value` is 0..1. Sentences fill it a third at a time, which is the only visible
## progress meter in the game - there is no score.
func set_fill(value: float, animate := true) -> void:
	fill_level = clampf(value, 0.0, 1.0)
	var pivot: Node3D = get_node("EnergyPivot")
	var target := Vector3(1.0, maxf(fill_level, 0.001), 1.0)
	if not animate:
		pivot.scale = target
		return
	Audio.play("charge", 0.9 + fill_level * 0.3)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "scale", target, 0.7)
	_sparks.emitting = true
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(_sparks):
			_sparks.emitting = false)


func seal() -> void:
	var tween := create_tween()
	tween.tween_property(_lid, "position:y", HEIGHT + 0.1, 0.5).set_trans(Tween.TRANS_BACK)
	_ring_speed = 3.5
	_glass.albedo_color = Color(0.6, 0.85, 1.0, 0.22)


func unseal() -> void:
	var tween := create_tween()
	tween.tween_property(_lid, "position:y", HEIGHT + 0.42, 0.5).set_trans(Tween.TRANS_BACK)
	_ring_speed = 0.35
	_glass.albedo_color = Color(0.6, 0.85, 1.0, 0.13)


## The four seconds where the machine "synthesises a new organism". Everything visible
## here is meant to read as *the three sentences being executed at once*.
func run_transformation() -> void:
	seal()
	_sparks.emitting = true
	Audio.play("transform")
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_energy_material, "albedo_color:a", 0.85, 1.6)
	tween.tween_property(self, "_ring_speed", 22.0, 1.8)
	await get_tree().create_timer(1.8).timeout

	flash_requested.emit(1.0)
	Fx.burst(self, Vector3(0, HEIGHT * 0.5, 0), "sparkle", Color.WHITE, RADIUS)
	await get_tree().create_timer(0.5).timeout

	var settle := create_tween()
	settle.tween_property(_energy_material, "albedo_color:a", 0.34, 0.8)
	_ring_speed = 1.2
	_sparks.emitting = false


func reset() -> void:
	set_fill(0.0, false)
	unseal()
	_energy_material.albedo_color = Color(0.31, 0.82, 1.0, 0.34)
