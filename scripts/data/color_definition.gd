class_name ColorDefinition
extends Resource
## A colour word plus the swatch shown in the Word Lab and painted onto the creature.

@export var word: String = ""
@export var color: Color = Color.WHITE


static func from_dict(d: Dictionary) -> ColorDefinition:
	var c := ColorDefinition.new()
	c.word = str(d.get("word", ""))
	c.color = Color.html(str(d.get("hex", "#ffffff")))
	return c


## Colour words are the only vocabulary a student reads off a swatch rather than a
## picture, so the label needs to stay legible on top of the swatch itself.
func label_color() -> Color:
	return Color("#12161f") if color.get_luminance() > 0.45 else Color("#f2f6fb")
