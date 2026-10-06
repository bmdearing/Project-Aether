extends Node3D
class_name GeneratedMap
## Builds a Map from MapGraph's room-connection graph - rebuilt fresh
## every scene load (no fixed seed). Placeholder BoxMesh/PlaneMesh
## primitives, colored per room - separated from MapGraph.gd so a later
## asset pass only touches mesh/material creation here, not layout.
##
## Player/enemies are spawned in code (positions depend on the generated
## layout, unknown until _ready()); the UI suite is static-equivalent,
## instantiated after the Player so its player-group lookups succeed.

const CELL_SIZE := 16.0
const ROOM_FOOTPRINT := 13.0
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.4
const DOORWAY_WIDTH := 4.0

## Vault room: a safety floor sits under the whole room at -0.5m so a
## missed jump is a stumble, not a fall through the world.
const JUMP_PLATFORM_HEIGHT := 1.2
const JUMP_PLATFORM_DEPTH := 4.0
const JUMP_GAP_DEPTH := 3.0
const SAFETY_FLOOR_DROP := 0.5

const ROOM_FLOOR_COLORS := [
	Color(0.16, 0.14, 0.12),
	Color(0.14, 0.16, 0.15),
	Color(0.15, 0.14, 0.17),
	Color(0.17, 0.15, 0.13),
]
const VAULT_FLOOR_COLOR := Color(0.32, 0.24, 0.06)
const WALL_COLOR := Color(0.22, 0.2, 0.19)
const PLATFORM_COLOR := Color(0.5, 0.4, 0.15)

const PLAYER_SCENE := preload("res://entities/player/Player.tscn")
## "One Vault per Map" guarantees exactly one Figment boss per Map, on the
## Vault's platform (see FigmentBoss.gd).
const FIGMENT_BOSS_SCENE := preload("res://entities/enemies/figment_boss/FigmentBoss.tscn")

## Added after _spawn_player() - Godot readies children before parents,
## so these would find no Player in their own _ready() otherwise.
const UI_SCENES: Array[PackedScene] = [
	preload("res://ui/debug/DebugOverlay.tscn"),
	preload("res://ui/fate_board_editor/FateBoardEditor.tscn"),
	preload("res://ui/inventory/InventoryScreen.tscn"),
	preload("res://ui/crafting/CraftingScreen.tscn"),
	preload("res://ui/abilities/AbilitiesScreen.tscn"),
	preload("res://ui/character_screen/CharacterScreen.tscn"),
	preload("res://ui/map_screen/MapScreen.tscn"),
	preload("res://ui/ability_bar/AbilityBar.tscn"),
	preload("res://ui/player_hud/PlayerHUD.tscn"),
	preload("res://ui/death_screen/DeathScreen.tscn"),
	preload("res://ui/pause_menu/PauseMenu.tscn"),
]

var graph: MapGraph
## Populated as rooms are spawned - used by tests to sanity-check spawn
## positions against actual room bounds without duplicating the layout
## math in the test script.
var last_player_spawn: Vector3

## v4.7 HUD mob counter: every enemy this map spawned (instance id -> true)
## until it dies, plus the total ever spawned.
var _living_enemies: Dictionary = {}
var _enemies_total: int = 0

func _ready() -> void:
	# Standalone (F6) launch: no MainMenu/save ran, so GameState is still defaults.
	GameState.initialize_standalone()
	EventBus.enemy_died.connect(_on_enemy_died)
	graph = MapGraph.generate()
	for cell in graph.rooms:
		_build_room(graph.rooms[cell])
	_build_doorway_bridges()
	_spawn_player()
	_spawn_enemies()
	_spawn_ui()
	_emit_enemy_count()  # HUD is up now (added by _spawn_ui())

func _on_enemy_died(enemy: Node) -> void:
	if _living_enemies.erase(enemy.get_instance_id()):
		_emit_enemy_count()

func _emit_enemy_count() -> void:
	EventBus.enemy_count_changed.emit(_living_enemies.size(), _enemies_total)

## Rooms (13m footprint) sit CELL_SIZE (16m) apart, so each doorway
## needs a floor bridge closing the 3m gap. Each connection is processed
## once via a canonical pair key, not twice from both rooms' side.
func _build_doorway_bridges() -> void:
	var built := {}
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		for neighbor in room.connections:
			var key := _pair_key(cell, neighbor)
			if built.has(key):
				continue
			built[key] = true
			_build_bridge(cell, neighbor)

func _pair_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%s|%s" % [lo, hi]

func _build_bridge(a: Vector2i, b: Vector2i) -> void:
	var mid := (_cell_to_world(a) + _cell_to_world(b)) / 2.0
	var delta: Vector2i = b - a
	var gap_size := CELL_SIZE - ROOM_FOOTPRINT
	var size_x: float = gap_size if delta.x != 0 else DOORWAY_WIDTH
	var size_z: float = DOORWAY_WIDTH if delta.x != 0 else gap_size
	_build_floor(mid, size_x, size_z, 0.0, _random_floor_color())

func _spawn_ui() -> void:
	for scene in UI_SCENES:
		add_child(scene.instantiate())

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)

func _build_room(room: MapGraph.RoomData) -> void:
	var origin := _cell_to_world(room.cell)
	if room.has_jump_platform:
		_build_split_floor(origin, room)
	else:
		_build_floor(origin, ROOM_FOOTPRINT, ROOM_FOOTPRINT, 0.0, _random_floor_color())

	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = room.cell + dir
		_build_wall_side(origin, dir, room.connections.has(neighbor))

