extends Control
## Title screen. Also the only place the game states, in plain language, what the
## student is going to do - which is what the grammar target actually is.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())
	Audio.play_ambience(true)
	_build()


func _build() -> void:
	var centre := UiKit.vbox(14)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(centre)

	centre.add_child(UiKit.title("CREATURE LAB", UiKit.H1, UiKit.ACCENT))
	centre.add_child(UiKit.title("It was... Now it is...", UiKit.H2, UiKit.GOLD))
	centre.add_child(UiKit.spacer(6))
	centre.add_child(UiKit.title(
		"Choose an animal. Say three sentences. Watch it change.", UiKit.BODY, UiKit.MUTED))
	centre.add_child(UiKit.spacer(18))

	var buttons := UiKit.vbox(10)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.custom_minimum_size = Vector2(320, 0)
	centre.add_child(buttons)

	buttons.add_child(_menu_button("Make a Creature", func() -> void:
		Game.set_phase(Game.Phase.ANIMAL_SELECTION), true))

	if not Game.zoo.is_empty():
		buttons.add_child(_menu_button("My Zoo  (%d)" % Game.zoo.size(), func() -> void:
			Game.set_phase(Game.Phase.ZOO)))

	buttons.add_child(_menu_button("Teacher Settings", func() -> void: Game.open_settings()))

	if not OS.has_feature("web"):
		buttons.add_child(_menu_button("Quit", func() -> void: get_tree().quit()))

	centre.add_child(UiKit.spacer(20))
	centre.add_child(UiKit.title(_input_summary(), UiKit.SMALL, UiKit.MUTED))


func _menu_button(text: String, action: Callable, accent := false) -> Button:
	var b := UiKit.button(text, UiKit.H3, accent)
	b.custom_minimum_size = Vector2(320, 54)
	b.pressed.connect(func() -> void:
		Audio.play("select")
		action.call())
	return b


## Teachers need to know at a glance whether this machine will hear the class or ask
## them to type.
func _input_summary() -> String:
	if Speech.uses_microphone():
		return "Microphone ready  -  hold SPACE to speak"
	return "No microphone on this build - students type their sentence instead"
