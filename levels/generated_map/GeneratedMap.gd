extends Node3D
class_name GeneratedMap
## Builds a Map from MapGraph's room-connection graph. Generation runs off
## the global RNG seeded with map_seed, so the same seed rebuilds the same
## layout and enemy spawns - that's how a map left through a portal comes
## back (capture_state()/_apply_restore()). Geometry stays simple BoxMesh/PlaneMesh
## pieces; the Figment's MapTileset style supplies their materials, the
## atmosphere, and the doodads RoomDresser places in each room.
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

## Fallback colours, used only when no MapTileset style loads.
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
	preload("res://ui/debug/inventory_debug/InventoryDebugScreen.tscn"),
	preload("res://ui/abilities/AbilitiesScreen.tscn"),
	preload("res://ui/character_screen/CharacterScreen.tscn"),
	preload("res://ui/map_screen/MapScreen.tscn"),
	preload("res://ui/ability_bar/AbilityBar.tscn"),
	preload("res://ui/player_hud/PlayerHUD.tscn"),
	preload("res://ui/death_screen/DeathScreen.tscn"),
	preload("res://ui/pause_menu/PauseMenu.tscn"),
]

var graph: MapGraph
var layout: MapLayout
## Metres between cell centres - CELL_SIZE for rooms, wider for open layouts.
var cell_size: float = CELL_SIZE
## Walls built inside the playable area (room walls); 0 for open layouts.
var interior_wall_count := 0
var _boss: Enemy
var _terrain: TerrainBuilder
## Populated as rooms are spawned - used by tests to sanity-check spawn
## positions against actual room bounds without duplicating the layout
## math in the test script.
var last_player_spawn: Vector3

## v4.7 HUD mob counter: every enemy this map spawned (instance id -> true)
## until it dies, plus the total ever spawned.
var _living_enemies: Dictionary = {}
var _enemies_total: int = 0

var tileset: MapTileset
var _floor_mat: Material
var _wall_mat: Material
var _dresser: RoomDresser

var map_seed: int
var tileset_id: String = ""
## Enemies are identified across a portal trip by spawn order.
var _next_spawn_index := 0
var _dead_spawn_indices: Array[int] = []
var _portal: Portal
var _portal_player_position: Vector3
var _portal_player_yaw: float

func _ready() -> void:
	add_to_group("generated_map")
	# Standalone (F6) launch: no MainMenu/save ran, so GameState is still defaults.
	GameState.initialize_standalone()
	var restore: Dictionary = GameState.portal_map_state if GameState.returning_through_portal else {}
	GameState.returning_through_portal = false
	if restore.is_empty():
		GameState.portal_map_state = {}
		GameState.portals_opened = 0
	elif restore.get("figment", {}) is Dictionary and not restore.get("figment", {}).is_empty():
		GameState.active_map = ItemSerializer.from_dict(restore["figment"]) as FigmentItem

	map_seed = int(restore.get("seed", randi()))
	seed(map_seed)
	_apply_tileset(_pick_tileset(restore.get("tileset_id", "")))
	EventBus.enemy_died.connect(_on_enemy_died)
	layout = MapLayout.for_tileset(tileset)
	cell_size = layout.cell_size
	graph = layout.generate_graph()
	_build_layout()
	_spawn_player()
	_spawn_enemies()
	randomize()
	if not restore.is_empty():
		_apply_restore(restore)
	_spawn_ui()
	_emit_enemy_count()  # HUD is up now (added by _spawn_ui())
	if not restore.is_empty():
		EventBus.portal_returned.emit()

## The active Figment's rolled style; a random one for Figments rolled
## before styles existed, or a standalone launch.
func _build_layout() -> void:
	match layout.kind:
		MapLayout.Kind.ROOMS:
			for cell in graph.rooms:
				_build_room(graph.rooms[cell])
			_build_doorway_bridges()
		MapLayout.Kind.OPEN_FIELD:
			_terrain = TerrainBuilder.new(self, _floor_mat, _wall_mat)
			_terrain.build_open_field(graph, cell_size)
			_terrain.scatter_doodads(_dresser, tileset, graph, cell_size, layout.scatter_per_cell, _cell_to_world(graph.start_cell))
			_spawn_vault_boss(_terrain.build_dais(_cell_to_world(graph.vault_cell), 1.6, _floor_mat))
		MapLayout.Kind.CANYON:
			_terrain = TerrainBuilder.new(self, _floor_mat, _wall_mat)
			_terrain.build_canyon(graph, cell_size)
			_terrain.scatter_doodads(_dresser, tileset, graph, cell_size, layout.scatter_per_cell, _cell_to_world(graph.start_cell))
			_spawn_vault_boss(_terrain.build_dais(_cell_to_world(graph.vault_cell), 2.0, _wall_mat))

func _spawn_vault_boss(pos: Vector3) -> void:
	_boss = FIGMENT_BOSS_SCENE.instantiate()
	_spawn_enemy(_boss, pos)

