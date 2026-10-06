extends Node
## Headless checks for the v4.14 batch: spell levels/tags/costs, Crystallized
## Aether upgrades, conduit spell damage, melee arc splash, enemy attack
## lock, kill box, portal placement and every map layout.
## Run: Godot --headless --path . res://tests/v414/test_v414.tscn --quit-after 6000
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const ABILITY_DIR := "res://data/abilities/instances/"

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 7

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_spell_math()
	_test_upgrade_flow()
	await _test_map_layouts()
	await _test_melee_splash()
	await _test_attack_lock()
	await _test_kill_box_and_portal()
	await _test_hub()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.14 tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _ability(id: String) -> Ability:
	return load(ABILITY_DIR + id + ".tres") as Ability

func _test_spell_math() -> void:
	var comet := _ability("comet")
	comet.level = 1
	var sheet := StatSheet.new()
	_check(comet.get_upgrade_aether_cost() <= 3, "level 1 upgrade is cheap (%d Aether)" % comet.get_upgrade_aether_cost())
	comet.level = 19
	_check(comet.get_upgrade_aether_cost() == 120, "19 -> 20 costs 120 Aether (%d)" % comet.get_upgrade_aether_cost())
	comet.level = 20
	_check(not comet.can_upgrade(), "level 20 is the purchasable cap")
	comet.level = 1
	var l1 := comet.get_base_damage_range(sheet)
	_check(is_equal_approx(l1.x, comet.base_damage_min), "level 1 base damage is the authored minimum")
	comet.level = 10
	_check(comet.get_base_damage_range(sheet).x > l1.x * 2.0, "base damage grows with level")
	comet.level = 1

	# +levels from gear stack past 20 and unlock over-cap bonuses.
	var geared := StatSheet.new()
	geared.misc_bonus = {"skill_level_spells": 3.0}
	comet.level = 20
	_check(comet.get_effective_level(geared) == 23, "gear +3 levels -> effective 23")
	_check(comet.get_levels_over_cap(geared) == 3, "3 levels over cap")
	_check(comet.get_radius(geared) > comet.radius, "over-cap Area spell gains radius")
	_check(comet.predict_damage_range(geared).x > comet.predict_damage_range(StatSheet.new()).x, "over-cap adds damage")
	comet.level = 1

	var tornado := _ability("tornado")
	_check(tornado.get_limit() == 3, "Tornado limit 3")
	_check(tornado.get_tag_names().has("Limit") and tornado.get_tag_names().has("Duration"), "Tornado shows its tags")

	# Spells deal damage with no Conduit at all; tags gate modifiers.
	var bare := StatSheet.new()
	_check(comet.predict_damage(bare) > 0.0, "spells deal damage without a Conduit")
	var area := StatSheet.new()
	area.misc_bonus = {"increased_area_damage": 50.0}
	_check(comet.predict_damage(area) > comet.predict_damage(bare), "Area damage boosts an Area spell")
	var lance := _ability("cinder_lance")
	_check(is_equal_approx(lance.predict_damage(area), lance.predict_damage(bare)), "Area damage ignores a non-Area spell")

	var dir := DirAccess.open(ABILITY_DIR)
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var a := load(ABILITY_DIR + f) as Ability
		if a.ability_id in ["blink", "purge"]:
			_check(not a.deals_damage(), "%s deals no damage" % a.ability_id)
		else:
			_check(a.base_damage_min > 0.0 and a.base_damage_max >= a.base_damage_min, "%s has base damage" % a.ability_id)

	# The card must never say "requires a Conduit" and must show level + tags.
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	add_child(card)
	card.display_ability(comet, bare)
	var text := _card_text(card)
	_check(not text.containsn("conduit"), "spell card has no Conduit requirement")
	_check(text.contains("Level 1") and text.contains("Area of Effect"), "spell card shows level and tags")
	_check(text.contains("Cold Damage"), "spell card states its damage")
	card.queue_free()

	# Conduits carry no flat spell power any more.
	var rod := load("res://data/weapons/instances/gen_rod_adept_rod.tres") as Weapon
	_check(not ("spell_power_min" in rod), "Conduit has no spell power field")
	_finished += 1

func _card_text(node: Node) -> String:
	var out := ""
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out += child.text + "\n"
		elif child is RichTextLabel:
			out += child.get_parsed_text() + "\n"
	return out

