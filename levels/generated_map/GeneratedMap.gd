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

## Dungeon (ROOMS) layout: rooms of varied rectangular size, centred in
## their grid cells and joined by walled corridors from doorway to doorway.
## Every floor is flat - the Vault used to have a jump gap that trapped bosses.
const CELL_SIZE := 30.0
## Per-axis footprint range of an ordinary room; the start room is smaller,
## the Vault (boss room) larger.
const ROOM_SIZE := Vector2(15.0, 23.0)
const START_ROOM_SIZE := 14.0
const BOSS_ROOM_SIZE := 27.0
const WALL_HEIGHT := 5.0
const WALL_THICKNESS := 0.6
const DOORWAY_WIDTH := 4.0
const CORRIDOR_WIDTH := 4.0
## Rooms at least this big on both axes may get four pillars.
const PILLAR_ROOM_MIN := 18.0
const PILLAR_CHANCE := 0.6
const PILLAR_SIZE := 1.4
## Second enemy pack in rooms with at least this much floor area.
const BIG_ROOM_AREA := 380.0
## Boss room: the altar (where the completion portal opens) sits this far
## in from the wall opposite the entrance.
const ALTAR_INSET := 4.5
const ALTAR_RADIUS := 2.4

## Fallback colours, used only when no MapTileset style loads.
const ROOM_FLOOR_COLORS := [
	Color(0.16, 0.14, 0.12),
	Color(0.14, 0.16, 0.15),
	Color(0.15, 0.14, 0.17),
	Color(0.17, 0.15, 0.13),
]
const VAULT_FLOOR_COLOR := Color(0.32, 0.24, 0.06)
const WALL_COLOR := Color(0.22, 0.2, 0.19)

const PLAYER_SCENE := preload("res://entities/player/Player.tscn")
## "One Vault per Map" guarantees exactly one Figment boss per Map, on the
## boss room (see FigmentBoss.gd).
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
## Rooms layout: cell -> Vector2 half-extents (x, z) of that room.
var room_half: Dictionary = {}
## Where the portal home opens when the Figment's boss dies.
var boss_portal_point: Vector3
var _completion_portal: Portal
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
	EventBus.figment_completed.connect(_on_figment_completed)
	layout = MapLayout.for_tileset(tileset)
	cell_size = layout.cell_size
	graph = layout.generate_graph()
	_build_layout()
	_spawn_player()
	_spawn_enemies()
	_spawn_chests()
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
			_roll_room_sizes()
			for cell in graph.rooms:
				_build_room(graph.rooms[cell])
			_build_corridors()
		MapLayout.Kind.OPEN_FIELD:
			_terrain = TerrainBuilder.new(self, _floor_mat, _wall_mat)
			_terrain.build_open_field(graph, cell_size)
			_terrain.scatter_doodads(_dresser, tileset, graph, cell_size, layout.scatter_per_cell, _cell_to_world(graph.start_cell))
			var dune_crest := _terrain.build_dais(_cell_to_world(graph.vault_cell), 1.6, _floor_mat)
			boss_portal_point = dune_crest
			_spawn_vault_boss(dune_crest)
		MapLayout.Kind.CANYON:
			_terrain = TerrainBuilder.new(self, _floor_mat, _wall_mat)
			_terrain.build_canyon(graph, cell_size)
			_terrain.scatter_doodads(_dresser, tileset, graph, cell_size, layout.scatter_per_cell, _cell_to_world(graph.start_cell))
			var mesa := _terrain.build_dais(_cell_to_world(graph.vault_cell), 2.0, _wall_mat)
			boss_portal_point = mesa
			_spawn_vault_boss(mesa)

func _spawn_vault_boss(pos: Vector3) -> void:
	_boss = FIGMENT_BOSS_SCENE.instantiate()
	_boss.profile_id = FigmentBoss.pick_profile_id()  # seeded, so a portal return rebuilds the same boss
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
	if is_instance_valid(_portal):
		_portal.queue_free()
	_portal_player_position = player.global_position
	_portal_player_yaw = player.rotation.y
	var pos := _ground_point(_clear_portal_spot(player), player.global_position.y)
	_portal = _add_portal(pos)
	GameState.portals_opened += 1
	EventBus.portal_opened.emit(pos)
	return true


