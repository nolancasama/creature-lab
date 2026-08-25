extends Control
## Teacher-owned configuration, stored separately from gameplay and never written by it.
##
## The three dials at the top are what replaced the spec's undefined "Easy Mode": how
## much choice the student gets, how strictly speech is judged, and how much of the
## sentence is printed for them.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())
	_build()


func _build() -> void:
	var frame := UiKit.vbox(12)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 90
	frame.offset_right = -90
	frame.offset_top = 40
	frame.offset_bottom = -40
	add_child(frame)

	var header := UiKit.hbox(12)
	frame.add_child(header)
	header.add_child(UiKit.label("先生用設定", UiKit.H2, UiKit.ACCENT))
	header.add_child(UiKit.expander())
	var back := UiKit.button("完了", UiKit.H3, true)
	UiKit.style_navigation(back)
	back.custom_minimum_size = Vector2(180, 56)
	back.pressed.connect(func() -> void:
		Settings.save_settings()
		Game.close_settings())
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.get_v_scroll_bar().custom_minimum_size.x = 16
	frame.add_child(scroll)

	var column := UiKit.vbox(14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_choice_section(
		"学習者が言う文の長さ",
		"過去形だけなら短く、音声認識がより安定します。クリーチャーの変化は同じです。",
		[["過去形だけ（It was small.）", Settings.SAY_PAST],
			["過去形のあと、現在形を3文", Settings.SAY_SPLIT],
			["文をすべて言う", Settings.SAY_FULL]],
		func() -> String: return Settings.say_mode,
		func(value: String) -> void: Settings.say_mode = value))

	column.add_child(_choice_section(
		"単語をえらぶ人", "元のデザインの「かんたんモード」です。",
		[["学習者が自由にえらぶ", Settings.CHOICE_FREE], ["ゲームが組み合わせを指定", Settings.CHOICE_GUIDED]],
		func() -> String: return Settings.choice_mode,
		func(value: String) -> void: Settings.choice_mode = value))

	column.add_child(_choice_section(
		"表示する文の量",
		"学期中に、全文表示、空欄つき、非表示の順で難しくできます。",
		[["全文", Settings.PROMPT_FULL], ["空欄つき", Settings.PROMPT_GAPPED], ["表示しない", Settings.PROMPT_HIDDEN]],
		func() -> String: return Settings.prompt_mode,
		func(value: String) -> void: Settings.prompt_mode = value))

	column.add_child(_choice_section(
		"音声判定のきびしさ",
		"やさしい判定は2語の順番だけ、厳密な判定は文全体を確認します。",
		[["やさしい", str(Settings.STRICT_LENIENT)], ["ふつう", str(Settings.STRICT_NORMAL)], ["厳密", str(Settings.STRICT_EXACT)]],
		func() -> String: return str(Settings.strictness),
		func(value: String) -> void: Settings.strictness = int(value)))

	column.add_child(_vocabulary_section())
	column.add_child(_toggles_section())
	column.add_child(_audio_section())
	column.add_child(_zoo_section())


func _section(title: String, subtitle := "") -> VBoxContainer:
	var panel := UiKit.panel(Color("#101a2b"), 14, 2, UiKit.PANEL_HI)
	var column := UiKit.vbox(8)
	panel.add_child(column)
	column.add_child(UiKit.label(title, UiKit.H3, UiKit.GOLD))
	if not subtitle.is_empty():
		column.add_child(UiKit.label(subtitle, UiKit.SMALL, UiKit.MUTED))
	panel.set_meta("column", column)
	return column


func _wrap(column: VBoxContainer) -> Control:
	return column.get_parent()


## A row of mutually exclusive buttons bound to one setting.
func _choice_section(title: String, subtitle: String, options: Array, getter: Callable, setter: Callable) -> Control:
	var column := _section(title, subtitle)
	var row := UiKit.hbox(8)
	column.add_child(row)
	var buttons := {}
	for option in options:
		var label := str(option[0])
		var value := str(option[1])
		var b := UiKit.button(label, UiKit.BODY)
		b.custom_minimum_size = Vector2(220, 52)
		b.set_meta("choice_label", label)
		row.add_child(b)
		buttons[value] = b
		b.pressed.connect(func() -> void:
			setter.call(value)
			Audio.play("click")
			_paint_choice(buttons, str(getter.call())))
	_paint_choice(buttons, str(getter.call()))
	return _wrap(column)


func _paint_choice(buttons: Dictionary, active: String) -> void:
	for value in buttons:
		var b: Button = buttons[value]
		UiKit.style_choice(b, str(value) == active)


