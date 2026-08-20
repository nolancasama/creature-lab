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

## The stand height the HOT flames were visually tuned against (the dog). Other species
## scale their flame size by their own height over this.
const FLAME_TUNED_HEIGHT := 1.55


## `animate` plays the transition into the new shape; without it the creature simply
## starts out transformed, which is what the zoo, the ghost and the finished creature
## want.
static func apply_all(rig: CreatureRig, traits: Dictionary, animate := false) -> void:
	if rig == null or rig.definition == null:
		return

	# Deformation has to survive the reset below, so remember where it currently is.
	var from_body := 1.0
	var from_leg := 1.0
	var from_bulk := 1.0
	var from_feel := 0.0
	if rig.feel != null:
		from_feel = rig.feel.feel
	if rig.deformer != null:
		from_body = rig.deformer.body_length
		from_leg = rig.deformer.leg_target
	if rig.muscle != null:
		from_bulk = rig.muscle.bulk.get("chest", 1.0)

	rig.reset_modifiers()

	var body_target := 1.0
	var leg_target := 1.0
	var bulk_target := 1.0
	var feel_target := 0.0
	# Colour last: it repaints roles that other modifiers may have tinted.
	var color_word := ""
	var saw_thermal := false
	var saw_age := false
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
		elif pair.modifier == "BULK":
			bulk_target = pair.value_for(word)
		elif pair.modifier == "MATERIAL":
			feel_target = pair.value_for(word)
		else:
			if pair.modifier == "THERMAL":
				saw_thermal = true
			elif pair.modifier == "AGE":
				saw_age = true
			_apply_pair(rig, str(category), word, animate)
	if not color_word.is_empty():
		_apply_color(rig, color_word)
	# A pending HOT/COLD pick was cancelled: nothing else clears thermal_fx_root, since
	# reset_modifiers() deliberately leaves it alone (see thermal_applied).
	if not saw_thermal and not is_nan(rig.thermal_applied):
		rig.clear_thermal_fx()
		rig.thermal_applied = NAN
	# The accessories are already gone with reset_modifiers(); this clears the flag that
	# remembers they were there, so re-picking young greets the student again.
	if not saw_age:
		rig.young_applied = false
		rig.old_applied = false

	if rig.deformer != null:
		if animate:
			rig.deformer.set_state(from_body, from_leg)
			rig.deformer.animate_to(body_target, leg_target)
		else:
			rig.deformer.set_state(body_target, leg_target)
	if rig.muscle != null:
		if animate:
			rig.muscle.set_state(from_bulk)
			rig.muscle.animate_to(bulk_target)
		else:
			rig.muscle.set_state(bulk_target)
	if rig.feel != null:
		if animate:
			rig.feel.set_state(from_feel)
			rig.feel.animate_to(feel_target)
		else:
			rig.feel.set_state(feel_target)
	# AGE props may have been built before BODY_LENGTH was snapped to its final pose.
	# Animated changes continue refreshing them from CreatureRig._process().
	rig.sync_bone_accessories()


static func _apply_color(rig: CreatureRig, word: String) -> void:
	# One call: the shader re-lights this colour with the model's own light/dark
	# pattern, so markings survive the repaint.
	rig.recolor(Content.color_of(word, rig.definition.skin_color))


static func _apply_pair(rig: CreatureRig, category: String, word: String, animate := false) -> void:
	var pair := Content.pair_for_category(category)
	if pair == null:
		return
	var value := pair.value_for(word)
	var mid := rig.definition.stand_height * 0.55

	match pair.modifier:
		"SCALE_UNIFORM":
			rig.scale_body(Vector3.ONE * value)
		"TEMPO":
			# SPEED is behaviour, not a playback multiplier - PaceDeformer owns the whole
			# thing, including how much of the value survives as animation speed. The old
			# permanent motion streak is gone with it: speed lines now appear only while
			# the animal is actually moving, which is the only time they mean anything.
			if animate:
				rig.pace.animate_to(value)
			else:
				rig.pace.set_state(value)
		"THERMAL":
			_apply_thermal(rig, value, mid, animate)
		"AGE":
			_apply_age(rig, value, mid, animate)
		"SURFACE":
			_apply_surface(rig, value, mid)


