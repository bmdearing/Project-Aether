extends Node
## Headless checks for the v4.72 mapping pass: tiers/bands, the three mod
## pools and their rewards, completion progress and tier gating, the Figment
## Tree (graph, allocation, refunds, effects), mod effects on enemies and
## boss abilities, Pack Size, saving, and the tree screen.
## Run: Godot --headless --path . res://tests/v472/test_v472.tscn --quit-after 6000
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const HUB := "res://levels/hub/Hub.tscn"

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 9

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
	_test_bands_and_pools()
	_test_rewards()
	_test_progress()
	_test_tree()
	_test_tree_effects()
	_test_save()
	await _test_enemy_mods()
	await _test_map()
	await _test_screen()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.72 tests: %d checks, %d failures" % [_checks, _failures])
	GameState.active_map = null
	get_tree().quit(1 if _failures > 0 else 0)

func _figment_with(mods: Dictionary, tier: int = 15) -> FigmentItem:
	var f := FigmentItem.new()
	f.tier = tier
	f.tileset_id = "dungeon_cellblock"
	for id in mods:
		var a := ItemAffix.new()
		a.stat_key = id
		a.value = mods[id]
		if id == "monster_conversion":
			a.damage_type = Constants.DamageType.FIRE
		f.affixes.append(a)
	f.recompute_rewards()
	return f

func _test_bands_and_pools() -> void:
	_check(FigmentRoller.MAX_TIER == 21, "21 tiers")
	_check(FigmentMods.band_of(1) == FigmentMods.Band.LOW and FigmentMods.band_of(7) == FigmentMods.Band.LOW, "tiers 1-7 are Low")
	_check(FigmentMods.band_of(8) == FigmentMods.Band.MID and FigmentMods.band_of(14) == FigmentMods.Band.MID, "tiers 8-14 are Mid")
	_check(FigmentMods.band_of(15) == FigmentMods.Band.HIGH and FigmentMods.band_of(21) == FigmentMods.Band.HIGH, "tiers 15-21 are High")
	var pools := {1: 0, 2: 0, 3: 0}
	for id in FigmentMods.MODS:
		pools[FigmentMods.pool_of(id)] += 1
	_check(pools[1] >= 3 and pools[2] >= 3 and pools[3] >= 3, "each pool has mods (%s)" % pools)
	var ok_low := true
	var ok_mid := true
	var high_pool_3 := false
	var counts_ok := true
	for i in 200:
		var low := FigmentRoller.roll(randi_range(1, 7))
		var mid := FigmentRoller.roll(randi_range(8, 14))
		var high := FigmentRoller.roll(randi_range(15, 21))
		for a in low.affixes:
			ok_low = ok_low and FigmentMods.pool_of(a.stat_key) == 1
		for a in mid.affixes:
			ok_mid = ok_mid and FigmentMods.pool_of(a.stat_key) <= 2
		for a in high.affixes:
			high_pool_3 = high_pool_3 or FigmentMods.pool_of(a.stat_key) == 3
		counts_ok = counts_ok and low.affixes.size() >= 1 and low.affixes.size() <= 3 and high.affixes.size() >= 4
	_check(ok_low, "Low Figments roll only Pool I")
	_check(ok_mid, "Mid Figments roll Pools I-II")
	_check(high_pool_3, "High Figments can roll Pool III")
	_check(counts_ok, "mod counts follow the band")
	var conv := FigmentRoller.roll(21)
	while conv.get_mod("monster_conversion") == null:
		conv = FigmentRoller.roll(21)
	var affix := conv.get_mod("monster_conversion")
	_check(FigmentMods.CONVERSION_TYPES.has(affix.damage_type) and affix.description.contains(Constants.DAMAGE_TYPE_NAME[affix.damage_type]), "conversion names its type (%s)" % affix.description)
	_finished += 1

func _test_rewards() -> void:
	var easy := _figment_with({"monster_move_speed": 12.0, "monster_area": 20.0})
	var hard := _figment_with({"monster_damage": 40.0, "boss_damage": 40.0})
	_check(easy.pack_size_multiplier > hard.pack_size_multiplier, "easy mods give more Pack Size")
	_check(hard.loot_quantity_multiplier > easy.loot_quantity_multiplier and hard.loot_rarity_multiplier > easy.loot_rarity_multiplier, "hard mods give more Quantity/Rarity")
	_check(is_equal_approx(easy.pack_size_multiplier, 1.16), "pack size sums per mod (%.2f)" % easy.pack_size_multiplier)
	GameState.active_map = hard
	var mods := Loot.multipliers(null, {})
	_check(is_equal_approx(mods["quantity"], hard.loot_quantity_multiplier), "Figment quantity reaches Loot (%.2f)" % mods["quantity"])
	GameState.active_map = null
	_finished += 1

