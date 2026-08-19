class_name DescriptorCarousel
extends PanelContainer
## Choosing what to turn the animal into: one card at a time, not a wall of words.
##
## Drop-in for WordLab on the recording screen - same `pair_selected` signal, same
## set_used/set_disabled_categories/set_restriction/set_locked state API - so nothing in
## LabController or CreatureState had to learn about carousels. WordLab itself is still
## built, but as the Word List reference sheet behind a button, which is what a full grid
## of every pair at once is actually good for.
##
## Two views share one fixed rect, and only ever swap their contents:
##   CATEGORY - the horizontal card carousel, previous and next peeking in at the sides.
##              Each adjective is its own card, so tapping one both picks the pair and
##              says which way it runs: the tapped word is what the animal WAS.
##   COLOUR   - two carousels, because colours have no opposite and need both ends picked
## The panel is anchored by its parent, so switching views cannot move or resize it. That
## is deliberate: the old grid changed height between states and the whole right side of
## the screen jumped.
##
## No arrow or separator glyphs anywhere. The web export bundles only Godot's default
## font, which has no U+2194 or U+2192, and there is no system font to fall back on -
## the same trap that turned the settings gear into a tofu box. "<" and ">" are ASCII and
## safe; between two words the game says "to".

signal pair_selected(category: String, before: String, after: String)

enum View { CATEGORY, COLOUR }

## Sized to fit the panel it is mounted in, not chosen for looks: the row is
## arrow + side + main + side + arrow plus four gaps, and the right panel gives it 596px
## once its own padding is taken off. Overshoot that and the far arrow lands outside the
## panel, which is exactly how the first build shipped its right arrow off the edge.
## One card per adjective, side by side, so the pair still reads as a pair. Two of these
## plus the gap has to come in under what CARD_SIZE used to occupy or the row stops fitting.
const WORD_CARD_SIZE := Vector2(115, 124)
const WORD_GAP := 8
const SIDE_CARD_SIZE := Vector2(104, 88)
const ARROW_SIZE := 44
const CAROUSEL_GAP := 8
const SWATCH_SIZE := Vector2(210, 96)
const SLIDE_TIME := 0.16 ## Long enough to see which way the deck moved, short enough to spam.

var _view := View.CATEGORY
var _index := 0 ## Which slot the carousel is centred on.
var _slots: Array = [] ## TraitDefinition, or the COLOUR sentinel string.
var _used := PackedStringArray()
var _disabled := PackedStringArray()
var _locked := false
var _restriction := ""

var _was_index := 0
var _now_index := 0

var _views := {} ## View -> Control
var _prev_card: PanelContainer = null
var _main_host: Control = null ## Fixed layout cell; only its child slides.
var _main_card: HBoxContainer = null
var _word_cards: Array[Button] = []
var _next_card: PanelContainer = null
var _left_arrow: Button = null
var _right_arrow: Button = null
var _status: Label = null
var _was_swatch: Button = null
var _now_swatch: Button = null
var _colour_sentence: Label = null
var _colour_use: Button = null
var _reference: Window = null
var _slide: Tween = null


func _ready() -> void:
	add_theme_stylebox_override("panel",
		UiKit.stylebox(Color(0.06, 0.1, 0.16, 0.92), 16, 2, UiKit.PANEL_HI, 26))
	_build_slots()

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stack)

	# All three live in the same rect at once, with visibility deciding which is on show.
	# Building them once means switching views cannot re-run a layout pass and shift
	# anything, and the panel keeps the size its parent gave it.
	for view in [View.CATEGORY, View.COLOUR]:
		var page := VBoxContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.add_theme_constant_override("separation", 14)
		page.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_child(page)
		_views[view] = page
	_build_category_view(_views[View.CATEGORY])
	_build_colour_view(_views[View.COLOUR])
	_show_view(View.CATEGORY)
	_refresh()


## Colours ride at the end of the same deck rather than in a panel of their own: to a
## student "what colour was it" is one more transformation to choose, not a different
## kind of question.
func _build_slots() -> void:
	_slots.clear()
	for pair in Content.enabled_pairs():
		_slots.append(pair)
	if not Content.enabled_colors().is_empty():
		_slots.append(Content.COLOR_CATEGORY)


# --- Category carousel -------------------------------------------------------

