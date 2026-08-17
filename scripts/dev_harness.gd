class_name DevHarness
extends RefCounted
## Command-line hooks for checking the build without clicking through it.
##
##   godot --path . -- --selftest          content, assembly and grammar checks, then quit
##   godot --path . -- --phase=lab         jump straight to a screen
##   godot --path . -- --shot=lab          jump there, save user://shot_lab.png, quit
##   godot --path . -- --backtest          abandon a half-finished round, then restart it

const SHOT_DELAY := 1.6


static func run_if_requested(main: Node) -> void:
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var phase := ""
	var selftest := false
	for arg in args:
		var text := str(arg)
		if text == "--selftest":
			selftest = true
		elif text.begins_with("--shot="):
			shot = text.substr(7)
		elif text.begins_with("--phase="):
			phase = text.substr(8)

	if selftest:
		_selftest(main)
		return
	if args.has("--autoplay"):
		_autoplay(main)
	elif args.has("--backtest"):
		_backtest(main)
	elif not shot.is_empty():
		_screenshot(main, shot)
	elif not phase.is_empty():
		_goto(phase)
## Plays a whole round through the real UI signals - pick a card, say the sentence,
## three times, then the chamber - and reports where it ended up. This is the only check
## that covers the awaits in the transformation sequence.
static func _autoplay(main: Node) -> void:
	var tree := main.get_tree()
	_goto("lab")
	await tree.create_timer(1.4).timeout

	var picks := [
		["LENGTH", "long", "short"],
		["HARDNESS", "hard", "soft"],
		[Content.COLOR_CATEGORY, "red", "blue"],
	]
	for pick in picks:
		var word_lab: WordLab = _find_word_lab(Router.current_scene)
		if word_lab == null:
			printerr("[autoplay] FAIL: no Word Lab in %s" % Router.current_scene)
			tree.quit(1)
			return
		word_lab.pair_selected.emit(str(pick[0]), str(pick[1]), str(pick[2]))
		await tree.create_timer(0.7).timeout
		Speech.submit_typed(GrammarValidator.expected_sentence(str(pick[1]), str(pick[2])))
		await tree.create_timer(2.6).timeout
		print("[autoplay] slot %d recorded" % Game.current.slots_filled())

	# The chamber sequence plus the fade into the naming screen.
	await tree.create_timer(12.0).timeout

	var ok := Game.phase == Game.Phase.NAMING
	print("[autoplay] ended in phase %s" % Game.Phase.keys()[Game.phase])
	if ok:
		await RenderingServer.frame_post_draw
		main.get_viewport().get_texture().get_image().save_png("user://shot_autoplay.png")
		print("[autoplay] PASS")
	else:
		printerr("[autoplay] FAIL: expected NAMING")
	tree.quit(0 if ok else 1)


## Abandoning a half-finished round used to leave the Word Lab on screen with
## Game.current already null, so every adjective card was silently dead against its own
## guard. Presses the real back button and checks a fresh round can still be recorded.
static func _backtest(main: Node) -> void:
	var tree := main.get_tree()
	_goto("lab")
	await tree.create_timer(1.4).timeout

	# Record one sentence first, so the round is genuinely half-finished when abandoned.
	var word_lab := _find_word_lab(Router.current_scene)
	if word_lab == null:
		printerr("[backtest] FAIL: no Word Lab to start from")
		tree.quit(1)
		return
	word_lab.pair_selected.emit("LENGTH", "long", "short")
	await tree.create_timer(0.7).timeout
	Speech.submit_typed(GrammarValidator.expected_sentence("long", "short"))
	await tree.create_timer(2.6).timeout
	print("[backtest] %d slot(s) recorded, now backing out" % Game.current.slots_filled())

	var back := _find_button(Router.current_scene, "<")
	if back == null:
		printerr("[backtest] FAIL: no back button on the recording screen")
		tree.quit(1)
		return
	back.pressed.emit()
	await tree.create_timer(1.0).timeout

	if Game.current != null:
		printerr("[backtest] FAIL: abandoned creature is still current")
		tree.quit(1)
		return
	if _find_word_lab(Router.current_scene) != null:
		printerr("[backtest] FAIL: Word Lab still on screen after backing out")
		tree.quit(1)
		return
	print("[backtest] back returned to picking")

	# The regression itself: start over and check a card still registers.
	var go := _find_button(Router.current_scene, "Start Creating  ->")
	if go == null:
		printerr("[backtest] FAIL: no Start Creating button after backing out")
		tree.quit(1)
		return
	go.pressed.emit()
	await tree.create_timer(1.0).timeout

	word_lab = _find_word_lab(Router.current_scene)
	if word_lab == null:
		printerr("[backtest] FAIL: no Word Lab after restarting")
		tree.quit(1)
		return
	word_lab.pair_selected.emit("LENGTH", "long", "short")
	await tree.create_timer(0.7).timeout
	Speech.submit_typed(GrammarValidator.expected_sentence("long", "short"))
	await tree.create_timer(2.6).timeout

	var slots := Game.current.slots_filled() if Game.current != null else 0
	if slots == 1:
		print("[backtest] PASS")
		tree.quit(0)
	else:
		printerr("[backtest] FAIL: card did not register after backing out (%d slots)" % slots)
		tree.quit(1)