## PORTAL_DISTANCE ahead of the player, or, when a wall or prop is in the
## way, the first of the other three directions with room (the roomiest one
## if none has). A portal used to land inside the wall you faced.
func _clear_portal_spot(player: Player) -> Vector3:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var space := get_world_3d().direct_space_state
	var origin := player.global_position + Vector3.UP * 1.0
	var need := PORTAL_DISTANCE + Portal.RADIUS
	var best_dir := forward
	var best_room := -1.0
	for turn in [0.0, PI / 2.0, -PI / 2.0, PI]:
		var dir := forward.rotated(Vector3.UP, turn)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * need)
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		var room := need if hit.is_empty() else origin.distance_to(hit["position"])
		if room >= need:
			return player.global_position + dir * PORTAL_DISTANCE
		if room > best_room:
			best_room = room
			best_dir = dir
	return player.global_position + best_dir * maxf(best_room - Portal.RADIUS - 0.2, 0.0)
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


## The boss's death completes the Figment and opens a portal home at a fixed
## spot: the boss room's altar, or the top of the dais in open layouts.
## It doesn't count toward the portal limit.
func _on_figment_completed(_figment: FigmentItem) -> void:
	_open_completion_portal.call_deferred()

func _open_completion_portal() -> void:
	if is_instance_valid(_completion_portal):
		return
	_completion_portal = _add_portal(boss_portal_point)
## Saves this map's state and goes to the Hub.
func leave_through_portal() -> void:
	GameState.portal_map_state = capture_state()
	SaveManager.save_game()
	get_tree().paused = false
	LoadingScreen.change_scene(GameState.HUB_SCENE)

## JSON-safe snapshot: the seed rebuilds the layout and spawns; on top of
## that go the defeated enemies, the loot on the ground, and the portal.
func capture_state() -> Dictionary:
	var loot := []
	for child in get_children():
		if child.is_queued_for_deletion():
			continue
		if child is LootPickup:
			var pos: Vector3 = child.position
			if child.currency_id != &"":
				loot.append({"currency": String(child.currency_id), "count": child.currency_count, "pos": _vec_to_array(pos)})
			elif child.slate:
				loot.append({"slate": SlateSerializer.to_dict(child.slate), "pos": _vec_to_array(pos)})
			elif child.item:
				var ref = child.item.resource_path if child.item.resource_path != "" else ItemSerializer.to_dict(child.item)
				loot.append({"item": ref, "pos": _vec_to_array(pos)})
		elif child is GoldPickup:
			var pos: Vector3 = child.position
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
		"chests_opened": _opened_chest_indices(),
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
	for i in state.get("chests_opened", []):
		if int(i) >= 0 and int(i) < _chests.size():
			_chests[int(i)].set_opened()
	var portal_pos := _array_to_vec(state.get("portal", []))
	if player:
		player.global_position = _array_to_vec(state.get("player", []))
		player.rotation.y = facing_away(portal_pos, player.global_position, float(state.get("player_yaw", 0.0)))
	_portal_player_position = _array_to_vec(state.get("player", []))
	_portal_player_yaw = float(state.get("player_yaw", 0.0))
	_portal = _add_portal(portal_pos)
	if _boss != null and (not is_instance_valid(_boss) or _boss.is_queued_for_deletion() or not _boss.is_inside_tree()):
		_open_completion_portal()

const LOOT_PICKUP_SCENE := preload("res://entities/pickups/loot_pickup/LootPickup.tscn")
const GOLD_PICKUP_SCENE := preload("res://entities/pickups/gold_pickup/GoldPickup.tscn")

## Yaw that faces from `from` towards `at` and beyond (player forward is -Z);
## `fallback` when the two are on top of each other.
static func facing_away(from: Vector3, at: Vector3, fallback: float) -> float:
	var away := Vector2(at.x - from.x, at.z - from.z)
	if away.length() < 0.05:
		return fallback
	return atan2(-away.x, -away.y)

static func _vec_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _array_to_vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() == 3 else Vector3.ZERO

func _exit_tree() -> void:
	AudioManager.play_ambience("")

func _apply_tileset(style: MapTileset) -> void:
	tileset = style
	if style == null:
		return
	AudioManager.play_ambience(style.ambience_id)
	_floor_mat = style.make_floor_material()
	_wall_mat = style.make_wall_material()
	$WorldEnvironment.environment = style.make_environment()
	var sun: DirectionalLight3D = $DirectionalLight3D
	sun.visible = style.sun_energy > 0.0
	sun.light_energy = style.sun_energy
	sun.light_color = style.sun_color
	_dresser = RoomDresser.new(style, self, WALL_THICKNESS, DOORWAY_WIDTH)