func _build_category_view(page: VBoxContainer) -> void:
	var row := UiKit.hbox(CAROUSEL_GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(row)

	_left_arrow = _arrow("<", -1)
	row.add_child(_left_arrow)

	_prev_card = _side_card()
	row.add_child(_prev_card)

	# The pair arrives as two cards, not one card with two words on it. A pair is two
	# choices, and the card the student taps is the state the animal starts in - so the
	# thing they tap has to be the word itself, with its own edges.
	# The row's Container must own a fixed cell, not the card that animates. Moving a
	# Container-managed child by setting position.x corrupts its layout offsets: after the
	# first click the pair was pulled toward x=0 and overlapped one chevron. The host never
	# moves; the card slides locally inside it and is clipped at the cell edges.
	_main_host = Control.new()
	_main_host.name = "MainCardHost"
	_main_host.custom_minimum_size = Vector2(
		WORD_CARD_SIZE.x * 2.0 + WORD_GAP, WORD_CARD_SIZE.y)
	_main_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_main_host.clip_contents = true
	row.add_child(_main_host)

	_main_card = UiKit.hbox(WORD_GAP)
	_main_card.name = "SlidingWordCards"
	_main_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_host.add_child(_main_card)
	_main_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 2:
		var word_card := Button.new()
		word_card.custom_minimum_size = WORD_CARD_SIZE
		word_card.focus_mode = Control.FOCUS_NONE
		word_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		word_card.pressed.connect(_activate.bind(i))
		_main_card.add_child(word_card)
		_word_cards.append(word_card)

	_next_card = _side_card()
	row.add_child(_next_card)

	_right_arrow = _arrow(">", 1)
	row.add_child(_right_arrow)

	_status = UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_status)

	var word_list := UiKit.button("Word List", UiKit.SMALL)
	word_list.custom_minimum_size = Vector2(140, 38)
	word_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(word_list, UiKit.PANEL_HI)
	word_list.pressed.connect(_open_reference)
	page.add_child(word_list)


func _arrow(glyph: String, step: int) -> Button:
	var b := UiKit.button(glyph, UiKit.H2)
	b.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	# Square, and centred against the cards. Left to fill, an HBox stretches it to the
	# tallest thing in the row and the arrow becomes a full-height pill.
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(b, UiKit.PANEL_HI)
	b.pressed.connect(func() -> void: _step(step))
	return b


func _side_card() -> PanelContainer:
	var card := UiKit.panel(Color("#16233a"), 12, 2, UiKit.PANEL_HI, 8)
	card.custom_minimum_size = SIDE_CARD_SIZE
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.modulate = Color(1, 1, 1, 0.55) ## Peeking in, not competing with the centre.
	var label := UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(label)
	return card


## Wraps, so the deck has no dead ends to hunt for the one remaining category in.
func _step(direction: int) -> void:
	if _slots.is_empty() or _locked or not _restriction.is_empty():
		return
	Audio.play("click")
	_index = wrapi(_index + direction, 0, _slots.size())
	_refresh()
	if _slide != null and _slide.is_valid():
		_slide.kill()
	# The card arrives from the side it came from, so the movement itself says which way
	# the deck went - a card that only fades leaves that ambiguous.
	# Local to MainCardHost. The arrows, side previews and host retain the positions the
	# outer HBox assigned them throughout the animation.
	_main_card.position.x = -direction * 26.0
	_slide = create_tween()
	_slide.tween_property(_main_card, "position:x", 0.0, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _slot_words(slot) -> PackedStringArray:
	if slot is TraitDefinition:
		return (slot as TraitDefinition).words()
	return PackedStringArray(["colours"])


func _slot_category(slot) -> String:
	if slot is TraitDefinition:
		return (slot as TraitDefinition).category
	return Content.COLOR_CATEGORY


## Two words side by side with a gap, never "big <-> small": see the glyph note above.
func _slot_title(slot) -> String:
	if slot is TraitDefinition:
		var pair: TraitDefinition = slot
		return "%s    %s" % [pair.word_a.to_upper(), pair.word_b.to_upper()]
	return "COLOURS"


## Which half was tapped IS the direction: tapping "big" says the animal was big and will
## become small. That is the one instruction this game has always given, and asking again
## on a second screen would only add a step to say what the tap already said.
func _activate(half: int) -> void:
	if _slots.is_empty():
		return
	var slot = _slots[_index]
	var category := _slot_category(slot)
	if _blocked(category):
		Audio.play("fail", 0.9)
		return
	if slot is TraitDefinition:
		var pair: TraitDefinition = slot
		var before := pair.word_a if half == 0 else pair.word_b
		Audio.play("select")
		pair_selected.emit(pair.category, before, pair.opposite_of(before))
		return
	Audio.play("select")
	_was_index = 0
	_now_index = 1
	_sync_colour()
	_show_view(View.COLOUR)


# --- Colours -----------------------------------------------------------------

func _build_colour_view(page: VBoxContainer) -> void:
	page.add_child(_colour_row("It was", true))
	page.add_child(_colour_row("Now it is", false))

	_colour_sentence = UiKit.label("", UiKit.BODY, UiKit.TEXT)
	_colour_sentence.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_colour_sentence)

	_colour_use = UiKit.button("Use these colours", UiKit.BODY)
	_colour_use.custom_minimum_size = Vector2(260, 52)
	_colour_use.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_colour_use.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(_colour_use, UiKit.ACCENT, true)
	_colour_use.pressed.connect(_choose_colours)
	page.add_child(_colour_use)

	page.add_child(_back_button())


