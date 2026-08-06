extends Node
## Root of the running game. Owns the scene container, the transition fade and the debug
## layer, then gets out of the way - every feature lives in its own scene controller.

var scene_root: Node = null
var fade: ColorRect = null
var debug_overlay: Control = null


func _ready() -> void:
	_register_actions()
	_build_layers()
	Router.attach(scene_root, fade)
	DevHarness.run_if_requested(self)


## Input actions are registered here rather than in project.godot: the file format for
## input events is fiddly to hand-author and this keeps the bindings visible in code.
func _register_actions() -> void:
	_bind("push_to_talk", KEY_SPACE)
	_bind("toggle_debug", KEY_F3)
	_bind("toggle_fullscreen", KEY_F11)
	_bind("back", KEY_ESCAPE)


func _bind(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _build_layers() -> void:
	scene_root = Node.new()
	scene_root.name = "SceneRoot"
	add_child(scene_root)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 50
	add_child(overlay)

	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade)

	var debug_layer := CanvasLayer.new()
	debug_layer.name = "DebugLayer"
	debug_layer.layer = 60
	add_child(debug_layer)

	debug_overlay = DebugOverlay.new()
	debug_overlay.visible = false
	debug_layer.add_child(debug_overlay)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and Settings.debug_mode:
		debug_overlay.visible = not debug_overlay.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		Settings.fullscreen = not Settings.fullscreen
		Settings.save_settings()
		get_viewport().set_input_as_handled()
