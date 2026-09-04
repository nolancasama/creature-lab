extends Node
## Root of the running game. Owns the scene container, the transition fade and the debug
## layer, then gets out of the way - every feature lives in its own scene controller.

const SETTINGS_SCENE := preload("res://scenes/TeacherSettings.tscn")

var scene_root: Node = null
var fade: ColorRect = null
var debug_overlay: Control = null

var _settings_layer: CanvasLayer = null
var _settings: Control = null


func _ready() -> void:
	_register_actions()
	_build_layers()

	# Connected once, here, for the life of the game: the overlay itself is built and freed
	# per opening, so nothing accumulates across repeated visits to settings.
	Game.settings_opened.connect(_open_settings)
	Game.settings_closed.connect(_close_settings)

	# Open on animal selection instead of the title screen: it was one tap between the
	# student and the game, carrying nothing they needed. Set before attach, not with
	# set_phase() after, so the router opens straight onto selection rather than fading
	# through a title nobody is meant to see. The harness drives its own phases and must
	# find the FSM where it expects it.
	if not DevHarness.is_requested():
		Game.phase = Game.Phase.ANIMAL_SELECTION
	Router.attach(scene_root, fade)
	# Before anything is picked: get the driver to compile the trait effects' shaders
	# while the animal picker is up, not when a student taps HOT or COLD. See ShaderWarmup
	# for the measurements - on the web renderer this is the difference between a first
	# HOT pick taking ten seconds and taking a frame.
	var warmup := ShaderWarmup.run(self)
	# Those warmup frames block, so the picker underneath spends the first seconds of a
	# session stuttering. Cover it with the splash until the warmup says it is done. Not
	# under the harness: it would sit over every --shot= capture and every driven test.
	if not DevHarness.is_requested():
		LoadingScreen.show_over(self, warmup)
	DevHarness.run_if_requested(self)


## Input actions are registered here rather than in project.godot: the file format for
## input events is fiddly to hand-author and this keeps the bindings visible in code.
func _register_actions() -> void:
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

	# Above the router's fade and the loading splash, below the debug layers, so settings
	# covers the game completely but F3 diagnostics still sit on top of it.
	_settings_layer = CanvasLayer.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.layer = 58
	add_child(_settings_layer)

	var debug_layer := CanvasLayer.new()
	debug_layer.name = "DebugLayer"
	debug_layer.layer = 60
	add_child(debug_layer)

	debug_overlay = DebugOverlay.new()
	debug_overlay.visible = false
	debug_layer.add_child(debug_overlay)

	# Its own panel rather than part of DebugOverlay: that one is gated on a debug build and
	# toggled with F3, neither of which is available in an exported game on a Chromebook.
	debug_layer.add_child(SpeechLog.new())


## Mount settings above the running screen and freeze that screen in place.
##
## PROCESS_MODE_DISABLED rather than a transparent input-blocker: it stops _process,
## _unhandled_input, timers and tweens across the whole gameplay subtree in one move, so
## neither a tap nor a key can reach the game underneath and the turntable stops turning
## instead of spinning behind an opaque panel. Autoloads are untouched, so audio and the
## save service keep working normally.
func _open_settings() -> void:
	if _settings != null:
		return
	# The screen used to be freed here, and _exit_tree() cancelled any live microphone
	# session on the way out. Nothing leaves the tree now, so a student who had tapped the
	# mic just before the gear would otherwise still be recorded behind the panel.
	Speech.cancel()
	if is_instance_valid(Router.current_scene):
		Router.current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	_settings = SETTINGS_SCENE.instantiate()
	_settings_layer.add_child(_settings)


func _close_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
	if is_instance_valid(Router.current_scene):
		Router.current_scene.process_mode = Node.PROCESS_MODE_INHERIT


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and Settings.debug_mode:
		debug_overlay.visible = not debug_overlay.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		Settings.fullscreen = not Settings.fullscreen
		Settings.save_settings()
		get_viewport().set_input_as_handled()
