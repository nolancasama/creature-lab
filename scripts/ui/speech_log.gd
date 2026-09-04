class_name SpeechLog
extends Control
## The diagnostic lines, on screen, because the browser console is not reachable here.
##
## Lives on the global debug layer rather than inside a scene, so it survives every screen
## change - the interesting sequence spans the recording screen and the transformation, and
## a panel that died with its scene would lose exactly the handover being investigated.
##
## Bottom-left, deliberately: the gear is top-right, the animal is centred, and the console
## sits along the bottom middle. This is the one corner nothing else wants.

const WIDTH := 560.0
const MARGIN := 12.0

var _body: RichTextLabel = null


func _ready() -> void:
	name = "SpeechLog"
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE ## Never eats a tap meant for the game.
	var panel := UiKit.panel(Color(0.03, 0.06, 0.1, 0.86), 10, 2, UiKit.ACCENT, 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = MARGIN
	panel.offset_right = MARGIN + WIDTH
	panel.offset_top = -300.0
	panel.offset_bottom = -MARGIN
	add_child(panel)

	_body = UiKit.rich("", UiKit.SMALL)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Every line wraps to two or three at this width, so the buffer has always been taller
	# than the panel - and a label that simply overflows loses the BOTTOM, which is the
	# newest line and the only one anybody reads. Following the tail keeps the most recent
	# event on screen and lets the old ones fall off the top, where they belong.
	_body.scroll_active = true
	_body.scroll_following = true
	panel.add_child(_body)


func _process(_delta: float) -> void:
	visible = Settings.speech_log
	if not visible or _body == null:
		return
	# Rebuilt from the buffer each frame rather than appended to: the buffer is a ring, so
	# tracking what changed would cost more than redrawing fourteen short lines.
	_body.text = "\n".join(Diagnostics.lines)