func _on_enemy_died(enemy: Node) -> void:
	if enemy.has_meta(&"spawn_index"):
		_dead_spawn_indices.append(int(enemy.get_meta(&"spawn_index")))
	if _living_enemies.erase(enemy.get_instance_id()):
		_emit_enemy_count()

func _emit_enemy_count() -> void:
	EventBus.enemy_count_changed.emit(_living_enemies.size(), _enemies_total)

## Each connection becomes a walled corridor between the two rooms' doorways.
## Each pair is built once via a canonical key, not twice from both sides.
func _build_corridors() -> void:
	var built := {}
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		for neighbor in room.connections:
			var key := _pair_key(cell, neighbor)
			if built.has(key):
				continue
			built[key] = true
			_build_corridor(cell, neighbor)

func _pair_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%s|%s" % [lo, hi]

func _build_corridor(a: Vector2i, b: Vector2i) -> void:
	var d := Vector3(b.x - a.x, 0, b.y - a.y)
	var half_a: Vector2 = room_half[a]
	var half_b: Vector2 = room_half[b]
	var reach_a: float = half_a.x if d.x != 0.0 else half_a.y
	var reach_b: float = half_b.x if d.x != 0.0 else half_b.y
	var from := _cell_to_world(a) + d * reach_a
	var to := _cell_to_world(b) - d * reach_b
	var length := from.distance_to(to)
	var mid := (from + to) / 2.0
	var along_x := d.x != 0.0
	# The floor runs a little into both rooms so there's no seam at the doorway.
	_build_floor(mid, length + 0.6 if along_x else layout.corridor_width, layout.corridor_width if along_x else length + 0.6, 0.0, _random_floor_color())
	var side := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	for s in [-1.0, 1.0]:
		_add_wall_segment(mid + side * s * (layout.corridor_width + WALL_THICKNESS) / 2.0, length, along_x)
	if tileset and tileset.room_light_energy > 0.0 and length > 6.0:
		var light := OmniLight3D.new()
		light.light_color = tileset.light_color
		light.light_energy = tileset.room_light_energy * 0.8
		light.omni_range = maxf(length * 0.7, 5.0)
		light.position = mid + Vector3(0, layout.wall_height - 1.0, 0)
		add_child(light)

func _spawn_ui() -> void:
	for scene in UI_SCENES:
		add_child(scene.instantiate())

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * cell_size, 0.0, cell.y * cell_size)

## Footprints are rolled up front so corridors know where each room's walls are.
func _roll_room_sizes() -> void:
	room_half = {}
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		var size := Vector2(randf_range(layout.room_size.x, layout.room_size.y), randf_range(layout.room_size.x, layout.room_size.y))
		if room.is_start:
			size = Vector2.ONE * minf(START_ROOM_SIZE, layout.room_size.y)
		elif room.is_vault:
			size = Vector2.ONE * layout.boss_room_size
		room_half[cell] = size / 2.0

func _build_room(room: MapGraph.RoomData) -> void:
	var origin := _cell_to_world(room.cell)
	var half: Vector2 = room_half[room.cell]
	_build_floor(origin, half.x * 2.0, half.y * 2.0, 0.0, VAULT_FLOOR_COLOR if room.is_vault else _random_floor_color())

	var open_sides: Array = []
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = room.cell + dir
		var connected: bool = room.connections.has(neighbor)
		_build_wall_side(origin, half, dir, connected)
		if connected:
			open_sides.append(dir)

	if room.is_vault:
		_build_boss_room(origin, half, open_sides)
	elif minf(half.x, half.y) * 2.0 >= minf(PILLAR_ROOM_MIN, layout.room_size.y - 1.0) and randf() < layout.pillar_chance:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_add_pillar(origin + Vector3(corner.x * half.x * 0.5, 0, corner.y * half.y * 0.5))
	if layout.cave_walls and not room.is_vault:
		_add_outcrops(origin, half, open_sides)
	if _dresser:
		_dresser.dress(origin, half, open_sides, room.is_vault)
	if tileset and tileset.room_light_energy > 0.0:
		var fill := OmniLight3D.new()
		fill.light_color = tileset.light_color
		fill.light_energy = tileset.room_light_energy
		fill.omni_range = maxf(half.x, half.y) * 1.7
		fill.position = origin + Vector3(0, layout.wall_height - 0.6, 0)
		add_child(fill)

