class_name TraitVisuals
extends RefCounted
## Turns a {category: word} dictionary into what you actually see on the platform.
##
## Always applied as a whole set from a clean baseline rather than incrementally, so the
## result never depends on the order the student picked their cards, and "undo the card
## I mis-tapped" is just another call with one fewer entry.
##
## Body length and leg length are handled apart from the rest: they are collected into
## target values and handed to the deformer, which either snaps to them or plays a
## cartoon transition into them. Everything else applies instantly either way.

const HOT := Color("#ff7a2f")
const COLD := Color("#8fd6ff")
const AGED := Color("#8f8c86")


## `animate` plays the transition into the new shape; without it the creature simply
## starts out transformed, which is what the zoo, the ghost and the finished creature
## want.
static func apply_all(rig: CreatureRig, traits: Dictionary, animate := false) -> void:
	if rig == null or rig.definition == null:
		return

	# Deformation has to survive the reset below, so remember where it currently is.
	var from_body := 1.0
	var from_leg := 1.0
	if rig.deformer != null:
		from_body = rig.deformer.body_length
		from_leg = rig.deformer.leg_target

	rig.reset_modifiers()

	var body_target := 1.0
	var leg_target := 1.0
	# Colour last: it repaints roles that other modifiers may have tinted.
	var color_word := ""
	for category in traits:
		var word := str(traits[category])
		if str(category) == Content.COLOR_CATEGORY:
			color_word = word
			continue
		var pair := Content.pair_for_category(str(category))
		if pair == null:
			continue
		if pair.modifier == "BODY_LENGTH":
			body_target = pair.value_for(word)
		elif pair.modifier == "LEG_LENGTH":
			leg_target = pair.value_for(word)
		else:
			_apply_pair(rig, str(category), word)
	if not color_word.is_empty():
		_apply_color(rig, color_word)

	if rig.deformer != null:
		if animate:
			rig.deformer.set_state(from_body, from_leg)
			rig.deformer.animate_to(body_target, leg_target)
		else:
			rig.deformer.set_state(body_target, leg_target)


static func _apply_color(rig: CreatureRig, word: String) -> void:
	# One call: the shader re-lights this colour with the model's own light/dark
	# pattern, so markings survive the repaint.
	rig.recolor(Content.color_of(word, rig.definition.skin_color))


static func _apply_pair(rig: CreatureRig, category: String, word: String) -> void:
	var pair := Content.pair_for_category(category)
	if pair == null:
		return
	var value := pair.value_for(word)
	var mid := rig.definition.stand_height * 0.55

	match pair.modifier:
		"SCALE_UNIFORM":
			rig.scale_body(Vector3.ONE * value)
		"BULK":
			rig.scale_parts(rig.definition.bulk_bones, Vector3(value, 1.0, value))
		"TEMPO":
			rig.tempo = value
			if value > 1.0:
				rig.add_fx(Fx.make("motion", Color("#bfe9ff"), 0.5), Vector3(0, mid, -0.5))
		"THERMAL":
			_apply_thermal(rig, value, mid)
		"AGE":
			_apply_age(rig, value, mid)
		"SURFACE":
			_apply_surface(rig, value, mid)
		"MATERIAL":
			_apply_material(rig, value)


static func _apply_thermal(rig: CreatureRig, value: float, mid: float) -> void:
	if value > 0.0:
		rig.tint_role("skin", HOT, 0.28)
		rig.set_emission("skin", HOT, 0.55)
		rig.add_fx(Fx.make("embers", HOT, 0.7), Vector3(0, mid, 0))
	else:
		rig.tint_role("skin", COLD, 0.28)
		rig.set_surface("skin", 0.55, 0.05)
		rig.add_fx(Fx.make("frost", COLD, 0.8), Vector3(0, mid * 1.4, 0))


static func _apply_age(rig: CreatureRig, value: float, mid: float) -> void:
	if value > 0.5: # old
		rig.tint_role("skin", AGED, 0.32)
		rig.scale_body(Vector3(1.0, 0.94, 1.0)) # a little stooped
		rig.tempo *= 0.75
		rig.add_fx(Fx.make("dust", Color("#c9c2b4"), 0.6), Vector3(0, mid * 0.5, 0))
	else: # young
		rig.scale_body(Vector3(0.92, 0.86, 0.92))
		rig.tint_role("skin", rig.definition.skin_color.lightened(0.45), 0.28)
		rig.tempo *= 1.25


static func _apply_surface(rig: CreatureRig, value: float, mid: float) -> void:
	if value > 0.5: # worn out
		rig.set_surface("skin", 1.0, 0.0)
		rig.tint_role("skin", Color("#6b6459"), 0.22)
		rig.add_fx(Fx.make("dust", Color("#b3a893"), 0.7), Vector3(0, mid * 0.6, 0))
	else: # brand new
		rig.set_surface("skin", 0.45, 0.1)
		rig.set_emission("skin", Color.WHITE, 0.12)
		rig.add_fx(Fx.make("sparkle", Color("#fff2b0"), 0.9), Vector3(0, mid, 0))


static func _apply_material(rig: CreatureRig, value: float) -> void:
	if value > 0.5: # hard
		rig.set_surface("skin", 0.15, 0.85)
	else: # soft
		rig.set_surface("skin", 1.0, 0.0)
		rig.scale_body(Vector3(1.08, 0.95, 1.08)) # squashy