func _test_progress() -> void:
	GameState.figment_completions = {}
	GameState.figment_tree_unlocked_nodes = []
	_check(FigmentProgress.max_drop_tier() == 1, "nothing completed: drops cap at Tier 1")
	var capped := true
	for i in 50:
		capped = capped and FigmentRoller.roll_for_drop(9).tier == 1
	_check(capped, "drops can't pass the cap")
	_check(FigmentProgress.record("dungeon_cellblock", 1), "first clear is new")
	_check(not FigmentProgress.record("dungeon_cellblock", 1), "a repeat isn't")
	_check(FigmentProgress.record("desert_dunes", 1), "another style at the same tier is new")
	_check(FigmentProgress.points_earned() == 2, "a point per style per band (%d)" % FigmentProgress.points_earned())
	_check(not FigmentProgress.record("dungeon_cellblock", 5), "another tier in a cleared band isn't new")
	_check(FigmentProgress.record("dungeon_cellblock", 8), "the next band is new")
	_check(FigmentProgress.points_earned() == 3 and FigmentProgress.highest_in_band("dungeon_cellblock", 0) == 5, "band points and highest tier per band")
	_check(FigmentProgress.max_drop_tier() == 9, "the highest clear sets the drop cap")
	FigmentProgress.record("snow_tundra", 9)
	_check(FigmentProgress.completed_in_band(FigmentMods.Band.MID) == 2 and FigmentProgress.completed_in_band(FigmentMods.Band.LOW) == 2, "band counts")
	_check(FigmentProgress.total_possible() == MapTileset.all_ids().size() * 3, "possible = styles x 3 bands")
	_check(FigmentProgress.milestone_reached(FigmentProgress.MILESTONES[1]) and not FigmentProgress.milestone_reached(FigmentProgress.MILESTONES[-1]), "milestones unlock in order")
	var fig := FigmentRoller.roll(10)
	_check(not CraftingSystem.empower_figment(fig)["success"] and fig.tier == 10, "empower stops at the cap")
	FigmentProgress.record("snow_tundra", 10)
	var before := fig.affixes.size()
	_check(CraftingSystem.empower_figment(fig)["success"] and fig.tier == 11 and fig.affixes.size() >= before, "empower raises tier under the cap")
	_finished += 1

func _test_tree() -> void:
	GameState.figment_tree_unlocked_nodes = []
	var nodes := FigmentTree.all_nodes()
	_check(nodes.size() >= 60, "tree has room to grow (%d nodes)" % nodes.size())
	# Every node reaches the root; no two sit on top of each other.
	var reached := {FigmentTree.ROOT_ID: true}
	var frontier: Array[String] = [FigmentTree.ROOT_ID]
	while not frontier.is_empty():
		for id in FigmentTree.get_node_by_id(frontier.pop_back()).links:
			if not reached.has(id):
				reached[id] = true
				frontier.append(id)
	_check(reached.size() == nodes.size(), "every node connects to the root")
	var min_gap := INF
	for a in nodes.size():
		for b in range(a + 1, nodes.size()):
			min_gap = minf(min_gap, nodes[a].position.distance_to(nodes[b].position))
	_check(min_gap > 0.45, "nodes don't overlap (closest %.2f)" % min_gap)
	var sectors := {}
	for n in nodes:
		sectors[n.sector] = true
	for s in ["Terrain", "Factions", "Monsters", "Rewards", "Encounters", "Figments"]:
		_check(sectors.has(s), "sector %s exists" % s)

	GameState.figment_completions = {}
	_check(not FigmentTree.can_unlock("terrain_trunk_1"), "no points, no allocation")
	for style in ["dungeon_cellblock", "desert_dunes"]:
		for tier in [1, 8, 15]:
			FigmentProgress.record(style, tier)
	_check(not FigmentTree.can_unlock("terrain_trunk_2"), "must link to an allocated node")
	_check(FigmentTree.unlock("terrain_trunk_1") and FigmentTree.unlock("terrain_trunk_2"), "allocate along the trunk")
	_check(FigmentProgress.points_available() == 4, "points spent (%d left)" % FigmentProgress.points_available())
	_check(not FigmentTree.can_refund("terrain_trunk_1"), "can't refund a node others hang from")
	_check(FigmentTree.refund("terrain_trunk_2") and FigmentTree.refund("terrain_trunk_1"), "refund from the tip")
	_check(FigmentProgress.points_available() == 6, "refunds give the points back")
	_finished += 1