func get_living_enemy_count() -> int:
	return _living_enemies.size()

func has_boss() -> bool:
	return is_instance_valid(_boss)

func _pick_tileset(saved_id: String = "") -> MapTileset:
	tileset_id = saved_id
	if tileset_id == "":
		tileset_id = GameState.active_map.tileset_id if GameState.active_map else ""
	var style := MapTileset.load_style(tileset_id)
	if style == null:
		tileset_id = MapTileset.random_id()
		style = MapTileset.load_style(tileset_id)
	return style

## ---- Portals -----------------------------------------------------------

## Opens (or moves) the portal to the Hub in front of the player.
func open_portal() -> bool:
	if Constants.MAX_PORTALS >= 0 and GameState.portals_opened >= Constants.MAX_PORTALS:
		return false
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return false
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	if is_instance_valid(_portal):
		_portal.queue_free()
	_portal_player_position = player.global_position
	_portal_player_yaw = player.rotation.y
	var pos := _ground_point(player.global_position + forward * PORTAL_DISTANCE, player.global_position.y)
	_portal = _add_portal(pos)
	GameState.portals_opened += 1
	EventBus.portal_opened.emit(pos)
	return true

const PORTAL_DISTANCE := 2.5
const GROUND_PROBE_UP := 2.0
const GROUND_PROBE_DOWN := 6.0

## Floor height under pos (probing from above it, so a raised floor is found
## too); fallback_y when there's no floor there, e.g. at a ledge.
func _ground_point(pos: Vector3, fallback_y: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * GROUND_PROBE_UP, pos + Vector3.DOWN * GROUND_PROBE_DOWN)
	query.collision_mask = 1
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	pos.y = hit["position"].y if hit else fallback_y
	return pos

func _add_portal(pos: Vector3) -> Portal:
	var portal := Portal.new()
	portal.destination = Portal.Destination.HUB
	portal.taken.connect(leave_through_portal)
	add_child(portal)
	portal.global_position = pos
	return portal

## Saves this map's state and goes to the Hub.
func leave_through_portal() -> void:
	GameState.portal_map_state = capture_state()
	SaveManager.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.HUB_SCENE)

## JSON-safe snapshot: the seed rebuilds the layout and spawns; on top of
## that go the defeated enemies, the loot on the ground, and the portal.
func capture_state() -> Dictionary:
	var loot := []
	for child in get_children():
		if child.is_queued_for_deletion():
			continue
		if child is LootPickup:
			var pos: Vector3 = child.position
			pos.y = child._base_y
			if child.currency_id != &"":
				loot.append({"currency": String(child.currency_id), "count": child.currency_count, "pos": _vec_to_array(pos)})
			elif child.slate:
				loot.append({"slate": SlateSerializer.to_dict(child.slate), "pos": _vec_to_array(pos)})
			elif child.item:
				var ref = child.item.resource_path if child.item.resource_path != "" else ItemSerializer.to_dict(child.item)
				loot.append({"item": ref, "pos": _vec_to_array(pos)})
		elif child is GoldPickup:
			var pos: Vector3 = child.position
			pos.y = child._base_y
			loot.append({"gold": child.amount, "pos": _vec_to_array(pos)})
	var portal_pos: Vector3 = _portal.global_position if is_instance_valid(_portal) else last_player_spawn
	var player_pos: Vector3 = _portal_player_position if is_instance_valid(_portal) else last_player_spawn
	return {
		"seed": map_seed,
		"tileset_id": tileset_id,
		"figment": ItemSerializer.to_dict(GameState.active_map) if GameState.active_map else {},
		"dead": _dead_spawn_indices.duplicate(),
		"loot": loot,
		"portal": _vec_to_array(portal_pos),
		"player": _vec_to_array(player_pos),
		"player_yaw": _portal_player_yaw,
	}

func _apply_restore(state: Dictionary) -> void:
	var dead := {}
	for i in state.get("dead", []):
		dead[int(i)] = true
	for child in get_children():
		if child is Enemy and dead.has(int(child.get_meta(&"spawn_index", -1))):
			_living_enemies.erase(child.get_instance_id())
			_dead_spawn_indices.append(int(child.get_meta(&"spawn_index")))
			remove_child(child)
			child.queue_free()

	for entry in state.get("loot", []):
		var pos := _array_to_vec(entry.get("pos", []))
		if entry.has("gold"):
			var gold: GoldPickup = GOLD_PICKUP_SCENE.instantiate()
			gold.amount = int(entry["gold"])
			gold.position = pos
			add_child(gold)
			continue
		var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
		if entry.has("currency"):
			pickup.currency_id = StringName(entry["currency"])
			pickup.currency_count = int(entry.get("count", 1))
		elif entry.get("item") is Dictionary and ItemSerializer.is_legacy_brand(entry["item"]):
			pickup.currency_id = ItemSerializer.legacy_brand_currency(entry["item"])
			if pickup.currency_id == &"":
				pickup.free()
				continue
		elif entry.has("slate"):
			pickup.slate = SlateSerializer.from_dict(entry["slate"])
		else:
			var ref = entry.get("item")
			pickup.item = (load(ref) as Item).duplicate(true) if ref is String else ItemSerializer.from_dict(ref)
		pickup.position = pos
		add_child(pickup)

	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.global_position = _array_to_vec(state.get("player", []))
		player.rotation.y = float(state.get("player_yaw", 0.0))
	_portal_player_position = _array_to_vec(state.get("player", []))
	_portal_player_yaw = float(state.get("player_yaw", 0.0))
	_portal = _add_portal(_array_to_vec(state.get("portal", [])))