func _random_floor_color() -> Color:
	return ROOM_FLOOR_COLORS[randi() % ROOM_FLOOR_COLORS.size()]

## The boss room: one flat floor (nothing to fall into or get stuck on), four
## pillars for cover, and an altar opposite the entrance where the portal
## home opens once the boss dies. The boss waits between the centre and the altar.
func _build_boss_room(origin: Vector3, half: Vector2, open_sides: Array) -> void:
	var entrance: Vector2i = open_sides[0] if not open_sides.is_empty() else Vector2i.DOWN
	var back := -Vector3(entrance.x, 0, entrance.y)
	var back_reach: float = half.x if entrance.x != 0 else half.y
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_add_pillar(origin + Vector3(corner.x * (half.x - 5.5), 0, corner.y * (half.y - 5.5)))
	var altar := origin + back * (back_reach - ALTAR_INSET)
	_add_altar(altar)
	boss_portal_point = altar
	_spawn_vault_boss(origin + back * 3.0 + Vector3(0, 0.05, 0))

## Cave rooms: rough rock shoulders jutting from the walls, clear of doorways,
## so a mine room isn't a clean box.
const OUTCROPS_PER_ROOM := Vector2i(4, 7)
const OUTCROP_WIDTH := Vector2(1.6, 3.4)
const OUTCROP_DEPTH := Vector2(0.8, 2.0)

func _add_outcrops(origin: Vector3, half: Vector2, open_sides: Array) -> void:
	for i in randi_range(OUTCROPS_PER_ROOM.x, OUTCROPS_PER_ROOM.y):
		var dir: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT].pick_random()
		var along_len: float = half.x if dir.y != 0 else half.y
		var t := randf_range(-along_len + 1.5, along_len - 1.5)
		if dir in open_sides and absf(t) < layout.corridor_width / 2.0 + 2.0:
			continue
		var width := randf_range(OUTCROP_WIDTH.x, OUTCROP_WIDTH.y)
		var depth := randf_range(OUTCROP_DEPTH.x, OUTCROP_DEPTH.y)
		var height := layout.wall_height * randf_range(0.55, 1.0)
		var wall_dist: float = half.y if dir.y != 0 else half.x
		var along := Vector3(1, 0, 0) if dir.y != 0 else Vector3(0, 0, 1)
		var pos := origin + Vector3(dir.x, 0, dir.y) * (wall_dist - depth / 2.0 + 0.2) + along * t
		var size := Vector3(width, height, depth) if dir.y != 0 else Vector3(depth, height, width)
		var body := StaticBody3D.new()
		body.position = pos + Vector3(0, height / 2.0, 0)
		body.rotation.y = randf_range(-0.25, 0.25)
		add_child(body)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = _wall_mat if _wall_mat else _plain_material(WALL_COLOR)
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		if _dresser:
			var r := maxf(size.x, size.z) / 2.0 + 0.3
			_dresser.reserve(Rect2(Vector2(pos.x, pos.z) - Vector2.ONE * r, Vector2.ONE * r * 2.0))

## A full-height square column with collision; reserved so props avoid it.
func _add_pillar(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, layout.wall_height / 2.0, 0)
	add_child(body)
	var size := Vector3(PILLAR_SIZE, layout.wall_height, PILLAR_SIZE)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _wall_mat if _wall_mat else _plain_material(WALL_COLOR)
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	if _dresser:
		_dresser.reserve(Rect2(Vector2(pos.x, pos.z) - Vector2.ONE * PILLAR_SIZE, Vector2.ONE * PILLAR_SIZE * 2.0))

## A glowing rune circle flush with the floor - no collision, so nothing can
## catch on it.
func _add_altar(pos: Vector3) -> void:
	var color: Color = tileset.light_color if tileset else Color(0.6, 0.8, 1.0)
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ALTAR_RADIUS
	disc.bottom_radius = ALTAR_RADIUS
	disc.height = 0.04
	ring.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	ring.material_override = mat
	ring.position = pos + Vector3(0, 0.03, 0)
	add_child(ring)
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 1.2
	glow.omni_range = 6.0
	glow.position = pos + Vector3(0, 1.5, 0)
	add_child(glow)
	if _dresser:
		_dresser.reserve(Rect2(Vector2(pos.x, pos.z) - Vector2.ONE * (ALTAR_RADIUS + 1.0), Vector2.ONE * (ALTAR_RADIUS + 1.0) * 2.0))

