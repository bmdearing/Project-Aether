extends Control
class_name Compass
## Heading strip across the top of the screen: cardinal and intercardinal
## letters and degree ticks slide past as the player turns. North is -Z,
## east +X, matching the minimap and the Map screen.

const WIDTH := 460.0
const HEIGHT := 30.0
const TOP := 8.0
## Degrees visible either side of the heading.
const HALF_SPAN := 75.0
const LETTERS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = TOP
	offset_bottom = TOP + HEIGHT

## Heading in degrees clockwise from north for a body yaw.
static func heading_of(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var heading := heading_of(player.global_rotation.y)
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0, 0, 0, 0.45))
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), AetherStyle.GOLD_DIM, 1.0)
	var font := AetherStyle.title()
	var numbers := AetherStyle.numbers()
	for d in range(0, 360, 15):
		var offset := wrapf(d - heading, -180.0, 180.0)
		if absf(offset) > HALF_SPAN:
			continue
		var x := size.x / 2.0 + offset / HALF_SPAN * (size.x / 2.0 - 12.0)
		var fade := 1.0 - absf(offset) / HALF_SPAN * 0.7
		if LETTERS.has(d):
			var text: String = LETTERS[d]
			var big := d % 90 == 0
			var px := 17 if big else 13
			var color := (AetherStyle.GOLD_BRIGHT if d == 0 else (AetherStyle.TEXT if big else AetherStyle.TEXT_DIM))
			color.a *= fade
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_string(font, Vector2(x - w / 2.0, size.y - 9.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		else:
			draw_line(Vector2(x, size.y - 8.0), Vector2(x, size.y - 2.0), Color(AetherStyle.GOLD_DIM, fade), 1.0)
			var label := str(d)
			var w := numbers.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(numbers, Vector2(x - w / 2.0, 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(AetherStyle.TEXT_DIM, 0.6 * fade))
	# Centre pointer.
	var c := size.x / 2.0
	draw_colored_polygon(PackedVector2Array([Vector2(c - 5, size.y), Vector2(c + 5, size.y), Vector2(c, size.y - 6)]), AetherStyle.AETHER)
