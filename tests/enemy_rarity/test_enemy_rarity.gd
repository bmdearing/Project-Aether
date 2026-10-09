extends Node
## Enemy rarity tiers (Patch v3.9 + user direction 2026-10-09): Elite packs
## share one pack affix, Champions' auras buff nearby enemies, Ascendants are
## the dedicated units with their own pool, and the affix mechanics work.
## Run: Godot --headless --path . res://tests/enemy_rarity/test_enemy_rarity.tscn --quit-after 8000
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const SPOT := Vector3(600, 0, 600)

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 7
var _map: GeneratedMap

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
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "dungeon_cellblock"
	GameState.active_map = figment
	_map = load(MAP).instantiate()
	add_child(_map)
	await _frames(4)
	_add_floor()
	_test_pools()
	_test_pack_weights()
	await _test_elite_pack()
	await _test_champion_aura()
	await _test_ascendant()
	await _test_mechanics()
	await _test_volatile()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("enemy rarity tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_map.add_child(body)
	body.global_position = SPOT

## Spawns a pack at SPOT with a forced rarity; returns the new enemies.
func _pack(ids: Array[String], rarity: Constants.EnemyRarity, at: Vector3 = SPOT) -> Array[Enemy]:
	var before := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		before[e] = true
	_map._spawn_pack(ids, at, rarity)
	var spawned: Array[Enemy] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not before.has(e):
			spawned.append(e as Enemy)
	return spawned

func _clear(enemies: Array) -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.remove_from_group("enemy")
			e.queue_free()

func _test_pools() -> void:
	var pack := EnemyRarityComponent.affixes_for_category(EnemyAffix.AffixCategory.PACK)
	var champion := EnemyRarityComponent.affixes_for_category(EnemyAffix.AffixCategory.CHAMPION)
	var ascendant := EnemyRarityComponent.affixes_for_category(EnemyAffix.AffixCategory.ASCENDANT)
	_check(pack.size() >= 8, "Elite pack pool has 8+ affixes (%d)" % pack.size())
	_check(champion.filter(func(a: EnemyAffix): return a.has_aura).size() >= 4, "Champions have 4+ auras")
	_check(ascendant.size() >= 7, "Ascendants have their own pool of 7+ (%d)" % ascendant.size())
	for affix in pack + champion + ascendant:
		_check(affix.display_name != "" and affix.description != "", "%s has a name and description" % affix.affix_id)
	_finished += 1

func _test_pack_weights() -> void:
	var counts := {}
	for i in 2000:
		var r := EnemyRarityComponent.roll_pack_rarity()
		counts[r] = counts.get(r, 0) + 1
	_check(counts.get(Constants.EnemyRarity.NORMAL, 0) > counts.get(Constants.EnemyRarity.ELITE, 0) and counts.get(Constants.EnemyRarity.ELITE, 0) > counts.get(Constants.EnemyRarity.CHAMPION, 0) and counts.get(Constants.EnemyRarity.CHAMPION, 0) > counts.get(Constants.EnemyRarity.ASCENDANT, 0) and counts.get(Constants.EnemyRarity.ASCENDANT, 0) > 0, "pack rarity odds fall Normal > Elite > Champion > Ascendant (%s)" % counts)
	_finished += 1

func _test_elite_pack() -> void:
	var ids: Array[String] = ["unchartered_brigand", "unchartered_cutthroat", "unchartered_javelineer"]
	var pack := _pack(ids, Constants.EnemyRarity.ELITE)
	await _frames(2)
	var affix: EnemyAffix = pack[0].rarity_component.affixes[0] if not pack[0].rarity_component.affixes.is_empty() else null
	var all_elite := pack.all(func(e: Enemy): return e.rarity_component.rarity == Constants.EnemyRarity.ELITE)
	var shared := pack.all(func(e: Enemy): return e.rarity_component.affixes.size() == 1 and e.rarity_component.affixes[0] == affix)
	_check(pack.size() == 3 and all_elite, "every member of an Elite pack is Elite")
	_check(affix != null and affix.category == EnemyAffix.AffixCategory.PACK and shared, "the pack shares one pack affix (%s)" % (affix.display_name if affix else "-"))
	_check(pack[0].rarity_component.pack.size() == 3, "each member knows its pack")
	_clear(pack)
	await _frames(2)
	_finished += 1

func _test_champion_aura() -> void:
	var ids: Array[String] = ["unchartered_brigand", "unchartered_brigand", "unchartered_brigand"]
	var pack := _pack(ids, Constants.EnemyRarity.CHAMPION)
	var champions := pack.filter(func(e: Enemy): return e.rarity_component.rarity == Constants.EnemyRarity.CHAMPION)
	_check(champions.size() == 1, "a Champion pack has one Champion leader")
	var champ: Enemy = champions[0]
	var aura: EnemyAffix = null
	for a in champ.rarity_component.affixes:
		if a.has_aura:
			aura = a
	_check(aura != null, "the Champion has an aura")
	var follower: Enemy = pack.filter(func(e: Enemy): return e != champ)[0]
	_check(follower.rarity_component.rarity == Constants.EnemyRarity.NORMAL, "the rest of its pack are Normal")
	# A different aura than the one rolled, set by hand so the check is exact.
	var might := load("res://data/enemies/affixes/champion_aura_damage.tres") as EnemyAffix
	var plain: Array[EnemyAffix] = [might]
	champ.rarity_component.affixes = plain
	var stranger := EnemyRoster.create_unit("hollowed_shambler")
	_map._spawn_enemy(stranger, SPOT + Vector3(3, 0, 0))
	var far := EnemyRoster.create_unit("hollowed_shambler")
	_map._spawn_enemy(far, SPOT + Vector3(30, 0, 0))
	for e in pack + [stranger, far]:
		e.set_physics_process(false)
		e.global_position = SPOT + (Vector3(30, 0.1, 0) if e == far else Vector3(randf_range(-2, 2), 0.1, randf_range(-2, 2)))
	await get_tree().create_timer(EnemyRarityComponent.AURA_TICK + 0.2).timeout
	var base: float = Constants.ENEMY_RARITY_DAMAGE_MULT.get(Constants.EnemyRarity.NORMAL, 1.0)
	_check(is_equal_approx(stranger.rarity_component.get_damage_multiplier(), base * 1.3), "the aura reaches nearby enemies that didn't spawn with it (%.2f)" % stranger.rarity_component.get_damage_multiplier())
	_check(is_equal_approx(far.rarity_component.get_damage_multiplier(), base), "but not enemies out of range")
	_check(champ.rarity_component.get_damage_multiplier() > Constants.ENEMY_RARITY_DAMAGE_MULT[Constants.EnemyRarity.CHAMPION], "the Champion's own aura reaches itself")
	var renewal: Array[EnemyAffix] = [load("res://data/enemies/affixes/champion_aura_renewal.tres") as EnemyAffix]
	champ.rarity_component.affixes = renewal
	stranger.health.current_health = stranger.health.max_health * 0.5
	await get_tree().create_timer(1.0).timeout
	_check(stranger.health.current_health > stranger.health.max_health * 0.505, "Aura of Renewal heals a Normal enemy in range")
	champ.health.apply_damage(1.0e9)
	await get_tree().create_timer(EnemyRarityComponent.AURA_LINGER + 0.2).timeout
	_check(is_equal_approx(stranger.rarity_component.get_damage_multiplier(), base), "the buff fades once the Champion is gone")
	_clear(pack + [stranger, far])
	await _frames(2)
	_finished += 1

func _test_ascendant() -> void:
	var ids: Array[String] = ["unchartered_brigand", "unchartered_cutthroat"]
	for i in 3:
		var pack := _pack(ids, Constants.EnemyRarity.ASCENDANT)
		var ascendants := pack.filter(func(e: Enemy): return e.rarity_component.rarity == Constants.EnemyRarity.ASCENDANT)
		_check(ascendants.size() == 1 and Constants.ASCENDANT_UNITS.has(ascendants[0].definition.resource_path.get_file().get_basename()), "an Ascendant pack is led by a Vindicator, Dreadknight or Cantor (%s)" % (ascendants[0].definition.resource_path.get_file().get_basename() if not ascendants.is_empty() else "-"))
		_check(pack.size() <= 1 + Constants.ASCENDANT_ESCORTS, "with at most %d escorts" % Constants.ASCENDANT_ESCORTS)
		if not ascendants.is_empty():
			var affixes: Array = ascendants[0].rarity_component.affixes
			_check(affixes.size() == 2 and affixes.all(func(a: EnemyAffix): return a.category == EnemyAffix.AffixCategory.ASCENDANT), "it rolls two affixes from the Ascendant pool")
		_clear(pack)
		await _frames(2)
	_finished += 1

func _test_mechanics() -> void:
	var ids: Array[String] = ["unchartered_brigand", "unchartered_brigand", "unchartered_brigand"]
	var pack := _pack(ids, Constants.EnemyRarity.ELITE)
	await _frames(2)
	var frenzy := load("res://data/enemies/affixes/pack_frenzied.tres") as EnemyAffix
	for e in pack:
		var list: Array[EnemyAffix] = [frenzy]
		e.rarity_component.affixes = list
		e.set_physics_process(false)
	var survivor: Enemy = pack[1]
	var before := survivor.rarity_component.get_damage_multiplier()
	pack[0].health.apply_damage(1.0e9)
	await _frames(2)
	_check(survivor.rarity_component.get_damage_multiplier() > before * 1.1 and survivor.get_attack_speed_multiplier() > 1.1, "Frenzied: a packmate's death enrages the rest")
	_clear(pack)

	var golem := EnemyRoster.create_unit("synod_vindicator")
	var jugg := load("res://data/enemies/affixes/ascendant_juggernaut.tres") as EnemyAffix
	var shell := load("res://data/enemies/affixes/ascendant_arcane_shell.tres") as EnemyAffix
	var asc: Array[EnemyAffix] = [jugg, shell]
	EnemyRarityComponent.attach(golem, Constants.EnemyRarity.ASCENDANT, asc)
	_map._spawn_enemy(golem, SPOT)
	golem.set_physics_process(false)
	await _frames(4)
	golem.status_effects.apply_effect("chill")
	golem.interrupt_attack()
	_check(not golem.status_effects.has_effect("chill") and not golem.is_staggered(), "Juggernaut ignores Chill and staggers")
	_check(golem.get_ward_max() >= golem.health.max_health * 0.39, "Arcane Shell grants Ward of 40% Life (%.0f / %.0f)" % [golem.get_ward_max(), golem.health.max_health])
	_clear([golem])

	var iron := EnemyRoster.create_unit("unchartered_enforcer")
	var ironclad: Array[EnemyAffix] = [load("res://data/enemies/affixes/pack_ironclad.tres") as EnemyAffix]
	EnemyRarityComponent.attach(iron, Constants.EnemyRarity.ELITE, ironclad)
	_map._spawn_enemy(iron, SPOT)
	iron.set_physics_process(false)
	iron.armor_value = 0.0
	await _frames(3)
	var hp := iron.health.current_health
	iron.take_damage(100.0, Constants.DamageType.FIRE)
	_check(is_equal_approx(hp - iron.health.current_health, 70.0), "Ironclad takes 30% less damage (%.1f)" % (hp - iron.health.current_health))
	_clear([iron])
	await _frames(2)
	_finished += 1

func _test_volatile() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var bomber := EnemyRoster.create_unit("unchartered_brigand")
	var volatile: Array[EnemyAffix] = [load("res://data/enemies/affixes/pack_volatile.tres") as EnemyAffix]
	EnemyRarityComponent.attach(bomber, Constants.EnemyRarity.ELITE, volatile)
	_map._spawn_enemy(bomber, SPOT)
	bomber.set_physics_process(false)
	await _frames(3)
	player.global_position = SPOT + Vector3(1.0, 0.1, 0)
	await _frames(2)
	var life := player.health.current_health
	bomber.health.apply_damage(1.0e9)
	await get_tree().create_timer(EnemyRarityComponent.VOLATILE_DELAY + 0.3).timeout
	_check(player.health.current_health < life or player.ward.current_ward < player.ward.max_ward, "Volatile: standing by a corpse when it blows up hurts")
	_finished += 1
