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
##   COLOUR   - one carousel used in sequence: first "Before", then "Now".
## The panel is anchored by its parent, so switching views cannot move or resize it. That
## is deliberate: the old grid changed height between states and the whole right side of
## the screen jumped.
##
## No arrow or separator glyphs anywhere. The web export bundles only Godot's default
## font, which has no U+2194 or U+2192, and there is no system font to fall back on -
## the same trap that turned the settings gear into a tofu box. "<" and ">" are ASCII and
## safe; between two words the game says "to".

signal pair_selected(category: String, before: String, after: String)
signal before_colour_previewed(word: String)
signal colour_selection_cancelled()

enum View { CATEGORY, COLOUR }
enum ColourStep { BEFORE, AFTER }

## Sized to fit the panel it is mounted in, not chosen for looks: the row is
## arrow + side + main + side + arrow plus four gaps. Keep the total within the fixed
## selection console or the far arrow lands outside it, which is exactly how the first
## build shipped its right arrow off the edge.
## One card per adjective, side by side, so the pair still reads as a pair. Two of these
## plus the gap has to come in under what CARD_SIZE used to occupy or the row stops fitting.
## Every card in the deck is this size, middle one included. A larger centre card says
## "this is the selection" - but any visible word can be tapped, so there is no selection
## to point at, and the odd one out only made the row read as a scroller.
const WORD_CARD_SIZE := Vector2(112, 78)
const WORD_TEXT_SIZE := UiKit.BODY ## Uniform across the deck, and big enough to read.
const WORD_GAP := 8
const SIDE_CARD_SIZE := Vector2(112, 78)
const ARROW_SIZE := 55 ## 25% larger than the former 44px chevron controls.
const CATEGORY_ARROW_FONT := 38 ## 25% larger than the former 30px glyphs.
const COLOUR_ARROW_FONT := 28 ## 25% larger than the former 22px glyphs.
const CAROUSEL_GAP := 8
const CAROUSEL_ARROW_GAP := 24 ## Three times the word-to-word gap, only beside the chevrons.
const COLOUR_CARD_GAP := 10
const COLOUR_ARROW_GAP := 30 ## Triple the card gap so the chevrons read as navigation.
const SWATCH_SIZE := Vector2(220, 94)
const COLOUR_SIDE_SIZE := Vector2(96, 68)
const ACTION_SIZE := Vector2(148, 46)
const SLIDE_TIME := 0.16 ## Long enough to see which way the deck moved, short enough to spam.
const COLOUR_CONFIRM_TIME := 0.32

var _view := View.CATEGORY
var _index := 0 ## Which slot the carousel is centred on.
var _slots: Array = [] ## TraitDefinition, or the COLOUR sentinel string.
var _used := PackedStringArray()
var _disabled := PackedStringArray()
var _locked := false
var _restriction := ""

var _was_index := 0
var _now_index := 0
var _colour_step := ColourStep.BEFORE

var _views := {} ## View -> Control
var _prev_card: PanelContainer = null
var _main_host: Control = null ## Fixed layout cell; only its child slides.
var _main_card: HBoxContainer = null
var _word_cards: Array[Button] = []
var _next_card: PanelContainer = null
var _left_arrow: Button = null
var _right_arrow: Button = null
var _status: Label = null
var _colour_heading: Label = null
var _colour_prev: Button = null
var _colour_swatch: Button = null
var _colour_next: Button = null
var _colour_feedback: Label = null
var _colour_cancel: Button = null
var _colour_committing := false
var _reference: Window = null
var _slide: Tween = null


func _ready() -> void:
	# The cards are a control console beneath the platform, not a second screen-sized panel.
	# Their own faces provide contrast while the laboratory remains visible around them.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
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
		page.add_theme_constant_override("separation", 10)
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
## One card per adjective, not one per pair. A student choosing "It was big" is making a
## single choice, and showing them two words at once asks them to read both and work out
## which half they want before they can move. Its opposite is still what the animal
## becomes - that is the pair's job, not the card's - so the deck runs big, small, tall,
## short, and tapping any one of them says the animal started there.
func _build_slots() -> void:
	_slots.clear()
	for pair in Content.enabled_pairs():
		for word in pair.words():
			_slots.append({"pair": pair, "word": str(word)})
	if not Content.enabled_colors().is_empty():
		_slots.append(Content.COLOR_CATEGORY)


# --- Category carousel -------------------------------------------------------

