class_name LoadingScreen
extends CanvasLayer
## The splash held over the first seconds of a session, while the driver compiles the
## trait shaders.
##
## It is not covering a download. The game is already running underneath: main.gd opens
## straight onto the animal picker, and ShaderWarmup then spends fourteen frames drawing
## one of every particle and material variant so the driver compiles them here instead of
## mid-lesson. Under the web renderer those frames BLOCK - see ShaderWarmup for the
## measurements, where a cold HOT pick cost 9.8 seconds - so what a student used to see
## was the picker, already up, stuttering. This holds a finished-looking screen over that
## instead of a janky live one.
##
## Held until the warmup actually says it is done rather than for a set time. The compile
## cost is whatever a given machine's driver makes it, and the Chromebooks in one
## classroom do not agree on that; a timer would be wrong on most of them. MINIMUM and
## MAXIMUM only stop the two bad ends: a flash too short to read as intentional, and a
## wait long enough to look hung.

const MINIMUM := 1.2 ## Below this the splash reads as a glitch rather than a screen.
## Nothing measured should reach this. It exists so a machine whose driver stalls far
## past the measured costs still gets into the game rather than sitting on the art.
const MAXIMUM := 8.0
const FADE_OUT := 0.45

const SPLASH := preload("res://ui/splash.jpg")
const LOADING_TEXT := "じゅんびちゅう"

const DOT_COUNT := 3
const DOT_SIZE := 14.0
const DOT_GAP := 14.0
const DOT_CYCLE := 1.05 ## One full travel of the pulse across the row.
const DOT_DIM := 0.28

var _root: Control = null
var _dots: Array[Panel] = []
var _elapsed := 0.0
var _warm := false
var _closing := false


## `warmup` may be null - headless, or nothing to compile - which counts as already warm.
static func show_over(host: Node, warmup: ShaderWarmup) -> LoadingScreen:
	var screen := LoadingScreen.new()
	screen._warm = warmup == null
	host.add_child(screen)
	if warmup != null:
		warmup.finished.connect(screen._on_warm)
	return screen


func _ready() -> void:
	name = "LoadingScreen"
	# Above the router's fade (50), below the debug layers (60). The game fading in behind
	# this must not show through, and F3 diagnostics must still sit on top of it.
	layer = 55
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Stops every tap and click reaching the picker that is already live underneath.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var art := TextureRect.new()
	art.texture = SPLASH
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Covered, not scaled to fit: the art is 3:2 and the viewport expands with the window,
	# so fitting would letterbox it against a colour the art does not have.
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DOT_GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Low enough to sit on the dark floor rather than across the lit platform rim, which is
	# the busiest band in the art and the one place the caption loses contrast.
	row.offset_top = -68
	row.offset_bottom = -22
	row.offset_left = -220
	row.offset_right = 220
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(row)

	var label := UiKit.label(LOADING_TEXT, UiKit.H3, UiKit.TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The art behind the caption is dark but not uniformly so; an outline keeps the word
	# readable wherever the crop happens to put it.
	label.add_theme_color_override("font_outline_color", UiKit.INK)
	label.add_theme_constant_override("outline_size", 6)
	row.add_child(label)

	# Deliberately three plain panels rather than a spinner texture or a shader: this
	# screen exists because shader variants are still compiling, and an indicator that
	# introduced one of its own would stall on the very frame it is meant to cover.
	for i in DOT_COUNT:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel",
			UiKit.stylebox(UiKit.ACCENT, int(DOT_SIZE / 2.0)))
		row.add_child(dot)
		_dots.append(dot)


## Driven from _process rather than a Tween on purpose. The compile stalls block the main
## thread, so no animation can stay smooth through them; what this buys is that the dots
## resume from wherever the clock actually is instead of from wherever a tween was
## interrupted. A stutter that keeps moving reads as working - a spinner that freezes
## reads as crashed, which is the whole reason this is dots.
func _process(delta: float) -> void:
	_elapsed += delta
	var phase := fmod(_elapsed, DOT_CYCLE) / DOT_CYCLE
	for i in _dots.size():
		var offset := float(i) / float(max(_dots.size(), 1))
		var wave := 0.5 + 0.5 * sin(TAU * (phase - offset))
		_dots[i].modulate.a = lerpf(DOT_DIM, 1.0, pow(wave, 3.0))

	if _closing:
		return
	if _elapsed < MINIMUM:
		return
	if _warm or _elapsed >= MAXIMUM:
		_close()


func _on_warm() -> void:
	_warm = true


func _close() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(queue_free)