const LOOT_PICKUP_SCENE := preload("res://entities/pickups/loot_pickup/LootPickup.tscn")
const GOLD_PICKUP_SCENE := preload("res://entities/pickups/gold_pickup/GoldPickup.tscn")

static func _vec_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _array_to_vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() == 3 else Vector3.ZERO

func _apply_tileset(style: MapTileset) -> void:
	tileset = style
	if style == null:
		return
	_floor_mat = style.make_floor_material()
	_wall_mat = style.make_wall_material()
	$WorldEnvironment.environment = style.make_environment()
	var sun: DirectionalLight3D = $DirectionalLight3D
	sun.visible = style.sun_energy > 0.0
	sun.light_energy = style.sun_energy
	sun.light_color = style.sun_color
	_dresser = RoomDresser.new(style, self, ROOM_FOOTPRINT, WALL_THICKNESS, DOORWAY_WIDTH)

func _on_enemy_died(enemy: Node) -> void:
	if enemy.has_meta(&"spawn_index"):
		_dead_spawn_indices.append(int(enemy.get_meta(&"spawn_index")))
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
	return Vector3(cell.x * cell_size, 0.0, cell.y * cell_size)

func _build_room(room: MapGraph.RoomData) -> void:
	var origin := _cell_to_world(room.cell)
	if room.has_jump_platform:
		_build_split_floor(origin, room)
	else:
		_build_floor(origin, ROOM_FOOTPRINT, ROOM_FOOTPRINT, 0.0, _random_floor_color())

	var open_sides: Array = []
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = room.cell + dir
		var connected: bool = room.connections.has(neighbor)
		_build_wall_side(origin, dir, connected)
		if connected:
			open_sides.append(dir)
	if _dresser:
		# The Vault keeps its dressing on the main floor, off the jump gap and platform.
		var max_z := -ROOM_FOOTPRINT / 2.0 + (ROOM_FOOTPRINT - JUMP_PLATFORM_DEPTH - JUMP_GAP_DEPTH) - 0.3 if room.has_jump_platform else INF
		_dresser.dress(origin, open_sides, -INF, max_z)

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

	_spawn_vault_boss(origin + Vector3(0, JUMP_PLATFORM_HEIGHT + 0.05, platform_center_z))

func _build_floor(center: Vector3, size_x: float, size_z: float, height: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, height, 0)
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)
	mesh_instance.mesh = plane
	if _floor_mat:
		mesh_instance.material_override = _floor_mat
	else:
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
	interior_wall_count += 1
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, WALL_HEIGHT / 2.0, 0)
	add_child(body)

	var size := Vector3(length, WALL_HEIGHT, WALL_THICKNESS) if horizontal else Vector3(WALL_THICKNESS, WALL_HEIGHT, length)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	if _wall_mat:
		mesh_instance.material_override = _wall_mat
	else:
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
	if layout.kind != MapLayout.Kind.ROOMS:
		_spawn_enemies_open()
		return
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

## Open layouts: packs_per_cell packs near each cell's centre; the Vault's
## elite pack waits between the boss dais and the way in.
const OPEN_PACK_SPREAD := 0.2
const VAULT_PACK_OFFSET := 9.0

func _spawn_enemies_open() -> void:
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start:
			continue
		var center := _cell_to_world(cell)
		if room.is_vault:
			var toward_start := (_cell_to_world(graph.start_cell) - center).normalized()
			_spawn_pack(EnemyRoster.roll_pack(Constants.ENEMY_PACKS_VAULT_ELITE), center + toward_start * VAULT_PACK_OFFSET)
			continue
		for i in randi_range(layout.packs_per_cell.x, layout.packs_per_cell.y):
			var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * cell_size * OPEN_PACK_SPREAD
			_spawn_pack(EnemyRoster.roll_pack(Constants.ENEMY_PACKS_NORMAL), center + offset)

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
	enemy.set_meta(&"spawn_index", _next_spawn_index)
	_next_spawn_index += 1
	add_child(enemy)
	enemy.global_position = pos
	_living_enemies[enemy.get_instance_id()] = true
	_enemies_total += 1