static func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


static func _find_word_lab(node: Node) -> WordLab:
	if node == null:
		return null
	if node is WordLab:
		return node
	for child in node.get_children():
		var found := _find_word_lab(child)
		if found != null:
			return found
	return null


## Drive the FSM through legal transitions to reach a screen, seeding whatever state
## that screen needs to render.
static func _goto(phase: String) -> void:
	var ids := Content.animal_ids()
	if ids.is_empty():
		return
	match phase:
		"select":
			Game.set_phase(Game.Phase.ANIMAL_SELECTION)
		"lab":
			# The recording sub-state of ANIMAL_SELECTION: Game.current already begun,
			# so the scene's _ready() skips the picking grid and goes straight there.
			Game.begin_creature("dog" if ids.has("dog") else ids[0])
			Game.set_phase(Game.Phase.ANIMAL_SELECTION)
		"chamber":
			_seed_full_creature(ids)
			Game.set_phase(Game.Phase.ANIMAL_SELECTION)
			Game.set_phase(Game.Phase.CREATURE_LAB)
		"naming":
			_seed_full_creature(ids)
			Game.set_phase(Game.Phase.ANIMAL_SELECTION)
			Game.set_phase(Game.Phase.CREATURE_LAB)
			Game.set_phase(Game.Phase.TRANSFORMATION)
			Game.set_phase(Game.Phase.NAMING)
		"zoo":
			for i in 5:
				Game.spawn_debug_creature()
			Game.set_phase(Game.Phase.ZOO)
		"settings":
			Game.open_settings()


static func _seed_full_creature(ids: PackedStringArray) -> void:
	Game.begin_creature("dog" if ids.has("dog") else ids[0])
	Game.record_sentence("LENGTH", "long", "short")
	Game.record_sentence("HARDNESS", "hard", "soft")
	Game.record_sentence(Content.COLOR_CATEGORY, "red", "blue")
	Game.current.generated_name = NameGenerator.candidates(Game.current)[0]


static func _screenshot(main: Node, phase: String) -> void:
	_goto(phase)
	await main.get_tree().create_timer(SHOT_DELAY).timeout
	await RenderingServer.frame_post_draw
	var image := main.get_viewport().get_texture().get_image()
	var path := "user://shot_%s.png" % phase
	image.save_png(path)
	print("[shot] saved %s -> %s" % [path, ProjectSettings.globalize_path(path)])
	main.get_tree().quit()