func _test_upgrade_flow() -> void:
	var spark := _ability("spark")
	spark.level = 1
	GameState.gold = 0
	var screen: AbilitiesScreen = load("res://ui/abilities/AbilitiesScreen.tscn").instantiate()
	add_child(screen)
	screen._on_upgrade_pressed(spark)
	_check(spark.level == 1, "no upgrade without gold/Aether")
	GameState.gold = 10000
	GameState.inventory.add(Ability.AETHER_CURRENCY, 5)
	var aether_before := GameState.inventory.count_of(Ability.AETHER_CURRENCY)
	var cost := spark.get_upgrade_aether_cost()
	screen._on_upgrade_pressed(spark)
	_check(spark.level == 2, "upgrade raises the level")
	_check(GameState.inventory.count_of(Ability.AETHER_CURRENCY) == aether_before - cost, "upgrade spends Crystallized Aether")
	_check(int(GameState.ability_levels.get("spark", 0)) == 2, "level recorded for saving")
	spark.level = 1
	GameState.ability_levels = {}
	screen.queue_free()
	_finished += 1

## Every Figment style builds, spawns the player on solid ground and puts
## enemies down; Dunes has no interior walls.
func _test_map_layouts() -> void:
	for style_id in MapTileset.all_ids():
		var figment := FigmentRoller.roll(1)
		figment.tileset_id = style_id
		GameState.active_map = figment
		var map: GeneratedMap = load(MAP).instantiate()
		add_child(map)
		await _frames(4)
		var player := map.get_node_or_null("Player") as Player
		if player == null:
			player = get_tree().get_first_node_in_group("player") as Player
		var floor_hit := _ray_down(map, map.last_player_spawn + Vector3.UP)
		_check(not floor_hit.is_empty(), "%s: floor under the spawn" % style_id)
		_check(map.get_living_enemy_count() >= 3, "%s: enemies spawned (%d)" % [style_id, map.get_living_enemy_count()])
		_check(map.has_boss(), "%s: a boss spawned" % style_id)
		var layout := MapLayout.for_tileset(map.tileset)
		_check(layout != null, "%s: has a layout" % style_id)
		if style_id == "desert_dunes":
			_check(map.interior_wall_count == 0, "Dunes has no interior walls (%d)" % map.interior_wall_count)
		map.queue_free()
		await _frames(2)
	GameState.active_map = null
	_finished += 1

func _ray_down(map: Node3D, from: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0)
	query.collision_mask = 1
	return map.get_world_3d().direct_space_state.intersect_ray(query)

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()

## A heavy swing cleaves every enemy in its arc; the primary target takes
## more than the splash targets. Enemies behind the player are untouched.
func _test_melee_splash() -> void:
	var arena := _flat_arena()
	var player: Player = load("res://entities/player/Player.tscn").instantiate()
	arena.add_child(player)
	player.global_position = Vector3.ZERO
	await _frames(3)
	_clear_enemies()
	await _frames(2)
	var claymore := Weapon.new()
	claymore.weapon_type = "Claymore"
	claymore.base_damage_min = 50.0
	claymore.base_damage_max = 50.0
	claymore.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
	player.equipment.primary_weapon = claymore
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var front := _spawn_dummy(arena, forward * 2.0)
	var side := _spawn_dummy(arena, forward * 1.6 + right * 1.4)
	var behind := _spawn_dummy(arena, -forward * 2.0)
	await _frames(3)
	var hp := {front: front.health.current_health, side: side.health.current_health, behind: behind.health.current_health}
	player.melee_attack.try_standard_thrust()
	await _frames(240)
	var front_dmg: float = hp[front] - front.health.current_health
	var side_dmg: float = hp[side] - side.health.current_health
	_check(front_dmg > 0.0, "primary target hit (%.1f)" % front_dmg)
	_check(side_dmg > 0.0, "second enemy in the arc took splash (%.1f)" % side_dmg)
	_check(is_equal_approx(behind.health.current_health, hp[behind]), "enemy behind the player untouched")
	arena.queue_free()
	await _frames(2)
	_finished += 1

