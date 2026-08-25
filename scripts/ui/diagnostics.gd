class_name Diagnostics
extends RefCounted
## A short history of what the speech path just did, readable without a developer console.
##
## The console is not reachable in practice on the machines this runs on. A Godot web export
## takes the keyboard, so Ctrl+Shift+J never gets to Chrome, and on a Chromebook the menu
## route is a hunt. Meanwhile the only interesting failures - a transcript dropped after a
## cancel, a sentence refused for one of five reasons, a take filed into the wrong slot -
## happen in the browser and nowhere else, so "just read the console" was the one instruction
## that could not be followed.
##
## So the same lines go to both: print() for anyone who does have a console, and this ring
## buffer for the on-screen panel. Off by default; a teacher turns it on from the gear.

const CAPACITY := 14 ## About what fits on screen without covering the game.

static var lines: PackedStringArray = PackedStringArray()


## Record one line. Prefixed by area so a glance separates speech from voice capture.
static func note(area: String, text: String) -> void:
	var line := "%s %s" % [area, text]
	print(line) ## Still goes to the console for anyone who can open one.
	lines.append(line)
	while lines.size() > CAPACITY:
		lines.remove_at(0)


static func clear() -> void:
	lines.clear()