## HOT is layered from several small, cheap pieces rather than one particle system,
## because that's what actually reads as "fire" instead of "red dots": a warm emissive
## glow that flickers, licking flame tongues at the feet/back/head/tail, rising embers
## as a quieter secondary layer, and a flickering light so the platform underneath is
## lit by the fire rather than staying cold. `animate` adds a one-shot ignite whoosh;
## the persistent layers apply either way so a zoo creature still reads as hot while
## just standing there.
##
## The particle systems (and COLD's ColdEffect) live in thermal_fx_root, which -
## unlike fx_root - survives apply_all's reset. `changed` gates rebuilding them: every
## card tap re-applies the WHOLE committed trait set, so without this, tapping ANY
## other card while HOT/COLD is already committed would tear down and recreate these
## particle systems too. A freshly-built one starts empty and takes seconds to look
## full again (snow's lifetime alone is 5s) - that repeated, needless rebuild is what
## reads as "the animation takes a few seconds to activate" on every interaction.
static func _apply_thermal(rig: CreatureRig, value: float, mid: float, animate := false) -> void:
	var h := rig.definition.stand_height
	var changed := not is_equal_approx(rig.thermal_applied, value)
	rig.thermal_applied = value
	if value > 0.0:
		var energy := 0.62
		rig.tint_role("skin", HOT, 0.28)
		rig.set_emission("skin", HOT, energy)
		rig.set_emission_flicker(1.0)
		rig.tempo *= 1.06 # a little more energetic, not frantic

		if not changed:
			return
		rig.clear_thermal_fx()

		# Animals are normalised to their own stand height, which ranges from a 1.15
		# chicken to a 2.15 horse. Flames are sized against the dog and scaled from
		# there, so every species gets proportionally the same fire.
		var flame_scale := h / FLAME_TUNED_HEIGHT

		# Where the body actually is, per species. A fraction of stand_height cannot find
		# the torso on both a chicken and a horse - long legs and a raised neck move it a
		# long way relative to the crown - and getting this wrong is what made the fire
		# look like a separate bonfire standing behind the animal.
		var spine := _bone_point(rig, "back", Vector3(0, h * 0.62, 0))
		var skull := _bone_point(rig, "head_top", Vector3(0, h * 0.90, h * 0.20))
		var rear := _bone_point(rig, "rear", Vector3(0, h * 0.55, -h * 0.35))

		# The main sheet of fire, running the length of the spine. The emission box is
		# deliberately TALL - it spans from inside the torso to above the back line - so
		# it does not matter that the spine bone sits anywhere from 0.51 to 0.85 of stand
		# height depending on species: some tongues always spawn clear of the body and
		# the rest rise out through it, which is what fire on a back should look like.
		var back_fire := Fx.make("flame", HOT, h * 0.10, flame_scale)
		Fx.spread_along(back_fire, Vector3(h * 0.05, h * 0.14, h * 0.22))
		rig.add_thermal_fx(back_fire, spine, true)

		# Small licks at the head and tail so the silhouette itself looks alight. The
		# head one is deliberately small and sits at the skull bone rather than above the
		# crown: a big plume rising off the top of the head reads as a candle wick.
		rig.add_thermal_fx(Fx.make("flame", Color("#ffd27a"), h * 0.07, flame_scale * 0.5), skull, true)
		rig.add_thermal_fx(Fx.make("flame", Color("#ff5a1f"), h * 0.08, flame_scale * 0.65), rear, true)
		# Quiet rising embers behind everything else.
		rig.add_thermal_fx(Fx.make("embers", HOT, h * 0.5, flame_scale), Vector3(0, mid, 0), true)

		# The fire has to light its surroundings or it reads as a decal stuck on top of
		# the scene. Kept broad and dim rather than bright and tight - a hot puddle on
		# the platform looks like a spotlight, a wide wash looks like firelight.
		rig.add_thermal_fx(FlameLight.create(Color("#ff9a3c"), 1.5, h * 3.6), Vector3(0, h * 0.5, 0), true)

		if animate:
			rig.pulse_emission(energy * 1.8, energy, 0.55)
			var back: Node3D = rig.sockets.get("back", rig.body)
			Fx.burst(back, Vector3.ZERO, "flame", HOT, 0.45)
			Fx.burst(back, Vector3(0, 0.2, 0), "embers", HOT, 0.55)
	else:
		# Deliberately NOT glossy. HARD owns shine, and a cold animal rendered as polished
		# ice would collide with it; frost is matte and dusty, so pushing roughness up and
		# metallic to zero separates the two adjectives with no extra shader work. The
		# tint stays light so the animal's own colours read through it - the student has
		# to see it is still the same animal, only cold.
		rig.tint_role("skin", COLD, 0.16)
		rig.set_surface("skin", 0.95, 0.0)
		rig.tempo *= 0.9 # hunkered down, moving a little less

		if not changed:
			return
		rig.clear_thermal_fx()

		var cold := ColdEffect.create(rig)
		rig.add_thermal_fx(cold, Vector3.ZERO)
		if animate:
			cold.play_intro()


