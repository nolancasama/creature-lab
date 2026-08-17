class_name Fx
extends RefCounted
## Particle presets built in code so the project carries no texture assets.

static var _dot: ImageTexture = null
static var _flame_shape: ImageTexture = null
static var _flame_ramp: GradientTexture1D = null
static var _flame_scale_curve: CurveTexture = null


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


## A teardrop "tongue of flame" silhouette - wide and soft at the base, pinched to a
## point at the top - so flame particles read as fire instead of generic round dots.
static func flame_shape_texture() -> ImageTexture:
	if _flame_shape != null:
		return _flame_shape
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		# 0 at the base (bottom of the image), 1 at the tip (top).
		var t := 1.0 - float(y) / float(size - 1)
		# Widest a third of the way up, tapering to a sharp point at the tip and a
		# rounded base, with a gentle S-curve so the tongue looks licked, not conical.
		var width := sin(PI * clampf(1.0 - t, 0.0, 1.0) * 0.92) * (1.0 - t * t * 0.55)
		width = maxf(width, 0.0)
		for x in size:
			var nx := (float(x) / float(size - 1) - 0.5) * 2.0
			# Lean the tongue slightly as it rises, like a flame caught mid-flicker.
			nx -= sin(t * PI) * 0.18
			var d := absf(nx) / maxf(width, 0.001)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (1.0 - t * 0.15)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	_flame_shape = ImageTexture.create_from_image(image)
	return _flame_shape


## Bright pale-yellow core cooling through orange to red as a flame particle ages, then
## fading out - the colour-over-lifetime that actually sells "fire" rather than "red".
static func flame_color_ramp() -> GradientTexture1D:
	if _flame_ramp != null:
		return _flame_ramp
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color("#fff3c4"),
		Color("#ffcf5c"),
		Color("#ff8a2f"),
		Color("#e8481f"),
		Color("#7a1808"),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.38, 0.62, 1.0])
	# Alpha fade is carried by the gradient's own colour alpha, read by the particle
	# shader's colour-over-lifetime; without this the flame would cut off hard. The tail
	# thins early and hard: these particles blend additively, so a tongue that lingers as
	# dull red goes magenta against the blue sky and reads as smoke rather than fire.
	var colors := gradient.colors
	colors[0].a = 0.95
	colors[2].a = 0.80
	colors[3].a = 0.22
	colors[4].a = 0.0
	gradient.colors = colors
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_flame_ramp = ramp
	return _flame_ramp


## Grows quickly out of the emission point, then shrinks to a point as it burns out -
## the shape change that makes a billboard actually read as "flickering" rather than a
## particle that merely fades.
static func flame_scale_curve() -> CurveTexture:
	if _flame_scale_curve != null:
		return _flame_scale_curve
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(0.6, 0.85))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	_flame_scale_curve = tex
	return _flame_scale_curve


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


## kind: flame | embers | frost | sparkle | dust | glow | motion
##
## `size_scale` multiplies the individual particle size. Emitters are placed in an
## animal's normalised space, so without this a chicken and a horse would get
## identically-sized flames and the chicken would look like a birthday candle.
static func make(kind: String, tint := Color.WHITE, radius := 0.8, size_scale := 1.0) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius
	process.spread = 25.0
	process.color = tint

	var particles: GPUParticles3D
	match kind:
		"flame":
			# Licking tongues of fire: the shaped billboard plus the yellow->red ramp is
			# what reads as "flame" instead of "particles"; a narrow emission cone and a
			# short spread keep the tongues climbing together rather than scattering.
			# Many small short-lived tongues rather than a few large ones, so they
			# overlap into one moving mass instead of being individually countable.
			particles = _base(34, 0.85, 0.2)
			var quad := QuadMesh.new()
			quad.size = Vector2(0.20, 0.30) * size_scale
			var mat := _billboard_material()
			mat.albedo_texture = flame_shape_texture()
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.55, 0.15)
			mat.emission_energy_multiplier = 1.6
			quad.material = mat
			particles.draw_pass_1 = quad
			process.emission_sphere_radius = radius * 0.35
			process.direction = Vector3(0, 1, 0)
			process.spread = 14.0
			process.gravity = Vector3(0, 0.55, 0)
			process.initial_velocity_min = 0.35
			process.initial_velocity_max = 0.75
			process.scale_min = 0.7
			process.scale_max = 1.3
			process.scale_curve = flame_scale_curve()
			process.color_ramp = flame_color_ramp()
			# A few degrees of lean for variety, but NO angular velocity: a rotating
			# tongue stops reading as fire and starts reading as a falling leaf. Flames
			# point up.
			process.angle_min = -9.0
			process.angle_max = 9.0
			# A gentle side-to-side sway per particle, the cheapest way to fake flicker
			# without per-frame scripting.
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 0.9
			process.turbulence_noise_scale = 2.2
			process.turbulence_influence_min = 0.35
			process.turbulence_influence_max = 0.6
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
		_: # embers - small glowing sparks drifting up, secondary to the flame tongues
			particles = _base(22, 1.7, 0.09 * size_scale)
			var ember_mat := particles.draw_pass_1.material as StandardMaterial3D
			ember_mat.emission_enabled = true
			ember_mat.emission = tint
			ember_mat.emission_energy_multiplier = 2.2
			process.direction = Vector3(0, 1, 0)
			process.spread = 18.0
			process.gravity = Vector3(0, 0.55, 0)
			process.initial_velocity_min = 0.3
			process.initial_velocity_max = 0.9
			process.scale_min = 0.35
			process.scale_max = 0.9
			process.color_ramp = flame_color_ramp()
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 0.6
			process.turbulence_noise_scale = 3.0
			process.turbulence_influence_min = 0.5
			process.turbulence_influence_max = 0.8

	particles.process_material = process
	return particles


## Spread an emitter over a volume instead of a point, so flames cover a whole back or
## footprint rather than rising as a single candle-like column beside the animal.
static func spread_along(particles: GPUParticles3D, extents: Vector3) -> void:
	var process := particles.process_material as ParticleProcessMaterial
	if process == null:
		return
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents


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
	# `finished` is a signal on the particle node itself, so the queue_free connection
	# is self-contained - unlike an external SceneTreeTimer capturing `particles` as a
	# closure upvalue, there is no way for this reference to go stale.
	particles.finished.connect(particles.queue_free)