func _random_floor_color() -> Color:
	return ROOM_FLOOR_COLORS[randi() % ROOM_FLOOR_COLORS.size()]

## Vault-only: splits the footprint along Z into a main floor and an
## elevated platform with a gap between them, plus a full safety floor
## underneath. The Figment's boss stands on the platform as the jump's
## payoff - killing it "completes" the Figment (EventBus.figment_completed).
func _build_split_floor(origin: Vector3, room: MapGraph.RoomData) -> void:
	_build_floor(origin, ROOM_FOOTPRINT, ROOM_FOOTPRINT, -SAFETY_FLOOR_DROP, VAULT_FLOOR_COLOR)

	var main_depth := ROOM_FOOTPRINT - JUMP_PLATFORM_DEPTH - JUMP_GAP_DEPTH
	var half := ROOM_FOOTPRINT / 2.0
	var main_center_z := -half + main_depth / 2.0
	_build_floor(origin + Vector3(0, 0, main_center_z), ROOM_FOOTPRINT, main_depth, 0.0, VAULT_FLOOR_COLOR)

	var platform_center_z := half - JUMP_PLATFORM_DEPTH / 2.0
	_build_floor(origin + Vector3(0, 0, platform_center_z), ROOM_FOOTPRINT, JUMP_PLATFORM_DEPTH, JUMP_PLATFORM_HEIGHT, PLATFORM_COLOR)

	var enemy_pos := origin + Vector3(0, JUMP_PLATFORM_HEIGHT + 0.95, platform_center_z)
	_spawn_enemy(FIGMENT_BOSS_SCENE.instantiate(), enemy_pos)

func _build_floor(center: Vector3, size_x: float, size_z: float, height: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, height, 0)
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)
	mesh_instance.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, 1.0, size_z)
	collision.position = Vector3(0, -0.5, 0)
	collision.shape = shape
	body.add_child(collision)

func _build_wall_side(origin: Vector3, dir: Vector2i, connected: bool) -> void:
	var half := ROOM_FOOTPRINT / 2.0
	var horizontal := dir == Vector2i.UP or dir == Vector2i.DOWN  # spans X, faces +/-Z
	var side_offset: Vector3
	match dir:
		Vector2i.UP: side_offset = Vector3(0, 0, -half)
		Vector2i.DOWN: side_offset = Vector3(0, 0, half)
		Vector2i.LEFT: side_offset = Vector3(-half, 0, 0)
		_: side_offset = Vector3(half, 0, 0)

	if not connected:
		_add_wall_segment(origin + side_offset, ROOM_FOOTPRINT, horizontal)
		return

	var segment_length := (ROOM_FOOTPRINT - DOORWAY_WIDTH) / 2.0
	if segment_length <= 0.1:
		return  # doorway too wide for this footprint - shouldn't happen with current constants
	var along := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
	var reach := DOORWAY_WIDTH / 2.0 + segment_length / 2.0
	_add_wall_segment(origin + side_offset - along * reach, segment_length, horizontal)
	_add_wall_segment(origin + side_offset + along * reach, segment_length, horizontal)

func _add_wall_segment(center: Vector3, length: float, horizontal: bool) -> void:
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, WALL_HEIGHT / 2.0, 0)
	add_child(body)

	var size := Vector3(length, WALL_HEIGHT, WALL_THICKNESS) if horizontal else Vector3(WALL_THICKNESS, WALL_HEIGHT, length)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WALL_COLOR
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _spawn_player() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var spawn := _cell_to_world(graph.start_cell) + Vector3(0, 1.0, 0)
	player.global_position = spawn
	last_player_spawn = spawn

## Packs stand in a ring this far from their own center.
const PACK_RING_RADIUS := 1.8
const PACK_CENTER_JITTER := 2.5

## One pack per non-start room; the Vault's elite pack holds its main floor
## (the boss already owns the platform, see _build_split_floor()).
func _spawn_enemies() -> void:
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start:
			continue
		var center := _cell_to_world(cell)
		var table: Array = Constants.ENEMY_PACKS_NORMAL
		if room.is_vault:
			var main_depth := ROOM_FOOTPRINT - JUMP_PLATFORM_DEPTH - JUMP_GAP_DEPTH
			center += Vector3(0, 0, -ROOM_FOOTPRINT / 2.0 + main_depth / 2.0)
			table = Constants.ENEMY_PACKS_VAULT_ELITE
		else:
			center += Vector3(randf_range(-PACK_CENTER_JITTER, PACK_CENTER_JITTER), 0, randf_range(-PACK_CENTER_JITTER, PACK_CENTER_JITTER))
		_spawn_pack(EnemyRoster.roll_pack(table), center)

func _spawn_pack(unit_ids: Array[String], center: Vector3) -> void:
	var start_angle := randf() * TAU
	for i in unit_ids.size():
		var offset := Vector3.ZERO
		if unit_ids.size() > 1:
			var angle := start_angle + TAU * i / unit_ids.size()
			offset = Vector3(cos(angle), 0, sin(angle)) * PACK_RING_RADIUS
		_spawn_enemy(EnemyRoster.create_unit(unit_ids[i]), center + offset)

func _spawn_enemy(enemy: Enemy, pos: Vector3) -> void:
	EnemyRarityComponent.roll_and_attach(enemy)
	add_child(enemy)
	enemy.global_position = pos
	_living_enemies[enemy.get_instance_id()] = true
	_enemies_total += 1