static func _selftest(main: Node) -> void:
	# A plain Array, not PackedStringArray: packed arrays are copy-on-write, so
	# appends inside _check() would never reach the caller.
	var failures: Array[String] = []

	_check(failures, Content.animals.size() >= 7, "expected 7 animals, got %d" % Content.animals.size())
	_check(failures, Content.pairs.size() >= 8, "expected 8 opposite pairs, got %d" % Content.pairs.size())
	_check(failures, Content.colors.size() >= 10, "expected 10 colours, got %d" % Content.colors.size())
	_check(failures, Content.fantasy_parts.size() >= 10, "expected fantasy parts, got %d" % Content.fantasy_parts.size())

	# Every animal must load its model, and every bone the data references must really
	# exist in that model - a typo in animals.json is otherwise invisible until a trait
	# silently does nothing.
	for def in Content.animals:
		var rig := CreatureFactory.build_plain(def.id)
		_check(failures, rig != null, "%s did not build" % def.id)
		if rig == null:
			continue
		_check(failures, rig.skeleton != null, "%s: no skeleton in model '%s'" % [def.id, def.model])
		_check(failures, rig.mesh_instance != null, "%s: no mesh in model '%s'" % [def.id, def.model])
		_check(failures, not def.body_bones.is_empty(), "%s has no LONG/SHORT body bones" % def.id)
		for group in MuscleDeformer.GROUPS:
			_check(failures, not def.bulk_bones_for(group).is_empty(),
				"%s has no bones for muscle group '%s'" % [def.id, group])
		_check(failures, def.legs.size() >= 2, "%s has fewer than 2 legs configured" % def.id)
		for leg in def.legs:
			_check(failures, def.foot_contacts.has(str(leg.get("id", ""))),
				"%s: explicit sole contact missing for '%s'" % [def.id, leg.get("id", "")])

		if rig.skeleton != null:
			var all_bones: Array[String] = []
			all_bones.append_array(Array(def.body_bones))
			for group in MuscleDeformer.GROUPS:
				all_bones.append_array(Array(def.bulk_bones_for(group)))
			all_bones.append_array(Array(def.leg_bones))
			for leg in def.legs:
				all_bones.append_array(Array(leg["bones"] as PackedStringArray))
			for socket in def.sockets:
				all_bones.append(def.socket_bone(str(socket)))
			for bone in all_bones:
				_check(failures, rig.skeleton.find_bone(bone) != -1,
					"%s: bone '%s' not in model" % [def.id, bone])

		for socket in ["head_top", "back", "rear", "face"]:
			_check(failures, def.sockets.has(socket), "%s: socket '%s' missing" % [def.id, socket])

		# Height normalisation is what lets a chicken and a horse share a camera.
		_check(failures, absf(rig.crown_height() - def.stand_height) < 0.01,
			"%s: normalised to %.2f, expected %.2f" % [def.id, rig.crown_height(), def.stand_height])
		_check(failures, rig.deformer.requires_grounding() == def.ground_neutral,
			"%s: neutral grounding policy was not respected" % def.id)

		# LONG must actually move the torso, TALL must actually lift the body, and both
		# must return to exactly rest - otherwise a cancelled card leaves a dent.
		# Local pose, not global: a skeleton outside the scene tree never recomputes its
		# global pose, and the selftest builds rigs unparented.
		var tip := rig.skeleton.find_bone(def.body_bones[def.body_bones.size() - 1])
		var rest_tip: Vector3 = rig.skeleton.get_bone_rest(tip).origin
		rig.deformer.set_state(1.95, 1.0)
		var long_tip: Vector3 = rig.skeleton.get_bone_pose_position(tip)
		_check(failures, long_tip.distance_to(rest_tip) > 0.01,
			"%s: LONG did not move the torso" % def.id)

		rig.deformer.set_state(1.0, 2.2)
		_check(failures, rig.deformer.lift > 0.01,
			"%s: TALL did not lift the body (feet would sink)" % def.id)
		rig.deformer.set_state(1.0, 0.45)
		_check(failures, rig.deformer.lift < -0.005,
			"%s: SHORT legs did not lower the body" % def.id)

		# STRONG may scale its muscle bones. WEAK must leave every joint transform neutral
		# and make the visible change exclusively through absolute shader parameters.
		rig.deformer.reset()
		var neutral_positions: Array[Vector3] = []
		for bone_idx in rig.skeleton.get_bone_count():
			neutral_positions.append(rig.skeleton.get_bone_pose_position(bone_idx))
		var chest_bone := rig.skeleton.find_bone(def.bulk_bones_for("chest")[0])
		rig.muscle.set_state(1.35)
		_check(failures, rig.skeleton.get_bone_pose_scale(chest_bone).x > 1.05,
			"%s: STRONG did not thicken the chest" % def.id)
		rig.muscle.set_state(0.60)
		for bone_idx in rig.skeleton.get_bone_count():
			_check(failures, rig.skeleton.get_bone_pose_scale(bone_idx).is_equal_approx(Vector3.ONE),
				"%s: WEAK scaled skeletal bone '%s'" % [def.id, rig.skeleton.get_bone_name(bone_idx)])
			_check(failures, rig.skeleton.get_bone_pose_position(bone_idx).is_equal_approx(neutral_positions[bone_idx]),
				"%s: WEAK moved joint '%s'" % [def.id, rig.skeleton.get_bone_name(bone_idx)])
		_check(failures, is_zero_approx(rig.muscle.lift),
			"%s: WEAK changed the creature root height" % def.id)
		var region_amounts: PackedFloat32Array = rig.material.get_shader_parameter("weak_region_amount")
		var visible_weak := false
		for amount in region_amounts:
			visible_weak = visible_weak or amount > 0.9
		_check(failures, visible_weak, "%s: WEAK mesh thinning did not activate" % def.id)
		_check(failures, float(rig.material.get_shader_parameter("weak_rib_amount")) > 0.9,
			"%s: WEAK rib deformation did not activate" % def.id)
		rig.muscle.set_state(1.35)
		rig.muscle.set_state(0.60)
		_check(failures, rig.skeleton.get_bone_pose_scale(chest_bone).is_equal_approx(Vector3.ONE),
			"%s: STRONG to WEAK retained skeletal bulk" % def.id)
		rig.muscle.reset()
		_check(failures, absf(rig.skeleton.get_bone_pose_scale(chest_bone).x - 1.0) < 0.001,
			"%s: muscle did not return to rest" % def.id)
		_check(failures, float(rig.material.get_shader_parameter("weak_rib_amount")) < 0.001,
			"%s: WEAK surface deformation did not reset" % def.id)

		# HARD must shine and stiffen; SOFT must puff and stay loose. The two have to
		# move opposite directions or the adjectives are not distinguishable.
		_check(failures, not def.floppy_bones.is_empty(), "%s has no floppy appendages" % def.id)
		rig.feel.set_state(1.0)
		var hard_motion := rig.feel.motion_scale()
		var hard_scale := rig.feel.scale_multiplier
		_check(failures, rig.feel.hardness() > 0.9 and rig.feel.softness() < 0.01,
			"%s: HARD did not register" % def.id)
		rig.feel.set_state(-1.0)
		_check(failures, rig.feel.softness() > 0.9, "%s: SOFT did not register" % def.id)
		_check(failures, rig.feel.scale_multiplier.x > hard_scale.x + 0.02,
			"%s: SOFT is not puffier than HARD" % def.id)
		_check(failures, rig.feel.motion_scale() > hard_motion + 0.3,
			"%s: SOFT is not looser than HARD" % def.id)
		rig.feel.reset()
		_check(failures, rig.feel.scale_multiplier.is_equal_approx(Vector3.ONE),
			"%s: feel did not return to rest" % def.id)

		rig.deformer.reset()
		var back_tip: Vector3 = rig.skeleton.get_bone_pose_position(tip)
		_check(failures, back_tip.distance_to(rest_tip) < 0.001,
			"%s: deformation did not return to rest" % def.id)

		# Exercise the real post-animation grounding pass in-tree. Pair extensions must be
		# symmetrical and every explicit sole point must converge on the flat platform.
		main.add_child(rig)
		if def.ground_neutral:
			var neutral_body_y := rig.body.position.y
			# Repeated passes catch common-extension feedback, which used to ratchet the
			# whole Tiger upward only after it had been selected for about a second.
			for ground_step in 120:
				rig.solve_idle_grounding_immediately()
			var neutral_contacts := rig.foot_contact_positions()
			_check(failures, absf(rig.body.position.y - neutral_body_y) < 0.002,
				"%s: neutral stance correction lifted the whole animal" % def.id)
			for contact_idx in neutral_contacts.size():
				_check(failures, absf(neutral_contacts[contact_idx].y - CreatureRig.GROUND_CLEARANCE) < 0.005,
					"%s: neutral foot '%s' did not ground (y=%.3f)" % [def.id,
						def.legs[contact_idx].get("id", ""), neutral_contacts[contact_idx].y])
			_check(failures, rig.deformer.ground_extension(0) > 0.002,
				"%s: neutral front paws were not lowered" % def.id)
			_check(failures, is_equal_approx(rig.deformer.ground_extension(0), rig.deformer.ground_extension(1)),
				"%s: neutral front-paw correction became asymmetric" % def.id)
			_check(failures, rig.deformer.ground_extension(2) < 0.001 and rig.deformer.ground_extension(3) < 0.001,
				"%s: neutral correction changed the rear paws" % def.id)
		rig.deformer.set_state(1.0, 1.35)
		for ground_step in 4:
			rig.solve_idle_grounding_immediately()
		var contacts := rig.foot_contact_positions()
		for contact_idx in contacts.size():
			_check(failures, absf(contacts[contact_idx].y - CreatureRig.GROUND_CLEARANCE) < 0.025,
				"%s: foot '%s' did not ground (y=%.3f)" % [def.id,
					def.legs[contact_idx].get("id", ""), contacts[contact_idx].y])
		if def.legs.size() >= 4:
			_check(failures, is_equal_approx(rig.deformer.ground_extension(0), rig.deformer.ground_extension(1)),
				"%s: front pair grounding became asymmetric" % def.id)
			_check(failures, is_equal_approx(rig.deformer.ground_extension(2), rig.deformer.ground_extension(3)),
				"%s: rear pair grounding became asymmetric" % def.id)
		main.remove_child(rig)
		rig.free()

	# Traits and fantasy assembly, exercised across every pair and both directions.
	for def in Content.animals:
		var state := CreatureState.create(def.id)
		state.add_entry("SIZE", "small", "big")
		state.add_entry("TEMPERATURE", "hot", "cold")
		state.add_entry(Content.COLOR_CATEGORY, "red", "blue")
		var creature := CreatureFactory.build_fantasy(state)
		_check(failures, creature != null, "%s: fantasy build failed" % def.id)
		var names := NameGenerator.candidates(state)
		_check(failures, names.size() > 0 and not names[0].is_empty(), "%s: no name generated" % def.id)
		_check(failures, state.fingerprint() == CreatureState.from_dict(state.to_dict()).fingerprint(),
			"%s: fingerprint not stable through save/load" % def.id)
		if creature != null:
			creature.free()

	for pair in Content.pairs:
		for word in pair.words():
			var rig := CreatureFactory.build_plain(Content.animals[0].id)
			TraitVisuals.apply_all(rig, {pair.category: word})
			_check(failures, rig != null, "%s/%s failed to apply" % [pair.category, word])
			rig.free()

	_grammar_checks(failures)

	if failures.is_empty():
		print("[selftest] PASS")
	else:
		printerr("[selftest] %d FAILURE(S):" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
	main.get_tree().quit(0 if failures.is_empty() else 1)


static func _grammar_checks(failures: Array[String]) -> void:
	var cases := [
		# transcript, before, after, strictness, expected ok, note
		["It was small. Now it is big.", "small", "big", GrammarValidator.NORMAL, true, "clean sentence"],
		["it was small now it is big", "small", "big", GrammarValidator.NORMAL, true, "no punctuation"],
		["um it was small now it is big okay", "small", "big", GrammarValidator.NORMAL, true, "edge filler"],
		["it was small now it's big", "small", "big", GrammarValidator.NORMAL, true, "contraction expanded"],
		["it was small and now it is big", "small", "big", GrammarValidator.EXACT, true, "exact tolerates 'and'"],
		["it was small now it is big please", "small", "big", GrammarValidator.EXACT, false, "exact rejects extras"],
		["small big", "small", "big", GrammarValidator.LENIENT, true, "lenient keywords"],
		["small big", "small", "big", GrammarValidator.NORMAL, false, "normal needs the frame"],
		["it was big now it is small", "small", "big", GrammarValidator.NORMAL, false, "reversed pair"],
		["it was red now it is blew", "red", "blue", GrammarValidator.NORMAL, true, "homophone blew->blue"],
		["it was read now it is blue", "red", "blue", GrammarValidator.NORMAL, true, "homophone read->red"],
		["it was hot now it is called", "hot", "cold", GrammarValidator.NORMAL, true, "homophone called->cold"],
		["it was small", "small", "big", GrammarValidator.NORMAL, false, "half a sentence"],
		["", "small", "big", GrammarValidator.NORMAL, false, "silence"],
	]
	for case in cases:
		var result := GrammarValidator.validate(str(case[0]), str(case[1]), str(case[2]), int(case[3]))
		_check(failures, bool(result["ok"]) == bool(case[4]),
			"grammar: %s - '%s' gave ok=%s reason=%s" % [str(case[5]), str(case[0]), result["ok"], result["reason"]])

	# Half-credit feedback is what the retry ladder shows the student.
	var partial := GrammarValidator.validate("it was small now it is red", "small", "big", GrammarValidator.NORMAL)
	_check(failures, bool(partial["said_before"]) and not bool(partial["said_after"]) and str(partial["reason"]) == "no_after",
		"grammar: partial credit not detected")


static func _check(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
