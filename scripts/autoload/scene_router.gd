extends Node
## Swaps the scene shown inside Main/SceneRoot in response to Game.phase_changed.
##
## TRANSFORMATION maps to the lab on purpose. The spec listed it as its own scene, but
## the animal is supposed to *walk into* the chamber that is standing in the lab -
## teleporting to a fresh scene at that exact moment would break the one beat the whole
## design is built around. Same scene path = no reload, the lab just changes gear.

## Phase -> scene path. Built at runtime because autoload enums are not constant
## expressions at parse time.
var scenes := {}

var current_scene: Node = null

var _container: Node = null
var _fade: ColorRect = null
var _current_path := ""
var _target_path := ""
var _swapping := false


func _ready() -> void:
	scenes = {
		Game.Phase.TITLE: "res://scenes/TitleScreen.tscn",
		Game.Phase.ANIMAL_SELECTION: "res://scenes/AnimalSelection.tscn",
		Game.Phase.CREATURE_LAB: "res://scenes/CreatureLab.tscn",
		Game.Phase.TRANSFORMATION: "res://scenes/CreatureLab.tscn",
		Game.Phase.NAMING: "res://scenes/NamingScreen.tscn",
		Game.Phase.ZOO: "res://scenes/Zoo.tscn",
		Game.Phase.TEACHER_SETTINGS: "res://scenes/TeacherSettings.tscn",
	}


func attach(container: Node, fade: ColorRect) -> void:
	_container = container
	_fade = fade
	Game.phase_changed.connect(_on_phase_changed)
	_swap(str(scenes.get(Game.phase, "")), false)


func _on_phase_changed(next: int, _previous: int) -> void:
	_swap(str(scenes.get(next, "")), true)


## A swap takes two fades to finish, and phases can change during them (the debug jump
## does exactly that). Rather than dropping those requests, the newest target is recorded
## and the in-flight swap keeps going until it has caught up.
func _swap(path: String, animate: bool) -> void:
	if path.is_empty() or _container == null:
		return
	_target_path = path
	if _swapping:
		return
	_swapping = true
	var fade_in := animate
	while _target_path != _current_path or not is_instance_valid(current_scene):
		var next_path := _target_path
		if fade_in:
			await _fade_to(1.0, 0.16)
		if is_instance_valid(current_scene):
			current_scene.queue_free()
			current_scene = null
		var packed: PackedScene = load(next_path)
		if packed == null:
			push_error("Router could not load %s" % next_path)
			break
		current_scene = packed.instantiate()
		_container.add_child(current_scene)
		_current_path = next_path
		await _fade_to(0.0, 0.22)
		fade_in = true
	_swapping = false


func _fade_to(alpha: float, duration: float) -> void:
	if _fade == null:
		return
	_fade.visible = alpha > 0.001 or _fade.color.a > 0.001
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, duration)
	await tween.finished
	_fade.visible = alpha > 0.001
