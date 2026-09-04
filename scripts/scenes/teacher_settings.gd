extends Control
## Teacher-owned configuration, stored separately from gameplay and never written by it.
##
## The three dials at the top are what replaced the spec's undefined "Easy Mode": how
## much choice the student gets, how tolerant recognition is, and how much of the
## sentence is printed for them.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# This is mounted over the live gameplay screen rather than replacing it, so it has to
	# swallow anything aimed at what is still underneath. Main also freezes that scene;
	# this is the half that stops a stray tap landing on a button behind the backdrop.
	mouse_filter = Control.MOUSE_FILTER_STOP
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
		"学習言語 / Target Language", "学習者が見て、話す言語をえらびます。",
		# にほんご, not 日本語: 日 and 本 are not in the bundled font subset, and the same kana
		# constraint already governs every student-facing word in the pack.
		[["English", Settings.TARGET_ENGLISH], ["にほんご", Settings.TARGET_JAPANESE]],
		func() -> String: return Settings.target_language_choice(),
		func(value: String) -> void: Settings.set_target_language(value)))

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

	# きびしい became チャレンジ: the mode is not a harsher judgement of the child, it is a
	# harder game, and it now also gives them the most tries before the sentence is handed
	# to them. The label a student might glimpse should say that.
	column.add_child(_choice_section(
		"発音判定",
		# Worded from the kanji the bundled subset actually carries: 多 and 数 are not in it,
		# and the font check catches that rather than letting tofu boxes reach a classroom.
		"きびしい設定ほど、やりなおせるチャンスがふえます。（%d / %d / %d）" % [
			Settings.ASSIST_AFTER[Settings.HEAR_LENIENT],
			Settings.ASSIST_AFTER[Settings.HEAR_NORMAL],
			Settings.ASSIST_AFTER[Settings.HEAR_EXACT]],
		[["やさしい", str(Settings.HEAR_LENIENT)], ["標準", str(Settings.HEAR_NORMAL)], ["チャレンジ", str(Settings.HEAR_EXACT)]],
		func() -> String: return str(Settings.strictness),
		func(value: String) -> void: Settings.strictness = int(value)))

	column.add_child(_graphics_section())

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


func _graphics_section() -> Control:
	var column := _section("グラフィック / Graphics")
	var helper := UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	column.add_child(helper)
	var row := UiKit.hbox(8)
	column.add_child(row)
	var buttons := {}
	var options := [
		["Performance / 軽い", GraphicsQuality.PERFORMANCE, "動きが重いときにおすすめ"],
		["Standard / 標準", GraphicsQuality.STANDARD, "おすすめ"],
		["High / 高画質", GraphicsQuality.HIGH, "高性能なパソコン向け"],
	]
	var refresh := func() -> void:
		_paint_choice(buttons, Settings.graphics_quality)
		for option in options:
			if str(option[1]) == Settings.graphics_quality:
				helper.text = str(option[2])
				break
	for option in options:
		var value := str(option[1])
		var button := UiKit.button(str(option[0]), UiKit.BODY)
		button.custom_minimum_size = Vector2(220, 52)
		row.add_child(button)
		buttons[value] = button
		button.pressed.connect(func() -> void:
			Audio.play("click")
			Settings.set_graphics_quality(value)
			refresh.call())
	refresh.call()
	return _wrap(column)


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
	var count := UiKit.label("保存中：%d体" % Game.zoo.size(), UiKit.SMALL, UiKit.MUTED)
	reset.pressed.connect(func() -> void:
		Audio.play("click")
		_confirm_zoo_reset(count))
	row.add_child(reset)
	row.add_child(count)
	return _wrap(column)


## Resetting throws away every creature a class made, and the button used to do it on the
## first press - one mis-tap on a teacher's screen mid-lesson and a morning's work was gone
## with nothing to undo it. The zoo's own release row already asks before sending a single
## creature home; wiping all of them had less protection than releasing one.
##
## A modal rather than the zoo's inline yes/no swap: this is the destructive end of a
## settings page a teacher scrolls quickly, so it takes over the screen and says how many
## animals are about to be lost, and the safe answer is the one that reads first.
func _confirm_zoo_reset(count_label: Label) -> void:
	var living := Game.zoo.size()

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Dimmed rather than opaque: the teacher can still see which screen they are on, and
	# MOUSE_FILTER_STOP means nothing behind it can be pressed by accident.
	var shade := ColorRect.new()
	shade.color = Color(UiKit.BG, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)

	# A CenterContainer rather than a centre anchor preset: the panel is sized by its own
	# content, and this is the one arrangement that centres it without hard-coding a height.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(centre)

	var frame := UiKit.panel(UiKit.PANEL, 16, 2, UiKit.BAD.darkened(0.35), 26)
	frame.custom_minimum_size = Vector2(560, 0)
	centre.add_child(frame)

	var box := UiKit.vbox(16)
	frame.add_child(box)
	box.add_child(UiKit.title("どうぶつえんをリセットしますか？", UiKit.H3, UiKit.TEXT))
	box.add_child(UiKit.label(
		"%d体のどうぶつが すべていなくなります。もとにもどせません。" % living,
		UiKit.SMALL, UiKit.MUTED))

	var buttons := UiKit.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	# Cancel first and styled as the ordinary control; the destructive one has to be chosen.
	var cancel := UiKit.button("キャンセル", UiKit.SMALL)
	cancel.custom_minimum_size = Vector2(200, UiKit.MIN_TOUCH)
	cancel.focus_mode = Control.FOCUS_NONE
	UiKit.style_navigation(cancel)
	buttons.add_child(cancel)

	var confirm := UiKit.button("リセットする", UiKit.SMALL)
	confirm.custom_minimum_size = Vector2(200, UiKit.MIN_TOUCH)
	confirm.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(confirm, UiKit.BAD.darkened(0.52))
	buttons.add_child(confirm)

	cancel.pressed.connect(func() -> void:
		Audio.play("click")
		overlay.queue_free())
	confirm.pressed.connect(func() -> void:
		Game.reset_zoo()
		Audio.play("pop")
		# The count is built once with the section, so it would otherwise keep reporting the
		# creatures that no longer exist until the teacher reopened the page.
		count_label.text = "保存中：%d体" % Game.zoo.size()
		overlay.queue_free())