func _plain_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

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

func _build_wall_side(origin: Vector3, half: Vector2, dir: Vector2i, connected: bool) -> void:
	var horizontal := dir == Vector2i.UP or dir == Vector2i.DOWN  # spans X, faces +/-Z
	var side_offset := Vector3(dir.x * (half.x + WALL_THICKNESS / 2.0), 0, dir.y * (half.y + WALL_THICKNESS / 2.0))
	# Walls sit just outside the floor and overlap at the corners.
	var length: float = (half.x if horizontal else half.y) * 2.0 + WALL_THICKNESS * 2.0
	if not connected:
		_add_wall_segment(origin + side_offset, length, horizontal)
		return
	var segment_length := (length - DOORWAY_WIDTH) / 2.0
	var along := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
	var reach := DOORWAY_WIDTH / 2.0 + segment_length / 2.0
	_add_wall_segment(origin + side_offset - along * reach, segment_length, horizontal)
	_add_wall_segment(origin + side_offset + along * reach, segment_length, horizontal)

func _add_wall_segment(center: Vector3, length: float, horizontal: bool) -> void:
	interior_wall_count += 1
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, layout.wall_height / 2.0, 0)
	add_child(body)

	var size := Vector3(length, layout.wall_height, WALL_THICKNESS) if horizontal else Vector3(WALL_THICKNESS, layout.wall_height, length)

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

## One pack per room except the start and the Vault: the Vault holds only
## its boss (FigmentBoss; the elites that used to guard it are now bosses).
func _spawn_enemies() -> void:
	if layout.kind != MapLayout.Kind.ROOMS:
		_spawn_enemies_open()
		return
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start or room.is_vault:
			continue
		var half: Vector2 = room_half[cell]
		var packs := 2 if half.x * half.y * 4.0 >= BIG_ROOM_AREA else 1
		for i in packs:
			# A second pack stands off to one side of the room, not on the first.
			var side := Vector3(half.x * 0.35, 0, 0) if half.x >= half.y else Vector3(0, 0, half.y * 0.35)
			var base := _cell_to_world(cell) + (side * (1.0 if i == 0 else -1.0) if packs > 1 else Vector3.ZERO)
			var center := base + Vector3(randf_range(-PACK_CENTER_JITTER, PACK_CENTER_JITTER), 0, randf_range(-PACK_CENTER_JITTER, PACK_CENTER_JITTER))
			_spawn_pack(EnemyRoster.roll_pack(Constants.ENEMY_PACKS_NORMAL), center)

## Treasure chests: CHEST_COUNT of them in random rooms other than the start
## and the Vault, in a free corner (rooms) or off-centre (open layouts).
## Seeded with the map, so a portal return rebuilds the same ones.
const CHEST_COUNT := Vector2i(2, 3)
const CHEST_CLEARANCE := 1.2
var _chests: Array[TreasureChest] = []

func _spawn_chests() -> void:
	var cells: Array[Vector2i] = []
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if not room.is_start and not room.is_vault:
			cells.append(cell)
	cells.sort()
	var count := mini(randi_range(CHEST_COUNT.x, CHEST_COUNT.y), cells.size())
	for i in count:
		var cell: Vector2i = cells.pop_at(randi() % cells.size())
		var spot := _chest_spot(cell)
		var chest := TreasureChest.new()
		chest.rotation.y = randf() * TAU
		add_child(chest)
		chest.global_position = spot
		_chests.append(chest)
	_ground_chests.call_deferred()

func _chest_spot(cell: Vector2i) -> Vector3:
	var origin := _cell_to_world(cell)
	var half: Vector2 = room_half.get(cell, Vector2.ONE * cell_size * 0.4)
	var corners: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	corners.shuffle()
	var inset := 0.75 if layout.kind == MapLayout.Kind.ROOMS else 0.35
	for corner in corners:
		var pos := origin + Vector3(corner.x * half.x * inset, 0, corner.y * half.y * inset)
		var rect := Rect2(Vector2(pos.x, pos.z) - Vector2.ONE * CHEST_CLEARANCE, Vector2.ONE * CHEST_CLEARANCE * 2.0)
		if _dresser == null or not _dresser._overlaps(rect):
			if _dresser:
				_dresser.reserve(rect)
			return pos
	return origin + Vector3(half.x * 0.3, 0, 0)

