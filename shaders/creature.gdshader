shader_type spatial;

// Drives every visual trait on a skinned animal model.
//
// The colour trait is why this exists. Multiplying a target colour over the model's
// texture (the obvious StandardMaterial3D approach) fails on dark animals - a black cat
// times blue is still black, so "Now it is blue" doesn't read. Instead this takes the
// target colour and re-applies the *original texture's light/dark pattern* on top, so a
// black cat turns properly blue while its stripes, socks and collar stay visible.

uniform sampler2D base_tex : source_color;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wash : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

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

	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = emission_colour.rgb * emission_energy;
}
