extends SceneTree
## Headless checks for the enemy roster, map tilesets and the Hub AmmoStore.
## Run: Godot --headless --path . --script res://tests/test_roster_ammo.gd
## Exits 0 when every check passes. Custom classes are only touched through
## runtime load() and untyped locals: in --script mode a typed local or a
## preload() can compile before the autoloads they reference are registered.

const UNIT_IDS := [
	"unchartered_cutthroat", "unchartered_javelineer", "unchartered_brigand",
	"unchartered_enforcer", "unchartered_chieftain", "directorate_adjudicator",
	"synod_vindicator", "synod_exarch", "legion_threshold_knight", "lord_of_the_elements",
	"hollowed_shambler", "legion_dreadknight", "synod_warden_golem", "synod_ember_golem",
	"synod_aether_golem", "veilborne_mindbender", "veilborne_cantor", "xalatath",
]
const UNIT_SCENES := ["res://entities/enemies/units/MeleeUnit.tscn", "res://entities/enemies/units/RangedUnit.tscn"]
const MAP_RUNS := 20
const PISTOL_WEAPON := "res://data/weapons/instances/gen_machine_pistol_assault_machine_pistol.tres"
const SHOTGUN_WEAPON := "res://data/weapons/instances/gen_loaded_shotgun_breaker_shotgun.tres"

var _checks := 0
var _failures := 0
var _constants: Node
var _game_state: Node
var _ammo: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	await _frames(2)
	_constants = root.get_node("Constants")
	_game_state = root.get_node("GameState")
	_ammo = root.get_node("AmmoInventory")
	_game_state.active_map = null
	await _test_definitions_and_units()
	await _test_generated_maps()
	await _test_tilesets()
	await _test_ammo_store()
	_test_no_retired_references()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _expected_health(def) -> float:
	return _constants.MOB_BASE_HEALTH[def.archetype_category] * (1.0 + _constants.MOB_HEALTH_GROWTH_PER_LEVEL * (def.mob_level - 1))

func _expected_damage(def) -> float:
	return _constants.MOB_BASE_DAMAGE[def.archetype_category] * (1.0 + _constants.MOB_DAMAGE_GROWTH_PER_LEVEL * (def.mob_level - 1))

func _test_definitions_and_units() -> void:
	for id in UNIT_IDS:
		var def = load("res://data/enemies/definitions/%s.tres" % id)
		_check(def != null, "%s definition loads" % id)
		if def == null:
			continue
		_check(def.lore_description != "", "%s has lore" % id)
		for scene_path in UNIT_SCENES:
			var enemy = load(scene_path).instantiate()
			enemy.definition = def
			root.add_child(enemy)
			await _frames(3)
			var tag := "%s on %s" % [id, scene_path.get_file()]
			_check(is_equal_approx(enemy.health.max_health, _expected_health(def)), "%s health %.1f == %.1f" % [tag, enemy.health.max_health, _expected_health(def)])
			var attack = enemy.get_node_or_null("MeleeAttack")
			if attack == null:
				attack = enemy.get_node_or_null("RangedAttack")
			_check(attack != null and is_equal_approx(attack.damage_amount, _expected_damage(def)), "%s damage == %.2f" % [tag, _expected_damage(def)])
			_check(enemy._model_root != null, "%s model instanced" % tag)
			var tree = enemy._model_root.get_node_or_null("AnimationTree") if enemy._model_root else null
			_check(tree != null and tree.active, "%s AnimationTree active" % tag)
			_check(enemy._anim_controller != null and enemy._anim_controller.animation_set == def.animation_set, "%s AnimationSet applied" % tag)
			var player = enemy._anim_controller._player if enemy._anim_controller else null
			_check(player != null, "%s AnimationPlayer found" % tag)
			if player:
				for slot in ["idle", "walk", "run", "attack_light", "attack_heavy", "attack_special", "hit_reaction", "stagger", "death", "death_alt", "ability_cast"]:
					var clip: String = def.animation_set.get(slot)
					_check(clip.is_empty() or player.has_animation(clip), "%s clip %s='%s' exists" % [tag, slot, clip])
				var idle = player.get_animation(def.animation_set.idle)
				_check(idle != null and idle.loop_mode == Animation.LOOP_LINEAR, "%s idle loops" % tag)
				var attack_clip = player.get_animation(def.animation_set.attack_light)
				_check(attack_clip != null and attack_clip.loop_mode == Animation.LOOP_NONE, "%s attack plays once" % tag)
				# The swing is the telegraph: its hit frame must land when the wind-up ends.
				var windup: float = attack.telegraph_duration if "telegraph_duration" in attack else attack.windup_duration
				enemy.begin_attack_telegraph(windup)
				var node = tree.tree_root.get_node("Attack")
				var speed: float = attack_clip.length / node.timeline_length
				var hit_time: float = node.timeline_length * def.animation_set.attack_hit_fraction
				var clamped: bool = is_equal_approx(speed, 0.4) or is_equal_approx(speed, 2.0)
				_check(node.use_custom_timeline and node.stretch_time_scale and (clamped or absf(hit_time - windup) < 0.01), "%s hit frame at %.2fs for a %.2fs wind-up" % [tag, hit_time, windup])
				_check(not enemy._model_root.find_children("*", "MeshInstance3D", true, false).any(func(m): return m.material_override != null), "%s no flash override on attack" % tag)
			enemy.queue_free()
			await _frames(1)

	var lord = load("res://entities/enemies/lord_of_the_elements/LordOfTheElements.tscn").instantiate()
	root.add_child(lord)
	await _frames(2)
	_check(lord.rank == _constants.EnemyRank.BOSS, "Lord rank is BOSS")
	var seen := []
	for i in 4:
		lord.begin_attack_telegraph(1.0)
		seen.append(lord.get_node("MeleeAttack").damage_type)
	var dt = _constants.DamageType
	_check(seen == [dt.FIRE, dt.COLD, dt.LIGHTNING, dt.FIRE], "Lord cycles Fire -> Cold -> Lightning (got %s)" % [seen])
	lord.queue_free()
	await _frames(1)

