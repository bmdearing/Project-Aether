extends Control
class_name NotchedBar
## Drawn over the XP bar: a notch every 5% (heavier every 20%) and a thin
## gold line along the top edge. Mouse-transparent.

const DIVISIONS := 20
const MAJOR_EVERY := 4

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	for i in range(1, DIVISIONS):
		var x: float = size.x * i / float(DIVISIONS)
		var major := i % MAJOR_EVERY == 0
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(0, 0, 0, 0.9 if major else 0.6), 2.0 if major else 1.0)
	draw_line(Vector2.ZERO, Vector2(size.x, 0.0), AetherStyle.GOLD_DIM, 1.0)