func _colour_row(caption: String, is_was: bool) -> Control:
	var box := UiKit.vbox(4)
	var label := UiKit.label(caption, UiKit.SMALL, UiKit.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var left := UiKit.button("<", UiKit.H3)
	left.custom_minimum_size = Vector2(44, 44)
	left.focus_mode = Control.FOCUS_NONE
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER ## Square, not a full-height pill.
	UiKit.style_button(left, UiKit.PANEL_HI)
	left.pressed.connect(func() -> void: _step_colour(is_was, -1))
	row.add_child(left)

	var swatch := Button.new()
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.focus_mode = Control.FOCUS_NONE
	swatch.disabled = true ## A label that happens to be paintable, not a control.
	swatch.add_theme_font_size_override("font_size", UiKit.H3)
	row.add_child(swatch)
	if is_was:
		_was_swatch = swatch
	else:
		_now_swatch = swatch

	var right := UiKit.button(">", UiKit.H3)
	right.custom_minimum_size = Vector2(44, 44)
	right.focus_mode = Control.FOCUS_NONE
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(right, UiKit.PANEL_HI)
	right.pressed.connect(func() -> void: _step_colour(is_was, 1))
	row.add_child(right)
	return box


## Stepping the "now" wheel onto the "was" colour keeps going rather than stopping there,
## so "It was red. Now it is red." is not something the student can even land on, let
## alone submit. Stepping "was" onto "now" pushes the other wheel along for the same
## reason - whichever one the student is turning stays under their control.
func _step_colour(is_was: bool, direction: int) -> void:
	var colours := Content.enabled_colors()
	if colours.size() < 2 or _locked:
		return
	Audio.play("click")
	if is_was:
		_was_index = wrapi(_was_index + direction, 0, colours.size())
		if _was_index == _now_index:
			_now_index = wrapi(_now_index + direction, 0, colours.size())
	else:
		_now_index = wrapi(_now_index + direction, 0, colours.size())
		if _now_index == _was_index:
			_now_index = wrapi(_now_index + direction, 0, colours.size())
	_sync_colour()


func _sync_colour() -> void:
	var colours := Content.enabled_colors()
	if colours.is_empty():
		return
	_was_index = clampi(_was_index, 0, colours.size() - 1)
	_now_index = clampi(_now_index, 0, colours.size() - 1)
	if _was_index == _now_index:
		_now_index = wrapi(_now_index + 1, 0, colours.size())
	var was: ColorDefinition = colours[_was_index]
	var now: ColorDefinition = colours[_now_index]
	_paint(_was_swatch, was)
	_paint(_now_swatch, now)
	_colour_sentence.text = "It was %s. Now it is %s." % [was.word, now.word]


## The swatch wears the colour it names, so the word and the thing agree even for a
## student who cannot yet read it.
func _paint(swatch: Button, colour: ColorDefinition) -> void:
	if swatch == null:
		return
	var shade := Content.color_of(colour.word, Color.WHITE)
	swatch.text = colour.word
	var box := UiKit.stylebox(shade, 12, 2, shade.lightened(0.25), 6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		swatch.add_theme_stylebox_override(state, box)
	# Dark text on pale colours, pale text on dark ones, so "yellow" and "black" both read.
	var ink := Color("#08111c") if shade.get_luminance() > 0.45 else UiKit.TEXT
	for state in ["font_color", "font_disabled_color", "font_hover_color"]:
		swatch.add_theme_color_override(state, ink)


func _choose_colours() -> void:
	var colours := Content.enabled_colors()
	if colours.size() < 2 or _locked or _blocked(Content.COLOR_CATEGORY):
		return
	var was: ColorDefinition = colours[_was_index]
	var now: ColorDefinition = colours[_now_index]
	if was.word == now.word:
		return ## Unreachable by the wheels, but never emit a sentence that says nothing.
	Audio.play("select")
	pair_selected.emit(Content.COLOR_CATEGORY, was.word, now.word)
	_show_view(View.CATEGORY)


# --- Shared ------------------------------------------------------------------

func _back_button() -> Button:
	var b := UiKit.button("Back", UiKit.SMALL)
	b.custom_minimum_size = Vector2(120, 38)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(b, UiKit.PANEL_HI)
	b.pressed.connect(func() -> void:
		Audio.play("click")
		_show_view(View.CATEGORY))
	return b


func _show_view(view: int) -> void:
	_view = view
	for key in _views:
		(_views[key] as Control).visible = key == view
	_refresh()


## The full grid, read-only. WordLab already draws every pair and colour at once and is
## locked out of selecting anything here, so the reference sheet costs one instance
## rather than a second copy of the same layout.
func _open_reference() -> void:
	Audio.play("click")
	if _reference != null and is_instance_valid(_reference):
		_reference.popup_centered(Vector2i(700, 560))
		return
	_reference = Window.new()
	_reference.title = "Word List"
	_reference.transient = true
	_reference.exclusive = true
	_reference.close_requested.connect(func() -> void: _reference.hide())
	var backdrop := UiKit.backdrop()
	_reference.add_child(backdrop)
	var sheet := WordLab.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reference.add_child(sheet)
	sheet.set_locked(true) ## Reference only - every word in here is deliberately inert.
	add_child(_reference)
	_reference.popup_centered(Vector2i(700, 560))


# --- State (the WordLab contract) --------------------------------------------

func set_locked(value: bool) -> void:
	_locked = value
	if value:
		_show_view(View.CATEGORY)
	else:
		_refresh()


func set_used(categories: PackedStringArray) -> void:
	_used = categories
	_settle_index()
	_show_view(View.CATEGORY)


func set_disabled_categories(categories: PackedStringArray) -> void:
	_disabled = categories
	_settle_index()
	_refresh()


func set_restriction(category: String) -> void:
	_restriction = category
	if not category.is_empty():
		for i in _slots.size():
			if _slot_category(_slots[i]) == category:
				_index = i
				break
	_refresh()


func _blocked(category: String) -> bool:
	return _locked or _used.has(category) or _disabled.has(category) \
		or (not _restriction.is_empty() and category != _restriction)


## After a category is spent, park the deck on something the student can actually pick,
## rather than leaving them looking at a card with a tick on it.
func _settle_index() -> void:
	if _slots.is_empty():
		return
	for offset in _slots.size():
		var i := wrapi(_index + offset, 0, _slots.size())
		if not _blocked(_slot_category(_slots[i])):
			_index = i
			return


func _refresh() -> void:
	if _slots.is_empty() or _main_card == null:
		return
	_index = clampi(_index, 0, _slots.size() - 1)
	var slot = _slots[_index]
	var category := _slot_category(slot)
	var done: bool = _used.has(category)
	var blocked := _blocked(category)

	var words := _slot_words(slot)
	var face := UiKit.OK.darkened(0.55) if done else Color("#16233a")
	var edge := UiKit.OK if done else UiKit.ACCENT
	for i in _word_cards.size():
		var card := _word_cards[i]
		# Colours are one card, not two: there is no opposite of red to put on the other.
		card.visible = i < words.size()
		if not card.visible:
			continue
		card.text = words[i].to_upper() if slot is TraitDefinition else "COLOURS"
		card.add_theme_font_size_override("font_size", UiKit.H3)
		card.disabled = blocked
		for state in ["normal", "disabled"]:
			card.add_theme_stylebox_override(state, UiKit.stylebox(face, 14, 2, edge, 10))
		card.add_theme_stylebox_override("hover",
			UiKit.stylebox(face.lightened(0.14), 14, 2, UiKit.ACCENT, 10))
		card.add_theme_stylebox_override("pressed",
			UiKit.stylebox(face.darkened(0.18), 14, 2, UiKit.ACCENT, 10))
		card.add_theme_color_override("font_color", UiKit.TEXT)
		card.add_theme_color_override("font_disabled_color", UiKit.MUTED)
		card.custom_minimum_size = Vector2(
			WORD_CARD_SIZE.x if words.size() > 1 else WORD_CARD_SIZE.x * 2 + WORD_GAP,
			WORD_CARD_SIZE.y)

	_side(_prev_card, wrapi(_index - 1, 0, _slots.size()))
	_side(_next_card, wrapi(_index + 1, 0, _slots.size()))
	var single := _slots.size() < 2
	_left_arrow.disabled = _locked or single or not _restriction.is_empty()
	_right_arrow.disabled = _left_arrow.disabled

	if _status != null:
		if _locked:
			_status.text = "Say the sentence first."
		elif done:
			_status.text = "Already used on this creature."
		elif blocked:
			_status.text = "Not for this creature."
		else:
			_status.text = ""


func _side(card: PanelContainer, index: int) -> void:
	if card == null or card.get_child_count() == 0:
		return
	var label: Label = card.get_child(0)
	if _slots.size() < 2:
		card.visible = false
		return
	card.visible = true
	var slot = _slots[index]
	label.text = _slot_title(slot)
	card.modulate = Color(1, 1, 1, 0.22 if _used.has(_slot_category(slot)) else 0.42)