func _test_generated_maps() -> void:
	var roster_names := []
	for id in UNIT_IDS:
		roster_names.append(load("res://data/enemies/definitions/%s.tres" % id).display_name)
	var map_scene = load("res://levels/generated_map/GeneratedMap.tscn")
	var figment_boss_script = load("res://entities/enemies/figment_boss/FigmentBoss.gd")
	for run in MAP_RUNS:
		var map = map_scene.instantiate()
		root.add_child(map)
		await _frames(2)
		var enemies := get_nodes_in_group("enemy")
		_check(enemies.size() >= map.graph.rooms.size(), "map %d spawned %d enemies for %d rooms" % [run, enemies.size(), map.graph.rooms.size()])
		var bosses := 0
		for enemy in enemies:
			if enemy.get_script() == figment_boss_script:
				bosses += 1
				_check(enemy._model_root != null, "map %d FigmentBoss has a model" % run)
			else:
				_check(enemy.definition != null and enemy.definition.display_name in roster_names, "map %d enemy '%s' is from the roster" % [run, enemy.get_display_name()])
		_check(bosses == 1, "map %d has exactly one FigmentBoss (%d)" % [run, bosses])
		map.queue_free()
		await _frames(2)

func _test_tilesets() -> void:
	var tileset_script = load("res://data/tilesets/MapTileset.gd")
	var ids: PackedStringArray = tileset_script.all_ids()
	_check(ids.size() >= 6, "at least 6 tileset styles (%d)" % ids.size())
	for id in ids:
		var style = tileset_script.load_style(id)
		_check(style != null and style.id == id, "%s loads with matching id" % id)
		if style == null:
			continue
		for tex in ["floor_albedo", "floor_normal", "floor_orm", "wall_albedo", "wall_normal", "wall_orm"]:
			_check(style.get(tex) != null, "%s %s set" % [id, tex])
		_check(not style.archways.is_empty() and not style.wall_props.is_empty() and not style.clusters.is_empty(), "%s has arches, wall props and clusters" % id)
		for list in [style.archways, style.wall_props, style.floor_props, style.clusters, style.wall_lights]:
			for scene in list:
				_check(scene != null and scene.can_instantiate(), "%s doodad scene instantiable" % id)

	var roller = load("res://data/figments/figment_roller.gd")
	var serializer = load("res://data/items/item_serializer.gd")
	for i in 10:
		var fig = roller.roll(randi_range(1, 5))
		_check(fig.tileset_id in ids, "rolled Figment tileset '%s' is a real style" % fig.tileset_id)
		_check(fig.display_name.ends_with(" Figment"), "Figment named by style (%s)" % fig.display_name)
		var copy = serializer.from_dict(serializer.to_dict(fig))
		_check(copy.tileset_id == fig.tileset_id, "tileset_id survives save/load")

	var map_scene = load("res://levels/generated_map/GeneratedMap.tscn")
	var mdx_model_script = load("res://entities/enemies/models/MdxModel.gd")
	for id in ids:
		var fig = load("res://data/figments/figment_item.gd").new()
		fig.tileset_id = id
		_game_state.active_map = fig
		var map = map_scene.instantiate()
		root.add_child(map)
		await _frames(2)
		_check(map.tileset != null and map.tileset.id == id, "map built in style %s" % id)
		var doodads := 0
		for c in map.get_children():
			if c.get_script() == mdx_model_script:
				doodads += 1
		_check(doodads >= map.graph.rooms.size() * 2, "%s map dressed (%d doodads, %d rooms)" % [id, doodads, map.graph.rooms.size()])
		_check(get_nodes_in_group("enemy").size() >= map.graph.rooms.size(), "%s map spawned enemies" % id)
		map.queue_free()
		await _frames(2)
	_game_state.active_map = null

