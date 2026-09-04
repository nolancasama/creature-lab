class_name DescriptorCarousel
extends PanelContainer
## Choosing what to turn the animal into: a focused horizontal strip, not a wall of words.
##
## Drop-in for WordLab on the recording screen - same `pair_selected` signal, same
## set_used/set_disabled_categories/set_restriction/set_locked state API - so nothing in
## LabController or CreatureState had to learn about carousels. WordLab itself is still
## built, but as the Word List reference sheet behind a button, which is what a full grid
## of every pair at once is actually good for.
##
## Two views share one fixed rect, and only ever swap their contents:
##   CATEGORY - five visible cards with the focused choice centred in the strip.
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
signal before_colour_selected(word: String)
signal colour_selection_cancelled()
signal colour_step_changed(choosing_now: bool)

enum View { CATEGORY, COLOUR }
enum ColourStep { BEFORE, AFTER }

## Sized to fit the panel it is mounted in. Five cards, four internal gaps, two arrow gaps
## and two chevrons total 750px, just inside the fixed 760px selection console.
## Five adjective cards occupy the viewport: the middle three remain completely clear,
## while the outer third of the far-left and far-right cards dissolves at the edge.
const WORD_CARD_SIZE := Vector2(112, 78)
const WORD_TEXT_SIZE := UiKit.BODY ## Uniform across the deck, and big enough to read.
const WORD_GAP := 8
const WORD_VIEWPORT_WIDTH := WORD_CARD_SIZE.x * 5.0 + WORD_GAP * 4.0
const WORD_EDGE_FADE_WIDTH := WORD_CARD_SIZE.x * 0.33
const WORD_STRIDE := WORD_CARD_SIZE.x + WORD_GAP
const ARROW_SIZE := 55 ## 25% larger than the former 44px chevron controls.
const CATEGORY_ARROW_FONT := 38 ## 25% larger than the former 30px glyphs.
const COLOUR_ARROW_FONT := 28 ## 25% larger than the former 22px glyphs.
const CAROUSEL_ARROW_GAP := 24 ## Three times the word-to-word gap, only beside the chevrons.
const COLOUR_CARD_GAP := 10
const COLOUR_ARROW_GAP := 30 ## Triple the card gap so the chevrons read as navigation.
## The colour deck follows the same five-card presentation and outer-third edge fade.
const COLOUR_CARD_SIZE := Vector2(108, 86)
const COLOUR_VIEWPORT_WIDTH := COLOUR_CARD_SIZE.x * 5.0 + COLOUR_CARD_GAP * 4.0
const COLOUR_EDGE_FADE_WIDTH := COLOUR_CARD_SIZE.x * 0.33
const COLOUR_STRIDE := COLOUR_CARD_SIZE.x + COLOUR_CARD_GAP
const COLOUR_TEXT_SIZE := UiKit.H3 ## Uniform across the colour deck.
const ACTION_SIZE := Vector2(160, 52)
const SLIDE_TIME := 0.16 ## Long enough to see which way the deck moved, short enough to spam.
const COLOUR_CONFIRM_TIME := 0.32
const DRAG_START_DISTANCE := 8.0
const SWIPE_TRIGGER := 34.0
## The edge treatment: each card fades its own alpha out as it reaches the edge of the
## window.
##
## Two earlier versions of this were wrong in instructive ways.
##
## A dark gradient laid over the outer cards read as a smudge, because darkening is the
## wrong operation here - these cards are DARKER than the lab behind them, a #16233a face
## against a backdrop nearer #343840, so adding black to a card's edge makes it stand out
## like a drop shadow instead of receding. No width or opacity fixes that; widening it only
## makes a bigger smudge. Fading alpha is what actually recedes, whatever is behind.
##
## Compositing the row through a CanvasGroup and fading that in one pass is the tidier way
## to reach alpha, and it does not work here: the group drew as a flat white block with the
## ramp correctly applied to it, children and all. So the fade lives on each card instead,
## where COLOR is simply that card's own stylebox and text and multiplying its alpha does
## exactly what it says.
##
## The ramp is measured in the VIEWPORT's coordinates, not the card's, which is the whole
## reason for the card_origin uniform: the fade has to stay welded to the edge of the
## window while the cards slide underneath it, rather than travelling with any one card.
const EDGE_FADE_SHADER := """
shader_type canvas_item;

uniform float viewport_width = 592.0;
uniform float fade_width = 37.0;
uniform float card_origin = 0.0;

varying float local_x;

void vertex() {
	local_x = VERTEX.x;
}

void fragment() {
	float span = max(fade_width, 0.001);
	float x = card_origin + local_x;
	float inner = min(x / span, (viewport_width - x) / span);
	COLOR.a *= smoothstep(0.0, 1.0, clamp(inner, 0.0, 1.0));
}
"""

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
var _far_prev_card: Button = null
var _prev_card: Button = null
var _main_host: Control = null ## Fixed layout cell; only its child slides.
var _main_card: HBoxContainer = null
var _category_base_x := 0.0
var _category_fade_width := WORD_EDGE_FADE_WIDTH
var _word_cards: Array[Button] = []
var _word_track_cards := {} ## Relative slot (-4..4) -> Button; five are visible at rest.
var _next_card: Button = null
var _far_next_card: Button = null
var _left_arrow: Button = null
var _right_arrow: Button = null
var _status: Label = null
var _colour_heading: Label = null
var _colour_picker: VBoxContainer = null
var _colour_far_prev: Button = null
var _colour_prev: Button = null
var _colour_swatch: Button = null
var _colour_next: Button = null
var _colour_far_next: Button = null
var _colour_host: Control = null
var _colour_track: HBoxContainer = null
var _colour_base_x := 0.0
var _colour_fade_width := COLOUR_EDGE_FADE_WIDTH
var _colour_track_cards := {} ## Relative colour offset (-4..4) -> Button.
var _colour_feedback: Label = null
var _colour_cancel: Button = null
var _colour_committing := false
var _reference: Window = null
var _slide: Tween = null
var _drag_candidate := false
var _dragging := false
var _drag_start_x := 0.0
var _drag_offset := 0.0
var _drag_view := View.CATEGORY
var _drag_pointer := -2 ## -1 mouse; non-negative values are touch indices.


