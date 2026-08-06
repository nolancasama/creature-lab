class_name TraitVisuals
extends RefCounted
## Turns a {category: word} dictionary into what you actually see on the platform.
##
## Always applied as a whole set from a clean baseline rather than incrementally, so the
## result never depends on the order the student picked their cards, and "undo the card
## I mis-tapped" is just another call with one fewer entry.

const HOT := Color("#ff7a2f")
const COLD := Color("#8fd6ff")
const AGED := Color("#8f8c86")


static func apply_all(rig: CreatureRig, traits: Dictionary) -> void:
	if rig == null or rig.definition == null:
		return
	rig.reset_modifiers()
	# Colour last: it repaints roles that other modifiers may have tinted.
	var color_word := ""
	for category in traits:
		if str(category) == Content.COLOR_CATEGORY:
			color_word = str(traits[category])
		else:
			_apply_pair(rig, str(category), str(traits[category]))
	if not color_word.is_empty():
		_apply_color(rig, color_word)


static func _apply_color(rig: CreatureRig, word: String) -> void:
	var base := Content.color_of(word, rig.definition.skin_color)
	rig.set_role_color("skin", base)
	rig.set_role_color("accent", base.darkened(0.28))
	rig.set_role_color("belly", base.lightened(0.38))


static func _apply_pair(rig: CreatureRig, category: String, word: String) -> void:
	var pair := Content.pair_for_category(category)
	if pair == null:
		return
	var value := pair.value_for(word)
	var mid := rig.definition.stand_height * 0.55

	match pair.modifier:
		"SCALE_UNIFORM":
			rig.scale_body(Vector3.ONE * value)
		"SCALE_Y":
			# Keep the volume believable: a tall creature also gets a little narrower.
			var cross: float = pow(value, -0.25)
			rig.scale_body(Vector3(cross, value, cross))
		"SCALE_FEATURE":
			rig.stretch_feature(value)
		"BULK":
			rig.scale_parts(rig.definition.bulk_parts, Vector3(value, 1.0, value))
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
		rig.tint_role("skin", HOT, 0.45)
		rig.tint_role("accent", HOT, 0.3)
		rig.set_emission("skin", HOT, 0.55)
		rig.add_fx(Fx.make("embers", HOT, 0.7), Vector3(0, mid, 0))
	else:
		rig.tint_role("skin", COLD, 0.5)
		rig.tint_role("accent", COLD, 0.35)
		rig.set_surface("skin", 0.25, 0.1)
		rig.add_fx(Fx.make("frost", COLD, 0.8), Vector3(0, mid * 1.4, 0))


static func _apply_age(rig: CreatureRig, value: float, mid: float) -> void:
	if value > 0.5: # old
		rig.tint_role("skin", AGED, 0.5)
		rig.tint_role("accent", AGED, 0.4)
		rig.scale_body(Vector3(1.0, 0.94, 1.0)) # a little stooped
		rig.tempo *= 0.75
		rig.add_fx(Fx.make("dust", Color("#c9c2b4"), 0.6), Vector3(0, mid * 0.5, 0))
	else: # young
		rig.scale_body(Vector3(0.92, 0.86, 0.92))
		rig.tint_role("skin", rig.definition.belly_color, 0.28)
		rig.tempo *= 1.25


static func _apply_surface(rig: CreatureRig, value: float, mid: float) -> void:
	if value > 0.5: # worn out
		rig.set_surface("skin", 1.0, 0.0)
		rig.tint_role("skin", Color("#6b6459"), 0.3)
		rig.add_fx(Fx.make("dust", Color("#b3a893"), 0.7), Vector3(0, mid * 0.6, 0))
	else: # brand new
		rig.set_surface("skin", 0.12, 0.15)
		rig.set_emission("skin", Color.WHITE, 0.12)
		rig.add_fx(Fx.make("sparkle", Color("#fff2b0"), 0.9), Vector3(0, mid, 0))


static func _apply_material(rig: CreatureRig, value: float) -> void:
	if value > 0.5: # hard
		rig.set_surface("skin", 0.15, 0.85)
		rig.set_surface("accent", 0.2, 0.7)
	else: # soft
		rig.set_surface("skin", 1.0, 0.0)
		rig.scale_body(Vector3(1.08, 0.95, 1.08)) # squashy
