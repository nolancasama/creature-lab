class_name Fx
extends RefCounted
## Particle presets built in code so the project carries no texture assets.

static var _dot: ImageTexture = null
static var _flame_shape: ImageTexture = null
static var _flame_ramp: GradientTexture1D = null
static var _flame_scale_curve: CurveTexture = null
static var _puff_scale_curve: CurveTexture = null
static var _frost_patch: ImageTexture = null


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


## Additive suits glowing things (fire, sparks). Cold is the opposite case: breath,
## snow and mist are opaque pale matter, and adding them to the background turns them
## into glowing blobs instead of soft white puffs, so those pass `additive = false`.
static func _billboard_material(additive := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = dot_texture()
	mat.disable_receive_shadows = true
	return mat


static func _base(amount: int, lifetime: float, particle_size: float, additive := true) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, amount)
	particles.lifetime = lifetime
	var quad := QuadMesh.new()
	quad.size = Vector2(particle_size, particle_size)
	quad.material = _billboard_material(additive)
	particles.draw_pass_1 = quad
	return particles


## Grows out of nothing and keeps expanding as it thins away - a puff of breath or mist
## spreading into cold air, as opposed to a flame tongue which peaks then shrinks.
static func puff_scale_curve() -> CurveTexture:
	if _puff_scale_curve != null:
		return _puff_scale_curve
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.35, 0.85))
	curve.add_point(Vector2(1.0, 1.35))
	var tex := CurveTexture.new()
	tex.curve = curve
	_puff_scale_curve = tex
	return _puff_scale_curve