func _process(_delta: float) -> void:
	_sync_edge_fades()


## Arrows step the deck and space or enter takes the word in the middle, mirroring the
## chevrons and the centre card exactly. Only while the deck is actually the thing being
## used: a locked deck is waiting for a sentence to be said, and stealing the confirm key
## from the Say It panel underneath it would be worse than having no shortcut at all.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _locked:
		return
	if _view == View.COLOUR:
		if event.is_action_pressed("ui_left"):
			_step_colour(-1)
		elif event.is_action_pressed("ui_right"):
			_step_colour(1)
		elif event.is_action_pressed("ui_accept"):
			_confirm_colour()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("ui_accept"):
		_activate()
	else:
		return
	get_viewport().set_input_as_handled()


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
	Settings.changed.connect(_on_settings_changed)
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

	# Nine cards live on the sliding track. Five are visible at rest; two buffers on each
	# side keep one- and two-card snaps continuous without exposing an empty edge.
	_main_host = Control.new()
	_main_host.name = "WordCarouselViewport"
	_main_host.custom_minimum_size = Vector2(WORD_VIEWPORT_WIDTH, WORD_CARD_SIZE.y)
	_main_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_main_host.clip_contents = true
	row.add_child(_main_host)

	_main_card = UiKit.hbox(WORD_GAP)
	_main_card.name = "SlidingWordCards"
	_main_card.custom_minimum_size = Vector2(WORD_CARD_SIZE.x * 9.0 + WORD_GAP * 8.0,
		WORD_CARD_SIZE.y)
	_main_host.add_child(_main_card)
	for offset in range(-4, 5):
		var card: Button
		if offset == 0:
			card = Button.new()
			card.custom_minimum_size = WORD_CARD_SIZE
			card.focus_mode = Control.FOCUS_ALL
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			card.pressed.connect(_activate)
			_word_cards.append(card)
		else:
			card = _side_card(offset)
			if absi(offset) > 2:
				card.focus_mode = Control.FOCUS_NONE
		card.material = _fade_material(WORD_VIEWPORT_WIDTH)
		_word_track_cards[offset] = card
		_main_card.add_child(card)
	_far_prev_card = _word_track_cards[-2]
	_prev_card = _word_track_cards[-1]
	_next_card = _word_track_cards[1]
	_far_next_card = _word_track_cards[2]
	_category_base_x = -WORD_STRIDE * 2.0
	_main_card.position = Vector2(_category_base_x, 0.0)
	row.add_child(_carousel_gap(CAROUSEL_ARROW_GAP))
	_right_arrow = _arrow(">", 1)
	row.add_child(_right_arrow)

	_status = UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_status)

	var word_list := UiKit.button("単語リスト", UiKit.SMALL)
	word_list.custom_minimum_size = Vector2(160, 52)
	word_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.style_secondary(word_list)
	word_list.pressed.connect(_open_reference)
	page.add_child(word_list)