## Where a socket's bone actually sits, ignoring the mounting offset authored to float
## fantasy horns and wings clear of the body. Flames want the body surface itself, not
## the point a hat would hover at.
static func _bone_point(rig: CreatureRig, socket: String, fallback: Vector3) -> Vector3:
	var node: Node3D = rig.sockets.get(socket)
	if node == null:
		return fallback
	return node.position - rig.definition.socket_offset(socket)


## YOUNG must never touch overall size - see YoungKit for why, and for what it builds
## instead. OLD keeps its slight stoop: that is a posture, and the student reads it as
## age rather than as the SMALL card.
static func _apply_age(rig: CreatureRig, value: float, mid: float, animate := false) -> void:
	var was_young := rig.young_applied
	rig.young_applied = value <= 0.5

	var was_old := rig.old_applied
	rig.old_applied = value > 0.5

	if value > 0.5: # old
		# No body squash, no slowed tempo, no grey wash, no dust - see OldKit for what each
		# of those collided with. The whole of OLD is now on the face.
		OldKit.apply(rig)
		if animate and not was_old:
			Audio.play("elder", rig.definition.voice_pitch)
		return

	# young
	var def := rig.definition
	var head_scale := def.young_head_scale()
	var head_bone := def.socket_bone("head_top")
	if not head_bone.is_empty():
		# Scaling the one head bone, not the body. Verified against all seven skeletons:
		# the head_top socket's bone is the skull on every species, carrying at most the
		# jaw and ears with it, so nothing below the neck moves.
		rig.scale_bone(head_bone, Vector3.ONE * head_scale)

	YoungKit.apply(rig, head_scale)

	rig.tint_role("skin", def.young_tint(), 0.32)
	rig.tempo *= 1.25

	# Once, on becoming young - not on every re-apply of an unchanged trait set, and not
	# in the zoo or the ghost, which render finished creatures without animating into them.
	if animate and not was_young:
		Audio.play("baby", def.voice_pitch)


static func _apply_surface(rig: CreatureRig, value: float, mid: float) -> void:
	if value > 0.5: # worn out
		rig.set_surface("skin", 1.0, 0.0)
		rig.tint_role("skin", Color("#6b6459"), 0.22)
		rig.add_fx(Fx.make("dust", Color("#b3a893"), 0.7), Vector3(0, mid * 0.6, 0))
	else: # brand new
		rig.set_surface("skin", 0.45, 0.1)
		rig.set_emission("skin", Color.WHITE, 0.12)
		rig.add_fx(Fx.make("sparkle", Color("#fff2b0"), 0.9), Vector3(0, mid, 0))



		rig.scale_body(Vector3(1.08, 0.95, 1.08)) # squashy