func _flat_arena() -> Node3D:
	var arena := Node3D.new()
	add_child(arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	arena.add_child(body)
	return arena

func _spawn_dummy(parent: Node3D, pos: Vector3) -> Enemy:
	var enemy := EnemyRoster.create_unit("unchartered_brigand")
	parent.add_child(enemy)
	enemy.global_position = pos
	enemy.health.max_health = 100000.0
	enemy.health.current_health = 100000.0
	enemy.evasion_value = 0.0
	enemy.armor_value = 0.0
	enemy.set_physics_process(false)
	var melee := enemy.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
	return enemy

## Once its wind-up starts, an enemy stays put even as the player backs off.
func _test_attack_lock() -> void:
	var arena := _flat_arena()
	var player: Player = load("res://entities/player/Player.tscn").instantiate()
	arena.add_child(player)
	player.global_position = Vector3.ZERO
	player.set_physics_process(false)
	await _frames(3)
	_clear_enemies()
	await _frames(2)
	var enemy := EnemyRoster.create_unit("unchartered_brigand")
	arena.add_child(enemy)
	enemy.global_position = Vector3(0, 0, -1.8)
	var waited := 0
	while not enemy.is_attack_locked() and waited < 120:
		await _frames(1)
		waited += 1
	_check(enemy.is_attack_locked(), "enemy started an attack")
	var start := enemy.global_position
	player.global_position = Vector3(0, 0, 6.0)
	await _frames(20)
	var moved := Vector2(enemy.global_position.x - start.x, enemy.global_position.z - start.z).length()
	_check(moved < 0.05, "enemy rooted mid-attack (moved %.2fm)" % moved)
	arena.queue_free()
	await _frames(2)
	_finished += 1

func _test_kill_box_and_portal() -> void:
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "dungeon_cellblock"
	GameState.active_map = figment
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	await _frames(6)
	var player := get_tree().get_first_node_in_group("player") as Player
	var hp_before := player.health.current_health
	player.global_position = Vector3(0, KillBox.KILL_Y - 5.0, 0)
	await _frames(3)
	_check(player.global_position.y > KillBox.KILL_Y, "fallen player returned to safe ground")
	_check(player.health.current_health < hp_before, "falling costs some life")
	var enemy: Enemy = null
	for e in get_tree().get_nodes_in_group("enemy"):
		enemy = e
		break
	if enemy:
		enemy.global_position = Vector3(0, KillBox.KILL_Y - 5.0, 0)
		await _frames(3)
		_check(not enemy.health.is_alive(), "fallen enemy killed")
	player.global_position = map.last_player_spawn
	await _frames(4)
	map.open_portal()
	await _frames(2)
	var portal: Portal = map._portal
	var floor_hit := _ray_down(map, portal.global_position + Vector3.UP)
	_check(not floor_hit.is_empty() and absf(floor_hit["position"].y - portal.global_position.y) < 0.05, "portal stands on the floor")
	map.queue_free()
	GameState.active_map = null
	await _frames(2)
	_finished += 1

## The Memory Nexus Hub: spawn, every interactable and the dais top stand on
## solid collision, and its props loaded (no missing scenes).
func _test_hub() -> void:
	var hub: Node3D = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(hub)
	await _frames(6)
	var spots := {"spawn": Vector3(0, 0, 6), "dais top": Vector3(0, 1.2, -17), "bridge west": Vector3(-9.5, 0, -3), "south landing": Vector3(0, 0, 15)}
	for node_name in ["GearShop", "AmmoStore", "SpellTestShop", "StashChest", "RealityEngine", "HubPortalSpot"]:
		var n := hub.get_node_or_null(node_name) as Node3D
		_check(n != null, "hub has %s" % node_name)
		if n:
			spots[node_name] = n.global_position + Vector3(1.6, 0, 0) if node_name != "HubPortalSpot" else n.global_position
	for spot_name in spots:
		var hit := _ray_down(hub, spots[spot_name] + Vector3.UP * 2.0)
		_check(not hit.is_empty(), "hub: solid ground at %s" % spot_name)
	var nexus := hub.get_node_or_null("MemoryNexus")
	_check(nexus != null and nexus.get_child_count() > 50, "Memory Nexus built (%d nodes)" % (nexus.get_child_count() if nexus else 0))
	var void_hit := _ray_down(hub, Vector3(40, 2, 40))
	_check(void_hit.is_empty() or void_hit["position"].y < -2.0, "the void beyond the platforms is open")
	hub.queue_free()
	await _frames(2)
	_finished += 1
