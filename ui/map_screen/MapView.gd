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

func render(new_graph: MapGraph, new_player_cell: Vector2i) -> void:
	graph = new_graph
	player_cell = new_player_cell
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
