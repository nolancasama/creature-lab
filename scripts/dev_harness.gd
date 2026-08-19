class_name DevHarness
extends RefCounted
## Command-line hooks for checking the build without clicking through it.
##
##   godot --path . -- --selftest          content, assembly and grammar checks, then quit
##   godot --path . -- --phase=lab         jump straight to a screen
##   godot --path . -- --shot=lab          jump there, save user://shot_lab.png, quit
##   godot --path . -- --shot=say          the recording screen with a card chosen
##   godot --path . -- --backtest          abandon a half-finished round, then restart it
##   godot --path . -- --splittest         the SAY_SPLIT present-tense pass, end to end
##   godot --path . -- --shot=present      the centred present-tense panel
##   godot --path . -- --look=young        one creature wearing one trait word, then quit
##   godot --path . -- --look=young:horse  the same, on a named animal
##   godot --path . -- --look=young+big    several traits stacked on one creature

const SHOT_DELAY := 1.6

const SPLIT_PICKS := [
	["LENGTH", "long", "short"],
	["HARDNESS", "hard", "soft"],
	[Content.COLOR_CATEGORY, "red", "blue"],
]


## True when a harness run is about to drive the game itself. Boot code checks this before
## moving the FSM: the harness sets its own phases, and set_phase() into a phase the game
## is already in returns early without ever reloading the scene.
static func is_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text in ["--selftest", "--autoplay", "--backtest", "--splittest"] \
				or text.begins_with("--shot=") or text.begins_with("--phase=") or text.begins_with("--look="):
			return true
	return false


static func run_if_requested(main: Node) -> void:
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var phase := ""
	var look := ""
	var selftest := false
	for arg in args:
		var text := str(arg)
		if text == "--selftest":
			selftest = true
		elif text.begins_with("--shot="):
			shot = text.substr(7)
		elif text.begins_with("--phase="):
			phase = text.substr(8)
		elif text.begins_with("--look="):
			look = text.substr(7)

	if selftest:
		_selftest(main)
		return
	if args.has("--autoplay"):
		_autoplay(main)
	elif args.has("--backtest"):
		_backtest(main)
	elif args.has("--splittest"):
		_splittest(main)
	elif not look.is_empty():
		_look(main, look)
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
		var word_lab: DescriptorCarousel = _find_word_lab(Router.current_scene)
		if word_lab == null:
			printerr("[autoplay] FAIL: no Word Lab in %s" % Router.current_scene)
			tree.quit(1)
			return
		word_lab.pair_selected.emit(str(pick[0]), str(pick[1]), str(pick[2]))
		await tree.create_timer(0.7).timeout
		Speech.submit_typed(_expected(str(pick[1]), str(pick[2])))
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
	Speech.submit_typed(_expected("long", "short"))
	await tree.create_timer(2.6).timeout
	print("[backtest] %d slot(s) recorded, now backing out" % Game.current.slots_filled())

	# By name, not by caption: the carousel's own left arrow is also "<".
	var back := Router.current_scene.find_child("BackToPicking", true, false) as Button
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
	var go := _find_button(Router.current_scene, "Start")
	if go == null:
		printerr("[backtest] FAIL: no Start button after backing out")
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
	Speech.submit_typed(_expected("long", "short"))
	await tree.create_timer(2.6).timeout

	var slots := Game.current.slots_filled() if Game.current != null else 0
	if slots == 1:
		print("[backtest] PASS")
		tree.quit(0)
	else:
		printerr("[backtest] FAIL: card did not register after backing out (%d slots)" % slots)
		tree.quit(1)


## What a correct answer sounds like under the current teacher settings - past-only is
## the default, so submitting the full sentence would be testing a mode nobody is in.
static func _expected(before: String, after: String) -> String:
	if Settings.past_only():
		return GrammarValidator.expected_past(before)
	return GrammarValidator.expected_sentence(before, after)