func _build_category_view(page: VBoxContainer) -> void:
	var row := UiKit.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(row)

	_left_arrow = _arrow("<", -1)
	row.add_child(_left_arrow)
	row.add_child(_carousel_gap(CAROUSEL_ARROW_GAP))

	_prev_card = _side_card(-1)
	row.add_child(_prev_card)
	row.add_child(_carousel_gap(CAROUSEL_GAP))

	# The row's Container must own a fixed cell, not the card that animates. Moving a
	# Container-managed child by setting position.x corrupts its layout offsets: after the
	# first click the pair was pulled toward x=0 and overlapped one chevron. The host never
	# moves; the card slides locally inside it and is clipped at the cell edges.
	_main_host = Control.new()
	_main_host.name = "MainCardHost"
	# Kept at the old two-card width so the console's centre column did not narrow when the
	# deck went to one word at a time - the surrounding layout is fixed, and a card that
	# suddenly occupied half of it would leave the row looking unbalanced.
	_main_host.custom_minimum_size = WORD_CARD_SIZE
	_main_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_main_host.clip_contents = true
	row.add_child(_main_host)
	row.add_child(_carousel_gap(CAROUSEL_GAP))

	_main_card = UiKit.hbox(WORD_GAP)
	_main_card.name = "SlidingWordCards"
	_main_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_host.add_child(_main_card)
	_main_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var word_card := Button.new()
	word_card.custom_minimum_size = WORD_CARD_SIZE
	word_card.focus_mode = Control.FOCUS_NONE
	word_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	word_card.pressed.connect(_activate)
	_main_card.add_child(word_card)
	_word_cards.append(word_card)

	_next_card = _side_card(1)
	row.add_child(_next_card)
	row.add_child(_carousel_gap(CAROUSEL_ARROW_GAP))

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
	var b := UiKit.button(glyph, CATEGORY_ARROW_FONT)
	b.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	# Square, and centred against the cards. Left to fill, an HBox stretches it to the
	# tallest thing in the row and the arrow becomes a full-height pill.
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(b, UiKit.PANEL_HI)
	b.pressed.connect(func() -> void: _step(step))
	return b


func _carousel_gap(width: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, 0)
	return gap


