extends Control
class_name NotchedBar
## Draws interior tick marks over a bar every 1/DIVISIONS of its width -
## used by the XP bar to mark each 10% of progress. Purely decorative,
## drawn on top of the bar's own background/fill (mouse-transparent).

const DIVISIONS := 10
const NOTCH_COLOR := Color(0, 0, 0, 0.5)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	for i in range(1, DIVISIONS):
		var x: float = size.x * i / float(DIVISIONS)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), NOTCH_COLOR, 1.0)
