extends Node
## Headless checks for v4.75 Area Level scaling: Depth/Tier/Pinnacle Area
## Levels, the XP gap rule, monsters scaled by Area Level alone (never player
## level) and flattened across units, drop item levels, the Figment boss, and
## the Fragmented Reality levelling stage (Depths, free run, drops, empower,
## completion opening Tier 1).
## Run: Godot --headless --path . res://tests/v475/test_v475.tscn --quit-after 8000
## Exits 0 when every check passes. Never writes the save file.

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 5

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
	_test_area_levels()
	_test_xp_rule()
	await _test_monsters()
	_test_levelling_stage()
	await _test_pinnacle()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.75 tests: %d checks, %d failures" % [_checks, _failures])
	GameState.active_map = null
	GameState.in_pinnacle = false
	get_tree().quit(1 if _failures > 0 else 0)

func _tier(t: int) -> FigmentItem:
	var f := FigmentItem.new()
	f.tier = t
	f.tileset_id = "dungeon_cellblock"
	return f

func _depth(d: int) -> FigmentItem:
	var f := FigmentItem.new()
	f.depth = d
	f.tileset_id = "dungeon_cellblock"
	return f

func _test_area_levels() -> void:
	_check(AreaLevel.of_figment(_depth(1)) == 1 and AreaLevel.of_figment(_depth(23)) == 67, "Depths 1-23 are Area Level 1-67")
	_check(AreaLevel.of_figment(_tier(1)) == 69 and AreaLevel.of_figment(_tier(21)) == 89, "Tiers 1-21 are Area Level 69-89")
	GameState.active_map = null
	GameState.in_pinnacle = true
	_check(AreaLevel.current() == 90, "Pinnacles are Area Level 90")
	GameState.in_pinnacle = false
	_check(AreaLevel.current() == 0, "no area outside a Figment or Pinnacle")
	_finished += 1

func _test_xp_rule() -> void:
	_check(AreaLevel.xp_zone(50) == 12, "the zone at level 50 is 12")
	_check(is_equal_approx(AreaLevel.xp_multiplier(50, 50), 1.0), "on-level: full XP")
	_check(is_equal_approx(AreaLevel.xp_multiplier(44, 50), 0.5), "6 below at 50: half XP")
	_check(is_zero_approx(AreaLevel.xp_multiplier(38, 50)) and is_zero_approx(AreaLevel.xp_multiplier(30, 50)), "38 and below at 50: no XP")
	_check(is_equal_approx(AreaLevel.xp_multiplier(56, 50), 1.1), "6 above at 50: +10%")
	_check(is_equal_approx(AreaLevel.xp_multiplier(62, 50), 1.2) and is_equal_approx(AreaLevel.xp_multiplier(80, 50), 1.2), "62 and above at 50: +20%, no more")
	_finished += 1

func _spawn(unit_id: String, holder: Node) -> Enemy:
	var e := EnemyRoster.create_unit(unit_id)
	EnemyRarityComponent.attach_normal(e)
	holder.add_child(e)
	return e

func _test_monsters() -> void:
	var holder := Node3D.new()
	add_child(holder)
	GameState.active_map = _tier(21)
	GameState.player_level = 1
	var low_player := _spawn("unchartered_brigand", holder)
	GameState.player_level = 90
	var high_player := _spawn("unchartered_brigand", holder)
	var golem := _spawn("synod_warden_golem", holder)
	await _frames(3)
	_check(low_player.level == 89 and golem.level == 89, "monster level is the Area Level, flattened across units (%d, %d)" % [low_player.level, golem.level])
	_check(is_equal_approx(low_player.health.max_health, high_player.health.max_health), "player level doesn't touch monster health")
	var expected := Constants.MOB_BASE_HEALTH["standard"] * pow(AreaLevel.HEALTH_GROWTH, 88)
	_check(is_equal_approx(low_player.health.max_health, expected), "health follows the exponential curve (%.0f vs %.0f)" % [low_player.health.max_health, expected])
	var melee := low_player.get_node("MeleeAttack") as EnemyMeleeAttack
	_check(is_equal_approx(melee.damage_amount, Constants.MOB_BASE_DAMAGE["standard"] * pow(AreaLevel.DAMAGE_GROWTH, 88)), "damage follows its curve")
	_check(is_equal_approx(low_player.get_outgoing_damage_multiplier(), 1.0), "no per-tier damage multiplier on top")
	_check(low_player._compute_item_level() >= 89, "drops are item level 89+ in a Tier 21 (%d)" % low_player._compute_item_level())
	var xp_on := low_player.earned_xp(89)
	_check(is_equal_approx(low_player.earned_xp(70) / (low_player.xp_reward * AreaLevel.xp_scale(70)), 1.2), "a level-70 player gets the capped +20% from a level-89 monster")
	_check(xp_on > 0.0, "on-level XP is positive")
	GameState.active_map = _depth(5)
	var shallow := _spawn("unchartered_brigand", holder)
	await _frames(2)
	_check(shallow.level == 13, "a Depth 5 monster is level 13")
	_check(is_zero_approx(shallow.earned_xp(40)), "a level-40 player gets nothing at Depth 5")
	var boss: FigmentBoss = load("res://entities/enemies/figment_boss/FigmentBoss.tscn").instantiate()
	boss.profile_id = "chieftain"
	GameState.active_map = _tier(21)
	holder.add_child(boss)
	await _frames(2)
	_check(boss.level == 89 and is_equal_approx(boss.health.max_health, FigmentBoss.BOSS_HEALTH * pow(AreaLevel.HEALTH_GROWTH, 88)), "the Figment boss scales with Area Level")
	var boss_melee := boss.get_node("MeleeAttack") as EnemyMeleeAttack
	_check(is_equal_approx(boss_melee.damage_amount, 40.0 * pow(AreaLevel.DAMAGE_GROWTH, 88)), "the Figment boss hits harder at Area Level 89 (%.0f)" % boss_melee.damage_amount)
	holder.queue_free()
	GameState.active_map = null
	await _frames(2)
	_finished += 1