func _side_card(direction: int) -> PanelContainer:
	var card := UiKit.panel(Color("#16233a"), 12, 2, UiKit.PANEL_HI, 8)
	card.custom_minimum_size = SIDE_CARD_SIZE
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.modulate = Color.WHITE ## A choice, not a preview of one - see _side().
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_select_visible_word(direction)
			card.accept_event()
		elif event is InputEventScreenTouch and event.pressed:
			_select_visible_word(direction)
			card.accept_event())
	var label := UiKit.label("", WORD_TEXT_SIZE, UiKit.TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _slot_pair(slot) -> TraitDefinition:
	if slot is Dictionary:
		return (slot as Dictionary).get("pair", null)
	return null


func _slot_category(slot) -> String:
	var pair := _slot_pair(slot)
	return pair.category if pair != null else Content.COLOR_CATEGORY


func _slot_title(slot) -> String:
	if slot is Dictionary:
		return str((slot as Dictionary).get("word", "")).to_upper()
	return "COLOURS"


## The card that was tapped IS the direction: tapping "big" says the animal was big and
## will become small. That is the one instruction this game has always given, and asking
## again on a second screen would only add a step to say what the tap already said.
func _activate() -> void:
	if _slots.is_empty():
		return
	var slot = _slots[_index]
	var category := _slot_category(slot)
	if _blocked(category):
		Audio.play("fail", 0.9)
		return
	var pair := _slot_pair(slot)
	if pair != null:
		var before := str((slot as Dictionary).get("word", ""))
		_audio_confirm_selection(before)
		pair_selected.emit(pair.category, before, pair.opposite_of(before))
		return
	Audio.play("select")
	_was_index = 0
	_now_index = _next_colour_index(_was_index, 1, true)
	_colour_step = ColourStep.BEFORE
	_sync_colour()
	_show_view(View.COLOUR)


## The peeking word cards are choices too. Move the selected slot onto the card that was
## pressed, refresh the deck so the choice becomes centred, then use the same activation
## path as pressing the centre card. The centre cell itself is unchanged in size.
func _select_visible_word(direction: int) -> void:
	if _slots.is_empty() or _locked or not _restriction.is_empty():
		return
	var target_index := wrapi(_index + direction, 0, _slots.size())
	if _blocked(_slot_category(_slots[target_index])):
		Audio.play("fail", 0.9)
		return
	_index = target_index
	_refresh()
	_activate()


# --- Colours -----------------------------------------------------------------

func _build_colour_view(page: VBoxContainer) -> void:
	_colour_heading = UiKit.label("", UiKit.H3, UiKit.GOLD)
	_colour_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_colour_heading)

	var row := UiKit.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(row)

	var left := UiKit.button("<", COLOUR_ARROW_FONT)
	left.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	left.focus_mode = Control.FOCUS_NONE
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER ## Square, not a full-height pill.
	UiKit.style_button(left, UiKit.PANEL_HI)
	left.pressed.connect(func() -> void: _step_colour(-1))
	row.add_child(left)
	row.add_child(_colour_gap(COLOUR_ARROW_GAP))

	_colour_prev = _colour_card(COLOUR_SIDE_SIZE, 0.48, true)
	_colour_prev.pressed.connect(func() -> void: _select_visible_colour(-1))
	row.add_child(_colour_prev)
	row.add_child(_colour_gap(COLOUR_CARD_GAP))

	_colour_swatch = _colour_card(SWATCH_SIZE, 1.0, true)
	_colour_swatch.add_theme_font_size_override("font_size", UiKit.H2)
	_colour_swatch.pressed.connect(_confirm_colour)
	row.add_child(_colour_swatch)
	row.add_child(_colour_gap(COLOUR_CARD_GAP))

	_colour_next = _colour_card(COLOUR_SIDE_SIZE, 0.48, true)
	_colour_next.pressed.connect(func() -> void: _select_visible_colour(1))
	row.add_child(_colour_next)
	row.add_child(_colour_gap(COLOUR_ARROW_GAP))

	var right := UiKit.button(">", COLOUR_ARROW_FONT)
	right.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	right.focus_mode = Control.FOCUS_NONE
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(right, UiKit.PANEL_HI)
	right.pressed.connect(func() -> void: _step_colour(1))
	row.add_child(right)

	_colour_feedback = UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	_colour_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_colour_feedback)

	var actions := UiKit.vbox(8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(actions)
	_colour_cancel = UiKit.button("Cancel", UiKit.BODY)
	_colour_cancel.custom_minimum_size = ACTION_SIZE
	_colour_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_colour_cancel.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(_colour_cancel, UiKit.PANEL_HI)
	_colour_cancel.pressed.connect(_cancel_colour)
	actions.add_child(_colour_cancel)


func _colour_gap(width: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, 0)
	return gap


func _colour_card(size: Vector2, alpha: float, selectable := false) -> Button:
	var card := Button.new()
	card.custom_minimum_size = size
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = not selectable
	if selectable:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.modulate.a = alpha
	card.add_theme_font_size_override("font_size", UiKit.H3)
	return card


## Stepping the "now" wheel onto the "was" colour keeps going rather than stopping there,
## so "It was red. Now it is red." is not something the student can even land on, let
## alone submit. Stepping "was" onto "now" pushes the other wheel along for the same
## reason - whichever one the student is turning stays under their control.
func _step_colour(direction: int) -> void:
	var colours := Content.enabled_colors()
	if colours.size() < 2 or _locked or _colour_committing:
		return
	Audio.play("click")
	if _colour_step == ColourStep.BEFORE:
		_was_index = _next_colour_index(_was_index, direction, false)
	else:
		# AFTER automatically skips the confirmed BEFORE colour. The student can see it
		# remains on the animal, but can never land on a sentence that changes nothing.
		_now_index = _next_colour_index(_now_index, direction, true)
	_sync_colour()


## Any visible colour card is a choice. Side cards use the same direction as their
## position relative to the centre, then go through the same confirmation path as the
## centre card. Browsing with the arrows remains preview-free until this is pressed.
func _select_visible_colour(direction: int) -> void:
	if _colour_committing or _locked or _blocked(Content.COLOR_CATEGORY):
		return
	var active_index := _was_index if _colour_step == ColourStep.BEFORE else _now_index
	var skip_before := _colour_step == ColourStep.AFTER
	var selected_index := _next_colour_index(active_index, direction, skip_before)
	if _colour_step == ColourStep.BEFORE:
		_was_index = selected_index
	else:
		_now_index = selected_index
	_sync_colour()
	_confirm_colour()


func _next_colour_index(from: int, direction: int, skip_before: bool) -> int:
	var colours := Content.enabled_colors()
	if colours.is_empty():
		return 0
	var candidate := from
	for _attempt in colours.size():
		candidate = wrapi(candidate + direction, 0, colours.size())
		if not skip_before or candidate != _was_index:
			return candidate
	return from


func _sync_colour() -> void:
	var colours := Content.enabled_colors()
	if colours.is_empty():
		return
	_was_index = clampi(_was_index, 0, colours.size() - 1)
	_now_index = clampi(_now_index, 0, colours.size() - 1)
	if _colour_step == ColourStep.AFTER and _was_index == _now_index:
		_now_index = _next_colour_index(_now_index, 1, true)
	var active_index := _was_index if _colour_step == ColourStep.BEFORE else _now_index
	var skip_before := _colour_step == ColourStep.AFTER
	var previous := _next_colour_index(active_index, -1, skip_before)
	var following := _next_colour_index(active_index, 1, skip_before)
	_paint(_colour_prev, colours[previous])
	_paint(_colour_swatch, colours[active_index])
	_paint(_colour_next, colours[following])
	_colour_heading.text = "Before" if _colour_step == ColourStep.BEFORE else "Now"
	_colour_feedback.text = "Tap any visible colour to choose it."
	_colour_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_colour_cancel.text = "Cancel"


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


func _emit_before_preview() -> void:
	var colours := Content.enabled_colors()
	if not colours.is_empty():
		# This signal is emitted only after an explicit colour-card press. Arrow browsing
		# changes the carousel labels without changing the animal.
		before_colour_previewed.emit((colours[_was_index] as ColorDefinition).word)


func _show_colour_confirmation(colour: ColorDefinition, step_name: String) -> void:
	_colour_feedback.text = "%s selected for %s." % [colour.word.capitalize(), step_name]
	_colour_feedback.add_theme_color_override("font_color", UiKit.OK)
	var shade := Content.color_of(colour.word, Color.WHITE)
	var box := UiKit.stylebox(shade, 12, 4, UiKit.OK, 6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		_colour_swatch.add_theme_stylebox_override(state, box)


## A confirmation chime alone is easy to miss in a busy classroom. Saying the chosen word
## makes the feedback useful to an ESL learner as well as confirming that the tap landed.
func _audio_confirm_selection(word: String) -> void:
	Audio.play("select")
	Tts.speak(word, 0.9)


func _confirm_colour() -> void:
	var colours := Content.enabled_colors()
	if colours.size() < 2 or _locked or _colour_committing \
			or _blocked(Content.COLOR_CATEGORY):
		return
	_colour_committing = true
	if _colour_step == ColourStep.BEFORE:
		var selected_before: ColorDefinition = colours[_was_index]
		_audio_confirm_selection(selected_before.word)
		_emit_before_preview()
		_show_colour_confirmation(selected_before, "Before")
		await get_tree().create_timer(COLOUR_CONFIRM_TIME).timeout
		# The panel can be torn down while this pause is running - the round ends, the
		# screen rebuilds, the scene is left. Everything below writes to nodes that no
		# longer exist by then, which is a handful of errors per shot and a real crash the
		# moment one of those writes matters.
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_colour_committing = false
		_colour_step = ColourStep.AFTER
		if _now_index == _was_index:
			_now_index = _next_colour_index(_was_index, 1, true)
		_sync_colour()
		return
	var was: ColorDefinition = colours[_was_index]
	var now: ColorDefinition = colours[_now_index]
	if was.word == now.word:
		_colour_committing = false
		return
	_audio_confirm_selection(now.word)
	_show_colour_confirmation(now, "Now")
	await get_tree().create_timer(COLOUR_CONFIRM_TIME).timeout
	_colour_committing = false
	pair_selected.emit(Content.COLOR_CATEGORY, was.word, now.word)
	_show_view(View.CATEGORY)


func _cancel_colour() -> void:
	if _colour_committing:
		return
	Audio.play("click")
	if _colour_step == ColourStep.AFTER:
		# Back means reconsider the whole colour transformation, beginning from the
		# confirmed BEFORE choice that is still painted on the animal.
		_colour_step = ColourStep.BEFORE
		_sync_colour()
		return
	colour_selection_cancelled.emit()
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

	var face := UiKit.OK.darkened(0.55) if done else Color("#16233a")
	# No accent ring on the middle card either: it is not a selection, it is just the one in
	# the middle. The tick colour stays, because "already used" is real information.
	var edge := UiKit.OK if done else UiKit.PANEL_HI
	for card in _word_cards:
		card.visible = true
		card.text = _slot_title(slot)
		# The same size as the words either side of it. Every visible word can be tapped, so
		# enlarging the middle one implied it was the only one that could be - and made the
		# deck read as a thing to scroll rather than a row of choices.
		card.add_theme_font_size_override("font_size", WORD_TEXT_SIZE)
		card.disabled = blocked
		for state in ["normal", "disabled"]:
			card.add_theme_stylebox_override(state, UiKit.stylebox(face, 14, 2, edge, 10))
		card.add_theme_stylebox_override("hover",
			UiKit.stylebox(face.lightened(0.14), 14, 2, UiKit.ACCENT, 10))
		card.add_theme_stylebox_override("pressed",
			UiKit.stylebox(face.darkened(0.18), 14, 2, UiKit.ACCENT, 10))
		card.add_theme_color_override("font_color", UiKit.TEXT)
		card.add_theme_color_override("font_disabled_color", UiKit.MUTED)

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
	var blocked := _blocked(_slot_category(slot))
	# Full strength unless the category is spent. These are tappable choices, and dimming
	# them said "preview" - a student cannot tell a faded word from an unavailable one.
	# Fading now means exactly one thing: already used on this creature.
	card.modulate = Color(1, 1, 1, 0.35) if blocked else Color.WHITE
	var label_colour: Color = UiKit.MUTED if blocked else UiKit.TEXT
	label.add_theme_color_override("font_color", label_colour)
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if blocked else Control.CURSOR_POINTING_HAND
