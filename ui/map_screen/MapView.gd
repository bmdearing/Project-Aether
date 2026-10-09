extends Control
class_name MapView
## Pure rendering surface for MapScreen.gd - draws the current MapGraph
## as a room grid connected by lines, colored by role (start/vault/
## normal) with the player's current room outlined. Kept as its own
## scripted Control (not just a signal handler on a plain node) since
## _draw() has to live on the Control actually being drawn.

const CELL_PIXELS := 48.0
const ROOM_SIZE := 34.0
const CONNECTION_COLOR := Color(0.55, 0.45, 0.28, 0.9)
const NORMAL_COLOR := Color(0.16, 0.19, 0.28)
const START_COLOR := Color(0.45, 0.86, 1.0)
const VAULT_COLOR := Color(0.9, 0.75, 0.2)
const PLAYER_MARKER_COLOR := Color(1, 1, 1)

var graph: MapGraph
var player_cell: Vector2i = Vector2i(-999, -999)
## Player position in cells (fractional) and body yaw, for the arrow.
var player_pos := Vector2(NAN, NAN)
var player_yaw := 0.0

func render(new_graph: MapGraph, new_player_cell: Vector2i, new_player_pos: Vector2 = Vector2(NAN, NAN), yaw: float = 0.0) -> void:
	graph = new_graph
	player_cell = new_player_cell
	player_pos = new_player_pos
	player_yaw = yaw
	queue_redraw()

func _draw() -> void:
	if graph == null:
		return
	var center := size / 2.0

	# Connections first, so room squares draw on top of the lines meeting them.
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		var pos := center + Vector2(cell.x, cell.y) * CELL_PIXELS
		for neighbor in room.connections:
			var npos := center + Vector2(neighbor.x, neighbor.y) * CELL_PIXELS
			draw_line(pos, npos, CONNECTION_COLOR, 3.0)

	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		var pos := center + Vector2(cell.x, cell.y) * CELL_PIXELS
		var color := NORMAL_COLOR
		if room.is_start:
			color = START_COLOR
		elif room.is_vault:
			color = VAULT_COLOR
		var rect := Rect2(pos - Vector2(ROOM_SIZE, ROOM_SIZE) / 2.0, Vector2(ROOM_SIZE, ROOM_SIZE))
		draw_rect(rect, color)
		if cell == player_cell:
			draw_rect(rect.grow(4.0), PLAYER_MARKER_COLOR, false, 3.0)
	if not is_nan(player_pos.x):
		_draw_player_arrow(center + player_pos * CELL_PIXELS)
	_draw_cardinals()

## North is up (-Z), east right (+X), as on the compass and minimap.
func _draw_cardinals() -> void:
	var font := AetherStyle.title()
	var px := 20
	for entry in [["N", Vector2(size.x / 2.0, 18.0)], ["S", Vector2(size.x / 2.0, size.y - 6.0)], ["W", Vector2(14.0, size.y / 2.0 + 7.0)], ["E", Vector2(size.x - 14.0, size.y / 2.0 + 7.0)]]:
		var text: String = entry[0]
		var at: Vector2 = entry[1]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, at - Vector2(w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, AetherStyle.GOLD_BRIGHT if text == "N" else AetherStyle.GOLD)
	# Small rose in the top-right corner.
	var c := Vector2(size.x - 34.0, 34.0)
	draw_arc(c, 18.0, 0.0, TAU, 32, AetherStyle.GOLD_DIM, 1.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16), c + Vector2(4, 0), c + Vector2(-4, 0)]), AetherStyle.GOLD_BRIGHT)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 16), c + Vector2(4, 0), c + Vector2(-4, 0)]), AetherStyle.GOLD_FAINT)

func _draw_player_arrow(c: Vector2) -> void:
	var forward := Vector2(-sin(player_yaw), -cos(player_yaw))
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([c + forward * 10.0, c - forward * 6.0 + side * 7.0, c - forward * 2.5, c - forward * 6.0 - side * 7.0]), Color.WHITE)
