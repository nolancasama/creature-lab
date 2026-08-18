class_name WordLab
extends PanelContainer
## The permanent vocabulary reference, built entirely from content files.
##
## The Word Lab never touches the animal. It reports a choice; LabController decides what
## that means and CreatureState records it. Tapping a word means "this is what it WAS",
## which is the only instruction a beginner needs to hold in their head.

signal pair_selected(category: String, before: String, after: String)

## One size for both grids: a pair card (two words) and a colour swatch (one word) occupy
## the same footprint, so the board reads as one system of equally weighted choices rather
## than two different densities stacked on top of each other.
const WORD_CARD_SIZE := Vector2(180, 70)
const PAIR_COLUMNS := 3
const COLOR_COLUMNS := 3 ## Matches PAIR_COLUMNS, so both grids line up at the same width.

var _pair_buttons := {} ## "category|word" -> Button
var _color_buttons := {} ## word -> Button
var _cards := {} ## category -> PanelContainer
var _color_hint: Label = null

var _used := PackedStringArray()
var _disabled := PackedStringArray()
var _locked := false
var _color_before := ""
var _restriction := "" ## Guided mode: only this category may be chosen. Empty = free.


func _ready() -> void:
	# Padding tripled from the original 10: at the panel's new full-height (it now matches
	# the picking screen's panel rather than sharing its rect with Say It), words sitting
	# flush against the rounded border read as clipped rather than framed.
	add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.06, 0.1, 0.16, 0.92), 16, 2, UiKit.PANEL_HI, 30))
	var column := UiKit.vbox(6)
	add_child(column)

	# No headings: the cards are the instruction, and a title plus two standing prompts
	# cost three lines of the panel's height to say what tapping one card teaches anyway.
	column.add_child(_build_pairs())
	column.add_child(UiKit.spacer(24))

	# Kept, but silent by default - it is the only place the second half of a colour round
	# ("now tap the colour it is NOW") can be asked for. See _refresh_colors().
	_color_hint = UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	_color_hint.visible = false
	column.add_child(_color_hint)
	column.add_child(_build_colors())


func _build_pairs() -> Control:
	var grid := GridContainer.new()
	grid.columns = PAIR_COLUMNS
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 20)

	for pair in Content.enabled_pairs():
		var card := UiKit.panel(Color("#101a2b"), 10, 0, Color.TRANSPARENT, 8)
		card.custom_minimum_size = WORD_CARD_SIZE
		var row := UiKit.hbox(4)
		card.add_child(row)
		row.add_child(_word_button(pair, pair.word_a))
		row.add_child(UiKit.spacer(12)) ## A gap rather than a "/" - simpler, and there is
		## no glyph the web export's font is guaranteed to carry that reads better.
		row.add_child(_word_button(pair, pair.word_b))
		grid.add_child(card)
		_cards[pair.category] = card
	return grid


func _word_button(pair: TraitDefinition, word: String) -> Button:
	var b := UiKit.button(word, UiKit.SMALL)
	b.custom_minimum_size = Vector2(66, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: _choose_pair(pair, word))
	# A long press reads the pair aloud without selecting anything.
	b.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			Tts.speak("%s. %s." % [pair.word_a, pair.word_b]))
	_pair_buttons["%s|%s" % [pair.category, word]] = b
	return b


func _build_colors() -> Control:
	var grid := GridContainer.new()
	grid.columns = COLOR_COLUMNS
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 20)

	for swatch in Content.enabled_colors():
		var b := UiKit.button(swatch.word, UiKit.SMALL)
		b.custom_minimum_size = WORD_CARD_SIZE
		UiKit.style_button(b, swatch.color)
		b.add_theme_color_override("font_color", swatch.label_color())
		b.add_theme_color_override("font_hover_color", swatch.label_color())
		b.add_theme_color_override("font_pressed_color", swatch.label_color())
		b.pressed.connect(func() -> void: _choose_color(swatch.word))
		grid.add_child(b)
		_color_buttons[swatch.word] = b
	return grid


func _choose_pair(pair: TraitDefinition, before: String) -> void:
	if _blocked(pair.category):
		return
	Audio.play("select")
	pair_selected.emit(pair.category, before, pair.opposite_of(before))


## Colours need two taps because any colour can follow any other, so the first tap sets
## "It was ___" and the second sets "Now it is ___".
func _choose_color(word: String) -> void:
	if _blocked(Content.COLOR_CATEGORY):
		return
	if _color_before.is_empty():
		_color_before = word
		Audio.play("click")
		_refresh_colors()
		return
	if word == _color_before:
		_color_before = ""
		Audio.play("click")
		_refresh_colors()
		return
	var before := _color_before
	_color_before = ""
	Audio.play("select")
	_refresh_colors()
	pair_selected.emit(Content.COLOR_CATEGORY, before, word)


# --- State -------------------------------------------------------------------

func set_locked(value: bool) -> void:
	_locked = value
	if value:
		_color_before = ""
	_refresh()


func set_used(categories: PackedStringArray) -> void:
	_used = categories
	_color_before = ""
	_refresh()


func set_disabled_categories(categories: PackedStringArray) -> void:
	_disabled = categories
	_color_before = ""
	_refresh()


## Guided mode hands the student one pair at a time instead of the whole board.
func set_restriction(category: String) -> void:
	_restriction = category
	_refresh()


func _blocked(category: String) -> bool:
	return _locked or _used.has(category) or _disabled.has(category) or (not _restriction.is_empty() and category != _restriction)


func _refresh() -> void:
	for key in _pair_buttons:
		var category := str(key).split("|")[0]
		var b: Button = _pair_buttons[key]
		b.disabled = _blocked(category)
	for category in _cards:
		var card: PanelContainer = _cards[category]
		var done: bool = _used.has(str(category))
		card.add_theme_stylebox_override("panel",
			UiKit.stylebox(Color("#0d1524") if done else Color("#101a2b"), 10,
				2 if done else 0, UiKit.OK.darkened(0.5), 8))
	_refresh_colors()


func _refresh_colors() -> void:
	var colors_done: bool = _used.has(Content.COLOR_CATEGORY)
	var colors_blocked := _blocked(Content.COLOR_CATEGORY)
	for word in _color_buttons:
		var b: Button = _color_buttons[word]
		b.disabled = colors_blocked
		var chosen: bool = str(word) == _color_before
		b.add_theme_constant_override("outline_size", 0)
		b.scale = Vector2.ONE * (1.06 if chosen else 1.0)
	if _color_hint == null:
		return
	if colors_done:
		_color_hint.text = "Colours - already used this round."
	elif colors_blocked:
		_color_hint.text = "" ## Disabled swatches say this without a line of text.
	elif _color_before.is_empty():
		_color_hint.text = "" ## The standing prompt is gone; the swatches say it themselves.
	else:
		_color_hint.text = "It was %s... now tap the colour it is NOW." % _color_before
	_color_hint.visible = not _color_hint.text.is_empty()
