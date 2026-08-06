class_name CreatureFactory
extends RefCounted
## Builds the two things the game ever shows: the laboratory animal (the combined
## "It was..." state) and the fantasy creature (the combined "Now it is..." state).
##
## Fantasy Creature = Base Animal + Final Traits + Fantasy Parts + Generated Name, and
## the whole thing is seeded from CreatureState.fingerprint(), so the same three
## sentences always grow the same creature - on any machine, in any session.


static func build_plain(animal_id: String) -> CreatureRig:
	var def := Content.animal(animal_id)
	if def == null:
		return null
	return CreatureRig.create(def)


## The animal standing on the platform. `pending` lets the lab preview a card the
## student has selected but not yet said out loud.
static func build_lab_animal(state: CreatureState, pending := {}) -> CreatureRig:
	var rig := build_plain(state.animal_id)
	if rig == null:
		return null
	apply_before(rig, state, pending)
	return rig


static func apply_before(rig: CreatureRig, state: CreatureState, pending := {}) -> void:
	var traits := state.before_traits()
	traits.merge(pending, true)
	TraitVisuals.apply_all(rig, traits)


static func build_fantasy(state: CreatureState) -> CreatureRig:
	var rig := build_plain(state.animal_id)
	if rig == null:
		return null
	TraitVisuals.apply_all(rig, state.after_traits())
	grow_fantasy_parts(rig, state)
	_make_eyes_glow(rig)
	return rig


## Bolt on the modular parts triggered by the "Now it is ___" words. Deterministic:
## content order decides which parts, the fingerprint decides only the small angular
## jitter that stops symmetrical spikes looking machine-stamped.
static func grow_fantasy_parts(rig: CreatureRig, state: CreatureState) -> void:
	var words := PackedStringArray()
	for word in state.after_traits().values():
		words.append(str(word))

	var rng := RandomNumberGenerator.new()
	rng.seed = state.fingerprint()

	for definition in Content.fantasy_parts_for(words):
		var group := Node3D.new()
		group.name = definition.id
		group.rotation_degrees.y = rng.randf_range(-6.0, 6.0)
		for spec in definition.parts:
			var node := CreatureRig.build_part_node(spec, rig.material_for(spec.role))
			node.rotation_degrees += Vector3(
				rng.randf_range(-4.0, 4.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-4.0, 4.0)
			)
			group.add_child(node)
		rig.attach_to_socket(definition.socket, group)


## Every creature that walks out of the chamber has living eyes - the one visual cue
## that says "this is no longer an ordinary animal", regardless of which traits were used.
static func _make_eyes_glow(rig: CreatureRig) -> void:
	var glow := Content.role_color("glow", Color("#b7ffdf"))
	rig.set_role_color("eye", glow)
	rig.set_emission("eye", glow, 1.4)


## A translucent copy used side by side with the finished creature, so the student can
## see the "It was..." animal and the "Now it is..." creature at the same moment. That
## contrast is the grammar point, and it is otherwise separated by a scene change.
static func build_before_ghost(state: CreatureState) -> CreatureRig:
	var rig := build_plain(state.animal_id)
	if rig == null:
		return null
	TraitVisuals.apply_all(rig, state.before_traits())
	rig.clear_fx()
	for role in rig.materials:
		var mat: StandardMaterial3D = rig.materials[role]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.3
		mat.emission_enabled = false
	return rig