func _test_tree_effects() -> void:
	GameState.figment_tree_unlocked_nodes = []
	GameState.figment_completions = {}
	for style in MapTileset.all_ids():
		for tier in [1, 8, 15]:
			FigmentProgress.record(style, tier)
	for id in ["monsters_trunk_1", "monsters_trunk_2", "pack_1", "pack_2"]:
		_check(FigmentTree.unlock(id), "allocate %s" % id)
	_check(is_zero_approx(FigmentTree.effect("pack_size")), "tree does nothing outside a Figment")
	GameState.active_map = _figment_with({})
	_check(is_equal_approx(FigmentTree.effect("pack_size"), 18.0), "pack size sums (%.0f)" % FigmentTree.effect("pack_size"))
	for id in ["terrain_trunk_1", "terrain_trunk_2", "snow_1", "snow_2", "snow_3", "snow_notable"]:
		FigmentTree.unlock(id)
	var snow := 0
	for i in 600:
		if MapTileset.family_of(FigmentRoller.roll_style()) == "snow":
			snow += 1
	# 4 of 19 styles are snow: ~21% unweighted; +120% weight -> ~37%.
	_check(snow > 600 * 0.29, "style weights steer drops (%d/600 snow)" % snow)
	for id in ["rewards_trunk_1", "reward_uniques_1", "reward_uniques_2", "reward_uniques_notable"]:
		FigmentTree.unlock(id)
	var w := Loot.rarity_weights(1.0)
	_check(w[Constants.ItemRarity.UNIQUE] > Loot.RARITY_WEIGHTS[Constants.ItemRarity.UNIQUE] * 1.6, "unique reward node raises unique weight")
	for id in ["monsters_trunk_1", "elite_1", "elite_2", "elite_notable"]:
		FigmentTree.unlock(id)
	var elites := 0
	for i in 2000:
		if EnemyRarityComponent.roll_pack_rarity() == Constants.EnemyRarity.ELITE:
			elites += 1
	_check(elites > 2000 * 0.26, "rarity weights steer packs (%d/2000 Elite)" % elites)
	GameState.active_map = null
	GameState.figment_tree_unlocked_nodes = []
	_finished += 1

func _test_save() -> void:
	var fig := FigmentRoller.roll(17)
	var copy := ItemSerializer.from_dict(ItemSerializer.to_dict(fig)) as FigmentItem
	_check(copy.tier == 17 and copy.affixes.size() == fig.affixes.size(), "Figment mods survive a save")
	_check(is_equal_approx(copy.pack_size_multiplier, fig.pack_size_multiplier), "Pack Size survives a save")
	for a in fig.affixes:
		_check(is_equal_approx(copy.mod_value(a.stat_key), a.value), "mod %s survives" % a.stat_key)
	_finished += 1

