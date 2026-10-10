extends RefCounted
class_name MapLayout
## Layout rules for one Figment type, picked by its MapTileset.layout:
##   ROOMS      - Dungeon: rooms of varied size joined by walled corridors,
##                pillared halls, the boss in a large flat arena.
##   OPEN_FIELD - Dunes: one open field, no interior walls, dune mounds,
##                packs scattered over it, the boss on a raised crest.
##   CANYON     - Badlands: open basins joined by narrowed passes between
##                jagged cliffs, rock spires for cover, the boss on a mesa.
## Each style then reshapes its kind through MapTileset's Layout fields (room
## sizes, how winding the graph is, corridor width, pillars, mounds, cliffs),
## so two styles of one kind don't play the same.
## Every layout still produces a MapGraph (cells + connections) so the Map
## screen, spawning and portals work the same way.

enum Kind { ROOMS, OPEN_FIELD, CANYON }

var kind: Kind = Kind.ROOMS
var cell_size: float = GeneratedMap.CELL_SIZE
var grid_size: int = 5
var room_count: Vector2i = Vector2i(7, 10)
var branch_stop_chance: float = 0.35
## Enemy packs per non-start cell (min, max).
var packs_per_cell: Vector2i = Vector2i(1, 1)
## Loose doodads scattered per cell (open layouts only; rooms use RoomDresser).
var scatter_per_cell: Vector2i = Vector2i(0, 0)

## Rooms only.
var room_size: Vector2 = GeneratedMap.ROOM_SIZE
var boss_room_size: float = GeneratedMap.BOSS_ROOM_SIZE
var corridor_width: float = GeneratedMap.CORRIDOR_WIDTH
var wall_height: float = GeneratedMap.WALL_HEIGHT
var pillar_chance: float = GeneratedMap.PILLAR_CHANCE
var cave_walls: bool = false
## Open fields and canyons.
var mounds_per_cell: Vector2i = TerrainBuilder.MOUNDS_PER_CELL
var mound_scale: float = 1.0
var pass_width_scale: float = 1.0
var cliff_height_scale: float = 1.0
var rivers: int = 0
var streams: int = 0

## Space kept for the corridor between the biggest room and the boss room.
const MIN_CORRIDOR := 4.0

const KIND_BY_NAME := {"rooms": Kind.ROOMS, "open_field": Kind.OPEN_FIELD, "canyon": Kind.CANYON}

static func for_tileset(tileset: MapTileset) -> MapLayout:
	var layout_name := tileset.layout if tileset else "rooms"
	var l := create(KIND_BY_NAME.get(layout_name, Kind.ROOMS))
	if tileset:
		l._apply_style(tileset)
	return l

func _apply_style(t: MapTileset) -> void:
	if t.scatter_scale != 1.0:
		scatter_per_cell = Vector2i(roundi(scatter_per_cell.x * t.scatter_scale), roundi(scatter_per_cell.y * t.scatter_scale))
	if t.grid_size > 0:
		grid_size = t.grid_size
	if t.room_count.x > 0:
		room_count = t.room_count
	if t.branch_stop_chance >= 0.0:
		branch_stop_chance = t.branch_stop_chance
	if t.cell_size > 0.0:
		cell_size = t.cell_size
	if t.room_size.x > 0.0:
		room_size = t.room_size
	if t.corridor_width > 0.0:
		corridor_width = t.corridor_width
	if t.wall_height > 0.0:
		wall_height = t.wall_height
	if t.pillar_chance >= 0.0:
		pillar_chance = t.pillar_chance
	cave_walls = t.cave_walls
	if t.mounds_per_cell.x >= 0:
		mounds_per_cell = t.mounds_per_cell
	mound_scale = t.mound_scale
	pass_width_scale = t.pass_width_scale
	cliff_height_scale = t.cliff_height_scale
	rivers = t.rivers
	streams = t.streams
	if kind == Kind.ROOMS:
		# The boss room outgrows the style's biggest room; cells stay wide
		# enough for a corridor between the two.
		boss_room_size = clampf(room_size.y + 5.0, 20.0, 32.0)
		cell_size = maxf(cell_size, (boss_room_size + room_size.y) / 2.0 + MIN_CORRIDOR)

static func create(layout_kind: Kind) -> MapLayout:
	var l := MapLayout.new()
	l.kind = layout_kind
	match layout_kind:
		Kind.OPEN_FIELD:
			l.cell_size = 28.0
			l.grid_size = 4
			l.packs_per_cell = Vector2i(1, 2)
			l.scatter_per_cell = Vector2i(4, 7)
		Kind.CANYON:
			l.cell_size = 26.0
			l.grid_size = 5
			l.room_count = Vector2i(6, 8)
			l.branch_stop_chance = 0.5
			l.packs_per_cell = Vector2i(1, 2)
			l.scatter_per_cell = Vector2i(3, 5)
	return l

func generate_graph() -> MapGraph:
	if kind == Kind.OPEN_FIELD:
		return MapGraph.generate_full_grid(grid_size)
	return MapGraph.generate(-1, grid_size, room_count, branch_stop_chance)