## Records the three past sentences, which is the way in to everything after them.
## False if the round did not complete, so callers fail loudly rather than asserting
## against a screen that never appeared.
static func _drive_past_pass(tree: SceneTree, tag: String) -> bool:
	for pick in SPLIT_PICKS:
		var word_lab := _find_word_lab(Router.current_scene)
		if word_lab == null:
			printerr("[%s] FAIL: no Word Lab in %s" % [tag, Router.current_scene])
			return false
		word_lab.pair_selected.emit(str(pick[0]), str(pick[1]), str(pick[2]))
		await tree.create_timer(0.7).timeout
		Speech.submit_typed(_expected(str(pick[1]), str(pick[2])))
		await tree.create_timer(2.6).timeout
	return true


## Settings.SAY_SPLIT: three past sentences, then three more in the present before
## anything transforms. The assertion that matters is the middle one - after the third
## past sentence the game must still be on the selection screen, because in every other
## mode that is exactly when it leaves for the chamber.
static func _splittest(main: Node) -> void:
	var tree := main.get_tree()
	Settings.say_mode = Settings.SAY_SPLIT
	_goto("lab")
	await tree.create_timer(1.4).timeout

	var recorded: bool = await _drive_past_pass(tree, "splittest")
	if not recorded:
		tree.quit(1)
		return
	print("[splittest] %d past sentences recorded" % Game.current.entries.size())

	await tree.create_timer(1.0).timeout
	if Game.phase != Game.Phase.ANIMAL_SELECTION:
		printerr("[splittest] FAIL: left for %s instead of asking for the present tense"
			% Game.Phase.keys()[Game.phase])
		tree.quit(1)
		return
	print("[splittest] held for the present-tense pass")

	for pick in SPLIT_PICKS:
		Speech.submit_typed(GrammarValidator.expected_present(str(pick[2])))
		await tree.create_timer(2.4).timeout

	await tree.create_timer(12.0).timeout
	var ok := Game.phase == Game.Phase.NAMING
	print("[splittest] ended in phase %s" % Game.Phase.keys()[Game.phase])
	print("[splittest] PASS" if ok else "[splittest] FAIL: expected NAMING")
	tree.quit(0 if ok else 1)


## Renders one creature wearing one trait, so a look can actually be seen rather than
## inferred from the code that builds it. `spec` is a trait word, optionally "word:animal"
## - "young", "young:horse", "cold:penguin". The word is committed as the creature's BEFORE
## trait, which is exactly the state the platform shows during recording. A final
## ":front" rotates it as though the player dragged it head-on, useful for checking
## face accessories whose spacing is hard to judge in the normal profile view.
static func _look(main: Node, spec: String) -> void:
	var tree := main.get_tree()
	var parts := spec.split(":")
	var words := str(parts[0]).split("+") ## "young+big" stacks two traits on one creature.
	var ids := Content.animal_ids()
	if ids.is_empty():
		printerr("[look] FAIL: no animals")
		tree.quit(1)
		return
	var animal_id: String = str(parts[1]) if parts.size() > 1 else ("dog" if ids.has("dog") else str(ids[0]))

	Game.begin_creature(animal_id)
	for word in words:
		var found: TraitDefinition = null
		for pair in Content.enabled_pairs():
			if pair.word_a == str(word) or pair.word_b == str(word):
				found = pair
				break
		if found == null:
			printerr("[look] FAIL: no trait pair contains '%s'" % word)
			tree.quit(1)
			return
		Game.record_sentence(found.category, str(word), found.opposite_of(str(word)))
	Game.set_phase(Game.Phase.ANIMAL_SELECTION)
	await tree.create_timer(SHOT_DELAY).timeout
	var view := str(parts[2]) if parts.size() > 2 else "profile"
	if view == "front" and Router.current_scene != null:
		var preview_root: Node3D = Router.current_scene.get("_preview_root")
		if preview_root != null:
			preview_root.rotation.y = PI
	await RenderingServer.frame_post_draw
	var suffix := "_%s" % view if view != "profile" else ""
	var path := "user://look_%s_%s%s.png" % [str(parts[0]).replace("+", "_"), animal_id, suffix]
	main.get_viewport().get_texture().get_image().save_png(path)
	print("[look] %s on %s -> %s" % [str(parts[0]), animal_id, ProjectSettings.globalize_path(path)])
	tree.quit(0)


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


