class_name DevHarness
extends RefCounted
## Command-line hooks for checking the build without clicking through it.
##
##   godot --path . -- --selftest          content, assembly and grammar checks, then quit
##   godot --path . -- --gaittest          walks every animal and measures foot slide
##   godot --path . -- --bones             every animal's skeleton, with the walk chain
##                                         each leg bone actually has beneath it
##   godot --path . -- --phase=lab         jump straight to a screen
##   godot --path . -- --shot=lab          jump there, save user://shot_lab.png, quit
##   godot --path . -- --shot=select       redesigned animal picker and thumbnail strip
##   godot --path . -- --shot=select-side  select a side card without recentering the deck
##   godot --path . -- --shot=zoo-name     open a resident's measured name card
##   godot --path . -- --shot=say          the recording screen with a card chosen
##   godot --path . -- --backtest          abandon a half-finished round, then restart it
##   godot --path . -- --splittest         the SAY_SPLIT present-tense pass, end to end
##   godot --path . -- --youngflowtest     SHORT + YOUNG through transformation/comparison
##   godot --path . -- --tallflowtest      tiger SHORT -> TALL machine-clearance regression
##   godot --path . -- --shot=present      the centred present-tense panel
##   godot --path . -- --shot=carousel     recording screen after one carousel step
##   godot --path . -- --shot=color-before sequential colour picker, Before step
##   godot --path . -- --shot=color-after  sequential colour picker, After step
##   godot --path . -- --shot=color-say    colour sentence ready to record
##   godot --path . -- --shot=young-finish finished SHORT + YOUNG creature with pacifier
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
		if text in ["--selftest", "--autoplay", "--backtest", "--splittest", "--youngflowtest",
				"--tallflowtest", "--bones", "--gaittest"] \
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
	elif args.has("--youngflowtest"):
		_youngflowtest(main)
	elif args.has("--tallflowtest"):
		_tallflowtest(main)
	elif args.has("--bones"):
		_bones(main)
	elif args.has("--gaittest"):
		_gaittest(main)
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

	# The default asks for the three present-tense sentences in a pass of their own once
	# the past tense is done, so a run through the real signal path has to answer those
	# too. Reading the mode rather than assuming it: this is the check that is supposed to
	# notice when the default changes.
	if Settings.needs_present_pass(Speech.uses_microphone()):
		await tree.create_timer(1.0).timeout
		if Game.phase != Game.Phase.ANIMAL_SELECTION:
			printerr("[autoplay] FAIL: no present-tense pass in split mode")
			tree.quit(1)
			return
		for entry in Game.current.entries:
			Speech.submit_typed(GrammarValidator.expected_present(str(entry["after"])))
			await tree.create_timer(2.4).timeout
		print("[autoplay] present-tense pass answered")

	# The transformation sequence plus the fade into the naming screen. It grows every time
	# a beat is added to it - three spoken sentences, each with a surge and now a pause to
	# let its trait land, then the peak and the reveal. Generous on purpose: this wait
	# failing means "the lab never finished", which is a slow and confusing thing to debug.
	await tree.create_timer(30.0).timeout

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
	var go := Router.current_scene.find_child("SelectAnimal", true, false) as Button
	if go == null:
		printerr("[backtest] FAIL: no SELECT button after backing out")
		tree.quit(1)
		return
	go.pressed.emit()
	# Longer than any confirm_selection_animation in animals.json (the longest is the
	# tiger at 1.35s) plus the recording screen build. _confirm() awaits that reaction
	# before entering, so a 1.0s wait here failed on every animal in the file.
	await tree.create_timer(2.6).timeout

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

	# Same longer sequence the autoplay wait accounts for: three spoken sentences with
	# their surges, then the peak and the reveal.
	await tree.create_timer(30.0).timeout
	var ok := Game.phase == Game.Phase.NAMING
	print("[splittest] ended in phase %s" % Game.Phase.keys()[Game.phase])
	print("[splittest] PASS" if ok else "[splittest] FAIL: expected NAMING")
	tree.quit(0 if ok else 1)


## Exercises the exact boundary that once detached YOUNG's pacifier: the chamber builds
## the finished rig, completes its reveal, and only then routes to the comparison screen,
## which constructs another finished rig from the same CreatureState.
static func _youngflowtest(main: Node) -> void:
	var tree := main.get_tree()
	var ids := Content.animal_ids()
	if ids.is_empty():
		printerr("[youngflowtest] FAIL: no animals")
		tree.quit(1)
		return
	# Tiger's broad curved muzzle exposed guard-rim clipping that a centre-point contact
	# check could not see, so exercise the real SHORT -> YOUNG chamber flow with it.
	_seed_young_short_creature(ids, "tiger")
	Game.set_phase(Game.Phase.ANIMAL_SELECTION)
	Game.set_phase(Game.Phase.CREATURE_LAB)
	# Wait on the state transition rather than a guessed cinematic length: captured speech
	# can legitimately make each of the three beats longer than the TTS fallback.
	for poll in 90:
		if Game.phase == Game.Phase.NAMING and Router.current_scene != null \
				and Router.current_scene.name == "NamingScreen":
			break
		await tree.create_timer(0.5).timeout
	if Game.phase != Game.Phase.NAMING or Router.current_scene == null \
			or Router.current_scene.name != "NamingScreen":
		printerr("[youngflowtest] FAIL: transformation ended in %s" % Game.Phase.keys()[Game.phase])
		tree.quit(1)
		return
	await RenderingServer.frame_post_draw
	var path := "user://shot_young_flow.png"
	main.get_viewport().get_texture().get_image().save_png(path)
	print("[youngflowtest] PASS -> %s" % ProjectSettings.globalize_path(path))
	tree.quit(0)


## Drives the reported tiger SHORT -> TALL case through the real cinematic and samples
## the prong-to-animal gap every frame. This catches collisions during leg extension, not
## merely an unsafe final resting position after the animation has already finished.
static func _tallflowtest(main: Node) -> void:
	var tree := main.get_tree()
	var ids := Content.animal_ids()
	if ids.is_empty():
		printerr("[tallflowtest] FAIL: no animals")
		tree.quit(1)
		return
	Game.begin_creature("tiger" if ids.has("tiger") else ids[0])
	Game.record_sentence("HEIGHT", "short", "tall")
	Game.record_sentence("AGE", "young", "old")
	Game.record_sentence(Content.COLOR_CATEGORY, "red", "blue")
	Game.current.generated_name = NameGenerator.candidates(Game.current)[0]
	Game.set_phase(Game.Phase.ANIMAL_SELECTION)
	Game.set_phase(Game.Phase.CREATURE_LAB)

	var collided := false
	var min_gap := INF
	for poll in 2700: ## Up to 45 seconds at 60fps, matching the other flow timeout.
		if Game.phase == Game.Phase.NAMING and Router.current_scene != null \
				and Router.current_scene.name == "NamingScreen":
			break
		var lab := Router.current_scene
		if lab != null:
			var array := lab.find_child("TransformArray", true, false) as TransformArray
			var stage := array.get_parent() as LabStage if array != null else null
			if stage != null and array.visible:
				var gap := array.position.y - TransformArray.DROP_BELOW - stage.creature_top()
				min_gap = minf(min_gap, gap)
				collided = collided or gap < -0.01
		await tree.process_frame

	var reached_naming := Game.phase == Game.Phase.NAMING and Router.current_scene != null \
		and Router.current_scene.name == "NamingScreen"
	if reached_naming and not collided and is_finite(min_gap):
		print("[tallflowtest] PASS: minimum machine gap %.3f" % min_gap)
		tree.quit(0)
	else:
		printerr("[tallflowtest] FAIL: reached_naming=%s collided=%s min_gap=%.3f" \
			% [reached_naming, collided, min_gap])
		tree.quit(1)


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
		"young-finish":
			_seed_young_short_creature(ids)
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


