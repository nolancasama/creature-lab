class_name Fx
extends RefCounted
## Particle presets built in code so the project carries no texture assets.

static var _dot: ImageTexture = null


## A soft radial dot used as the billboard for every particle preset.
static func dot_texture() -> ImageTexture:
	if _dot != null:
		return _dot
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / (size * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(image)
	return _dot


static func _billboard_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = dot_texture()
	mat.disable_receive_shadows = true
	return mat


static func _base(amount: int, lifetime: float, particle_size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, amount)
	particles.lifetime = lifetime
	var quad := QuadMesh.new()
	quad.size = Vector2(particle_size, particle_size)
	quad.material = _billboard_material()
	particles.draw_pass_1 = quad
	return particles


## kind: embers | frost | sparkle | dust | glow | motion
static func make(kind: String, tint := Color.WHITE, radius := 0.8) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius
	process.spread = 25.0
	process.color = tint

	var particles: GPUParticles3D
	match kind:
		"frost":
			particles = _base(26, 2.6, 0.12)
			process.direction = Vector3(0, -1, 0)
			process.gravity = Vector3(0, -0.45, 0)
			process.initial_velocity_min = 0.05
			process.initial_velocity_max = 0.25
			process.scale_min = 0.5
			process.scale_max = 1.2
		"sparkle":
			particles = _base(40, 1.1, 0.16)
			process.direction = Vector3(0, 1, 0)
			process.spread = 180.0
			process.gravity = Vector3(0, 0.4, 0)
			process.initial_velocity_min = 0.8
			process.initial_velocity_max = 2.2
			process.scale_min = 0.4
			process.scale_max = 1.0
		"dust":
			particles = _base(18, 2.2, 0.14)
			process.direction = Vector3(0, 1, 0)
			process.gravity = Vector3(0, 0.08, 0)
			process.initial_velocity_min = 0.02
			process.initial_velocity_max = 0.14
			process.scale_min = 0.6
			process.scale_max = 1.4
		"glow":
			particles = _base(20, 1.8, 0.2)
			process.direction = Vector3(0, 1, 0)
			process.spread = 180.0
			process.gravity = Vector3.ZERO
			process.initial_velocity_min = 0.1
			process.initial_velocity_max = 0.4
			process.scale_min = 0.5
			process.scale_max = 1.1
		"motion":
			particles = _base(22, 0.7, 0.13)
			process.direction = Vector3(0, 0, -1)
			process.spread = 12.0
			process.gravity = Vector3.ZERO
			process.initial_velocity_min = 1.6
			process.initial_velocity_max = 3.2
			process.scale_min = 0.3
			process.scale_max = 0.9
		_: # embers
			particles = _base(30, 1.5, 0.15)
			process.direction = Vector3(0, 1, 0)
			process.gravity = Vector3(0, 0.9, 0)
			process.initial_velocity_min = 0.4
			process.initial_velocity_max = 1.3
			process.scale_min = 0.4
			process.scale_max = 1.1

	particles.process_material = process
	return particles


## One-shot burst that removes itself once the last particle has died.
static func burst(parent: Node3D, at: Vector3, kind: String, tint: Color, radius := 0.6) -> void:
	if not is_instance_valid(parent):
		return
	var particles := make(kind, tint, radius)
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.position = at
	parent.add_child(particles)
	particles.emitting = true
	var timer := parent.get_tree().create_timer(particles.lifetime + 0.4)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free())
