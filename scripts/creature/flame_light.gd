class_name FlameLight
extends OmniLight3D
## A warm, irregularly flickering light carried by a burning creature.
##
## Without this the flame particles are additive billboards that light nothing: the
## platform under a blazing animal stays cool blue, and the whole effect reads as a
## sticker pasted over the scene rather than something on fire. Having the surroundings
## pulse orange is what actually sells "fire" from across a classroom.
##
## Shadows are off deliberately - a shadow-casting animated light is the single most
## expensive thing this effect could do, and the payoff here is the colour wash, not
## the shadows.

var base_energy := 1.0
var _phase := 0.0


static func create(color: Color, energy: float, range_m: float) -> FlameLight:
	var light := FlameLight.new()
	light.name = "FlameLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	light.base_energy = energy
	# A random start so two creatures burning side by side never flicker in lockstep.
	light._phase = randf() * TAU
	return light


func _process(delta: float) -> void:
	_phase += delta
	# Three detuned sines: the eye can't lock onto a repeating beat, so it reads as
	# genuine guttering rather than a pulsing lamp. Same trick as the shader's
	# emission_flicker, kept in phase-agreement by using the same frequencies.
	var n := sin(_phase * 9.1) * 0.5 + sin(_phase * 13.7 + 1.3) * 0.3 + sin(_phase * 5.3 + 3.1) * 0.2
	light_energy = base_energy * (1.0 + n * 0.28)