static func _seed_young_short_creature(ids: PackedStringArray, preferred := "dog") -> void:
	Game.begin_creature(preferred if ids.has(preferred) else ids[0])
	Game.record_sentence("LENGTH", "long", "short")
	Game.record_sentence("AGE", "old", "young")
	Game.record_sentence(Content.COLOR_CATEGORY, "red", "blue")
	Game.current.generated_name = NameGenerator.candidates(Game.current)[0]


static func _screenshot(main: Node, phase: String) -> void:
	# "say" is the recording screen with a card already chosen. Worth its own target
	# because Say It is hidden entirely until armed - it, the mic, and Cancel cannot be
	# seen from --shot=lab, which only ever shows the idle screen.
	if phase == "present":
		Settings.say_mode = Settings.SAY_SPLIT
	var routed_phase := "select" if phase == "select-side" \
		else ("zoo" if phase == "zoo-name" else phase)
	_goto("lab" if routed_phase in ["say", "present", "carousel", "color-before", "color-after", "color-say"] else routed_phase)
	await main.get_tree().create_timer(SHOT_DELAY).timeout
	if phase == "zoo-name":
		var zoo_scene := Router.current_scene
		var residents: Node3D = zoo_scene.get("_creatures") if zoo_scene != null else null
		if residents != null and residents.get_child_count() > 0:
			zoo_scene._show_info(residents.get_child(0))
			await main.get_tree().create_timer(0.5).timeout
	elif phase == "select-side":
		var selection_scene := Router.current_scene
		var cards: Array = selection_scene.get("_animal_cards") if selection_scene != null else []
		if cards.size() >= 4:
			var labels_before: Array[String] = []
			for card in cards:
				labels_before.append(str(card.text))
			(cards[3] as Button).pressed.emit()
			await main.get_tree().create_timer(0.6).timeout
			var labels_after: Array[String] = []
			for card in cards:
				labels_after.append(str(card.text))
			if labels_after != labels_before:
				printerr("[shot] FAIL: tapping an animal card recentered the carousel")
				main.get_tree().quit(1)
				return
	elif phase == "say":
		var word_lab := _find_word_lab(Router.current_scene)
		if word_lab != null:
			word_lab.pair_selected.emit("HARDNESS", "soft", "hard")
		await main.get_tree().create_timer(1.0).timeout
	elif phase == "present":
		var _reached: bool = await _drive_past_pass(main.get_tree(), "shot")
		await main.get_tree().create_timer(1.2).timeout
	elif phase == "carousel":
		var carousel := _find_word_lab(Router.current_scene)
		if carousel != null:
			carousel._step(1)
		await main.get_tree().create_timer(DescriptorCarousel.SLIDE_TIME + 0.1).timeout
	elif phase in ["color-before", "color-after", "color-say"]:
		var colour_carousel := _find_word_lab(Router.current_scene)
		if colour_carousel != null:
			for i in colour_carousel._slots.size():
				if colour_carousel._slot_category(colour_carousel._slots[i]) == Content.COLOR_CATEGORY:
					colour_carousel._index = i
					colour_carousel._refresh()
					colour_carousel._activate()
					break
			colour_carousel._step_colour(1)
			if phase in ["color-after", "color-say"]:
				await colour_carousel._confirm_colour()
			if phase == "color-after":
				var selection_scene := Router.current_scene
				if selection_scene != null and selection_scene.has_method("_commit"):
					selection_scene._commit(true)
					await main.get_tree().create_timer(1.3).timeout
				colour_carousel._step_colour(1)
		await main.get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var image := main.get_viewport().get_texture().get_image()
	var path := "user://shot_%s.png" % phase
	image.save_png(path)
	print("[shot] saved %s -> %s" % [path, ProjectSettings.globalize_path(path)])
	main.get_tree().quit()


