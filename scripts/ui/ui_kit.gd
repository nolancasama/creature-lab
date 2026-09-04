class_name UiKit
extends RefCounted
## Shared look for every screen, built in code.
##
## Most of this UI cannot be laid out in the editor anyway - the Word Lab, the DNA Log
## and the animal grid are all generated from content files - so a code-built theme keeps
## one source of truth instead of a .tres theme that half the widgets ignore.

## Deep backdrop for every 2D screen outside the zoo. Keeping it below the panel palette
## makes controls, and the creature stages they lead into, carry the visual focus.
const BG := Color("#070c14")
const PANEL := Color("#16233a")
const PANEL_HI := Color("#1e3050")
const LINE := Color("#2c4468")
const ACCENT := Color("#4fd1ff")
const GOLD := Color("#ffd166")
const OK := Color("#6ee7a0")
const BAD := Color("#ff8080")
## Neutral navigation is deliberately separate from the navy choice cards. Back, carousel
## arrows and close/done controls should read as movement, never as lesson content.
const NAV := Color("#3a4c63")
const NAV_HOVER := Color("#52657a")
const NAV_PRESSED := Color("#29384b")
const NAV_DISABLED := Color("#263244")
const NAV_EDGE := Color("#71839a")
## Reserved for the one or two actions that actually move the lesson forward (Start, the
## mic). Everything else in the palette is chrome - ACCENT included, which is already the
## standing colour of headers and the progress line - so a call-to-action needs a colour
## that never appears anywhere else on screen.
const CTA := Color("#ff8c42")
const TEXT := Color("#e8f0fa")
const MUTED := Color("#93a6bf")
const INK := Color("#08111c")

const H1 := 46
const H2 := 30
const H3 := 22
const BODY := 18
const SMALL := 17
const MIN_TOUCH := 52


static func stylebox(bg: Color, radius := 12, border := 0, border_color := Color.TRANSPARENT, padding := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if border > 0:
		box.border_width_left = border
		box.border_width_right = border
		box.border_width_top = border
		box.border_width_bottom = border
		box.border_color = border_color
	box.content_margin_left = padding if padding > 0 else 14
	box.content_margin_right = padding if padding > 0 else 14
	box.content_margin_top = padding if padding > 0 else 10
	box.content_margin_bottom = padding if padding > 0 else 10
	return box


static func panel(bg := PANEL, radius := 14, border := 0, border_color := Color.TRANSPARENT, padding := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, radius, border, border_color, padding))
	return p


static func label(text: String, size := BODY, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size := H2, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func rich(text: String, size := BODY) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", TEXT)
	return r


static func button(text: String, size := BODY, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = MIN_TOUCH
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", size)
	style_button(b, PANEL_HI if not accent else ACCENT, accent)
	return b


static func style_button(b: Button, base: Color, accent := false) -> void:
	var text_color := INK if accent else TEXT
	b.add_theme_stylebox_override("normal", stylebox(base, 10))
	b.add_theme_stylebox_override("hover", stylebox(base.lightened(0.14), 10))
	b.add_theme_stylebox_override("pressed", stylebox(base.darkened(0.16), 10))
	b.add_theme_stylebox_override("focus", stylebox(base, 10, 3, GOLD))
	b.add_theme_stylebox_override("disabled", stylebox(base.darkened(0.45), 10))
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.3))


static func style_primary(b: Button) -> void:
	style_button(b, CTA, true)


static func style_navigation(b: Button) -> void:
	b.add_theme_stylebox_override("normal", stylebox(NAV, 10, 1, NAV_EDGE))
	b.add_theme_stylebox_override("hover", stylebox(NAV_HOVER, 10, 2, TEXT))
	b.add_theme_stylebox_override("pressed", stylebox(NAV_PRESSED, 10, 2, NAV_EDGE))
	b.add_theme_stylebox_override("focus", stylebox(NAV, 10, 3, GOLD))
	b.add_theme_stylebox_override("disabled", stylebox(NAV_DISABLED, 10, 1, LINE))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, TEXT)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.15))


