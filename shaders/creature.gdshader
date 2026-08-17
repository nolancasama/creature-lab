shader_type spatial;

// Drives every visual trait on a skinned animal model.
//
// The colour trait is why this exists. Multiplying a target colour over the model's
// texture (the obvious StandardMaterial3D approach) fails on dark animals - a black cat
// times blue is still black, so "Now it is blue" doesn't read. Instead this takes the
// target colour and re-applies the *original texture's light/dark pattern* on top, so a
// black cat turns properly blue while its stripes, socks and collar stay visible.
//
// Hardness rides on top of all of it: the animal keeps its own colours and markings and
// simply turns polished and reflective, rather than being replaced by a metal statue.
// The hardening travels up the body from the feet using the model-space height passed
// down from the vertex stage.

uniform sampler2D base_tex : source_color;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wash : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float emission_flicker : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

// HARD. `harden_edge` is a model-space height: everything below it has already turned.
// Parking it above the model means "fully hard", below means "not started".
uniform float hardness : hint_range(0.0, 1.0) = 0.0;
uniform float harden_edge = 9999.0;
uniform float harden_width = 0.18;
uniform float sweep_glow : hint_range(0.0, 4.0) = 0.0;

// WEAK. Each region is a neutral bone segment supplied by CreatureRig. Vertices move
// radially toward that segment; projection along the segment never changes. This keeps
// every joint and all skeletal transforms untouched while visibly reducing soft-tissue
// volume. The fixed upper bound keeps the shader inexpensive on classroom hardware.
const int MAX_WEAK_REGIONS = 16;
uniform int weak_region_count = 0;
uniform vec3 weak_region_start[MAX_WEAK_REGIONS];
uniform vec3 weak_region_end[MAX_WEAK_REGIONS];
uniform float weak_region_radius[MAX_WEAK_REGIONS];
uniform float weak_region_scale[MAX_WEAK_REGIONS];
uniform float weak_region_amount[MAX_WEAK_REGIONS];

// Rib bounds are separate because the grooves need species-authored placement behind
// the front legs. They are shallow geometric depressions, never painted-only stripes.
uniform float weak_rib_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rib_center = vec3(0.0);
uniform vec3 rib_size = vec3(1.0);
uniform float rib_count : hint_range(3.0, 5.0) = 4.0;
uniform float rib_depth : hint_range(0.0, 0.08) = 0.02;

varying float model_height;
varying float rib_groove;

void vertex() {
	// VERTEX is model space here, which is what the sweep needs; in fragment() it would
	// already be view space.
	float best_deformation = 0.0;
	vec3 best_radial = vec3(0.0);
	for (int i = 0; i < MAX_WEAK_REGIONS; i++) {
		if (i >= weak_region_count) {
			break;
		}
		vec3 axis = weak_region_end[i] - weak_region_start[i];
		float axis_length_sq = max(dot(axis, axis), 0.000001);
		float along = dot(VERTEX - weak_region_start[i], axis) / axis_length_sq;
		float clamped_along = clamp(along, 0.0, 1.0);
		vec3 centerline = weak_region_start[i] + axis * clamped_along;
		vec3 radial = VERTEX - centerline;
		float radial_distance = length(radial);

		// Protect both joint centers and fade smoothly between adjacent regions. Vertices
		// beyond the region radius, including skulls, paws and identifying features, stay
		// exactly at their neutral positions.
		float joint_pin = smoothstep(0.03, 0.18, clamped_along)
			* smoothstep(0.03, 0.18, 1.0 - clamped_along);
		float radial_mask = 1.0 - smoothstep(weak_region_radius[i] * 0.82,
			weak_region_radius[i], radial_distance);
		float deformation = joint_pin * radial_mask * weak_region_amount[i]
			* (1.0 - weak_region_scale[i]);
		if (deformation > best_deformation) {
			best_deformation = deformation;
			best_radial = radial;
		}
	}
	// Only the radial component changes. The vertex's longitudinal position along its
	// neutral bone segment is invariant, so this cannot shorten a limb.
	VERTEX -= best_radial * best_deformation;

	vec3 rib_local = (VERTEX - rib_center) / max(rib_size, vec3(0.001));
	float vertical_mask = 1.0 - smoothstep(0.84, 1.0, abs(rib_local.y));
	float side_mask = smoothstep(0.16, 0.52, abs(rib_local.x))
		* (1.0 - smoothstep(0.78, 1.0, abs(rib_local.x)));
	float depth_mask = 1.0 - smoothstep(0.50, 1.0, abs(rib_local.z));
	float band_t = rib_local.y * 0.5 + 0.5;
	float bands = pow(abs(sin(band_t * rib_count * 3.14159265)), 7.0);
	rib_groove = weak_rib_amount * vertical_mask * side_mask * depth_mask * bands;
	VERTEX -= NORMAL * rib_groove * rib_depth;
	model_height = VERTEX.y;
}

void fragment() {
	vec4 tex = texture(base_tex, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

	// Floor so pure-black regions still take the colour; ceiling of exactly 1.0 so a
	// pale animal lands on the target colour instead of washing out past it.
	vec3 recoloured = tint.rgb * (0.45 + 0.55 * lum);
	vec3 albedo = mix(tex.rgb, recoloured, tint_amount);

	// A softer overlay used by hot/cold/old, which shift a creature toward a colour
	// without fully repainting it.
	albedo = mix(albedo, wash.rgb, wash_amount);
	// Just enough occlusion/roughness variation to make the genuine shallow geometry
	// readable at normal camera distance. With weak_rib_amount == 0 this is neutral.
	albedo *= 1.0 - rib_groove * 0.12;

	// How hardened this particular fragment is: 1 below the travelling edge, 0 above.
	float hardened = hardness * smoothstep(harden_edge + harden_width, harden_edge - harden_width, model_height);

	// Hard keeps the animal's own colours, just polished: a touch brighter and much
	// glossier, rather than repainted as metal. Metallic is kept modest deliberately -
	// pushing it high turns the animal DARK without strong environment reflections,
	// which reads as dirty rather than hard.
	albedo = mix(albedo, albedo * 1.22 + vec3(0.07), hardened);

	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_value + rib_groove * 0.08, 0.08, hardened);
	METALLIC = mix(metallic_value, 0.40, hardened);
	SPECULAR = mix(0.5, 1.0, hardened);

	// A polished rim. This is what actually sells "hard" on a cartoon model: a bright
	// glassy edge is legible from any angle, where a specular hotspot is not.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 sheen = vec3(0.70, 0.82, 1.0) * fresnel * hardened * 0.85;

	// A bright band riding the hardening front, so the change is visible sweeping up.
	float band = 1.0 - smoothstep(0.0, harden_width * 1.6, abs(model_height - harden_edge));

	// Cheap multi-sine flicker (no texture lookup) so a hot creature's inner glow
	// visibly guts and flares rather than sitting at one flat brightness - this is what
	// sells "lit from within by fire" instead of "painted orange".
	float flicker_mix = 1.0;
	if (emission_flicker > 0.0) {
		float n = sin(TIME * 9.1) * 0.5 + sin(TIME * 13.7 + 1.3) * 0.3 + sin(TIME * 5.3 + 3.1) * 0.2;
		flicker_mix = 1.0 + emission_flicker * n * 0.32;
	}

	EMISSION = emission_colour.rgb * emission_energy * flicker_mix + sheen
		+ vec3(0.75, 0.85, 1.0) * band * sweep_glow;
}