func _test_ammo_store() -> void:
	var player = load("res://entities/player/Player.tscn").instantiate()
	root.add_child(player)
	var store = load("res://entities/interactables/ammo_store/AmmoStore.tscn").instantiate()
	root.add_child(store)
	await _frames(2)
	var pistol = load(PISTOL_WEAPON).duplicate()
	var shotgun = load(SHOTGUN_WEAPON).duplicate()
	player.equipment.primary_weapons[0] = pistol
	player.equipment.primary_weapons[1] = shotgun
	var at = _constants.AmmoType
	var price = _constants.AMMO_ROUND_COST

	# Partial refill: 20 pistol + 4 shotgun reserve rounds, 5 pistol + 2 shotgun magazine rounds.
	_ammo.reset()
	_ammo.consume(at.PISTOL, 20)
	_ammo.consume(at.SHOTGUN, 4)
	pistol.current_magazine = pistol.magazine_size - 5
	shotgun.current_magazine = shotgun.magazine_size - 2
	var expected: int = (20 + 5) * price[at.PISTOL] + (4 + 2) * price[at.SHOTGUN]
	_check(store.get_resupply_cost(player) == expected, "partial cost %d == %d" % [store.get_resupply_cost(player), expected])
	player.ranged_attack._start_reload(pistol)
	_check(player.ranged_attack.is_reloading(), "pistol reload started")
	_game_state.gold = 1000
	var msg: String = store.resupply(player)
	_check(_game_state.gold == 1000 - expected, "gold charged (%d left, %s)" % [_game_state.gold, msg])
	_check(_ammo.get_reserve(at.PISTOL) == _ammo.STARTING_AMMO[at.PISTOL] and _ammo.get_reserve(at.SHOTGUN) == _ammo.STARTING_AMMO[at.SHOTGUN], "reserves topped up")
	_check(pistol.get_current_magazine() == pistol.magazine_size and shotgun.get_current_magazine() == shotgun.magazine_size, "magazines filled in both weapon sets")
	_check(not player.ranged_attack.is_reloading(), "reload cancelled by refill")

	# Short on gold: nothing changes.
	_ammo.consume(at.PISTOL, 10)
	pistol.current_magazine = 0
	var cost: int = store.get_resupply_cost(player)
	_game_state.gold = cost - 1
	msg = store.resupply(player)
	_check(msg == "Not enough Gold (cost %d)" % cost, "short-gold message (%s)" % msg)
	_check(_game_state.gold == cost - 1, "short gold not charged")
	_check(_ammo.get_reserve(at.PISTOL) == _ammo.STARTING_AMMO[at.PISTOL] - 10 and pistol.get_current_magazine() == 0, "short gold buys nothing")

	# Reserves above the starting amount stay untouched and cost nothing.
	_game_state.gold = 1000
	store.resupply(player)
	_game_state.gold = 1000
	_ammo.add(at.RIFLE, 50)
	var rifle_reserve: int = _ammo.get_reserve(at.RIFLE)
	_check(store.get_resupply_cost(player) == 0, "over-stocked reserve adds no cost")
	store.resupply(player)
	_check(_ammo.get_reserve(at.RIFLE) == rifle_reserve, "reserve above starting amount kept (%d)" % _ammo.get_reserve(at.RIFLE))

	# Fully stocked: free.
	msg = store.resupply(player)
	_check(msg == "Fully stocked" and _game_state.gold == 1000, "fully stocked press is free (%s, gold %d)" % [msg, _game_state.gold])

	store.queue_free()
	player.queue_free()
	_ammo.reset()
	await _frames(1)

func _test_no_retired_references() -> void:
	var retired := ["Glass" + "Cannon", "Mobile" + "Bruiser", "Heavy" + "Hitter", "Enemy" + "Archetype",
		"glass_" + "cannon", "mobile_" + "bruiser", "heavy_" + "hitter"]
	var hits := []
	for path in _project_files("res://"):
		var text := FileAccess.get_file_as_string(path)
		for name in retired:
			if text.contains(name):
				hits.append("%s: %s" % [path, name])
	_check(hits.is_empty(), "no references to retired units: %s" % [hits])

func _project_files(dir_path: String) -> Array:
	var files := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "builds" or dir_path.path_join(sub) == "res://tools/mdx_pipeline":
			continue
		files.append_array(_project_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.get_extension() in ["gd", "tscn", "tres", "godot", "cfg"]:
			files.append(dir_path.path_join(file))
	return files