## White at full strength fading to nothing, for breath and mist that should thin out
## rather than change hue.
static func _fade_ramp(tint: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	var clear := tint
	clear.a = 0.0
	var mid := tint
	mid.a = tint.a * 0.55
	gradient.colors = PackedColorArray([tint, mid, clear])
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


## kind: flame | embers | snow | breath | cold_mist | frost_cling | sparkle | dust
##       | glow | motion
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
			# Curl and taper instead of turbulence. Turbulence looks slightly better but
			# compiles a large noise function into the particle shader, and on the
			# Compatibility renderer the web build uses that cost about five SECONDS of
			# blocked main thread per turbulent preset the first time it is drawn - see
			# ShaderWarmup. Accel parameters are part of the base shader and free.
			process.tangential_accel_min = -0.7
			process.tangential_accel_max = 0.7
			process.radial_accel_min = -0.3
			process.radial_accel_max = 0.05
		"snow":
			# Flakes drifting down past the animal. Mixed rather than additive so they
			# read as soft opaque specks instead of glowing motes, and slow enough that
			# a child tracks individual flakes.
			particles = _base(80, 5.0, 0.035 * size_scale, false)
			process.direction = Vector3(0, -1, 0)
			process.spread = 12.0
			process.gravity = Vector3(0, -0.14, 0)
			process.initial_velocity_min = 0.04
			process.initial_velocity_max = 0.16
			process.scale_min = 0.45
			process.scale_max = 1.3
			# Spiral, so snow does not fall in dead-straight lines and look like rain.
			# Turbulence did this better but was far too expensive to compile on the web
			# renderer - see the flame preset above and ShaderWarmup.
			process.tangential_accel_min = -0.4
			process.tangential_accel_max = 0.4
			process.radial_accel_min = -0.12
			process.radial_accel_max = 0.12
			process.damping_min = 0.0
			process.damping_max = 0.35
		"breath":
			# A puff of visible breath: leaves the muzzle with some speed, then damps
			# almost to a stop and billows outward as it thins.
			particles = _base(16, 1.25, 0.13 * size_scale, false)
			# Every animal model in the pack faces -Z, so breath blows that way.
			process.direction = Vector3(0, 0.22, -1)
			process.spread = 28.0
			process.gravity = Vector3(0, 0.05, 0)
			process.initial_velocity_min = 0.5
			process.initial_velocity_max = 1.15
			process.damping_min = 0.9
			process.damping_max = 1.5
			process.scale_min = 0.5
			process.scale_max = 1.2
			process.scale_curve = puff_scale_curve()
			process.color_ramp = _fade_ramp(Color(1, 1, 1, 0.55))
		"cold_mist":
			# Slow, wide, low-lying haze pooling around the feet. Large soft particles at
			# low alpha; the point is a drifting ground fog, not visible individuals.
			particles = _base(16, 4.0, 0.34 * size_scale, false)
			# Big soft billboards lying close to the ground cut into the platform and
			# show their quad edges as hard rectangles. Proximity fade dissolves them
			# where they meet solid geometry, which is what makes this read as fog.
			var mist_mat := particles.draw_pass_1.material as StandardMaterial3D
			mist_mat.proximity_fade_enabled = true
			mist_mat.proximity_fade_distance = 0.45
			process.direction = Vector3(0, 1, 0)
			process.spread = 60.0
			process.gravity = Vector3(0, 0.015, 0)
			process.initial_velocity_min = 0.02
			process.initial_velocity_max = 0.11
			process.scale_min = 0.7
			process.scale_max = 1.5
			process.color_ramp = _fade_ramp(Color(0.83, 0.93, 1.0, 0.30))
		"frost_cling":
			# Tiny glints that hang almost still, reading as frost caught on ears, fur
			# and tail rather than as anything falling or rising.
			particles = _base(12, 2.2, 0.05 * size_scale)
			process.direction = Vector3(0, 1, 0)
			process.spread = 180.0
			process.gravity = Vector3(0, 0.01, 0)
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.05
			process.scale_min = 0.4
			process.scale_max = 1.1
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
		"speed":
			# Stylised motion lines for FAST's dashes. Every other effect here is a round
			# mote; these are stretched along their own direction of travel instead, which
			# is what makes them read as lines rather than a puff of bubbles. Short-lived
			# on purpose - speed lines on a standing animal are decoration, and a decoration
			# that is always on stops meaning "fast".
			particles = _base(14, 0.34, 0.06)
			var streak := particles.draw_pass_1 as QuadMesh
			streak.size = Vector2(0.05, 0.32)
			var streak_mat := streak.material as StandardMaterial3D
			streak_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			process.particle_flag_align_y = true
			process.direction = Vector3(0, 0, -1)
			process.spread = 8.0
			process.gravity = Vector3.ZERO
			process.initial_velocity_min = 2.6
			process.initial_velocity_max = 4.4
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
			# Drift, without turbulence's compile cost (see the flame preset above).
			process.tangential_accel_min = -0.5
			process.tangential_accel_max = 0.5
			process.radial_accel_min = 0.0
			process.radial_accel_max = 0.3

	particles.process_material = process
	return particles


## A patch of frost for the ground under a cold animal: brightest at the centre and
## breaking up into an irregular crystalline edge rather than fading as a clean circle,
## which would read as a spotlight.
static func frost_patch_texture() -> ImageTexture:
	if _frost_patch != null:
		return _frost_patch
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.055
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(centre) / (size * 0.5)
			# Push the edge in and out with noise so the rim looks like spreading frost.
			var edge := 1.0 - d + noise.get_noise_2d(x, y) * 0.22
			var a: float = clampf(edge, 0.0, 1.0)
			a = a * a
			# Fine crystal speckle inside the patch.
			var speckle: float = 0.75 + 0.25 * (noise.get_noise_2d(x * 2.4 + 40.0, y * 2.4) * 0.5 + 0.5)
			image.set_pixel(x, y, Color(1, 1, 1, a * speckle))
	_frost_patch = ImageTexture.create_from_image(image)
	return _frost_patch


## A flat disc of ground frost. Lies just above the platform surface; the caller scales
## it up as the frost spreads.
static func frost_patch(radius: float, tint: Color) -> MeshInstance3D:
	var patch := MeshInstance3D.new()
	patch.name = "FrostPatch"
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	# Lay it flat: QuadMesh stands upright in XY by default.
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = frost_patch_texture()
	mat.albedo_color = tint
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# It sits flush on the platform, so it must not fight it for depth.
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	quad.material = mat
	patch.mesh = quad
	return patch


## Spread an emitter over a volume instead of a point, so flames cover a whole back or
## footprint rather than rising as a single candle-like column beside the animal.
static func spread_along(particles: GPUParticles3D, extents: Vector3) -> void:
	var process := particles.process_material as ParticleProcessMaterial
	if process == null:
		return
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents


## One-shot burst that removes itself once the last particle has died. `direction` is in
## the parent's local space; leaving it zero preserves the particle kind's own default.
static func burst(parent: Node3D, at: Vector3, kind: String, tint: Color, radius := 0.6,
		size_scale := 1.0, direction := Vector3.ZERO) -> void:
	if not is_instance_valid(parent):
		return
	var particles := make(kind, tint, radius, size_scale)
	if not direction.is_zero_approx():
		var process := particles.process_material as ParticleProcessMaterial
		if process != null:
			process.direction = direction.normalized()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.position = at
	parent.add_child(particles)
	particles.emitting = true
	# `finished` is a signal on the particle node itself, so the queue_free connection
	# is self-contained - unlike an external SceneTreeTimer capturing `particles` as a
	# closure upvalue, there is no way for this reference to go stale.
	particles.finished.connect(particles.queue_free)
