class_name DnaLog
extends PanelContainer
## The three numbered sentence slots. This is the DNA the chamber will execute, so it
## stays on screen for the whole round and every completed sentence can be replayed.

var _rows: Array[Dictionary] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.06, 0.1, 0.16, 0.92), 16, 2, UiKit.PANEL_HI))
	var column := UiKit.vbox(8)
	add_child(column)

	var header := UiKit.hbox(8)
	column.add_child(header)
	header.add_child(UiKit.label("DNA LOG", UiKit.H3, UiKit.ACCENT))
	header.add_child(UiKit.expander())
	header.add_child(UiKit.label("It was... Now it is...", UiKit.SMALL, UiKit.MUTED))

	for i in CreatureState.SLOTS:
		column.add_child(_build_row(i))


func _build_row(index: int) -> Control:
	var row_panel := UiKit.panel(Color("#101a2b"), 10)
	var row := UiKit.hbox(10)
	row_panel.add_child(row)

	var number := UiKit.label("%d." % (index + 1), UiKit.H3, UiKit.MUTED)
	number.custom_minimum_size = Vector2(28, 0)
	row.add_child(number)

	var text := UiKit.label("", UiKit.BODY, UiKit.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(0, 46)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)

	var listen := UiKit.button("Listen", UiKit.SMALL)
	listen.visible = false
	row.add_child(listen)

	_rows.append({"panel": row_panel, "number": number, "text": text, "listen": listen, "sentence": ""})
	_refresh_row(index)
	return row_panel


func _refresh_row(index: int) -> void:
	var row := _rows[index]
	var sentence := str(row["sentence"])
	var text: Label = row["text"]
	var number: Label = row["number"]
	var listen: Button = row["listen"]
	var panel: PanelContainer = row["panel"]

	if sentence.is_empty():
		text.text = "- - -"
		text.add_theme_color_override("font_color", UiKit.MUTED.darkened(0.25))
		number.add_theme_color_override("font_color", UiKit.MUTED.darkened(0.25))
		listen.visible = false
		panel.add_theme_stylebox_override("panel", UiKit.stylebox(Color("#101a2b"), 10))
	else:
		text.text = sentence
		text.add_theme_color_override("font_color", UiKit.TEXT)
		number.add_theme_color_override("font_color", UiKit.OK)
		listen.visible = Tts.available()
		panel.add_theme_stylebox_override("panel",
			UiKit.stylebox(Color("#122a24"), 10, 2, UiKit.OK.darkened(0.35)))


func set_slot(index: int, sentence: String) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows[index]["sentence"] = sentence
	_refresh_row(index)
	var listen: Button = _rows[index]["listen"]
	for connection in listen.pressed.get_connections():
		listen.pressed.disconnect(connection["callable"])
	listen.pressed.connect(func() -> void: Tts.speak(sentence))

	# A slot landing should feel like a latch closing.
	var panel: PanelContainer = _rows[index]["panel"]
	panel.pivot_offset = panel.size * 0.5
	var tween := create_tween()
	tween.tween_property(panel, "scale", Vector2(1.05, 1.12), 0.12)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)


func sync(state: CreatureState) -> void:
	for i in CreatureState.SLOTS:
		var sentence := ""
		if state != null and i < state.entries.size():
			sentence = str(state.entries[i]["sentence"])
		_rows[i]["sentence"] = sentence
		_refresh_row(i)