func _test_enemy_mods() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var mods := {"monster_move_speed": 20.0, "monster_attack_speed": 25.0, "monster_damage": 40.0, "monster_area": 50.0,
		"monster_cast_speed": 100.0, "monster_projectiles": 2.0, "monster_crit": 100.0, "monster_conversion": 40.0,
		"boss_life": 50.0, "boss_damage": 50.0, "boss_area": 20.0, "boss_speed": 10.0}
	GameState.active_map = _figment_with(mods, 1)
	var normal := EnemyRoster.create_unit("unchartered_cutthroat")
	EnemyRarityComponent.attach_normal(normal)
	holder.add_child(normal)
	var asc := EnemyRoster.create_unit("synod_vindicator")
	EnemyRarityComponent.attach(asc, Constants.EnemyRarity.ASCENDANT, [] as Array[EnemyAffix])
	holder.add_child(asc)
	await _frames(2)
	_check(not normal.is_map_boss_target() and asc.is_map_boss_target(), "Ascendants take boss mods, normal monsters don't")
	_check(is_equal_approx(normal.get_map_move_speed_multiplier(), 1.2), "move speed mod")
	_check(is_equal_approx(asc.get_map_move_speed_multiplier(), 1.2 * 1.1), "boss speed stacks on Ascendants")
	_check(is_equal_approx(normal.get_area_multiplier(), 1.5) and is_equal_approx(asc.get_area_multiplier(), 1.5 * 1.2), "area mods")
	_check(normal.get_extra_projectiles() == 2, "extra projectiles")
	_check(normal.roll_crit(10.0) > 10.0, "crit mod lets monsters crit")
	var conv := normal.get_map_conversion()
	_check(conv.size() == 2 and is_equal_approx(conv[0], 0.4) and conv[1] == Constants.DamageType.FIRE, "conversion mod")
	var base_damage := normal.get_outgoing_damage_multiplier()
	GameState.active_map = _figment_with({}, 1)
	_check(is_equal_approx(base_damage / normal.get_outgoing_damage_multiplier(), 1.4), "damage mod")
	_check(is_zero_approx(normal.roll_crit(10.0) - 10.0), "no crit mod, no crits")
	GameState.active_map = _figment_with(mods, 1)
	_check(is_equal_approx(asc.get_outgoing_damage_multiplier() / normal.get_outgoing_damage_multiplier(), 1.5 * asc.rarity_component.get_damage_multiplier()), "boss damage on Ascendants")

	# Boss abilities: area, telegraph (floored) and volley count.
	var brain := BossBrain.new()
	asc.add_child(brain)
	var slam := BossAbility.make({"id": "t_slam", "kind": BossAbility.Kind.SLAM, "radius": 4.0, "telegraph": 1.0})
	var volley := BossAbility.make({"id": "t_volley", "kind": BossAbility.Kind.VOLLEY, "count": 3, "telegraph": 1.0})
	var s := brain._scaled(slam)
	_check(is_equal_approx(s.radius, 4.0 * 1.5 * 1.2) and is_equal_approx(slam.radius, 4.0), "boss ability radius scales on a copy")
	_check(is_equal_approx(s.telegraph, FigmentMods.MIN_TELEGRAPH_SHARE), "cast speed can't cut telegraphs below the floor (%.2f)" % s.telegraph)
	_check(brain._scaled(volley).count == 5, "volleys gain the extra projectiles")
	GameState.active_map = _figment_with({}, 1)
	_check(brain._scaled(slam) == slam, "no mods, no copy")

	# Figment boss: boss_life applies.
	GameState.active_map = _figment_with({}, 5)
	var plain_boss: FigmentBoss = load("res://entities/enemies/figment_boss/FigmentBoss.tscn").instantiate()
	plain_boss.profile_id = "chieftain"
	holder.add_child(plain_boss)
	GameState.active_map = _figment_with({"boss_life": 50.0}, 5)
	var tough_boss: FigmentBoss = load("res://entities/enemies/figment_boss/FigmentBoss.tscn").instantiate()
	tough_boss.profile_id = "chieftain"
	holder.add_child(tough_boss)
	await _frames(2)
	_check(is_equal_approx(tough_boss.health.max_health / plain_boss.health.max_health, 1.5), "boss life mod on the Figment boss")
	holder.queue_free()
	GameState.active_map = null
	await _frames(2)
	_finished += 1

func _test_map() -> void:
	var fig := _figment_with({"monster_move_speed": 12.0}, 3)
	fig.pack_size_multiplier = 3.0
	GameState.active_map = fig
	var map: GeneratedMap = load(MAP).instantiate()
	var grown := map._grow_pack(["a", "b"] as Array[String])
	_check(grown.size() == 6, "+200%% Pack Size triples a pack (%d)" % grown.size())
	fig.pack_size_multiplier = 1.0
	_check(map._grow_pack(["a", "b"] as Array[String]).size() == 2, "no Pack Size, no change")
	map.free()
	fig.pack_size_multiplier = 1.5
	fig.tileset_id = ""
	var scene: GeneratedMap = load(MAP).instantiate()
	add_child(scene)
	await _frames(40)
	_check(scene != null and scene.get_living_enemy_count() > 0, "a modded Figment builds and spawns")
	_check(scene != null and fig.tileset_id == scene.tileset_id and fig.tileset_id != "", "the built style is written back for completion")
	GameState.figment_completions = {}
	EventBus.figment_completed.emit(fig)
	_check(FigmentProgress.is_completed(fig.tileset_id, 3), "completing the boss records the style and tier")
	scene.queue_free()
	await _frames(3)
	GameState.active_map = null
	_finished += 1

func _test_screen() -> void:
	GameState.figment_tree_unlocked_nodes = []
	GameState.figment_completions = {}
	FigmentProgress.record("dungeon_mine", 1)
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(20)
	var screen := get_tree().get_first_node_in_group("figment_tree_screen") as FigmentTreeScreen
	_check(screen != null, "the Hub has the Figment Tree screen")
	if screen == null:
		return
	_check(MenuTabStrip.SCREENS.any(func(s): return s[0] == "figment_tree_screen"), "the tree is a Tab-menu screen")
	screen.open()
	await _frames(3)
	var view := screen._view
	var node := FigmentTree.get_node_by_id("figments_trunk_1")
	view._click(view._to_screen(node.position), false)
	_check(FigmentTree.is_allocated("figments_trunk_1"), "clicking a node allocates it")
	view._click(view._to_screen(node.position), true)
	_check(not FigmentTree.is_allocated("figments_trunk_1"), "right-clicking refunds it")
	_check(screen._points_label.text.begins_with("1 point"), "points shown (%s)" % screen._points_label.text)
	screen._is_open = false  # close() would save
	screen.visible = false
	get_tree().paused = false
	hub.queue_free()
	_finished += 1