## Prints each animal's skeleton so a gait can be written against the joints that exist
## rather than the ones a species ought to have. The walk poses one bone per leg, so the
## question this answers is what sits BELOW that bone: an upper leg alone can only swing
## like a rod, and no amount of curve-tuning substitutes for a missing carpus.
## Walks each animal forward and measures whether its planted feet stay planted.
##
## The eye cannot judge this from a screenshot and a moving picture is not available here,
## but the number is unambiguous: a foot in stance is on the ground, so its WORLD position
## must not change while the body travels over it. Anything else is the skating the walk is
## supposed to have stopped.
##
## Reported per animal: what fraction of the time each foot is stationary (should land near
## the gait's duty factor) and how fast the foot drifts while it is down, as a percentage of
## the body's own speed. Zero would be a perfect plant; the old sin-wave walk scored about
## 100%, because the foot swept continuously and never had a stance at all.
static func _gaittest(main: Node) -> void:
	var tree := main.get_tree()
	var failures: Array[String] = []
	for def in Content.animals:
		var rig := CreatureFactory.build_plain(def.id)
		var carrier := Node3D.new() ## Stands in for the zoo brain that normally moves a rig.
		main.add_child(carrier)
		carrier.add_child(rig)
		rig.moving = true
		var speed: float = def.walk_speed
		var contacts: Dictionary = rig.gait.contact_bones()
		print("[gaittest] %s speed %.2f %s" % [def.id, speed, rig.gait.describe()])
		var samples: Array[Dictionary] = []
		# Long enough to cover several strides whatever the species cadence.
		for frame in 700:
			await tree.process_frame
			carrier.position += Vector3(0.0, 0.0, -speed * SIM_STEP)
			var feet := {"__phase": rig.gait.phase()}
			for leg_id in contacts:
				feet[leg_id] = rig.skeleton.global_transform \
					* rig.skeleton.get_bone_global_pose(int(contacts[leg_id])).origin
			samples.append(feet)
		_report_slide(failures, def.id, samples, speed)
		_report_profile(def.id, samples, speed, rig.gait.leg_offsets())
		carrier.queue_free()
	if failures.is_empty():
		print("[gaittest] PASS")
	else:
		printerr("[gaittest] %d FAILURE(S):" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
	tree.quit(0 if failures.is_empty() else 1)


## Frame time assumed when converting a per-frame foot displacement into a speed. The
## harness runs unthrottled, so measuring real delta would compare against a number the
## simulation never saw.
const SIM_STEP := 1.0 / 60.0
## Below this fraction of body speed a foot counts as planted rather than swinging.
const PLANTED_FRACTION := 0.35


static func _report_slide(failures: Array[String], id: String,
		samples: Array[Dictionary], speed: float) -> void:
	if samples.size() < 3 or speed <= 0.0:
		return
	for leg_id in samples[0].keys():
		if str(leg_id).begins_with("__"): ## Bookkeeping, not a foot.
			continue
		var planted := 0
		var drift := 0.0
		var counted := 0
		# Skip the first frames: the cycle blends in from standing, so the earliest samples
		# describe an animal that is not walking yet.
		for i in range(400, samples.size()):
			if not samples[i].has(leg_id) or not samples[i - 1].has(leg_id):
				continue
			# Horizontal only. A foot pivoting on a straight leg necessarily rises a little
			# at both ends of its stance, and that is not sliding - sliding is ground the
			# foot covers while it is supposed to be standing on it.
			var a: Vector3 = samples[i][leg_id]
			var b: Vector3 = samples[i - 1][leg_id]
			var moved: float = Vector2(a.x - b.x, a.z - b.z).length()
			var foot_speed := moved / SIM_STEP
			counted += 1
			if foot_speed < speed * PLANTED_FRACTION:
				planted += 1
				drift += foot_speed / speed
		if counted == 0:
			continue
		var duty := float(planted) / float(counted)
		var slide := (drift / float(planted)) * 100.0 if planted > 0 else 100.0
		print("[gaittest] %-8s %-12s planted %3d%% of the time, drifting %4.1f%% of body speed"
			% [id, leg_id, roundi(duty * 100.0), slide])
		if duty < 0.30:
			failures.append("%s/%s: foot is almost never planted (%d%%)"
				% [id, leg_id, roundi(duty * 100.0)])
		if slide > 30.0:
			failures.append("%s/%s: planted foot slides at %d%% of body speed"
				% [id, leg_id, roundi(slide)])


## Foot speed against position in the stride, in tenths of a cycle. A correct walk shows a
## clear trough - the stance, where the foot is on the ground and barely moving - and a hump
## where it swings through. A flat line means there is no stance at all and the foot is being
## dragged the whole way round, which is what a sine-wave leg does.
static func _report_profile(id: String, samples: Array[Dictionary], speed: float,
		offsets: Dictionary) -> void:
	for leg_id in offsets:
		var buckets := []
		var counts := []
		for i in 10:
			buckets.append(0.0)
			counts.append(0)
		for i in range(400, samples.size()):
			if not samples[i].has(leg_id) or not samples[i - 1].has(leg_id):
				continue
			var a: Vector3 = samples[i][leg_id]
			var b: Vector3 = samples[i - 1][leg_id]
			var moved := Vector2(a.x - b.x, a.z - b.z).length() / SIM_STEP / speed
			var t: float = fposmod(float(samples[i]["__phase"]) + float(offsets[leg_id]), 1.0)
			var slot := clampi(int(t * 10.0), 0, 9)
			buckets[slot] += moved
			counts[slot] += 1
		var line := ""
		for i in 10:
			line += " %5.2f" % (buckets[i] / maxf(counts[i], 1))
		print("[gaittest] %-8s %-12s%s" % [id, leg_id, line])


## Every character the UI prints has to exist in the bundled font.
##
## This cannot be checked by looking at the game on this machine. Godot fills in glyphs its
## font lacks from an OS font, so on Windows the Japanese text and the tick marks render
## perfectly whether or not anything is bundled - and a browser has no OS fonts to borrow,
## so the web build drew blanks. The desktop is the misleading case, which is exactly why
## this is asserted against the font file rather than trusted to the eye.
##
## The sample is every non-ASCII character that appears inside a quoted string anywhere in
## the project, regenerated whenever this check is updated. Comments are excluded: a kanji
## in a comment is never drawn.
const UI_CHARACTERS := "×…✓、。「」あいうえおかがきぎくぐけげこさしじすずせぜそただちっつてでとどなにのはひびふぶへべぼまみめもやよらりるれろわをんァアィイウェエオカガキクグゲコゴサザジスセタダチッデトドニネハバビフプベペボマムメモャヤュユラリルレロンー一上下中了人今代伝体使保停備元先入全判利前力効化半単厳去古合同名向回在地場塔境声変夕夜大天太失妻存学安完定密少山岩嵐巨常度形影後怪扱承押指文新方明星春晶期木果根桜楽欄次止正残毛水氷河法流海準火灼炎焼熱牙珠現環生用由画番異疾目真短確示稲空立粉紅終組綿羽習老者聞自色花苔若英草葉蛇表見言設話認語説読識豆象送進過量鉄鋼長陽難雪雲霜霧青非面音順風鹿！（）－："


static func _font_checks(failures: Array[String]) -> void:
	var path := str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	_check(failures, not path.is_empty(),
		"no font is bundled, so the web build will draw blanks for anything outside ASCII")
	if path.is_empty():
		return
	var font: Font = load(path)
	_check(failures, font != null, "bundled font %s failed to load" % path)
	if font == null:
		return
	var missing := ""
	for i in UI_CHARACTERS.length():
		var ch := UI_CHARACTERS[i]
		if not font.has_char(ch.unicode_at(0)):
			missing += ch
	_check(failures, missing.is_empty(),
		"bundled font is missing %d glyph(s) the UI prints: %s" % [missing.length(), missing])


static func _bones(main: Node) -> void:
	for def in Content.animals:
		var rig := CreatureFactory.build_plain(def.id)
		var skeleton: Skeleton3D = rig.skeleton
		if skeleton == null:
			print("[bones] %s: NO SKELETON" % def.id)
			rig.free()
			continue
		print("[bones] === %s (%d bones) ===" % [def.id, skeleton.get_bone_count()])
		for leg in def.leg_bones:
			var idx := skeleton.find_bone(leg)
			if idx == -1:
				print("[bones]   %s -> MISSING FROM RIG" % leg)
				continue
			print("[bones]   %s%s" % [leg, _describe_chain(skeleton, idx, 1)])
		# The trunk from the root down. Printed as a hierarchy, not a list: which end of a
		# long spine chain is the neck and which is the tail is exactly what a gait needs
		# to know, and a flat list of names cannot say.
		for b in skeleton.get_bone_count():
			if skeleton.get_bone_parent(b) == -1:
				print("[bones]   ROOT %s%s" % [skeleton.get_bone_name(b),
					_describe_chain(skeleton, b, 1)])
		rig.free()
	main.get_tree().quit()


## One line per descendant, depth-first, with the rest-pose distance from its parent so a
## zero-length placeholder bone is obvious rather than looking like a usable joint.
static func _describe_chain(skeleton: Skeleton3D, idx: int, depth: int) -> String:
	var out := ""
	for child in skeleton.get_bone_children(idx):
		var length := skeleton.get_bone_rest(child).origin.length()
		out += "\n[bones]   %s%s (%.3f)" % ["  ".repeat(depth), skeleton.get_bone_name(child),
			length]
		out += _describe_chain(skeleton, child, depth + 1)
	return out


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
	Audio.play_ambience(true)
	_check(failures, Audio._ambience == null or not Audio._ambience.playing,
		"ambient laboratory hum still plays when requested")

	# A worst-case zoo solver probe: thirty residents begin at the exact same coordinate.
	# Repeated live passes must spread every circular footprint without leaving a single
	# intersecting pair. Keeping this parent outside the SceneTree avoids starting their
	# normal idle AI; it exercises the same separation method deterministically.
	var crowd := Node3D.new()
	var crowd_state := CreatureState.create("dog")
	var crowd_brains: Array[CreatureBrain] = []
	for i in 30:
		var crowd_brain := CreatureBrain.create(crowd_state, Vector3.ZERO)
		crowd.add_child(crowd_brain)
		crowd_brains.append(crowd_brain)
	var crowd_penetration := CreatureBrain.resolve_group_overlaps(crowd, 96)
	_check(failures, crowd_penetration < 0.002,
		"zoo crowd solver retained %.3f maximum penetration" % crowd_penetration)
	for i in crowd_brains.size():
		for j in range(i + 1, crowd_brains.size()):
			var required := crowd_brains[i].spacing_radius() \
				+ crowd_brains[j].spacing_radius() + CreatureBrain.NEIGHBOUR_GAP
			var horizontal := Vector2(
				crowd_brains[i].position.x - crowd_brains[j].position.x,
				crowd_brains[i].position.z - crowd_brains[j].position.z).length()
			_check(failures, horizontal >= required - 0.002,
				"zoo crowd solver left residents %d and %d overlapping by %.3f" \
				% [i, j, required - horizontal])
	crowd.free()

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
		_check(failures, rig.horizontal_footprint_radius() >= def.stand_height * 0.42,
			"%s: measured zoo footprint is smaller than its body" % def.id)
		_check(failures, not def.body_bones.is_empty(), "%s has no LONG/SHORT body bones" % def.id)
		_check(failures, not def.selection_reaction_animation.is_empty(),
			"%s has no browse selection reaction" % def.id)
		_check(failures, not def.confirm_selection_animation.is_empty(),
			"%s has no confirmed selection reaction" % def.id)
		_check(failures, Audio.has_sound(def.selection_reaction_sound),
			"%s browse sound '%s' is missing" % [def.id, def.selection_reaction_sound])
		_check(failures, Audio.has_sound(def.confirm_selection_sound),
			"%s confirm sound '%s' is missing" % [def.id, def.confirm_selection_sound])
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
			for profile in [def.selection_reaction_animation, def.confirm_selection_animation]:
				for track in profile.get("bones", []):
					all_bones.append(str(track.get("bone", "")))
			for bone in all_bones:
				_check(failures, rig.skeleton.find_bone(bone) != -1,
					"%s: bone '%s' not in model" % [def.id, bone])

		# Every profile must visibly move and return exactly to its starting transform. This
		# catches a zeroed data row and the more damaging carousel drift caused by an
		# interrupted reaction capturing the previous flourish as its new baseline.
		var reaction_start := rig.transform
		var reaction_duration := rig.play_selection_reaction(def.selection_reaction_animation)
		rig.advance_selection_reaction(reaction_duration * 0.5)
		_check(failures, not rig.transform.is_equal_approx(reaction_start),
			"%s browse reaction has no visible root motion" % def.id)
		rig.advance_selection_reaction(reaction_duration)
		_check(failures, rig.transform.is_equal_approx(reaction_start),
			"%s browse reaction did not restore its root pose" % def.id)

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

		# Persistent HOT fire must share the creature's movement frame. Local particle
		# coordinates keep flames already in flight attached during FAST's dashes too.
		TraitVisuals.apply_all(rig, {"TEMPERATURE": "hot"})
		_check(failures, rig.thermal_follows_body,
			"%s: HOT fire was not marked to follow the creature" % def.id)
		var hot_particles := 0
		for hot_child in rig.thermal_fx_root.get_children():
			if hot_child is GPUParticles3D:
				hot_particles += 1
				_check(failures, (hot_child as GPUParticles3D).local_coords,
					"%s: emitted HOT flames remain in world space" % def.id)
		_check(failures, hot_particles >= 4,
			"%s: HOT did not build its persistent flame layers" % def.id)
		rig.body.position = Vector3(0.37, 0.08, -0.21)
		rig.body.rotation.y = 0.24
		rig._sync_thermal_fx_to_body()
		_check(failures, rig.thermal_fx_root.position.is_equal_approx(rig.body.position),
			"%s: HOT fire root did not follow creature movement" % def.id)
		_check(failures,
			rig.thermal_fx_root.transform.basis.is_equal_approx(rig.body.transform.basis.orthonormalized()),
			"%s: HOT fire root did not follow creature turning" % def.id)
		rig.clear_thermal_fx()
		rig.thermal_applied = NAN
		rig.reset_modifiers()
		rig.body.position = Vector3.ZERO
		rig.body.rotation = Vector3.ZERO

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
		var expected_dark_grey := def.old_value("grey", "dark", 0.0)
		_check(failures, is_equal_approx(
			float(rig.material.get_shader_parameter("grey_dark_amount")), expected_dark_grey),
			"%s: OLD dark-marking greying does not match its species configuration" % def.id)
		if def.id == "tiger":
			_check(failures, expected_dark_grey > 0.99,
				"tiger: OLD does not turn the stripes grey")
		var spectacles := rig.find_accessory("OldSpectacles")
		_check(failures, spectacles != null, "%s: OLD spectacles were not built" % def.id)
		if spectacles != null:
			var spectacles_in_body := rig.accessory_transform_in_body(spectacles)
			var surface_front := float(spectacles.get_meta("surface_front"))
			var clearance := float(spectacles.get_meta("clearance"))
			var lens_size := float(spectacles.get_meta("lens_size"))
			var lens_spacing := float(spectacles.get_meta("lens_spacing"))
			var anchors := rig.face_anchors()
			_check(failures, spectacles_in_body.origin.z <= surface_front - clearance + 0.0001,
				"%s: OLD spectacles intersect the face" % def.id)
			_check(failures, surface_front - spectacles_in_body.origin.z < float(anchors["depth"]) * 0.09,
				"%s: OLD spectacles float too far ahead of the face" % def.id)
			_check(failures, lens_size <= float(anchors["span"]) * 0.421
				and lens_size <= float(anchors["half_w"]) * 0.921,
				"%s: OLD lenses exceed the usable head" % def.id)
			_check(failures, lens_spacing + lens_size * 0.5 <= float(anchors["half_w"]) * 1.09,
				"%s: OLD frames extend too far beyond the head" % def.id)
			if def.id == "deer":
				var deer_eye: Vector3 = anchors["eye"]
				_check(failures,
					spectacles_in_body.origin.y <= deer_eye.y - float(anchors["span"]) * 0.30,
					"deer: OLD glasses returned above the painted eye line")
				_check(failures, lens_size <= float(anchors["depth"]) * 0.225,
					"deer: OLD lenses became too large for its narrow face")
		var beard := rig.find_accessory("OldBeard")
		_check(failures, beard != null, "%s: OLD beard was not built" % def.id)
		if beard != null:
			_check(failures, beard.get_node_or_null("FrontSilhouette") is MeshInstance3D,
				"%s: OLD beard has no front silhouette" % def.id)
			_check(failures, beard.get_node_or_null("SideSilhouette") is MeshInstance3D,
				"%s: OLD beard has no profile silhouette" % def.id)
		if spectacles != null and beard != null:
			var old_head_bone := def.socket_bone("head_top")
			var glasses_relative: Transform3D = rig._bone_transform_in_body(old_head_bone) \
				.affine_inverse() * rig.accessory_transform_in_body(spectacles)
			var beard_relative: Transform3D = rig._bone_transform_in_body(old_head_bone) \
				.affine_inverse() * rig.accessory_transform_in_body(beard)
			var old_length_pair := Content.pair_for_category("LENGTH")
			if old_length_pair != null:
				rig.deformer.set_state(old_length_pair.value_for("short"), 1.0)
				rig.sync_bone_accessories()
				var short_head := rig._bone_transform_in_body(old_head_bone)
				_check(failures,
					(short_head.affine_inverse() * rig.accessory_transform_in_body(spectacles)) \
						.is_equal_approx(glasses_relative),
					"%s: OLD glasses did not follow the head through SHORT" % def.id)
				_check(failures,
					(short_head.affine_inverse() * rig.accessory_transform_in_body(beard)) \
						.is_equal_approx(beard_relative),
					"%s: OLD beard did not follow the head through SHORT" % def.id)
		rig.reset_modifiers()
		_check(failures,
			float(rig.material.get_shader_parameter("grey_dark_amount")) < 0.001,
			"%s: OLD dark-marking greying survived a reset" % def.id)

		# YOUNG's rigid pacifier starts at the scaled mouth surface. Its two meshes are
		# entirely on local +Z, so the teat touches the animal without floating and neither
		# the teat nor guard can penetrate the head.
		var young_scale := def.young_head_scale()
		rig.scale_bone(def.socket_bone("head_top"), Vector3.ONE * young_scale)
		YoungKit.apply(rig, young_scale)
		var pacifier := rig.find_accessory("Pacifier")
		_check(failures, pacifier != null, "%s: YOUNG pacifier was not built" % def.id)
		if pacifier != null:
			var anchors := rig.face_anchors()
			var plane_origin: Vector3 = pacifier.get_meta("surface_plane_origin", Vector3.ZERO)
			var plane_outward: Vector3 = pacifier.get_meta("surface_outward", Vector3.FORWARD)
			var guard_radius := float(pacifier.get_meta("guard_radius", 0.0))
			_check(failures, guard_radius > 0.0 and rig.head_surface_protrusion(
				plane_origin, plane_outward, guard_radius, guard_radius) <= 0.0001,
				"%s: YOUNG pacifier guard footprint intersects the face" % def.id)
			var contact: Vector3 = anchors["face_tip"] \
				if def.young_value("pacifier", "tip", 0.0) > 0.5 else anchors["mouth_surface"]
			var pacifier_down := def.young_value("pacifier", "down", 0.0)
			if not is_zero_approx(pacifier_down) \
					and def.young_value("pacifier", "tip", 0.0) <= 0.5:
				contact.y -= pacifier_down * float(anchors["span"])
				contact.z = rig.head_front_in_patch(0.0, contact.y,
					float(anchors["half_w"]) * 0.72,
					float(anchors["span"]) * 0.075, contact.z)
			contact.z += def.young_value("pacifier", "forward", 0.0) \
				* float(anchors["depth"]) * -1.0
			var test_head_pivot: Vector3 = anchors["head_pivot"]
			var raw_outward := Vector3(0.0, contact.y - test_head_pivot.y,
				contact.z - test_head_pivot.z).normalized()
			if raw_outward.length_squared() < 0.5 or raw_outward.z > -0.05:
				raw_outward = Vector3.FORWARD
			var expected_angle := atan2(-raw_outward.y, raw_outward.z) \
				+ deg_to_rad(def.young_value("pacifier", "tilt", 0.0))
			var expected_outward := Basis(Vector3.RIGHT, expected_angle) * Vector3.BACK
			var expected_plane := rig.fit_head_accessory_plane(contact, expected_outward,
				guard_radius, guard_radius,
				def.young_value("pacifier", "size", 0.52) * float(anchors["depth"]) * 0.015)
			_check(failures, plane_origin.distance_to(expected_plane) < 0.0001,
				"%s: YOUNG pacifier plane was not fitted to its whole guard" % def.id)
			var young_head_bone := def.socket_bone("head_top")
			var expected_contact: Vector3 = rig._bone_transform_in_body(young_head_bone) \
				* (rig._bone_rest_transform_in_body(young_head_bone).affine_inverse() * expected_plane)
			_check(failures,
				rig.accessory_transform_in_body(pacifier).origin.distance_to(expected_contact) < 0.001,
				"%s: YOUNG pacifier detached from its scaled mouth" % def.id)
			var guard := pacifier.get_node_or_null("Guard")
			var teat := pacifier.get_node_or_null("Teat")
			_check(failures, guard is MeshInstance3D and guard.position.z > 0.0,
				"%s: YOUNG pacifier guard crosses the mouth plane" % def.id)
			_check(failures, teat is MeshInstance3D and teat.position.z > guard.position.z,
				"%s: YOUNG pacifier ball does not face away from the animal" % def.id)
			# BODY_LENGTH translates the head through the spine. The pacifier must retain the
			# same head-relative offset after SHORT instead of staying at its neutral position.
			var head_bone := def.socket_bone("head_top")
			var relative_to_head: Transform3D = rig._bone_transform_in_body(head_bone) \
				.affine_inverse() * rig.accessory_transform_in_body(pacifier)
			var length_pair := Content.pair_for_category("LENGTH")
			if length_pair != null:
				rig.deformer.set_state(length_pair.value_for("short"), 1.0)
				rig.sync_bone_accessories()
				var short_relative: Transform3D = rig._bone_transform_in_body(head_bone) \
					.affine_inverse() * rig.accessory_transform_in_body(pacifier)
				_check(failures, short_relative.is_equal_approx(relative_to_head),
					"%s: YOUNG pacifier did not follow the head through SHORT" % def.id)
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
		var height_pair := Content.pair_for_category("HEIGHT")
		var tall_value := height_pair.value_for("tall") if height_pair != null else 2.20
		rig.deformer.set_state(1.0, tall_value)
		for ground_step in 4:
			rig.solve_idle_grounding_immediately()
		var contacts := rig.foot_contact_positions()
		for contact_idx in contacts.size():
			_check(failures, absf(contacts[contact_idx].y - CreatureRig.GROUND_CLEARANCE) < 0.005,
				"%s: foot '%s' did not ground (y=%.3f, correction=%.3f)" % [def.id,
					def.legs[contact_idx].get("id", ""), contacts[contact_idx].y,
					rig.deformer.ground_extension(contact_idx)])
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

	# Final-trait assembly, exercised across every animal. Fantasy attachments must stay
	# absent even when the selected After words still have legacy attachment definitions.
	for def in Content.animals:
		var state := CreatureState.create(def.id)
		state.add_entry("SIZE", "small", "big")
		state.add_entry("TEMPERATURE", "hot", "cold")
		state.add_entry(Content.COLOR_CATEGORY, "red", "blue")
		var creature := CreatureFactory.build_fantasy(state)
		_check(failures, creature != null, "%s: fantasy build failed" % def.id)
		if creature != null:
			_check(failures, creature.find_child("great_horns", true, false) == null,
				"%s: BIG still appended post-transformation horns" % def.id)
			_check(failures, creature.find_child("frost_crest", true, false) == null,
				"%s: COLD still appended a post-transformation crest" % def.id)
		var names := NameGenerator.candidates(state)
		_check(failures, names.size() > 0 and not names[0].is_empty(), "%s: no name generated" % def.id)
		_check(failures, names.size() > 0 and names[0].contains("の") \
			and not names[0].contains(" "), "%s: generated name is not Japanese-localized" % def.id)
		_check(failures, state.fingerprint() == CreatureState.from_dict(state.to_dict()).fingerprint(),
			"%s: fingerprint not stable through save/load" % def.id)
		if creature != null:
			creature.free()

		# Exercise the actual finished-creature factory with the combination that exposed the
		# bug. The pacifier's complete transform—not just its position—must remain fixed in
		# head space after SHORT has moved the skeleton.
		var young_state := CreatureState.create(def.id)
		young_state.add_entry("LENGTH", "long", "short")
		young_state.add_entry("AGE", "old", "young")
		young_state.add_entry(Content.COLOR_CATEGORY, "red", "blue")
		var young_creature := CreatureFactory.build_fantasy(young_state)
		_check(failures, young_creature != null,
			"%s: SHORT + YOUNG finished creature failed to build" % def.id)
		if young_creature != null:
			var final_pacifier := young_creature.find_accessory("Pacifier")
			_check(failures, final_pacifier != null,
				"%s: SHORT + YOUNG finished creature lost its pacifier" % def.id)
			if final_pacifier != null:
				var final_bone := def.socket_bone("head_top")
				var mount := final_pacifier.get_parent()
				var before_tree_relative: Transform3D = young_creature \
					._bone_transform_in_body(final_bone).affine_inverse() \
					* young_creature.accessory_transform_in_body(final_pacifier)
				_check(failures, mount is BoneAttachment3D,
					"%s: finished pacifier does not use a native bone mount" % def.id)
				if mount is BoneAttachment3D:
					var bone_mount := mount as BoneAttachment3D
					_check(failures, bone_mount.get_parent() == young_creature.skeleton,
						"%s: pacifier bone mount is detached from the skeleton" % def.id)
					_check(failures,
						bone_mount.bone_idx == young_creature.skeleton.find_bone(final_bone),
						"%s: pacifier bone mount targets the wrong bone" % def.id)
				var final_anchors := young_creature.face_anchors()
				var neutral_contact: Vector3 = final_anchors["face_tip"] \
					if def.young_value("pacifier", "tip", 0.0) > 0.5 \
					else final_anchors["mouth_surface"]
				var final_down := def.young_value("pacifier", "down", 0.0)
				if not is_zero_approx(final_down) \
						and def.young_value("pacifier", "tip", 0.0) <= 0.5:
					neutral_contact.y -= final_down * float(final_anchors["span"])
					neutral_contact.z = young_creature.head_front_in_patch(0.0,
						neutral_contact.y, float(final_anchors["half_w"]) * 0.72,
						float(final_anchors["span"]) * 0.075, neutral_contact.z)
				neutral_contact.z += def.young_value("pacifier", "forward", 0.0) \
					* float(final_anchors["depth"]) * -1.0
				var final_head_pivot: Vector3 = final_anchors["head_pivot"]
				var final_raw_outward := Vector3(0.0,
					neutral_contact.y - final_head_pivot.y,
					neutral_contact.z - final_head_pivot.z).normalized()
				if final_raw_outward.length_squared() < 0.5 or final_raw_outward.z > -0.05:
					final_raw_outward = Vector3.FORWARD
				var final_angle := atan2(-final_raw_outward.y, final_raw_outward.z) \
					+ deg_to_rad(def.young_value("pacifier", "tilt", 0.0))
				var final_outward := Basis(Vector3.RIGHT, final_angle) * Vector3.BACK
				var final_radius := def.young_value("pacifier", "size", 0.52) \
					* float(final_anchors["depth"]) * 0.52
				var fitted_contact := young_creature.fit_head_accessory_plane(neutral_contact,
					final_outward, final_radius, final_radius,
					def.young_value("pacifier", "size", 0.52) \
						* float(final_anchors["depth"]) * 0.015)
				var expected_final_contact: Vector3 = young_creature \
					._bone_transform_in_body(final_bone) \
					* (young_creature._bone_rest_transform_in_body(final_bone).affine_inverse() \
						* fitted_contact)
				_check(failures, young_creature.accessory_transform_in_body(final_pacifier) \
					.origin.distance_to(expected_final_contact) < 0.001,
					"%s: finished SHORT + YOUNG pacifier missed the transformed mouth" % def.id)
				# The comparison and zoo screens add a fully transformed rig to the tree only
				# after its accessories were fitted. The first native bone update must not move
				# the pacifier away from that fitted head-relative transform.
				main.add_child(young_creature)
				await main.get_tree().process_frame
				await main.get_tree().process_frame
				var live_relative: Transform3D = young_creature \
					._bone_transform_in_body(final_bone).affine_inverse() \
					* young_creature.accessory_transform_in_body(final_pacifier)
				_check(failures, live_relative.is_equal_approx(before_tree_relative),
					"%s: comparison-screen pacifier moved away from the face on entry" % def.id)
				main.remove_child(young_creature)
			young_creature.free()

	for pair in Content.pairs:
		for word in pair.words():
			var rig := CreatureFactory.build_plain(Content.animals[0].id)
			TraitVisuals.apply_all(rig, {pair.category: word})
			_check(failures, rig != null, "%s/%s failed to apply" % [pair.category, word])
			rig.free()

	_font_checks(failures)
	_speed_checks(failures)
	await _carousel_checks(failures, main)
	_voice_checks(failures)
	_compile_checks(failures)
	_present_pass_checks(failures)
	_leg_growth_checks(failures)
	_grammar_checks(failures)

	if failures.is_empty():
		print("[selftest] PASS")
	else:
		printerr("[selftest] %d FAILURE(S):" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
	main.get_tree().quit(0 if failures.is_empty() else 1)


static func _leg_growth_checks(failures: Array[String]) -> void:
	var height_pair := Content.pair_for_category("HEIGHT")
	var tall_value := height_pair.value_for("tall") if height_pair != null else 2.20
	for def in Content.animals:
		var rig := CreatureFactory.build_plain(def.id)
		rig.deformer.set_state(1.0, tall_value)
		var lowest := INF
		var highest := -INF
		for i in def.legs.size():
			var response := rig.deformer.leg_vertical_response(i)
			if response <= 0.0001:
				continue
			var factor: float = rig.deformer.leg_lengths[i]
			var growth := response * (factor - 1.0)
			lowest = minf(lowest, growth)
			highest = maxf(highest, growth)
		if lowest < INF and lowest > 0.0001:
			var mismatch := (highest / lowest - 1.0) * 100.0
			_check(failures, mismatch < 4.0,
				"%s: TALL grew its legs by different amounts (%.1f%% apart)" % [def.id, mismatch])
		rig.free()


## The student's recorded voice is optional by design: it records in the browser, so on
## desktop, in the editor, and on any browser without MediaRecorder there is simply no
## clip. What must hold is that a missing clip reports itself as missing - a recorder that
## quietly claims a length would make the sequence wait out that length in silence instead
## of having the lab speak - and that one child's recording cannot outlive their round.
## Loads every script and scene in the project. Nothing else here does: selftest builds
## rigs directly and never opens a screen, so a script that does not compile stays green
## through the whole suite and only shows up as a grey rectangle in a browser. That has
## happened twice - a redesign left a call behind, and a tap handler used `:=` on an
## untyped `pressed` - and both times every check below passed while the screen was dead.
##
## Loading is enough. A GDScript with a parse error fails to load, and a scene whose script
## will not compile fails with it, which is exactly the breakage being caught. Nothing is
## instantiated: these screens expect game state, and a check that needs the game set up
## correctly before it can run is a check that ends up switched off.
static func _compile_checks(failures: Array[String]) -> void:
	var pending: Array[String] = ["res://scripts", "res://scenes", "res://ui"]
	var loaded := 0
	while not pending.is_empty():
		var here: String = pending.pop_back()
		var dir := DirAccess.open(here)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := here.path_join(entry)
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
				loaded += 1
				# A broken GDScript still loads - it comes back as a Resource that cannot be
				# instantiated - so the object existing proves nothing on its own.
				var res := ResourceLoader.load(full)
				var ok := res != null
				if ok and res is GDScript:
					ok = (res as GDScript).can_instantiate()
				_check(failures, ok,
					"%s does not compile - every scene using it is a grey screen" % full)
			entry = dir.get_next()
		dir.list_dir_end()
	# A walk that finds nothing would pass silently for ever, which is worse than no check.
	_check(failures, loaded > 20, "compile check found almost nothing to load")


static func _voice_checks(failures: Array[String]) -> void:
	Voice.clear()
	_check(failures, is_zero_approx(Voice.clip_length(0)) and not Voice.has_clip(0),
		"voice: a cleared recorder still reports a clip")
	_check(failures, is_zero_approx(Voice.play(0)),
		"voice: playing a missing clip did not report itself as missing")
	_check(failures, Voice.play(-1) <= 0.0 and Voice.clip_length(99) <= 0.0,
		"voice: an out-of-range slot was not handled")
	# SAY_SPLIT records "It was small." and "Now it is big." as two takes minutes apart, so
	# the present halves are filed above PRESENT_SLOT and played after their own past half.
	Voice.keep_present_for(0)
	_check(failures, not Voice.has_clip(Voice.PRESENT_SLOT),
		"voice: a present half was invented with nothing recorded")
	_check(failures, is_zero_approx(Voice.play_sentence(0)),
		"voice: a sentence with neither half recorded still claimed a length")

	# Storing a slot with nothing captured must not invent one, or the transformation
	# would wait on a clip that plays nothing.
	Voice.keep_for(0)
	_check(failures, not Voice.has_clip(0),
		"voice: keeping a slot with no recording created a clip")

	# Nothing in here may touch AudioServer. Adding an input bus is what silenced the whole
	# web build once, and the fix was to move capture into the browser entirely.
	_check(failures, AudioServer.get_bus_index("VoiceCapture") == -1
		and AudioServer.get_bus_index("VoiceLab") == -1,
		"voice: the recorder is adding audio buses again")
	_check(failures, not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)),
		"voice: engine audio input is switched on again")
	Voice.clear()


