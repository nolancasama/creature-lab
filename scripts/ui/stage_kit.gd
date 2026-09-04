class_name StageKit
extends RefCounted
## Shared 3D staging: environment, lights, floors, cameras. Four scenes show creatures
## on a lit surface; only the mood differs, so the setup lives in one place.

## Animal Selection hands off to the transformation chamber with the router's fade
## skipped - request_seamless_next_swap() - specifically so the cut is invisible. That
## only holds if the floor itself does not change: any radius or colour drift between
## the two scenes' ground() calls becomes the one-frame pop the seamless swap exists to
## avoid. Both call sites take the value from here rather than a literal so they cannot
## drift apart again the way they had.
const GROUND_RADIUS := 30.0
const GROUND_COLOR := Color("#070b13")


static func environment(sky_top: Color, sky_horizon: Color, ambient := 0.35) -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top
	sky_material.sky_horizon_color = sky_horizon
	sky_material.ground_bottom_color = sky_horizon.darkened(0.5)
	sky_material.ground_horizon_color = sky_horizon

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = false
	env.glow_enabled = GraphicsQuality.glow_enabled()
	env.glow_intensity = GraphicsQuality.glow_intensity()
	env.glow_bloom = 0.12

	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.set_meta("graphics_environment", true)
	holder.environment = env
	return holder


static func key_light(angle_deg := Vector3(-48, -35, 0), energy := 1.15) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = angle_deg
	light.light_energy = energy
	light.shadow_enabled = GraphicsQuality.shadows_enabled()
	light.set_meta("graphics_key_light", true)
	return light


static func fill_light(color: Color, position: Vector3, energy := 6.0, range_m := 12.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.position = position
	return light


static func ground(radius: float, color: Color, ring_color := Color.TRANSPARENT) -> Node3D:
	var root := Node3D.new()
	root.name = "Ground"

	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.2
	mesh.radial_segments = 48
	disc.mesh = mesh
	disc.position.y = -0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	disc.material_override = mat
	root.add_child(disc)

	if ring_color.a > 0.0:
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = radius - 0.12
		ring_mesh.outer_radius = radius
		ring.mesh = ring_mesh
		ring.position.y = 0.02
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = ring_color
		ring_mat.emission_enabled = true
		ring_mat.emission = ring_color
		ring_mat.emission_energy_multiplier = 1.4
		ring.material_override = ring_mat
		root.add_child(ring)

	return root


static func camera(position: Vector3, look_at: Vector3, fov := 52.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = fov
	cam.position = position
	cam.look_at_from_position(position, look_at, Vector3.UP)
	cam.current = true
	return cam


## A glowing platform disc for a creature to stand on.
## Height of a platform's standing surface. Anything an animal stands on, and any
## decoration around it, has to agree on this or the contact stops reading.
const SURFACE_Y := 0.28


static func platform(radius: float, base: Color, glow: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Platform"
	var solid := StaticBody3D.new()
	solid.name = "PlatformCollider"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.28
	collision.shape = shape
	collision.position.y = 0.14
	solid.add_child(collision)
	root.add_child(solid)

	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.08
	mesh.height = 0.28
	mesh.radial_segments = 40
	disc.mesh = mesh
	disc.position.y = 0.14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.metallic = 0.5
	mat.roughness = 0.35
	disc.material_override = mat
	root.add_child(disc)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.92
	ring_mesh.outer_radius = radius * 1.02
	ring.mesh = ring_mesh
	# Sit the ring's top flush with the platform surface the animal stands on. Centring
	# it above the surface made the brightest thing on screen sit higher than the paws,
	# which read as the animal levitating inside the ring.
	ring.position.y = SURFACE_Y - radius * 0.05
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = glow
	ring_mat.emission_enabled = true
	ring_mat.emission = glow
	ring_mat.emission_energy_multiplier = 2.0
	ring.material_override = ring_mat
	root.add_child(ring)

	return root


## A full-screen CanvasLayer for UI that sits over a 3D scene.
static func ui_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	return layer