func _arrow(glyph: String, step: int) -> Button:
	var b := UiKit.button(glyph, CATEGORY_ARROW_FONT)
	b.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.focus_mode = Control.FOCUS_ALL
	# Square, and centred against the cards. Left to fill, an HBox stretches it to the
	# tallest thing in the row and the arrow becomes a full-height pill.
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_navigation(b)
	b.pressed.connect(func() -> void: _step(step))
	return b


func _carousel_gap(width: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, 0)
	return gap


## Holds the sliding track and fades whatever reaches the edge of the window. Sits at the
## viewport's origin and never moves, so the ramp measures from the edge the player sees
## rather than from the track, which is under it and travelling.
## One Shader compiled once and shared; every card gets its own ShaderMaterial pointing at
## it, because card_origin differs per card.
static var _fade_shader: Shader = null


func _fade_material(viewport_width: float) -> ShaderMaterial:
	if _fade_shader == null:
		_fade_shader = Shader.new()
		_fade_shader.code = EDGE_FADE_SHADER
	var material := ShaderMaterial.new()
	material.shader = _fade_shader
	material.set_shader_parameter("viewport_width", viewport_width)
	material.set_shader_parameter("fade_width", 0.0)
	material.set_shader_parameter("card_origin", 0.0)
	return material


## Tell every card where it currently sits inside its window, so the ramp stays put while
## the track slides. Runs every frame because the slide is a tween on the track's position
## and there is no cheaper moment that catches every value it passes through.
func _sync_edge_fades() -> void:
	_sync_track_fade(_main_card, _word_track_cards, _category_fade_width)
	_sync_track_fade(_colour_track, _colour_track_cards, _colour_fade_width)


func _sync_track_fade(track: Control, cards: Dictionary, width: float) -> void:
	if track == null:
		return
	var base := track.position.x
	for offset in cards:
		var card := cards[offset] as Control
		if card == null:
			continue
		var material := card.material as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("card_origin", base + card.position.x)
		material.set_shader_parameter("fade_width", width)


