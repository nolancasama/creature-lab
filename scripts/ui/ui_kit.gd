class_name UiKit
extends RefCounted
## Shared look for every screen, built in code.
##
## Most of this UI cannot be laid out in the editor anyway - the Word Lab, the DNA Log
## and the animal grid are all generated from content files - so a code-built theme keeps
## one source of truth instead of a .tres theme that half the widgets ignore.

const BG := Color("#0e1622")
const PANEL := Color("#16233a")
const PANEL_HI := Color("#1e3050")
const LINE := Color("#2c4468")
const ACCENT := Color("#4fd1ff")
const GOLD := Color("#ffd166")
const OK := Color("#6ee7a0")
const BAD := Color("#ff8080")
const TEXT := Color("#e8f0fa")
const MUTED := Color("#93a6bf")

const H1 := 46
const H2 := 30
const H3 := 22
const BODY := 18
const SMALL := 15


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
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	style_button(b, PANEL_HI if not accent else ACCENT, accent)
	return b


static func style_button(b: Button, base: Color, accent := false) -> void:
	var text_color := Color("#08111c") if accent else TEXT
	b.add_theme_stylebox_override("normal", stylebox(base, 10))
	b.add_theme_stylebox_override("hover", stylebox(base.lightened(0.14), 10))
	b.add_theme_stylebox_override("pressed", stylebox(base.darkened(0.16), 10))
	b.add_theme_stylebox_override("focus", stylebox(Color.TRANSPARENT, 10))
	b.add_theme_stylebox_override("disabled", stylebox(base.darkened(0.45), 10))
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.3))


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
	e.add_theme_font_size_override("font_size", BODY)
	e.add_theme_stylebox_override("normal", stylebox(Color("#0b1220"), 10, 2, PANEL_HI))
	e.add_theme_stylebox_override("focus", stylebox(Color("#0b1220"), 10, 2, ACCENT))
	e.add_theme_color_override("font_color", TEXT)
	return e


## Small square icon button for toolbar use.
static func icon_button(icon: String, size := 48) -> Button:
	var b := Button.new()
	b.text = icon
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_font_size_override("font_size", H2)
	style_button(b, PANEL_HI, false)
	return b


## Full-screen background wash used by the 2D screens.
static func backdrop() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = BG
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