## Sits each chest on the floor once the level's colliders are in the physics world.
func _ground_chests() -> void:
	await get_tree().physics_frame
	for chest in _chests:
		if is_instance_valid(chest):
			chest.settle()

func _opened_chest_indices() -> Array:
	var opened := []
	for i in _chests.size():
		if is_instance_valid(_chests[i]) and _chests[i].is_opened():
			opened.append(i)
	return opened

## Open layouts: packs_per_cell packs near each cell's centre; the Vault
## holds only its boss.
const OPEN_PACK_SPREAD := 0.2

func _spawn_enemies_open() -> void:
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start or room.is_vault:
			continue
		var center := _cell_to_world(cell)
		for i in randi_range(layout.packs_per_cell.x, layout.packs_per_cell.y):
			var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * cell_size * OPEN_PACK_SPREAD
			_spawn_pack(EnemyRoster.roll_pack(Constants.ENEMY_PACKS_NORMAL), center + offset)

## Rarity is rolled per pack (EnemyRarityComponent): an Elite pack shares one
## pack affix; a Champion leads an otherwise Normal pack; an Ascendant pack
## is one of Constants.ASCENDANT_UNITS with up to ASCENDANT_ESCORTS escorts.
func _spawn_pack(unit_ids: Array[String], center: Vector3, forced_rarity: int = -1) -> void:
	var rarity: Constants.EnemyRarity = EnemyRarityComponent.roll_pack_rarity() if forced_rarity < 0 else forced_rarity as Constants.EnemyRarity
	if rarity == Constants.EnemyRarity.ASCENDANT:
		var leader_id: String = Constants.ASCENDANT_UNITS.pick_random()
		var escorts := unit_ids.slice(0, mini(unit_ids.size(), randi_range(0, Constants.ASCENDANT_ESCORTS)))
		unit_ids = [leader_id] as Array[String]
		unit_ids.append_array(escorts)
	var shared: Array[EnemyAffix] = []
	if rarity == Constants.EnemyRarity.ELITE:
		shared = EnemyRarityComponent.roll_affixes(rarity)
	var leader := 0 if rarity == Constants.EnemyRarity.ASCENDANT else randi() % unit_ids.size()
	var members: Array = []
	var start_angle := randf() * TAU
	for i in unit_ids.size():
		var offset := Vector3.ZERO
		if unit_ids.size() > 1:
			var angle := start_angle + TAU * i / unit_ids.size()
			offset = Vector3(cos(angle), 0, sin(angle)) * PACK_RING_RADIUS
		var enemy := EnemyRoster.create_unit(unit_ids[i])
		var member_rarity := Constants.EnemyRarity.NORMAL
		var rolled: Array[EnemyAffix] = []
		if rarity == Constants.EnemyRarity.ELITE:
			member_rarity = rarity
			rolled = shared
		elif rarity != Constants.EnemyRarity.NORMAL and i == leader:
			member_rarity = rarity
			rolled = EnemyRarityComponent.roll_affixes(rarity)
		EnemyRarityComponent.attach(enemy, member_rarity, rolled, members)
		members.append(enemy)
		_spawn_enemy(enemy, center + offset)
		# Archon: a twin with the same affixes (each has half the Life, 65% damage).
		if member_rarity == Constants.EnemyRarity.ASCENDANT and rolled.any(func(x: EnemyAffix): return x.mechanic == EnemyRarityComponent.MECHANIC_ARCHON):
			var twin := EnemyRoster.create_unit(unit_ids[i])
			EnemyRarityComponent.attach(twin, member_rarity, rolled.duplicate(), members)
			members.append(twin)
			_spawn_enemy(twin, center + offset + Vector3(PACK_RING_RADIUS, 0, 0))

## Anything spawned without a rarity (the boss, summons) is Normal, so it can
## still receive Champion auras.
func _spawn_enemy(enemy: Enemy, pos: Vector3) -> void:
	if enemy.get_node_or_null("EnemyRarityComponent") == null:
		EnemyRarityComponent.attach_normal(enemy)
	enemy.set_meta(&"spawn_index", _next_spawn_index)
	_next_spawn_index += 1
	add_child(enemy)
	enemy.global_position = pos
	_living_enemies[enemy.get_instance_id()] = true
	_enemies_total += 1
