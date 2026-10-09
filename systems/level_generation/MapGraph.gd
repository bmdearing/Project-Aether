extends RefCounted
class_name MapGraph
## Pure-data room-and-connection graph for a generated Map - no Node3D,
## no geometry. Separated from GeneratedMap.gd (which turns this into
## walls/floors) so the generation algorithm can be tested in isolation.
##
## Algorithm: randomized Prim's-style spanning-tree growth from a start
## cell on a fixed grid - guarantees reachability while branching
## organically. Not doc-sourced, a standard roguelike technique.

const GRID_SIZE := 5
const ROOM_COUNT_MIN := 7
const ROOM_COUNT_MAX := 10
## Chance to drop a cell from the growth frontier once it's produced a
## child, instead of leaving it available to branch again - lower values
## produce longer winding corridors, higher values produce bushier/more
## branching layouts with more dead ends.
const BRANCH_STOP_CHANCE := 0.35

class RoomData:
	var cell: Vector2i
	var is_start: bool = false
	var is_vault: bool = false
	var distance_from_start: int = 0
	var connections: Array[Vector2i] = []

var rooms: Dictionary = {}  # Vector2i -> RoomData
var start_cell: Vector2i
var vault_cell: Vector2i
var grid_size: int = GRID_SIZE
var branch_stop_chance: float = BRANCH_STOP_CHANCE

static func generate(room_count: int = -1, size: int = GRID_SIZE, count_range: Vector2i = Vector2i(ROOM_COUNT_MIN, ROOM_COUNT_MAX), branch_stop: float = BRANCH_STOP_CHANCE) -> MapGraph:
	var graph := MapGraph.new()
	graph.grid_size = size
	graph.branch_stop_chance = branch_stop
	if room_count <= 0:
		room_count = randi_range(count_range.x, count_range.y)
	room_count = min(room_count, size * size)
	graph.start_cell = Vector2i(size / 2, size / 2)
	graph._carve(room_count)
	graph._assign_special_rooms()
	return graph

## Every cell of a size x size grid, each joined to all its neighbours - one
## open area. Start is the middle of a random edge, so the far side is the Vault.
static func generate_full_grid(size: int) -> MapGraph:
	var graph := MapGraph.new()
	graph.grid_size = size
	for x in size:
		for y in size:
			var room := RoomData.new()
			room.cell = Vector2i(x, y)
			graph.rooms[room.cell] = room
	for cell in graph.rooms:
		for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = cell + dir
			if graph.rooms.has(n):
				graph.rooms[cell].connections.append(n)
				graph.rooms[n].connections.append(cell)
	var edges := [Vector2i(size / 2, 0), Vector2i(size / 2, size - 1), Vector2i(0, size / 2), Vector2i(size - 1, size / 2)]
	graph.start_cell = edges[randi() % edges.size()]
	graph.rooms[graph.start_cell].is_start = true
	# Grid distance from the start (BFS == Manhattan here).
	for cell in graph.rooms:
		var d: Vector2i = cell - graph.start_cell
		graph.rooms[cell].distance_from_start = absi(d.x) + absi(d.y)
	graph._assign_special_rooms()
	return graph

## Named has_connection(), not is_connected() - Object already declares a
## built-in is_connected(signal, callable), and overriding it incompatibly
## is a hard compile error.
func has_connection(a: Vector2i, b: Vector2i) -> bool:
	return rooms.has(a) and rooms[a].connections.has(b)

## BFS reachability check from start_cell, used by tests.
func all_rooms_reachable() -> bool:
	var visited := {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for neighbor in rooms[current].connections:
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited.size() == rooms.size()

func _carve(room_count: int) -> void:
	var start_room := RoomData.new()
	start_room.cell = start_cell
	start_room.is_start = true
	rooms[start_cell] = start_room

	var frontier: Array[Vector2i] = [start_cell]
	while rooms.size() < room_count and not frontier.is_empty():
		var idx := randi() % frontier.size()
		var current: Vector2i = frontier[idx]
		var candidates := _unvisited_neighbors(current)
		if candidates.is_empty():
			frontier.remove_at(idx)
			continue
		var next: Vector2i = candidates[randi() % candidates.size()]

		var room := RoomData.new()
		room.cell = next
		room.distance_from_start = rooms[current].distance_from_start + 1
		rooms[next] = room
		rooms[current].connections.append(next)
		room.connections.append(current)
		frontier.append(next)

		if randf() < branch_stop_chance:
			frontier.remove_at(idx)

func _unvisited_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = cell + dir
		if n.x >= 0 and n.x < grid_size and n.y >= 0 and n.y < grid_size and not rooms.has(n):
			result.append(n)
	return result

## Vault = the room with the greatest graph distance from start: the boss
## room (GeneratedMap). One per map.
func _assign_special_rooms() -> void:
	var farthest: Vector2i = start_cell
	var farthest_dist := -1
	for cell in rooms:
		var d: int = rooms[cell].distance_from_start
		if d > farthest_dist:
			farthest_dist = d
			farthest = cell
	vault_cell = farthest
	rooms[vault_cell].is_vault = true