## A Button, exactly like the middle one. It used to be a panel wrapping a label, which
## looked close enough at rest but behaved differently the moment a finger or a cursor
## touched it: no hover, no press, no held state. Every visible word is equally pressable,
## so every visible word is the same control, painted by the same function.
func _side_card(direction: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = WORD_CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.pressed.connect(func() -> void: _select_visible_word(direction))
	return card


## Wraps, so the deck has no dead ends to hunt for the one remaining category in.
func _step(direction: int, drag_offset := NAN) -> void:
	if _slots.is_empty() or _locked or not _restriction.is_empty():
		return
	Audio.play("click")
	_index = wrapi(_index + direction, 0, _slots.size())
	_refresh()
	var arrival_offset := float(direction) * WORD_STRIDE
	if not is_nan(drag_offset):
		# Preserve the finger's partial travel when the refreshed deck changes which card
		# owns the centre slot; this prevents a jump at release before the snap begins.
		arrival_offset += drag_offset
	_animate_track_to_center(_main_card, _category_base_x, arrival_offset)


func _animate_track_to_center(track: Control, base_x: float, start_offset: float) -> void:
	if track == null:
		return
	if _slide != null and _slide.is_valid():
		_slide.kill()
	track.position.x = base_x + start_offset
	_slide = create_tween()
	_slide.tween_property(track, "position:x", base_x, SLIDE_TIME) \
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
		var word := str((slot as Dictionary).get("word", ""))
		return TargetLanguage.display_word(_slot_category(slot), word).to_lower()
	return "colors"


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
		_audio_confirm_selection(pair.category, before)
		pair_selected.emit(pair.category, before, pair.opposite_of(before))
		return
	Audio.play("select")
	_was_index = 0
	_now_index = _next_colour_index(_was_index, 1, true)
	_colour_step = ColourStep.BEFORE
	colour_step_changed.emit(false)
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
	_step(direction)
	_activate()


# --- Colours -----------------------------------------------------------------

func _build_colour_view(page: VBoxContainer) -> void:
	_colour_picker = UiKit.vbox(10)
	_colour_picker.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(_colour_picker)

	_colour_heading = UiKit.label("", UiKit.H3, UiKit.GOLD)
	_colour_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_colour_picker.add_child(_colour_heading)

	var row := UiKit.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_colour_picker.add_child(row)

	var left := UiKit.button("<", COLOUR_ARROW_FONT)
	left.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	left.focus_mode = Control.FOCUS_ALL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER ## Square, not a full-height pill.
	UiKit.style_navigation(left)
	left.pressed.connect(func() -> void: _step_colour(-1))
	row.add_child(left)
	row.add_child(_colour_gap(COLOUR_ARROW_GAP))

	_colour_host = Control.new()
	_colour_host.name = "ColourCarouselViewport"
	_colour_host.custom_minimum_size = Vector2(COLOUR_VIEWPORT_WIDTH, COLOUR_CARD_SIZE.y)
	_colour_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_colour_host.clip_contents = true
	row.add_child(_colour_host)
	_colour_track = UiKit.hbox(COLOUR_CARD_GAP)
	_colour_track.name = "SlidingColourCards"
	_colour_track.custom_minimum_size = Vector2(COLOUR_CARD_SIZE.x * 9.0 \
		+ COLOUR_CARD_GAP * 8.0, COLOUR_CARD_SIZE.y)
	_colour_host.add_child(_colour_track)
	for offset in range(-4, 5):
		var card := _colour_card()
		if offset == 0:
			card.pressed.connect(_confirm_colour)
		else:
			card.pressed.connect(_select_visible_colour.bind(offset))
			if absi(offset) > 2:
				card.focus_mode = Control.FOCUS_NONE
		card.material = _fade_material(COLOUR_VIEWPORT_WIDTH)
		_colour_track_cards[offset] = card
		_colour_track.add_child(card)
	_colour_far_prev = _colour_track_cards[-2]
	_colour_prev = _colour_track_cards[-1]
	_colour_swatch = _colour_track_cards[0]
	_colour_next = _colour_track_cards[1]
	_colour_far_next = _colour_track_cards[2]
	_colour_base_x = -COLOUR_STRIDE * 2.0
	_colour_track.position = Vector2(_colour_base_x, 0.0)
	row.add_child(_colour_gap(COLOUR_ARROW_GAP))
	var right := UiKit.button(">", COLOUR_ARROW_FONT)
	right.custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
	right.focus_mode = Control.FOCUS_ALL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_navigation(right)
	right.pressed.connect(func() -> void: _step_colour(1))
	row.add_child(right)

	_colour_feedback = UiKit.label("", UiKit.SMALL, UiKit.MUTED)
	_colour_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_colour_picker.add_child(_colour_feedback)

	var actions := UiKit.vbox(8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_colour_picker.add_child(actions)
	_colour_cancel = UiKit.button("キャンセル", UiKit.H3)
	_colour_cancel.custom_minimum_size = ACTION_SIZE
	_colour_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_colour_cancel.focus_mode = Control.FOCUS_ALL
	UiKit.style_secondary(_colour_cancel)
	_colour_cancel.pressed.connect(_cancel_colour)
	actions.add_child(_colour_cancel)

func _colour_gap(width: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, 0)
	return gap


## No size or alpha argument: there is one kind of colour card. The centre used to be more
## than twice the area of its neighbours; now the clipped viewport communicates scrolling
## without changing the established card design.
func _colour_card() -> Button:
	var card := Button.new()
	card.custom_minimum_size = COLOUR_CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_font_size_override("font_size", COLOUR_TEXT_SIZE)
	return card


## Stepping the "now" wheel onto the "was" colour keeps going rather than stopping there,
## so "It was red. Now it is red." is not something the student can even land on, let
## alone submit. Stepping "was" onto "now" pushes the other wheel along for the same
## reason - whichever one the student is turning stays under their control.
func _step_colour(direction: int, drag_offset := NAN) -> void:
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
	var arrival_offset := float(direction) * COLOUR_STRIDE
	if not is_nan(drag_offset):
		arrival_offset += drag_offset
	_animate_track_to_center(_colour_track, _colour_base_x, arrival_offset)


## Any visible colour card is a choice. Side cards use the same direction as their
## position relative to the centre, then go through the same confirmation path as the
## centre card. Browsing with the arrows remains preview-free until this is pressed.
func _select_visible_colour(direction: int) -> void:
	if _colour_committing or _locked or _blocked(Content.COLOR_CATEGORY):
		return
	var active_index := _was_index if _colour_step == ColourStep.BEFORE else _now_index
	var skip_before := _colour_step == ColourStep.AFTER
	var selected_index := _colour_offset_index(active_index, direction, skip_before)
	if _colour_step == ColourStep.BEFORE:
		_was_index = selected_index
	else:
		_now_index = selected_index
	_sync_colour()
	_animate_track_to_center(_colour_track, _colour_base_x,
		float(direction) * COLOUR_STRIDE)
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


func _colour_offset_index(from: int, offset: int, skip_before: bool) -> int:
	var result := from
	var direction := signi(offset)
	for _step in absi(offset):
		result = _next_colour_index(result, direction, skip_before)
	return result


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
	for offset in range(-4, 5):
		var colour_index := _colour_offset_index(active_index, offset, skip_before)
		_paint(_colour_track_cards[offset], colours[colour_index])
	_colour_heading.text = "へんしん前" if _colour_step == ColourStep.BEFORE else "いま"
	_colour_feedback.text = ""
	_colour_feedback.visible = false
	_colour_feedback.add_theme_color_override("font_color", UiKit.MUTED)
	_colour_cancel.text = "キャンセル"
	_colour_picker.visible = true
	if _colour_track != null:
		_colour_track.position.x = _colour_base_x
	var show_peeks := colours.size() >= 2
	_colour_fade_width = COLOUR_EDGE_FADE_WIDTH if show_peeks else 0.0


## The swatch wears the colour it names, so the word and the thing agree even for a
## student who cannot yet read it.
func _paint(swatch: Button, colour: ColorDefinition) -> void:
	if swatch == null:
		return
	var shade := Content.color_of(colour.word, Color.WHITE)
	swatch.text = TargetLanguage.display_word(Content.COLOR_CATEGORY, colour.word)
	for state in ["normal", "disabled"]:
		swatch.add_theme_stylebox_override(state,
			UiKit.stylebox(shade, 12, 2, shade.lightened(0.25), 6))
	# Tapping either visible side peek chooses it, so it has to answer the finger.
	swatch.add_theme_stylebox_override("hover",
		UiKit.stylebox(shade.lightened(0.14), 12, 2, UiKit.ACCENT, 6))
	swatch.add_theme_stylebox_override("pressed",
		UiKit.stylebox(shade.darkened(0.18), 12, 2, UiKit.ACCENT, 6))
	swatch.add_theme_stylebox_override("focus",
		UiKit.stylebox(shade, 12, 4, UiKit.GOLD, 6))
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
	_colour_feedback.text = "「%s」を%sの色にえらびました。" % [
		TargetLanguage.display_word(Content.COLOR_CATEGORY, colour.word), step_name]
	_colour_feedback.visible = true
	_colour_feedback.add_theme_color_override("font_color", UiKit.OK)
	var shade := Content.color_of(colour.word, Color.WHITE)
	var box := UiKit.stylebox(shade, 12, 4, UiKit.OK, 6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		_colour_swatch.add_theme_stylebox_override(state, box)


## A confirmation chime alone is easy to miss in a busy classroom. Saying the chosen word
## makes the feedback useful to an ESL learner as well as confirming that the tap landed.
func _audio_confirm_selection(category: String, word: String) -> void:
	Audio.play("select")
	Tts.speak(TargetLanguage.display_word(category, word), 0.9)


func _confirm_colour() -> void:
	var colours := Content.enabled_colors()
	if colours.size() < 2 or _locked or _colour_committing \
			or _blocked(Content.COLOR_CATEGORY):
		return
	_colour_committing = true
	if _colour_step == ColourStep.BEFORE:
		var selected_before: ColorDefinition = colours[_was_index]
		_audio_confirm_selection(Content.COLOR_CATEGORY, selected_before.word)
		_emit_before_preview()
		_colour_committing = false
		before_colour_selected.emit(selected_before.word)
		return
	var was: ColorDefinition = colours[_was_index]
	var now: ColorDefinition = colours[_now_index]
	if was.word == now.word:
		_colour_committing = false
		return
	_audio_confirm_selection(Content.COLOR_CATEGORY, now.word)
	_show_colour_confirmation(now, "いま")
	await get_tree().create_timer(COLOUR_CONFIRM_TIME).timeout
	_colour_committing = false
	colour_step_changed.emit(false)
	pair_selected.emit(Content.COLOR_CATEGORY, was.word, now.word)
	_show_view(View.CATEGORY)


## Called after the learner has completed the real "It was ..." input panel. The colour
## picker stays on BEFORE until then, so it cannot reveal or accept the Now colour early.
func continue_colour_after_past() -> void:
	_colour_step = ColourStep.AFTER
	if _now_index == _was_index:
		_now_index = _next_colour_index(_was_index, 1, true)
	_sync_colour()
	_show_view(View.COLOUR)
	colour_step_changed.emit(true)


func _cancel_colour() -> void:
	if _colour_committing:
		return
	Audio.play("click")
	if _colour_step == ColourStep.AFTER:
		# Back means reconsider the whole colour transformation, beginning from the
		# confirmed BEFORE choice that is still painted on the animal.
		_colour_step = ColourStep.BEFORE
		_sync_colour()
		colour_step_changed.emit(false)
		colour_selection_cancelled.emit()
		return
	colour_step_changed.emit(false)
	colour_selection_cancelled.emit()
	_show_view(View.CATEGORY)


# --- Pointer, touch and wheel navigation -------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var host := _active_carousel_host()
	if host == null or not host.is_visible_in_tree():
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT] \
				and host.get_global_rect().has_point(mouse.position):
			var direction := -1 if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_LEFT] else 1
			_step_active_carousel(direction)
			get_viewport().set_input_as_handled()
			return
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			if host.get_global_rect().has_point(mouse.position) and _carousel_can_move_or_tap():
				_begin_drag(mouse.position.x, -1)
				# We reproduce a tap on release. Handling the press here prevents the Button
				# underneath from also firing after a swipe.
				get_viewport().set_input_as_handled()
		elif _drag_candidate and _drag_pointer == -1:
			_finish_drag(mouse.position)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _drag_candidate and _drag_pointer == -1:
		_update_drag((event as InputEventMouseMotion).position.x)
		if _dragging:
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if host.get_global_rect().has_point(touch.position) and _carousel_can_move_or_tap():
				_begin_drag(touch.position.x, touch.index)
				get_viewport().set_input_as_handled()
		elif _drag_candidate and _drag_pointer == touch.index:
			_finish_drag(touch.position)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag and _drag_candidate \
			and _drag_pointer == (event as InputEventScreenDrag).index:
		_update_drag((event as InputEventScreenDrag).position.x)
		get_viewport().set_input_as_handled()


func _active_carousel_host() -> Control:
	return _main_host if _view == View.CATEGORY else _colour_host


func _active_carousel_track() -> Control:
	return _main_card if _view == View.CATEGORY else _colour_track


func _active_carousel_base_x() -> float:
	return _category_base_x if _view == View.CATEGORY else _colour_base_x


func _active_carousel_stride() -> float:
	return WORD_STRIDE if _view == View.CATEGORY else COLOUR_STRIDE


func _carousel_can_move_or_tap() -> bool:
	if _locked:
		return false
	if _view == View.CATEGORY:
		return _slots.size() >= 1 and _restriction.is_empty()
	return Content.enabled_colors().size() >= 2 and not _colour_committing


func _begin_drag(x: float, pointer: int) -> void:
	_drag_candidate = true
	_dragging = false
	_drag_start_x = x
	_drag_offset = 0.0
	_drag_view = _view
	_drag_pointer = pointer


func _update_drag(x: float) -> void:
	if _view != _drag_view:
		_cancel_drag()
		return
	var raw_offset := x - _drag_start_x
	if not _dragging and absf(raw_offset) >= DRAG_START_DISTANCE:
		_dragging = true
		if _slide != null and _slide.is_valid():
			_slide.kill()
	if not _dragging:
		return
	var limit := _active_carousel_stride() * 0.86
	_drag_offset = clampf(raw_offset, -limit, limit)
	var track := _active_carousel_track()
	if track != null:
		track.position.x = _active_carousel_base_x() + _drag_offset


func _finish_drag(position: Vector2) -> void:
	if _view != _drag_view:
		_cancel_drag()
		return
	if _dragging:
		if absf(_drag_offset) >= SWIPE_TRIGGER:
			# Dragging left asks for the next card; dragging right asks for the previous.
			_step_active_carousel(-signi(_drag_offset), _drag_offset)
		else:
			_animate_track_to_center(_active_carousel_track(),
				_active_carousel_base_x(), _drag_offset)
	else:
		_tap_active_carousel(position)
	_cancel_drag(false)


func _step_active_carousel(direction: int, drag_offset := NAN) -> void:
	if _view == View.CATEGORY:
		_step(direction, drag_offset)
	else:
		_step_colour(direction, drag_offset)


func _tap_active_carousel(position: Vector2) -> void:
	if _view == View.CATEGORY:
		for entry in [[_far_prev_card, -2], [_prev_card, -1], [_word_cards[0], 0],
				[_next_card, 1], [_far_next_card, 2]]:
			var card := entry[0] as Button
			if card != null and card.get_global_rect().has_point(position):
				card.grab_focus()
				if int(entry[1]) == 0:
					_activate()
				else:
					_select_visible_word(int(entry[1]))
				return
	else:
		for entry in [[_colour_far_prev, -2], [_colour_prev, -1], [_colour_swatch, 0],
				[_colour_next, 1], [_colour_far_next, 2]]:
			var card := entry[0] as Button
			if card != null and card.get_global_rect().has_point(position):
				card.grab_focus()
				if int(entry[1]) == 0:
					_confirm_colour()
				else:
					_select_visible_colour(int(entry[1]))
				return


func _cancel_drag(reset_track := true) -> void:
	if reset_track:
		var track := _active_carousel_track()
		if track != null:
			track.position.x = _active_carousel_base_x()
	_drag_candidate = false
	_dragging = false
	_drag_offset = 0.0
	_drag_pointer = -2


# --- Shared ------------------------------------------------------------------

func _back_button() -> Button:
	var b := UiKit.button("もどる", UiKit.SMALL)
	b.custom_minimum_size = Vector2(140, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	UiKit.style_navigation(b)
	b.pressed.connect(func() -> void:
		Audio.play("click")
		_show_view(View.CATEGORY))
	return b


func _show_view(view: int) -> void:
	_cancel_drag()
	_view = view
	for key in _views:
		(_views[key] as Control).visible = key == view
	_refresh()


func _on_settings_changed() -> void:
	_refresh()
	_sync_colour()


## The full grid, read-only. WordLab already draws every pair and colour at once and is
## locked out of selecting anything here, so the reference sheet costs one instance
## rather than a second copy of the same layout.
func _open_reference() -> void:
	Audio.play("click")
	if _reference != null and is_instance_valid(_reference):
		_reference.popup_centered(Vector2i(700, 560))
		return
	_reference = Window.new()
	_reference.title = "単語リスト"
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
	# AFTER the window joins the tree, not before. WordLab builds its cards in _ready(),
	# which does not run until its window is in the tree - so styling them any earlier
	# reaches an empty dictionary and silently does nothing.
	#
	# It has to LOOK inert, too: locked words still wore a pointer cursor and hover and
	# press faces, so the sheet invited taps it had no intention of answering.
	sheet.set_reference_mode()
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

	for offset in range(-4, 5):
		var card := _word_track_cards[offset] as Button
		if offset == 0:
			card.visible = true
			_paint_word_card(card, slot)
		else:
			_side(card, wrapi(_index + offset, 0, _slots.size()))
	var single := _slots.size() < 2
	_left_arrow.disabled = _locked or single or not _restriction.is_empty()
	_right_arrow.disabled = _left_arrow.disabled
	_main_card.position.x = _category_base_x
	_category_fade_width = 0.0 if single else WORD_EDGE_FADE_WIDTH

	if _status != null:
		if _locked:
			_status.text = "先に文を言ってください。"
		elif done:
			_status.text = "このクリーチャーにはすでに使いました。"
		elif blocked:
			_status.text = "このどうぶつには使えません。"
		else:
			_status.text = ""


func _side(card: Button, index: int) -> void:
	if card == null:
		return
	if _slots.size() < 2:
		card.visible = false
		return
	card.visible = true
	_paint_word_card(card, _slots[index])


## The whole look of a word card, wherever it sits in the row. Position is not a state: a
## card carries the same face, ring, text size, hover and press whether it is in the middle
## or beside it, and the only things that change it are what the word IS - already used on
## this creature, or not available for it.
func _paint_word_card(card: Button, slot) -> void:
	var category := _slot_category(slot)
	var done: bool = _used.has(category)
	var blocked := _blocked(category)
	# The tick colour stays, because "already used" is real information. Nothing else tells
	# one card from another - no accent ring on the middle one, because it is not a
	# selection, it is just the one in the middle.
	var face := UiKit.OK.darkened(0.55) if done else Color("#16233a")
	var edge := UiKit.OK if done else UiKit.PANEL_HI
	card.text = ("[x] " if done else "") + _slot_title(slot)
	card.add_theme_font_size_override("font_size", WORD_TEXT_SIZE)
	card.disabled = blocked
	card.modulate = Color.WHITE ## Never dimmed for sitting off centre.
	card.mouse_default_cursor_shape = \
		Control.CURSOR_ARROW if blocked else Control.CURSOR_POINTING_HAND
	for state in ["normal", "disabled"]:
		card.add_theme_stylebox_override(state, UiKit.stylebox(face, 14, 2, edge, 10))
	card.add_theme_stylebox_override("hover",
		UiKit.stylebox(face.lightened(0.14), 14, 2, UiKit.ACCENT, 10))
	card.add_theme_stylebox_override("pressed",
		UiKit.stylebox(face.darkened(0.18), 14, 2, UiKit.ACCENT, 10))
	card.add_theme_stylebox_override("focus",
		UiKit.stylebox(face, 14, 3, UiKit.GOLD, 10))
	card.add_theme_color_override("font_color", UiKit.TEXT)
	card.add_theme_color_override("font_disabled_color", UiKit.MUTED)