func _test_levelling_stage() -> void:
	GameState.game_mode = GameState.GameMode.FRAGMENTED_REALITY
	GameState.depth_cleared = 0
	GameState.figment_completions = {}
	_check(not FigmentProgress.levelling_complete() and FigmentProgress.max_drop_depth() == 1, "a new character starts at Depth 1")
	GameState.active_map = null
	_check(FigmentRoller.roll_for_drop().depth == 1, "outside a Figment, drops are Depth 1 while levelling")
	GameState.active_map = _depth(4)
	var deepest := 0
	for i in 60:
		deepest = maxi(deepest, FigmentRoller.roll_for_drop().depth)
	_check(deepest == 1, "drops can't pass the deepest Depth cleared + 1 (%d)" % deepest)
	EventBus.figment_completed.emit(_depth(1))
	EventBus.figment_completed.emit(_depth(2))
	EventBus.figment_completed.emit(_depth(3))
	_check(GameState.depth_cleared == 3 and FigmentProgress.max_drop_depth() == 4, "clearing Depths opens the next")
	_check(FigmentProgress.points_earned() == 0, "Depths give no tree points")
	var low := FigmentRoller.roll_depth(2)
	_check(low.affixes.is_empty() and low.rarity == Constants.ItemRarity.COMMON, "low Depths roll no mods")
	var fig := _depth(4)
	_check(not CraftingSystem.empower_figment(fig)["success"], "empower stops at the deepest Depth open")
	fig.depth = 3
	_check(CraftingSystem.empower_figment(fig)["success"] and fig.depth == 4, "empower takes a Depth one deeper")
	GameState.active_map = _depth(23)
	GameState.depth_cleared = 22
	var any_tier := false
	for i in 80:
		any_tier = any_tier or not FigmentRoller.roll_for_drop().is_levelling()
	_check(not any_tier, "no endgame Figments before Depth 23 is cleared")
	EventBus.figment_completed.emit(_depth(23))
	_check(FigmentProgress.levelling_complete(), "clearing Depth 23 ends the levelling stage")
	for i in 80:
		any_tier = any_tier or not FigmentRoller.roll_for_drop().is_levelling()
	_check(any_tier, "Depth 23 can then drop Tier 1")
	GameState.active_map = null
	_check(not FigmentRoller.roll_for_drop().is_levelling(), "after levelling, drops outside a Figment are Tier 1")
	GameState.depth_cleared = 0
	GameState.game_mode = GameState.GameMode.CAMPAIGN
	_check(FigmentProgress.levelling_complete(), "the Campaign skips the levelling stage")
	GameState.game_mode = GameState.GameMode.FRAGMENTED_REALITY
	var copy := ItemSerializer.from_dict(ItemSerializer.to_dict(_depth(9))) as FigmentItem
	_check(copy.depth == 9, "Depth survives a save")
	GameState.active_map = null
	_finished += 1

func _test_pinnacle() -> void:
	GameState.active_map = null
	GameState.in_pinnacle = true
	var holder := Node3D.new()
	add_child(holder)
	var e := _spawn("legion_dreadknight", holder)
	await _frames(2)
	_check(e.level == 90, "Pinnacle monsters are level 90 (%d)" % e.level)
	GameState.in_pinnacle = false
	var outside := _spawn("legion_dreadknight", holder)
	await _frames(2)
	_check(outside.level == outside.definition.mob_level, "outside any area, a monster keeps its own level")
	holder.queue_free()
	await _frames(2)
	_finished += 1