## Past-only remains a useful microphone option, but typing must still practise the
## present half. Full-sentence mode already contains it and must never duplicate it.
static func _present_pass_checks(failures: Array[String]) -> void:
	var original := Settings.say_mode
	Settings.say_mode = Settings.SAY_PAST
	_check(failures, Settings.needs_present_pass(false),
		"typing: Past-only skipped the present-tense pass")
	_check(failures, not Settings.needs_present_pass(true),
		"speech: Past-only unexpectedly added a present-tense pass")
	Settings.say_mode = Settings.SAY_SPLIT
	_check(failures, Settings.needs_present_pass(false) and Settings.needs_present_pass(true),
		"split: present-tense pass depends on the input backend")
	Settings.say_mode = Settings.SAY_FULL
	_check(failures, not Settings.needs_present_pass(false),
		"typing: full sentence duplicated the present-tense pass")
	Settings.say_mode = original


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

	# The clipped host never moves. Five full-size cards are visible at rest: the middle
	# three are unobscured, and only the outermost 10% of the far pair is edge-faded.
	var host_position := car._main_host.position
	car._step(1)
	_check(failures, car._main_host.position.is_equal_approx(host_position),
		"carousel: stepping moved the clipped layout cell")
	_check(failures, car._left_arrow.visible and car._right_arrow.visible,
		"carousel: stepping hid a chevron")
	_check(failures, car._main_host.clip_contents and car._colour_host.clip_contents,
		"carousel: a peek viewport does not clip offscreen cards")
	var word_clear_ratio := 1.0 - DescriptorCarousel.WORD_EDGE_FADE_WIDTH \
		/ DescriptorCarousel.WORD_CARD_SIZE.x
	var colour_clear_ratio := 1.0 - DescriptorCarousel.COLOUR_EDGE_FADE_WIDTH \
		/ DescriptorCarousel.COLOUR_CARD_SIZE.x
	_check(failures, is_equal_approx(word_clear_ratio, 0.90)
		and is_equal_approx(colour_clear_ratio, 0.90),
		"carousel: outer cards do not retain the requested 90%% clear area")
	_check(failures, is_equal_approx(DescriptorCarousel.WORD_VIEWPORT_WIDTH,
		DescriptorCarousel.WORD_CARD_SIZE.x * 5.0 + DescriptorCarousel.WORD_GAP * 4.0)
		and is_equal_approx(DescriptorCarousel.COLOUR_VIEWPORT_WIDTH,
		DescriptorCarousel.COLOUR_CARD_SIZE.x * 5.0
			+ DescriptorCarousel.COLOUR_CARD_GAP * 4.0),
		"carousel: viewport does not expose five complete card positions")
	_check(failures, car._word_track_cards.size() == 9
		and car._colour_track_cards.size() == 9,
		"carousel: sliding buffers cannot cover a two-card snap")
	_check(failures, car._category_left_fade != null and car._category_right_fade != null
		and car._colour_left_fade != null and car._colour_right_fade != null,
		"carousel: two-sided edge fades are missing")
	_check(failures, absf(car._main_card.position.x - car._category_base_x) \
		<= DescriptorCarousel.WORD_STRIDE + 0.01,
		"carousel: slide escaped the clipped word track")
	if car._slide != null and car._slide.is_valid():
		car._slide.kill()
	car._main_card.position.x = car._category_base_x
	car._index = 0
	car._step(-1) ## Wrap backward onto the one-card COLOURS slot.
	_check(failures, car._main_host.position.is_equal_approx(host_position),
		"carousel: backward wrap moved the clipped layout cell")
	_check(failures, car._left_arrow.visible and car._right_arrow.visible,
		"carousel: backward wrap hid a chevron")
	_check(failures, car._word_cards.size() == 1 and car._word_cards[0].visible,
		"carousel: colour slot did not settle into one centred card")
	if car._slide != null and car._slide.is_valid():
		car._slide.kill()
	car._main_card.position.x = car._category_base_x

	# A leftward drag advances one card, and release keeps the partial travel as the start
	# of the snap instead of teleporting the refreshed deck.
	var drag_start_index := car._index
	car._begin_drag(100.0, -1)
	car._update_drag(45.0)
	car._finish_drag(Vector2(45.0, 0.0))
	_check(failures, car._index == wrapi(drag_start_index + 1, 0, car._slots.size()),
		"carousel: left drag did not advance to the next centred card")
	_check(failures, not car._drag_candidate and not car._dragging,
		"carousel: drag state remained armed after snapping")
	if car._slide != null and car._slide.is_valid():
		car._slide.kill()
	car._main_card.position.x = car._category_base_x
	var right_drag_start := car._index
	car._begin_drag(45.0, -1)
	car._update_drag(100.0)
	car._finish_drag(Vector2(100.0, 0.0))
	_check(failures, car._index == wrapi(right_drag_start - 1, 0, car._slots.size()),
		"carousel: right drag did not return to the previous centred card")
	if car._slide != null and car._slide.is_valid():
		car._slide.kill()
	car._main_card.position.x = car._category_base_x

	# Colours are sequential: BEFORE browsing is visual only, and the first explicit
	# colour press emits the preview before entering AFTER. AFTER always skips the
	# confirmed colour.
	var colours := Content.enabled_colors()
	var previews: Array[String] = []
	var past_choices: Array[String] = []
	var selections: Array[PackedStringArray] = []
	var cancellations := [0]
	var colour_steps: Array[bool] = []
	car.before_colour_previewed.connect(func(word: String) -> void: previews.append(word))
	car.before_colour_selected.connect(func(word: String) -> void: past_choices.append(word))
	car.pair_selected.connect(func(category: String, before: String, after: String) -> void:
		if category == Content.COLOR_CATEGORY:
			selections.append(PackedStringArray([before, after])))
	car.colour_selection_cancelled.connect(func() -> void: cancellations[0] += 1)
	car.colour_step_changed.connect(func(choosing_now: bool) -> void:
		colour_steps.append(choosing_now))
	car._colour_step = DescriptorCarousel.ColourStep.BEFORE
	car._was_index = 0
	car._now_index = 1
	car._show_view(DescriptorCarousel.View.COLOUR)
	car._sync_colour()
	_check(failures, not car._colour_far_prev.disabled and not car._colour_prev.disabled
		and not car._colour_swatch.disabled and not car._colour_next.disabled
		and not car._colour_far_next.disabled,
		"carousel: not every visible colour card is selectable")
	# Uniformity, both decks: a card must not look different for sitting in the middle. The
	# centre swatch was twice the area of its neighbours and the centre word card was
	# enlarged and ringed, which both read as "this one is the selection" on a row where
	# every visible card is pressable.
	for deck in [[car._colour_far_prev, car._colour_prev, car._colour_swatch,
			car._colour_next, car._colour_far_next],
			[car._far_prev_card, car._prev_card, car._word_cards[0],
			car._next_card, car._far_next_card]]:
		var reference: Vector2 = (deck[2] as Control).custom_minimum_size
		var uniform_size := true
		for card in deck:
			uniform_size = uniform_size and (card as Control).custom_minimum_size == reference
		_check(failures, uniform_size, "carousel: cards in a deck are not the same size")
		for card in deck:
			var button := card as Button
			_check(failures, button != null,
				"carousel: a visible card is not a Button, so it cannot answer a press")
			if button == null:
				continue
			_check(failures, button.modulate.a >= 0.999,
				"carousel: a visible card is faded")
			_check(failures, button.get_theme_font_size("font_size")
				== (deck[2] as Button).get_theme_font_size("font_size"),
				"carousel: a visible card uses a different text size")
	_check(failures, car._colour_feedback.text.is_empty() and not car._colour_feedback.visible,
		"carousel: obsolete colour instruction is still visible")
	var colour_drag_start := car._was_index
	car._begin_drag(100.0, -1)
	car._update_drag(45.0)
	car._finish_drag(Vector2(45.0, 0.0))
	_check(failures, car._was_index == car._next_colour_index(colour_drag_start, 1, false),
		"carousel: left drag did not advance to the next centred colour")
	if car._slide != null and car._slide.is_valid():
		car._slide.kill()
	car._colour_track.position.x = car._colour_base_x
	car._step_colour(1)
	_check(failures, previews.is_empty(),
		"carousel: BEFORE browsing recoloured the live animal preview")
	var confirmed_before := car._was_index
	await car._confirm_colour()
	_check(failures, car._colour_step == DescriptorCarousel.ColourStep.BEFORE
		and car._colour_picker.visible and car._was_index == confirmed_before
		and previews.size() == 1
		and past_choices.size() == 1
		and previews[-1] == (colours[confirmed_before] as ColorDefinition).word
		and past_choices[-1] == previews[-1],
		"carousel: confirming BEFORE did not hand the colour to the past-tense panel")
	car.continue_colour_after_past()
	_check(failures, car._colour_step == DescriptorCarousel.ColourStep.AFTER
		and not colour_steps.is_empty() and colour_steps[-1],
		"carousel: completing the past clause did not reveal the Now colours")
	var previews_after_confirm := previews.size()
	for i in colours.size() * 2:
		car._step_colour(1)
		_check(failures, car._was_index != car._now_index,
			"carousel: AFTER landed on the confirmed BEFORE colour")
	for i in colours.size() * 2:
		car._step_colour(-1)
		_check(failures, car._was_index != car._now_index,
			"carousel: reverse AFTER landed on the confirmed BEFORE colour")
	_check(failures, previews.size() == previews_after_confirm,
		"carousel: AFTER browsing recoloured the live animal preview")
	car._cancel_colour()
	_check(failures, car._colour_step == DescriptorCarousel.ColourStep.BEFORE
		and car._was_index == confirmed_before and not colour_steps[-1],
		"carousel: cancelling AFTER did not return to the confirmed BEFORE choice")
	await car._confirm_colour()
	car.continue_colour_after_past()
	await car._confirm_colour()
	_check(failures, selections.size() == 1 and selections[0][0] != selections[0][1],
		"carousel: final colour confirmation did not emit a different pair")
	_check(failures, not colour_steps.is_empty() and not colour_steps[-1],
		"carousel: finishing the Now colour did not restore the default heading state")
	car._colour_step = DescriptorCarousel.ColourStep.BEFORE
	car._show_view(DescriptorCarousel.View.COLOUR)
	car._cancel_colour()
	_check(failures, cancellations[0] == 2 and car._view == DescriptorCarousel.View.CATEGORY,
		"carousel: cancelling BEFORE did not restore the main word carousel")

	var first := Content.enabled_pairs()[0]
	car.set_used(PackedStringArray([first.category]))
	_check(failures, car._blocked(first.category), "carousel: a used category stayed selectable")
	car.set_used(PackedStringArray())
	car.set_locked(true)
	_check(failures, car._blocked(first.category), "carousel: locking left cards selectable")
	car.set_locked(false)

	# Fixed bottom console: neither sequential view may outgrow its stable screen region.
	for view in [DescriptorCarousel.View.CATEGORY, DescriptorCarousel.View.COLOUR]:
		car._show_view(view)
		var needed := car.get_combined_minimum_size()
		_check(failures, needed.x <= 760.0 and needed.y <= 320.0,
			"carousel: view %d needs %s, more than the 760x320 console" % [view, needed])
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