## The carousel, not the Word List sheet behind its button - that sheet is a WordLab too,
## and is deliberately inert, so searching for the older type would find the wrong one.
static func _find_word_lab(node: Node) -> DescriptorCarousel:
	if node == null:
		return null
	if node is DescriptorCarousel:
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
	# "say" is the recording screen with a card already chosen. Worth its own target
	# because Say It is hidden entirely until armed - it, the mic, and Cancel cannot be
	# seen from --shot=lab, which only ever shows the idle screen.
	if phase == "present":
		Settings.say_mode = Settings.SAY_SPLIT
	_goto("lab" if phase in ["say", "present"] else phase)
	await main.get_tree().create_timer(SHOT_DELAY).timeout
	if phase == "say":
		var word_lab := _find_word_lab(Router.current_scene)
		if word_lab != null:
			word_lab.pair_selected.emit("HARDNESS", "soft", "hard")
		await main.get_tree().create_timer(1.0).timeout
	elif phase == "present":
		var _reached: bool = await _drive_past_pass(main.get_tree(), "shot")
		await main.get_tree().create_timer(1.2).timeout
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
	_check(failures, Content.pair_for_category("STRENGTH") != null,
		"hidden STRONG/WEAK compatibility pair was deleted")
	_check(failures, not Content.enabled_pairs().any(
		func(pair: TraitDefinition) -> bool: return pair.category == "STRENGTH"),
		"STRONG/WEAK still appears in selectable adjective pairs")
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
		for side in ["left", "right"]:
			var forelimb := def.forelimb_config(side)
			_check(failures, not str(forelimb.bone).is_empty(),
				"%s has no %s forelimb attachment" % [def.id, side])
			_check(failures, not str(forelimb.original_root).is_empty(),
				"%s has no %s original forelimb root" % [def.id, side])
			_check(failures, (forelimb.chain as PackedStringArray).size() >= 2,
				"%s has no usable %s Strong limb chain" % [def.id, side])
		_check(failures, def.legs.size() >= 2, "%s has fewer than 2 legs configured" % def.id)
		for leg in def.legs:
			_check(failures, def.foot_contacts.has(str(leg.get("id", ""))),
				"%s: explicit sole contact missing for '%s'" % [def.id, leg.get("id", "")])

		if rig.skeleton != null:
			var all_bones: Array[String] = []
			all_bones.append_array(Array(def.body_bones))
			for group in MuscleDeformer.GROUPS:
				all_bones.append_array(Array(def.bulk_bones_for(group)))
			for side in ["left", "right"]:
				var forelimb := def.forelimb_config(side)
				all_bones.append(str(forelimb.bone))
				all_bones.append(str(forelimb.original_root))
				all_bones.append_array(Array(forelimb.chain as PackedStringArray))
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

		# COLD breath must begin just beyond this species' measured snout and follow that
		# snout's own pitch, rather than using one fixed direction for every animal.
		var cold_probe := ColdEffect.create(rig)
		var cold_anchors := rig.face_anchors()
		var expected_breath_direction: Vector3 = Vector3(0.0,
			(cold_anchors["snout_tip"] as Vector3).y - (cold_anchors["head_pivot"] as Vector3).y,
			(cold_anchors["snout_tip"] as Vector3).z - (cold_anchors["head_pivot"] as Vector3).z).normalized()
		_check(failures, cold_probe.breath_direction().dot(expected_breath_direction) > 0.999,
			"%s: COLD breath does not follow the snout angle" % def.id)
		var expected_breath_origin: Vector3 = (cold_anchors["snout_tip"] as Vector3) \
			+ expected_breath_direction * def.stand_height * 0.012
		_check(failures, cold_probe.breath_origin().distance_to(expected_breath_origin) < 0.001,
			"%s: COLD breath is detached from the snout" % def.id)
		cold_probe.free()

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

		# STRONG swells the intact live forelimbs; every bone, paw and wing stays authored.
		# WEAK alone replaces exactly the two configured front legs/wings.
		rig.deformer.reset()
		var neutral_positions: Array[Vector3] = []
		for bone_idx in rig.skeleton.get_bone_count():
			neutral_positions.append(rig.skeleton.get_bone_pose_position(bone_idx))
		var forelimb_roots := rig.muscle.limb_morph.original_root_bones()
		rig.muscle.set_state(1.35)
		for bone_idx in rig.skeleton.get_bone_count():
			var bone_name := rig.skeleton.get_bone_name(bone_idx)
			_check(failures, rig.skeleton.get_bone_pose_scale(bone_idx).is_equal_approx(Vector3.ONE),
				"%s: STRONG altered existing limb/body bone '%s'" % [def.id, bone_name])
			_check(failures, rig.skeleton.get_bone_pose_position(bone_idx).is_equal_approx(neutral_positions[bone_idx]),
				"%s: STRONG moved existing joint '%s'" % [def.id, bone_name])
		_check(failures, rig.muscle.morph_amount > 0.99,
			"%s: STRONG forelimb morph did not activate" % def.id)
		var morph := rig.muscle.limb_morph
		_check(failures, morph != null and morph.mode == ForelimbMorph.Mode.STRONG,
			"%s: STRONG did not reach the strong forelimb mode" % def.id)
		if morph != null:
			# STRONG must grow the animal's own limb, never add geometry of its own.
			_check(failures, morph.strong_swell("left") > 0.9 and morph.strong_swell("right") > 0.9,
				"%s: STRONG did not swell both forelimbs" % def.id)
			var weak_arm_mesh := func(m: MeshInstance3D) -> bool:
				return morph.left_weak_arm.is_ancestor_of(m) or morph.right_weak_arm.is_ancestor_of(m)
			_check(failures,
				morph.find_children("*", "MeshInstance3D", true, false).all(weak_arm_mesh),
				"%s: STRONG added geometry instead of growing the animal's own limb" % def.id)
			_check(failures, not morph.left_weak_arm.visible and not morph.right_weak_arm.visible,
				"%s: WEAK arms leaked into STRONG" % def.id)
			morph.set_side_enabled("left", false)
			_check(failures, is_zero_approx(morph.strong_swell("left"))
				and morph.strong_swell("right") > 0.9,
				"%s: forelimb muscles cannot be enabled independently" % def.id)
			var left_root := rig.skeleton.find_bone(forelimb_roots[0])
			_check(failures, rig.skeleton.get_bone_pose_scale(left_root).is_equal_approx(Vector3.ONE),
				"%s: STRONG did not preserve its original limb" % def.id)
			morph.set_side_enabled("left", true)
		rig.muscle.set_state(0.60)
		for bone_idx in rig.skeleton.get_bone_count():
			var bone_name := rig.skeleton.get_bone_name(bone_idx)
			if forelimb_roots.has(bone_name):
				_check(failures, rig.skeleton.get_bone_pose_scale(bone_idx).x < 0.03,
					"%s: WEAK did not replace original forelimb '%s'" % [def.id, bone_name])
			else:
				_check(failures, rig.skeleton.get_bone_pose_scale(bone_idx).is_equal_approx(Vector3.ONE),
					"%s: WEAK altered non-forelimb bone '%s'" % [def.id, bone_name])
			_check(failures, rig.skeleton.get_bone_pose_position(bone_idx).is_equal_approx(neutral_positions[bone_idx]),
				"%s: WEAK moved joint '%s'" % [def.id, rig.skeleton.get_bone_name(bone_idx)])
		_check(failures, is_zero_approx(rig.muscle.lift),
			"%s: WEAK changed the creature root height" % def.id)
		_check(failures, morph.mode == ForelimbMorph.Mode.WEAK and morph.visible,
			"%s: WEAK forelimb replacements are not visible" % def.id)
		_check(failures, morph.left_weak_arm.get_node_or_null("TinyBiceps") is MeshInstance3D
			and morph.right_weak_arm.get_node_or_null("LimpHand") != null,
			"%s: WEAK arms lack skinny muscles or limp hands" % def.id)
		_check(failures, is_zero_approx(morph.strong_swell("left"))
			and is_zero_approx(morph.strong_swell("right")),
			"%s: STRONG's swollen forelimbs leaked into WEAK" % def.id)
		var region_amounts: PackedFloat32Array = rig.material.get_shader_parameter("weak_region_amount")
		var chest_deformed := false
		for amount in region_amounts:
			chest_deformed = chest_deformed or amount > 0.001
		_check(failures, not chest_deformed,
			"%s: WEAK retained old body-region shrinking" % def.id)
		_check(failures, float(rig.material.get_shader_parameter("weak_rib_amount")) < 0.001,
			"%s: WEAK retained old chest/rib deformation" % def.id)
		rig.muscle.set_state(1.35)
		rig.muscle.set_state(0.60)
		_check(failures, morph.mode == ForelimbMorph.Mode.WEAK
			and is_zero_approx(morph.strong_swell("left")) and morph.left_weak_arm.visible,
			"%s: STRONG to WEAK retained the wrong arm form" % def.id)
		rig.muscle.reset()
		_check(failures, not morph.visible and morph.mode == ForelimbMorph.Mode.NEUTRAL,
			"%s: forelimb morph did not return to rest" % def.id)
		for root_name in forelimb_roots:
			var root_idx := rig.skeleton.find_bone(root_name)
			_check(failures, rig.skeleton.get_bone_pose_scale(root_idx).is_equal_approx(Vector3.ONE),
				"%s: neutral did not restore original forelimb '%s'" % [def.id, root_name])
		_check(failures, float(rig.material.get_shader_parameter("weak_rib_amount")) < 0.001,
			"%s: neutral retained old WEAK surface deformation" % def.id)

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

		# OLD's supplied concave beard silhouette must exist on every species and remain
		# readable from both the default profile and a user-dragged front view. Its glasses
		# must sit just beyond the measured eye/bridge surface: never inside the head, and
		# never a muzzle-length out in space on horses or birds.
		rig.reset_modifiers()
		OldKit.apply(rig)
		var spectacles := rig.accessory_root.get_node_or_null("OldSpectacles")
		_check(failures, spectacles != null, "%s: OLD spectacles were not built" % def.id)
		if spectacles != null:
			var surface_front := float(spectacles.get_meta("surface_front"))
			var clearance := float(spectacles.get_meta("clearance"))
			var lens_size := float(spectacles.get_meta("lens_size"))
			var lens_spacing := float(spectacles.get_meta("lens_spacing"))
			var anchors := rig.face_anchors()
			_check(failures, spectacles.position.z <= surface_front - clearance + 0.0001,
				"%s: OLD spectacles intersect the face" % def.id)
			_check(failures, surface_front - spectacles.position.z < float(anchors["depth"]) * 0.09,
				"%s: OLD spectacles float too far ahead of the face" % def.id)
			_check(failures, lens_size <= float(anchors["span"]) * 0.421
				and lens_size <= float(anchors["half_w"]) * 0.921,
				"%s: OLD lenses exceed the usable head" % def.id)
			_check(failures, lens_spacing + lens_size * 0.5 <= float(anchors["half_w"]) * 1.09,
				"%s: OLD frames extend too far beyond the head" % def.id)
		var beard := rig.accessory_root.get_node_or_null("OldBeard")
		_check(failures, beard != null, "%s: OLD beard was not built" % def.id)
		if beard != null:
			_check(failures, beard.get_node_or_null("FrontSilhouette") is MeshInstance3D,
				"%s: OLD beard has no front silhouette" % def.id)
			_check(failures, beard.get_node_or_null("SideSilhouette") is MeshInstance3D,
				"%s: OLD beard has no profile silhouette" % def.id)
		rig.reset_modifiers()

		# YOUNG's rigid pacifier starts at the scaled mouth surface. Its two meshes are
		# entirely on local +Z, so the teat touches the animal without floating and neither
		# the teat nor guard can penetrate the head.
		var young_scale := def.young_head_scale()
		rig.scale_bone(def.socket_bone("head_top"), Vector3.ONE * young_scale)
		YoungKit.apply(rig, young_scale)
		var pacifier := rig.accessory_root.get_node_or_null("Pacifier")
		_check(failures, pacifier != null, "%s: YOUNG pacifier was not built" % def.id)
		if pacifier != null:
			var anchors := rig.face_anchors()
			var contact: Vector3 = anchors["face_tip"] \
				if def.young_value("pacifier", "tip", 0.0) > 0.5 else anchors["mouth_surface"]
			var pacifier_down := def.young_value("pacifier", "down", 0.0)
			if not is_zero_approx(pacifier_down) \
					and def.young_value("pacifier", "tip", 0.0) <= 0.5:
				contact.y -= pacifier_down * float(anchors["span"])
				contact.z = rig.head_front_in_patch(0.0, contact.y,
					float(anchors["half_w"]) * 0.72,
					float(anchors["span"]) * 0.075, contact.z)
			var expected_contact: Vector3 = anchors["head_pivot"] \
				+ (contact - anchors["head_pivot"]) * young_scale
			expected_contact.z += def.young_value("pacifier", "forward", 0.0) \
				* float(anchors["depth"]) * young_scale * -1.0
			_check(failures, pacifier.position.distance_to(expected_contact) < 0.001,
				"%s: YOUNG pacifier detached from its scaled mouth" % def.id)
			var guard := pacifier.get_node_or_null("Guard")
			var teat := pacifier.get_node_or_null("Teat")
			_check(failures, guard is MeshInstance3D and guard.position.z > 0.0,
				"%s: YOUNG pacifier guard crosses the mouth plane" % def.id)
			_check(failures, teat is MeshInstance3D and teat.position.z > guard.position.z,
				"%s: YOUNG pacifier ball does not face away from the animal" % def.id)
		rig.reset_modifiers()

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

	# Exercise both real timed transitions. STRONG must swell around the original downward
	# limbs without moving a joint; WEAK may replace those same two configured limbs.
	var animated_strong := CreatureFactory.build_plain(Content.animals[0].id)
	main.add_child(animated_strong)
	await main.get_tree().process_frame
	var neutral_body_scale: Vector3 = animated_strong.body.scale
	var neutral_front_positions := {}
	for side in ["left", "right"]:
		for bone_name in animated_strong.definition.forelimb_config(side).chain:
			var bone_idx := animated_strong.skeleton.find_bone(bone_name)
			neutral_front_positions[bone_name] = animated_strong.skeleton.get_bone_pose_position(bone_idx)
	animated_strong.muscle.animate_to(1.35)
	await main.get_tree().create_timer(0.08).timeout
	_check(failures, not animated_strong.muscle.limb_morph.visible,
		"STRONG muscle volume appeared before its glow began")
	_check(failures, animated_strong.body.scale.is_equal_approx(neutral_body_scale),
		"STRONG power-up scaled the animal during its charge")
	await main.get_tree().create_timer(0.34).timeout
	_check(failures, animated_strong.muscle.limb_morph.visible
		and animated_strong.muscle.morph_amount > 0.5,
		"STRONG timed growth did not add muscle to both forelimbs")
	_check(failures, animated_strong.body.scale.is_equal_approx(neutral_body_scale),
		"STRONG muscle growth scaled the animal")
	for bone_name in neutral_front_positions:
		var bone_idx := animated_strong.skeleton.find_bone(bone_name)
		_check(failures, animated_strong.skeleton.get_bone_pose_position(bone_idx)
			.is_equal_approx(neutral_front_positions[bone_name]),
			"STRONG moved existing forelimb joint '%s'" % bone_name)
	await main.get_tree().create_timer(0.55).timeout
	_check(failures, absf(animated_strong.muscle.morph_amount - 1.0) < 0.02
		and animated_strong.muscle.limb_morph.flex < 0.01
		and absf(animated_strong.muscle.yaw) < 0.001,
		"STRONG did not settle naturally without a flex pose")
	animated_strong.muscle.animate_to(1.0)
	await main.get_tree().create_timer(0.55).timeout
	_check(failures, not animated_strong.muscle.limb_morph.visible,
		"undoing STRONG did not restore the original forelimbs")

	animated_strong.muscle.animate_to(0.60)
	await main.get_tree().create_timer(0.12).timeout
	_check(failures, not animated_strong.muscle.limb_morph.visible,
		"WEAK forelimbs changed before their morph began")
	await main.get_tree().create_timer(0.40).timeout
	_check(failures, animated_strong.muscle.limb_morph.visible
		and animated_strong.muscle.limb_morph.mode == ForelimbMorph.Mode.WEAK
		and animated_strong.muscle.morph_amount > 0.7,
		"WEAK timed morph did not reveal both skinny forelimbs")
	var saw_failed_flex := false
	for sample in 12:
		await main.get_tree().create_timer(0.06).timeout
		saw_failed_flex = saw_failed_flex or animated_strong.muscle.limb_morph.flex > 0.25
	_check(failures, saw_failed_flex, "WEAK did not attempt its failed flex")
	await main.get_tree().create_timer(0.20).timeout
	_check(failures, animated_strong.muscle.limb_morph.flex < 0.05,
		"WEAK failed flex did not droop back down")
	_check(failures, animated_strong.body.scale.is_equal_approx(neutral_body_scale),
		"WEAK morph scaled the animal")
	animated_strong.muscle.animate_to(1.0)
	await main.get_tree().create_timer(0.50).timeout
	_check(failures, not animated_strong.muscle.limb_morph.visible,
		"undoing WEAK did not restore the original forelimbs")
	main.remove_child(animated_strong)
	animated_strong.free()

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

	_speed_checks(failures)
	_carousel_checks(failures, main)
	_grammar_checks(failures)

	if failures.is_empty():
		print("[selftest] PASS")
	else:
		printerr("[selftest] %d FAILURE(S):" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
	main.get_tree().quit(0 if failures.is_empty() else 1)


## The carousel replaced a grid that could not promise its own size. These assert the two
## things that would silently break a lesson: a sentence that says nothing ("It was red.
## Now it is red."), and content that outgrows the fixed panel - the failure that put the
## Say It panel's Cancel button below the bottom of the screen while reporting itself
## visible the whole time.
static func _carousel_checks(failures: Array[String], main: Node) -> void:
	var car := DescriptorCarousel.new()
	main.add_child(car)

	_check(failures, car._slots.size() >= 2, "carousel: not enough cards to scroll")
	_check(failures, car._slot_category(car._slots[car._slots.size() - 1]) == Content.COLOR_CATEGORY,
		"carousel: colours are not the last card")

	# Every wheel position, in both directions, must leave the two colours different.
	var colours := Content.enabled_colors()
	for i in colours.size() * 2:
		car._step_colour(false, 1)
		_check(failures, car._was_index != car._now_index,
			"carousel: colour wheels landed on the same colour stepping forward")
	for i in colours.size() * 2:
		car._step_colour(true, -1)
		_check(failures, car._was_index != car._now_index,
			"carousel: colour wheels landed on the same colour stepping back")

	var first := Content.enabled_pairs()[0]
	car.set_used(PackedStringArray([first.category]))
	_check(failures, car._blocked(first.category), "carousel: a used category stayed selectable")
	car.set_used(PackedStringArray())
	car.set_locked(true)
	_check(failures, car._blocked(first.category), "carousel: locking left cards selectable")
	car.set_locked(false)

	# Fixed panel: no view may need more room than the rect it is mounted in.
	for view in [DescriptorCarousel.View.CATEGORY, DescriptorCarousel.View.COLOUR]:
		car._show_view(view)
		var needed := car.get_combined_minimum_size()
		_check(failures, needed.x <= 648.0 and needed.y <= 620.0,
			"carousel: view %d needs %s, more than the panel's 648x620" % [view, needed])
	car.free()


## FAST and SLOW are behaviour, so what is worth asserting is that the behaviour is armed
## and that it stays in its own lane: SPEED must never touch what the animal IS, or the
## intentionally funny combinations (old + fast, strong + slow) stop working.
static func _speed_checks(failures: Array[String]) -> void:
	for def in Content.animals:
		var rig := CreatureFactory.build_plain(def.id)
		var neutral_scale := rig.body.scale

		TraitVisuals.apply_all(rig, {"SPEED": "fast"})
		_check(failures, rig.pace.pace == PaceDeformer.Pace.FAST,
			"%s: fast did not put the animal in the fast state" % def.id)
		_check(failures, rig.pace.playback < 1.6,
			"%s: fast fell back to a doubled playback speed" % def.id)
		_check(failures, rig.body.scale.is_equal_approx(neutral_scale),
			"%s: fast resized the animal" % def.id)

		TraitVisuals.apply_all(rig, {"SPEED": "slow"})
		_check(failures, rig.pace.pace == PaceDeformer.Pace.SLOW,
			"%s: slow did not put the animal in the slow state" % def.id)
		_check(failures, rig.pace.playback >= 0.30 and rig.pace.playback <= 0.60,
			"%s: slow playback outside the readable band (%.2f)" % [def.id, rig.pace.playback])
		_check(failures, rig.body.scale.is_equal_approx(neutral_scale),
			"%s: slow resized the animal" % def.id)

		# Switching away must put the animal back where it stood, not leave it parked
		# wherever its last dash ended.
		TraitVisuals.apply_all(rig, {})
		_check(failures, rig.pace.pace == PaceDeformer.Pace.NEUTRAL
			and rig.pace.offset.is_zero_approx() and is_zero_approx(rig.pace.yaw),
			"%s: clearing SPEED left the animal displaced" % def.id)

		# Stacking: the other adjective still lands, and SPEED still arms itself.
		TraitVisuals.apply_all(rig, {"SPEED": "fast", "SIZE": "big"})
		_check(failures, rig.pace.pace == PaceDeformer.Pace.FAST,
			"%s: big + fast lost the fast behaviour" % def.id)
		_check(failures, rig.body.scale.length() > neutral_scale.length(),
			"%s: big + fast lost the size change" % def.id)
		rig.free()


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

	# Past-only is the shipped default, so it needs its own row of cases: the same
	# transcripts must pass that fail when the whole sentence is required.
	var past_cases := [
		["It was small.", "small", "big", GrammarValidator.NORMAL, true, "past clause alone"],
		["it was small", "small", "big", GrammarValidator.NORMAL, true, "no punctuation"],
		["um it was small okay", "small", "big", GrammarValidator.NORMAL, true, "edge filler"],
		["it was small now it is big", "small", "big", GrammarValidator.NORMAL, true, "running on is not punished"],
		["small", "small", "big", GrammarValidator.LENIENT, true, "lenient keyword"],
		["small", "small", "big", GrammarValidator.NORMAL, false, "normal still needs the frame"],
		["it was big", "small", "big", GrammarValidator.NORMAL, false, "wrong half of the pair"],
		["it was small", "small", "big", GrammarValidator.EXACT, true, "exact wants just the clause"],
		["", "small", "big", GrammarValidator.NORMAL, false, "silence"],
	]
	for case in past_cases:
		var result := GrammarValidator.validate(str(case[0]), str(case[1]), str(case[2]), int(case[3]), true)
		_check(failures, bool(result["ok"]) == bool(case[4]),
			"grammar past-only: %s - '%s' gave ok=%s reason=%s" % [str(case[5]), str(case[0]), result["ok"], result["reason"]])

	# The missing second clause must never be reported as a failure in past-only.
	var past_partial := GrammarValidator.validate("it was small", "small", "big", GrammarValidator.NORMAL, true)
	_check(failures, str(past_partial["reason"]) == "ok",
		"grammar past-only: complete answer reported as %s" % past_partial["reason"])

	# Half-credit feedback is what the retry ladder shows the student.
	var partial := GrammarValidator.validate("it was small now it is red", "small", "big", GrammarValidator.NORMAL)
	_check(failures, bool(partial["said_before"]) and not bool(partial["said_after"]) and str(partial["reason"]) == "no_after",
		"grammar: partial credit not detected")


static func _check(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
