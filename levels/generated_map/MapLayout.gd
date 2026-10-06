extends RefCounted
class_name MapLayout
## Layout rules for one Figment type, picked by its MapTileset.layout:
##   ROOMS      - Dungeon: walled rooms on a grid, doorways, the Vault's jump gap.
##   OPEN_FIELD - Dunes: one open field, no interior walls, dune mounds,
##                packs scattered over it, the boss on a raised crest.
##   CANYON     - Badlands: open basins joined by narrowed passes between
##                jagged cliffs, rock spires for cover, the boss on a mesa.
## Every layout still produces a MapGraph (cells + connections) so the Map
## screen, spawning and portals work the same way.

enum Kind { ROOMS, OPEN_FIELD, CANYON }

var kind: Kind = Kind.ROOMS
var cell_size: float = 16.0
var grid_size: int = 5
var room_count: Vector2i = Vector2i(7, 10)
var branch_stop_chance: float = 0.35
## Enemy packs per non-start cell (min, max).
var packs_per_cell: Vector2i = Vector2i(1, 1)
## Loose doodads scattered per cell (open layouts only; rooms use RoomDresser).
var scatter_per_cell: Vector2i = Vector2i(0, 0)

const KIND_BY_NAME := {"rooms": Kind.ROOMS, "open_field": Kind.OPEN_FIELD, "canyon": Kind.CANYON}

static func for_tileset(tileset: MapTileset) -> MapLayout:
	var layout_name := tileset.layout if tileset else "rooms"
	return create(KIND_BY_NAME.get(layout_name, Kind.ROOMS))

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