static func style_secondary(b: Button) -> void:
	var face := Color("#101a2b")
	b.add_theme_stylebox_override("normal", stylebox(face, 10, 2, NAV_EDGE))
	b.add_theme_stylebox_override("hover", stylebox(NAV, 10, 2, TEXT))
	b.add_theme_stylebox_override("pressed", stylebox(face.darkened(0.16), 10, 2, NAV_EDGE))
	b.add_theme_stylebox_override("focus", stylebox(face, 10, 3, GOLD))
	b.add_theme_stylebox_override("disabled", stylebox(face.darkened(0.3), 10, 2, LINE))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, TEXT)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.15))


## A selected control keeps a dark choice-card face, gains a cyan ring, and also gains a
## check icon. The icon means selection never depends on colour perception alone.
static func style_choice(b: Button, selected: bool, base := PANEL_HI) -> void:
	var face: Color = Color("#173047") if selected else base
	var edge: Color = ACCENT if selected else LINE
	var width := 3 if selected else 1
	var original := str(b.get_meta("choice_text", b.text))
	b.set_meta("choice_text", original)
	b.text = ("[x] " if selected else "") + original
	b.add_theme_stylebox_override("normal", stylebox(face, 10, width, edge))
	b.add_theme_stylebox_override("hover", stylebox(face.lightened(0.12), 10,
		maxi(width, 2), ACCENT))
	b.add_theme_stylebox_override("pressed", stylebox(face.darkened(0.16), 10,
		maxi(width, 2), ACCENT))
	b.add_theme_stylebox_override("focus", stylebox(face, 10, 3, GOLD))
	b.add_theme_stylebox_override("disabled", stylebox(face.darkened(0.35), 10, width, edge))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, TEXT)
	b.add_theme_color_override("font_disabled_color", MUTED)


static func spacer(minimum := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(minimum, minimum)
	return c


static func expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func vbox(separation := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func line_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.focus_mode = Control.FOCUS_ALL
	e.custom_minimum_size.y = MIN_TOUCH
	e.add_theme_font_size_override("font_size", BODY)
	e.add_theme_stylebox_override("normal", stylebox(Color("#0b1220"), 10, 2, PANEL_HI))
	e.add_theme_stylebox_override("focus", stylebox(Color("#0b1220"), 10, 3, GOLD))
	e.add_theme_color_override("font_color", TEXT)
	return e


## Small square icon button for toolbar use.
static func icon_button(icon: String, size := 48) -> Button:
	var b := Button.new()
	b.text = icon
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(maxi(size, MIN_TOUCH), maxi(size, MIN_TOUCH))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", H2)
	style_navigation(b)
	return b


const GEAR_ICON := preload("res://ui/gear.svg")


## The Teacher Settings gear, identical on every screen that offers one. Callers position
## it and connect `pressed`; everything about how it looks lives here so the screens cannot
## drift apart.
##
## A drawn gear, not the "⚙" character: the export bundles only Godot's default font, which
## has no U+2699, and the web build has no system font to fall back on the way the desktop
## editor silently did - so the glyph arrived as a tofu box of hex digits. Same trap the
## pair separator hit; see the note in word_lab.gd.
##
## The gear alone, with no plate behind it. icon_button's panel-coloured box is right for
## the back arrow, which sits on flat 2D chrome, but this one sits over a lit 3D stage and
## read as a floating tile there. Feedback moves onto the icon itself so it still answers a
## hover and a press without a box to draw them on.
static func gear_button(size := 70) -> Button:
	var gear := icon_button("", size)
	gear.name = "SettingsGear"
	gear.icon = GEAR_ICON
	gear.expand_icon = true
	for state in ["normal", "hover", "pressed", "disabled"]:
		gear.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	gear.add_theme_stylebox_override("focus", stylebox(Color.TRANSPARENT, 12, 3, GOLD, 2))
	gear.tooltip_text = "先生用設定"
	gear.add_theme_color_override("icon_normal_color", TEXT)
	gear.add_theme_color_override("icon_hover_color", ACCENT)
	gear.add_theme_color_override("icon_pressed_color", ACCENT)
	return gear


## Full-screen background wash used by the 2D screens.
static func backdrop() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = BG
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
