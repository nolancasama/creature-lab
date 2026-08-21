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

	centre.add_child(UiKit.title("クリーチャーラボ", UiKit.H1, UiKit.ACCENT))
	centre.add_child(UiKit.title("It was... Now it is...", UiKit.H2, UiKit.GOLD))
	centre.add_child(UiKit.spacer(6))
	centre.add_child(UiKit.title(
		"どうぶつをえらび、3つの文を言って、へんしんを見よう。", UiKit.BODY, UiKit.MUTED))
	centre.add_child(UiKit.spacer(18))

	var buttons := UiKit.vbox(10)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.custom_minimum_size = Vector2(320, 0)
	centre.add_child(buttons)

	buttons.add_child(_menu_button("クリーチャーをつくる", func() -> void:
		Game.set_phase(Game.Phase.ANIMAL_SELECTION), "primary"))

	if not Game.zoo.is_empty():
		buttons.add_child(_menu_button("わたしのどうぶつえん  (%d)" % Game.zoo.size(), func() -> void:
			Game.set_phase(Game.Phase.ZOO)))

	buttons.add_child(_menu_button("先生用設定", func() -> void: Game.open_settings()))

	if not OS.has_feature("web"):
		buttons.add_child(_menu_button("終了", func() -> void: get_tree().quit(), "secondary"))

	centre.add_child(UiKit.spacer(20))
	centre.add_child(UiKit.title(_input_summary(), UiKit.SMALL, UiKit.MUTED))


func _menu_button(text: String, action: Callable, role := "navigation") -> Button:
	var b := UiKit.button(text, UiKit.H3)
	match role:
		"primary": UiKit.style_primary(b)
		"secondary": UiKit.style_secondary(b)
		_: UiKit.style_navigation(b)
	b.custom_minimum_size = Vector2(320, 54)
	b.pressed.connect(func() -> void:
		Audio.play("select")
		action.call())
	return b


## Teachers need to know at a glance whether this machine will hear the class or ask
## them to type.
func _input_summary() -> String:
	if Speech.uses_microphone():
		return "マイクの準備ができました － スペースキーを押して話します"
	return "マイクを使えないため、文を入力します"