func _vocabulary_section() -> Control:
	var column := _section("使用する単語",
		"すべてオフにした場合は、すべてオンとして扱います。")

	var pairs := GridContainer.new()
	pairs.columns = 5
	pairs.add_theme_constant_override("h_separation", 8)
	pairs.add_theme_constant_override("v_separation", 8)
	column.add_child(pairs)
	for pair in Content.pairs:
		if not pair.selectable:
			continue
		var b := UiKit.button("%s / %s" % [pair.word_a, pair.word_b], UiKit.SMALL)
		b.custom_minimum_size = Vector2(200, 52)
		b.toggle_mode = true
		b.button_pressed = Settings.is_pair_enabled(pair.id)
		_paint_toggle(b)
		b.toggled.connect(func(on: bool) -> void:
			Settings.toggle_pair(pair.id, on)
			_paint_toggle(b))
		pairs.add_child(b)

	var colors := GridContainer.new()
	colors.columns = 10
	colors.add_theme_constant_override("h_separation", 8)
	colors.add_theme_constant_override("v_separation", 8)
	column.add_child(colors)
	for swatch in Content.colors:
		var b := UiKit.button(swatch.word, UiKit.SMALL)
		b.custom_minimum_size = Vector2(104, 52)
		b.toggle_mode = true
		b.button_pressed = Settings.is_color_enabled(swatch.word)
		_paint_toggle(b)
		b.toggled.connect(func(on: bool) -> void:
			Settings.toggle_color(swatch.word, on)
			_paint_toggle(b))
		colors.add_child(b)

	return _wrap(column)


func _paint_toggle(b: Button) -> void:
	UiKit.style_choice(b, b.button_pressed, UiKit.PANEL.darkened(0.2))


func _toggles_section() -> Control:
	var column := _section("音声と読み上げ",
		"マイクをオフにすると文を入力します。ゲームの進み方は同じです。")
	var row := UiKit.hbox(8)
	column.add_child(row)
	row.add_child(_switch("マイク", func() -> bool: return Settings.stt_enabled,
		func(on: bool) -> void:
			Settings.stt_enabled = on
			Speech.select_backend()))
	row.add_child(_switch("読み上げ（TTS）", func() -> bool: return Settings.tts_enabled,
		func(on: bool) -> void: Settings.tts_enabled = on))
	row.add_child(_switch("全画面", func() -> bool: return Settings.fullscreen,
		func(on: bool) -> void:
			Settings.fullscreen = on
			Settings.save_settings()))
	row.add_child(_switch("しんだんログ", func() -> bool: return Settings.speech_log,
		func(on: bool) -> void:
			Settings.speech_log = on
			Settings.save_settings()))
	row.add_child(UiKit.label(
		"この環境の入力方法：%s" % Speech.prompt_label(), UiKit.SMALL, UiKit.MUTED))
	return _wrap(column)


func _switch(label: String, getter: Callable, setter: Callable) -> Button:
	var b := UiKit.button(label, UiKit.SMALL)
	b.custom_minimum_size = Vector2(210, 52)
	b.toggle_mode = true
	b.button_pressed = bool(getter.call())
	_paint_toggle(b)
	b.toggled.connect(func(on: bool) -> void:
		setter.call(on)
		_paint_toggle(b))
	return b


func _audio_section() -> Control:
	var column := _section("音量")
	var row := UiKit.hbox(12)
	column.add_child(row)
	row.add_child(_slider("音楽", Settings.music_volume, func(v: float) -> void:
		Settings.music_volume = v
		Audio.play_ambience(true)))
	row.add_child(_slider("効果音", Settings.sfx_volume, func(v: float) -> void:
		Settings.sfx_volume = v
		Audio.play("click")))
	return _wrap(column)


func _slider(label: String, value: float, setter: Callable) -> Control:
	var box := UiKit.vbox(4)
	box.custom_minimum_size = Vector2(300, 0)
	box.add_child(UiKit.label(label, UiKit.SMALL, UiKit.MUTED))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(280, 40)
	slider.value_changed.connect(func(v: float) -> void: setter.call(v))
	box.add_child(slider)
	return box


func _zoo_section() -> Control:
	var column := _section("どうぶつえん",
		"レッスン中のどうぶつえんです。異常終了でも失われないよう保存されます。")
	var row := UiKit.hbox(10)
	column.add_child(row)
	row.add_child(_switch("次回もどうぶつえんを残す", func() -> bool: return Settings.persist_zoo,
		func(on: bool) -> void: Settings.persist_zoo = on))
	var reset := UiKit.button("どうぶつえんをリセット", UiKit.SMALL)
	reset.custom_minimum_size = Vector2(220, 52)
	UiKit.style_button(reset, UiKit.BAD.darkened(0.52))
	reset.pressed.connect(func() -> void:
		Game.reset_zoo()
		Audio.play("pop"))
	row.add_child(reset)
	row.add_child(UiKit.label("保存中：%d体" % Game.zoo.size(), UiKit.SMALL, UiKit.MUTED))
	return _wrap(column)
