class_name DevHarness
extends RefCounted
## Command-line hooks for checking the build without clicking through it.
##
##   godot --path . -- --selftest          content, assembly and grammar checks, then quit
##   godot --path . -- --phase=lab         jump straight to a screen
##   godot --path . -- --shot=lab          jump there, save user://shot_lab.png, quit

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
		["SIZE", "small", "big"],
		["TEMPERATURE", "hot", "cold"],
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
		await tree.create_timer(1.8).timeout
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
	Game.record_sentence("SIZE", "small", "big")
	Game.record_sentence("TEMPERATURE", "hot", "cold")
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
		_check(failures, not def.feature_bones.is_empty(), "%s has no LENGTH feature bone" % def.id)

		if rig.skeleton != null:
			var all_bones: Array[String] = []
			all_bones.append_array(Array(def.feature_bones))
			all_bones.append_array(Array(def.bulk_bones))
			all_bones.append_array(Array(def.leg_bones))
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
