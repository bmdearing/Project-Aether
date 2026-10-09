extends Node
## Gear stats actually doing something: canonical stat keys (StatKeys) feeding
## damage, life, mana and crit; level-gated tiers; % / flat / hybrid weapon
## damage mods; Infusion and flat crit on the card; GearEffects conditional
## damage and on-hit gains; Slate drops with modifiers that apply when placed;
## the doc's accessories and base fixes; the pause menu Wiki.
## Run: Godot --headless --path . res://tests/gear/test_gear_stats.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const TEST_COUNT := 15

var _checks := 0
var _failures := 0
var _finished := 0
var _hub: Node
var _player: Player

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_hub = load(HUB).instantiate()
	add_child(_hub)
	await _frames(5)
	_player = get_tree().get_first_node_in_group("player") as Player
	_test_tiers()
	_test_weapon_mods()
	_test_card()
	_test_damage_stats()
	_test_resources()
	await _test_gear_effects()
	await _test_mechanics()
	_test_slates()
	_test_bases()
	await _test_pause_wiki()
	_test_roll_fixes()
	_test_corruption()
	_test_card_lines()
	_test_requirements()
	await _test_void_drops()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("gear stat tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _affix(key: String, value: float, desc: String = "") -> ItemAffix:
	var a := ItemAffix.new()
	a.stat_key = key
	a.value = value
	a.description = desc if desc != "" else key
	return a

func _sword() -> Weapon:
	var w := Weapon.new()
	w.weapon_type = "Greatsword"
	w.display_name = "Stat Test Sword"
	w.base_damage_min = 10.0
	w.base_damage_max = 20.0
	w.native_damage_type = Constants.DamageType.KINETIC
	return w

func _test_tiers() -> void:
	_check(ItemRoller.best_tier_for_level(1) == ItemRoller.TIER_COUNT and ItemRoller.best_tier_for_level(80) == 1, "Tier 1 needs item level 80, level 1 gets the worst tier")
	_check(ItemRoller.best_tier_for_level(40) > 1 and ItemRoller.best_tier_for_level(40) < ItemRoller.TIER_COUNT, "tiers open up with item level")
	var low_max := 0.0
	var high_max := 0.0
	for i in 200:
		low_max = maxf(low_max, ItemRoller.roll_levelled_tier("local_increased_weapon_damage", 1)["max"])
		high_max = maxf(high_max, ItemRoller.roll_levelled_tier("local_increased_weapon_damage", 91)["max"])
	_check(is_equal_approx(low_max, 39.0), "level 1 Weapon Damage rolls 30-39%")
	_check(is_equal_approx(high_max, 190.0), "high-level Weapon Damage reaches 190%")
	_check(ItemRoller.levelled_tiers_for("local_increased_spell_damage", 91).size() == 8, "Spell Damage uses the same 8-tier 30-190% table")
	var jewel_best := JewelModifierPool.best_tier_for(1)
	_check(jewel_best == JewelModifierPool.TIER_COUNT and JewelModifierPool.best_tier_for(80) == 1, "jewel tiers are level-gated too")
	_finished += 1

func _test_weapon_mods() -> void:
	var w := _sword()
	w.affixes.append(_affix("local_flat_weapon_damage", 10.0))
	_check(w.get_damage_range() == Vector2(20, 38), "Adds 10 to 18 on a 10-20 base: %s" % w.get_damage_range())
	var hybrid := _sword()
	hybrid.affixes.append(_affix("local_hybrid_weapon_damage", 50.0))
	_check(is_equal_approx(hybrid.get_local_multiplier("local_increased_weapon_damage"), 1.5) and hybrid.get_flat_added_damage().x == 10.0, "hybrid: +50% and Adds 10 to 18")
	_check(ItemRoller.describe_value("Adds %d to %d Weapon Damage", "local_flat_weapon_damage", 10.0) == "Adds 10 to 18 Weapon Damage", "flat damage text")
	_check(ItemRoller.describe_value("+%d%% to Cold Resistance", "cold_resistance", -30.0) == "-30% to Cold Resistance", "a negative resistance reads -30%, not +-30%")
	_check(ItemRoller.describe_value("+%d%% increased Attack Speed", "attack_speed", -25.0) == "25% reduced Attack Speed", "a negative increase reads as reduced")
	_check(ItemRoller.describe_value("%d%% reduced Mana cost of skills", "mana_cost_reduction", -50.0) == "50% increased Mana cost of skills", "a negative reduction reads as increased")
	var mana_pool := ManaComponent.new()
	add_child(mana_pool)
	mana_pool.set_max_mana(325.0)
	_check(mana_pool.current_mana == 325.0, "raising max Mana keeps a full pool full")
	mana_pool.spend(100.0)
	mana_pool.set_max_mana(200.0)
	_check(mana_pool.current_mana == 200.0, "lowering it clamps the pool")
	mana_pool.free()
	var crit := _sword()
	var base_crit := crit.get_local_crit_chance()
	crit.affixes.append(_affix("generic_of_the_sharp", 4.0))
	_check(is_equal_approx(crit.get_local_crit_chance(), base_crit + 0.04), "flat crit chance adds to the weapon's own crit")
	var fast := _sword()
	fast.affixes.append(_affix("generic_fluid", 15.0))
	_check(is_equal_approx(fast.get_local_multiplier("local_increased_attack_speed"), 1.15), "library Attack Speed mods are local")
	var rolled_any_flat := false
	for i in 300:
		var r := ItemRoller.roll(60)
		if r is Weapon and not (r as Weapon).is_conduit:
			for a in r.affixes:
				if a.key() == "local_flat_weapon_damage" or a.key() == "local_hybrid_weapon_damage":
					rolled_any_flat = true
	_check(rolled_any_flat, "flat and hybrid damage mods roll on drops")
	var conduit := _sword()
	conduit.affixes.append(_affix("local_increased_cast_speed", 15.0))
	_check(conduit.get_conduit_cast_speed_bonus() == 0.0, "local Cast Speed only counts on a Conduit")
	conduit.is_conduit = true
	_check(is_equal_approx(conduit.get_conduit_cast_speed_bonus(), 15.0), "a Conduit's local Cast Speed reaches the character")
	_finished += 1

func _card_text(card: ItemCard) -> String:
	var texts: Array[String] = []
	for c in card.find_children("*", "", true, false):
		if c is Label:
			texts.append((c as Label).text)
		elif c.get("label") != null and c.get("value") != null:
			texts.append("%s: %s" % [c.get("label"), c.get("value")])
	return "\n".join(texts)

func _test_card() -> void:
	var crossbow := _sword()
	crossbow.native_damage_type = Constants.DamageType.PIERCING
	crossbow.infused_damage_type = Constants.DamageType.FIRE
	crossbow.affixes.append(_affix("generic_of_the_sharp", 4.0, "+4.0% Critical Strike Chance"))
	crossbow.affixes.append(_affix("local_flat_weapon_damage", 10.0, "Adds 10 to 18 Weapon Damage"))
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	add_child(card)
	card.display_item(crossbow)
	var text := _card_text(card)
	_check(text.contains("Fire Damage") and not text.contains("Piercing Damage"), "an infused weapon's card shows its infused type")
	_check(text.contains("20 to 38"), "the damage line includes flat added damage")
	var expected_crit := "%s%%" % card._format_num(snapped(crossbow.get_local_crit_chance() * 100.0, 0.1))
	_check(text.contains("Crit Chance: " + expected_crit), "the crit line includes flat crit (%s)" % expected_crit)
	_check(crossbow.get_damage_type() == Constants.DamageType.FIRE, "infused weapons deal their infused type")
	card.queue_free()
	_finished += 1

func _test_damage_stats() -> void:
	var sheet := _player.stat_sheet
	var saved: Dictionary = sheet.misc_bonus
	var w := _sword()
	sheet.misc_bonus = {}
	var plain := w.predict_damage(1.0, sheet)
	sheet.misc_bonus = {"increased_physical_damage": 50.0}
	_check(w.predict_damage(1.0, sheet) > plain * 1.2, "% increased Physical damage raises Kinetic weapon hits")
	sheet.misc_bonus = {"increased_kinetic_damage": 50.0}
	_check(w.predict_damage(1.0, sheet) > plain * 1.2, "% increased Kinetic damage raises Kinetic weapon hits")
	sheet.misc_bonus = {"increased_fire_damage": 50.0}
	_check(is_equal_approx(w.predict_damage(1.0, sheet), plain), "Fire damage doesn't touch a Kinetic weapon")
	w.infused_damage_type = Constants.DamageType.FIRE
	_check(w.predict_damage(1.0, sheet) > plain * 1.2, "...until it's infused with Fire")
	sheet.misc_bonus = saved
	# Library and implicit names reach the same stats.
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.affixes.append(_affix("fire_scorching", 40.0))
	ring.affixes.append(_affix("generic_of_strength", 10.0))
	ring.affixes.append(_affix("generic_deadly", 30.0))
	ring.affixes.append(_affix("increased_bleed_damage", 20.0))
	var equipment := EquipmentComponent.new()
	equipment.rings = [ring]
	var misc := equipment.compute_misc_bonuses()
	_check(misc.get("increased_fire_damage", 0.0) == 40.0, "fire_scorching counts as increased Fire damage")
	_check(misc.get("crit_damage_increased", 0.0) == 30.0, "generic_deadly counts as Critical Strike damage")
	_check(misc.get("increased_ailment_damage_bleed", 0.0) == 20.0, "implicit Bleed damage counts as Bleed damage")
	_check(equipment.compute_stat_bonuses().get(Constants.Stat.STRENGTH, 0.0) == 10.0, "+Strength library mods count as Strength")
	_check(not misc.has("local_flat_crit_chance"), "local mods stay on their weapon")
	equipment.free()
	_finished += 1

func _test_resources() -> void:
	var sheet := _player.stat_sheet
	var saved: Dictionary = sheet.misc_bonus
	sheet.misc_bonus = {}
	_player._apply_derived_stats()
	var life := _player.health.max_health
	var mana := _player.mana.max_mana
	sheet.misc_bonus = {"flat_life": 50.0, "life_increased": 10.0, "flat_mana": 20.0, "mana_increased": 10.0, "ward_recovery_increased": 25.0, "flat_aether": 5.0}
	_player._apply_derived_stats()
	_check(is_equal_approx(_player.health.max_health, (life + 50.0) * 1.1), "flat Life and increased Life apply")
	_check(is_equal_approx(_player.mana.max_mana, (mana + 20.0) * 1.1), "flat Mana and increased Mana apply")
	_check(is_equal_approx(_player.ward.restoration_multiplier, 1.25), "increased Ward Recovery applies")
	_check(_player.fate_board.aether_capacity == FateBoard.capacity_for_level(GameState.player_level) + 5, "flat Aether capacity applies")
	sheet.misc_bonus = saved
	_player._apply_derived_stats()
	_finished += 1

func _test_gear_effects() -> void:
	var sheet := _player.stat_sheet
	var saved: Dictionary = sheet.misc_bonus
	var arena := Node3D.new()
	add_child(arena)
	var enemy := EnemyRoster.create_unit("hollowed_shambler")
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = _player.global_position + Vector3(0, 0, -2)
	await _frames(2)
	sheet.misc_bonus = {"damage_vs_chilled": 100.0, "life_on_hit": 5.0}
	enemy.health.max_health = 100000.0
	enemy.health.current_health = 50000.0
	_player.health.current_health = _player.health.max_health - 20.0
	var before := enemy.health.current_health
	enemy.take_damage(100.0, Constants.DamageType.KINETIC)
	var plain_loss := before - enemy.health.current_health
	EventBus.damage_dealt.emit(_player, enemy, plain_loss, Constants.DamageType.KINETIC, false, false)
	var no_chill_loss := before - enemy.health.current_health
	_check(is_equal_approx(no_chill_loss, plain_loss), "no bonus against an enemy that isn't Chilled")
	_check(is_equal_approx(_player.health.current_health, _player.health.max_health - 15.0), "Life on hit heals")
	enemy.status_effects.apply_effect("chill", _player, 10.0)
	_check(enemy.status_effects.has_effect("chill"), "chill landed for the test")
	before = enemy.health.current_health
	EventBus.damage_dealt.emit(_player, enemy, 100.0, Constants.DamageType.KINETIC, false, false)
	_check(before - enemy.health.current_health > 50.0, "+100% damage vs Chilled deals an extra share of the hit")
	sheet.misc_bonus = saved
	enemy.queue_free()
	arena.queue_free()
	await _frames(1)
	_finished += 1

func _test_slates() -> void:
	var rare := 0
	var with_mods := 0
	for i in 200:
		var s := SlateRoller.roll(40, 20.0)
		if s.rarity >= Constants.SlateRarity.RARE:
			rare += 1
			if s.explicits.size() >= 3:
				with_mods += 1
	_check(rare > 0 and with_mods == rare, "Rare Slate drops carry 3-4 modifiers (%d/%d)" % [with_mods, rare])
	var commons := 0
	for i in 50:
		if SlateRoller.roll(40, 0.0).explicits.is_empty():
			commons += 1
	_check(commons == 50, "Common Slates have no modifiers")
	var stubs := 0
	for tag in SlateAffixPool.get_all_tags():
		for a in SlateAffixPool.get_pool_for_tag(tag):
			if a.description.contains("stub"):
				stubs += 1
	_check(stubs == 0, "no placeholder Slate modifiers are left")
	var slate := Slate.new()
	slate.shape_cells = [Vector2i(0, 0), Vector2i(1, 0)]
	slate.tag = Constants.DamageType.FIRE
	slate.explicits.append(_affix("fire_increased_damage", 20.0, "+20% increased Fire damage"))
	var board := FateBoard.new()
	var placed := FateBoard.PlacedSlateData.new()
	placed.slate = slate
	board.placements["test"] = placed
	_check(ChainCalculator.slate_misc_bonuses(board).get("increased_fire_damage", 0.0) == 20.0, "a placed Slate's modifiers reach the character")
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	add_child(card)
	card.display_slate(slate)
	_check(_card_text(card).contains("+20% increased Fire damage"), "the Slate card lists its modifiers")
	card.queue_free()
	_finished += 1

func _test_bases() -> void:
	for id in ["agility_pendant", "intellect_pendant", "convergence_pendant", "aetheric_conduit", "vital_pendant", "resonant_pendant", "ward_ring", "vital_ring", "resonant_ring", "iron_ring", "swift_ring", "iron_belt", "leather_belt", "strength_belt"]:
		var item := load("res://data/items/instances/%s.tres" % id) as Item
		_check(item != null and not item.affixes.is_empty() and item.affixes[0].is_implicit, "%s exists with its implicit" % id)
	var vest := load("res://data/armor/instances/gen_body_armour_specters_carapace.tres") as Armor
	_check(vest.evasion_value > 1000.0, "high-level evasion armours have their defence (%d)" % vest.evasion_value)
	_check(not vest.affixes.is_empty(), "final armour tiers carry their implicit")
	var dagger := load("res://data/weapons/instances/gen_dagger_voidfang.tres") as Weapon
	_check(dagger and dagger.affixes.any(func(a): return a.key() == "local_increased_crit_chance"), "weapon lines carry their implicit throughout")
	for path in ["res://data/weapons/instances/gen_battle_rifle_sundering_battle_rifle.tres", "res://data/armor/instances/gen_body_armour_bastion_warplate.tres", "res://data/weapons/instances/gen_bolt_action_rifle_field_bolt_rifle.tres"]:
		_check(ResourceLoader.exists(path), "%s was restored" % path.get_file())
	_check(ItemRoller._is_excluded_line("throwing_knives_line1"), "Throwing Knives don't drop")
	_finished += 1

func _test_pause_wiki() -> void:
	var menus := _hub.find_children("*", "PauseMenu", true, false)
	var pause: PauseMenu = menus.front() if not menus.is_empty() else null
	_check(pause != null and pause.find_child("WikiButton", true, false) != null, "the pause menu has a Wiki button")
	if pause:
		pause._show_wiki(true)
		await _frames(1)
		_check(pause._wiki_center.visible and pause._wiki.uniques.listed_ids().size() == UniqueCatalog.DEFS.size(), "it opens the Unique wiki")
		pause._show_wiki(false)
	_finished += 1

func _enemy_near() -> Enemy:
	var enemy := EnemyRoster.create_unit("hollowed_shambler")
	_hub.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = _player.global_position + Vector3(0, 0, -2)
	return enemy

## The modifiers that needed a mechanic: ailment strength, Freeze threshold,
## Aetherburn, Stagger, explosion procs, debuff modifiers, stealth, stance.
func _test_mechanics() -> void:
	var sheet := _player.stat_sheet
	var saved: Dictionary = sheet.misc_bonus
	var enemy := _enemy_near()
	await _frames(2)
	var status := enemy.status_effects
	sheet.misc_bonus = {}
	status.apply_effect("chill", _player)
	var base_slow := status.get_move_speed_multiplier()
	status.clear_all_effects()
	sheet.misc_bonus = {"chill_effect": 100.0}
	status.apply_effect("chill", _player)
	_check(status.get_move_speed_multiplier() < base_slow, "Chill effectiveness slows more (%.2f < %.2f)" % [status.get_move_speed_multiplier(), base_slow])
	status.clear_all_effects()
	sheet.misc_bonus = {"shock_effect": 100.0, "ailment_effectiveness": 0.0}
	status.apply_effect("shock", _player)
	_check(is_equal_approx(status.get_shock_multiplier(), 1.0 + StatusEffectComponent.SHOCK_DAMAGE_INCREASE * 2.0), "Shock effectiveness doubles its bonus")
	status.clear_all_effects()
	sheet.misc_bonus = {"freeze_threshold_reduction": 34.0}
	_check(StatusEffectComponent.freeze_stacks_needed(_player) == 2, "reduced Freeze threshold freezes on fewer Chills")
	status.apply_effect("chill", _player)
	status.apply_effect("chill", _player)
	_check(status.has_effect("freeze"), "two Chills freeze with it")
	status.clear_all_effects()
	sheet.misc_bonus = {}
	enemy._ward_pool = 500.0
	enemy._ward_current = 500.0
	status.apply_effect("aetherburn", _player, 400.0)
	_check(status.has_effect("aetherburn") and StatusEffectComponent.AILMENT_IDS.has("aetherburn"), "Aetherburn is a real ailment")
	await get_tree().create_timer(0.7).timeout
	_check(enemy.get_ward() < 500.0, "Aetherburn ticks burn Ward (%.0f)" % enemy.get_ward())
	status.clear_all_effects()

	# Stagger
	enemy._ward_pool = 0.0
	enemy._ward_current = 0.0
	sheet.misc_bonus = {}
	enemy.stance.reset()
	enemy.stance.apply_attack_stance_damage(100.0, Constants.DamageType.KINETIC)
	var plain_drain := enemy.stance.max_stance - enemy.stance.current_stance
	enemy.stance.reset()
	sheet.misc_bonus = {"stagger_effect": 100.0}
	enemy.stance.apply_attack_stance_damage(100.0, Constants.DamageType.KINETIC)
	_check(is_equal_approx(enemy.stance.max_stance - enemy.stance.current_stance, plain_drain * 2.0), "Stagger effect doubles Stance damage")
	enemy.stance.reset()
	_check(not enemy.is_staggered(), "not Staggered by default")
	sheet.misc_bonus = {"stagger_chance": 100.0, "damage_vs_staggered": 100.0}
	enemy.health.max_health = 100000.0
	enemy.health.current_health = 50000.0
	var before := enemy.health.current_health
	EventBus.damage_dealt.emit(_player, enemy, 100.0, Constants.DamageType.KINETIC, false, false)
	_check(enemy.is_staggered(), "Stagger chance staggers")
	_check(before - enemy.health.current_health > 50.0, "Staggered enemies take the bonus")
	sheet.misc_bonus = {"explosion_stun_chance": 100.0}
	EventBus.damage_dealt.emit(_player, enemy, 100.0, Constants.DamageType.EXPLOSIVE, false, false)
	_check(status.is_stunned(), "explosions can Stun")
	status.clear_all_effects()
	sheet.misc_bonus = {"explosion_bleed": 20.0}
	EventBus.damage_dealt.emit(_player, enemy, 100.0, Constants.DamageType.EXPLOSIVE, false, false)
	_check(status.has_effect("bleed"), "explosions leave a Bleed")
	status.clear_all_effects()

	# Debuff modifiers
	sheet.misc_bonus = {}
	var out_plain := enemy.get_outgoing_damage_multiplier()
	status.apply_effect("unraveling", _player)
	sheet.misc_bonus = {"unraveled_damage_reduction": 20.0}
	_check(is_equal_approx(enemy.get_outgoing_damage_multiplier(), out_plain * 0.8), "Unraveled enemies deal less damage")
	status.clear_all_effects()
	sheet.misc_bonus = {}
	status.apply_effect("pallid", _player)
	before = enemy.health.current_health
	enemy.take_damage(100.0, Constants.DamageType.PALE, true)
	var pallid_plain := before - enemy.health.current_health
	sheet.misc_bonus = {"pallid_damage_taken": 50.0}
	before = enemy.health.current_health
	enemy.take_damage(100.0, Constants.DamageType.PALE, true)
	_check(before - enemy.health.current_health > pallid_plain * 1.4, "Pallid enemies take more damage")
	status.clear_all_effects()

	# Spell damage while in stance
	var spell := load("res://data/abilities/instances/cinder_lance.tres") as Ability
	sheet.misc_bonus = {"spell_damage_in_stance": 100.0}
	sheet.in_stance = false
	var out_of_stance := spell.predict_damage_range(sheet).y
	sheet.in_stance = true
	_check(spell.predict_damage_range(sheet).y > out_of_stance * 1.3, "Spell damage in stance applies only in stance")
	sheet.in_stance = false
	sheet.misc_bonus = saved
	enemy.queue_free()
	await _frames(1)
	_finished += 1

## One modifier per stat on drops, whole skill levels, implicits kept.
func _test_roll_fixes() -> void:
	var dupes := 0
	var kept_implicits := 0
	var accessories := 0
	for i in 400:
		var item := ItemRoller.roll(85, 5.0)
		if item == null or item.rarity >= Constants.ItemRarity.UNIQUE:
			continue
		var keys := item.affixes.filter(func(a): return not a.is_implicit).map(func(a): return a.key())
		for k in keys:
			if keys.count(k) > 1:
				dupes += 1
		if item.get_item_type() in [&"ring", &"amulet", &"belt"]:
			accessories += 1
			if item.affixes.any(func(a): return a.is_implicit):
				kept_implicits += 1
	_check(dupes == 0, "no item rolls two modifiers for the same stat (%d)" % dupes)
	_check(accessories > 0 and kept_implicits == accessories, "dropped jewellery keeps its implicit (%d/%d)" % [kept_implicits, accessories])
	var levels := {}
	for i in 300:
		var r := ItemRoller.roll_tier_range("skill_level_entropic", 1.0, 2.0, 90)
		levels[ItemRoller.roll_value("skill_level_entropic", Vector2(r["min"], r["max"]))] = r["tier"]
	_check(levels.keys().all(func(v): return v == 1.0 or v == 2.0) and levels.get(1.0) == 2 and levels.get(2.0) == 1, "skill levels are +1 at Tier 2, +2 at Tier 1: %s" % levels)
	_check(ItemRoller.roll_tier_range("skill_level_entropic", 1.0, 2.0, 30)["max"] == 1.0, "+2 needs item level 80")
	_finished += 1

func _test_corruption() -> void:
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	_check(not ImplicitPool.pool_for_type(&"ring").is_empty() and not ImplicitPool.pool_for_type(&"greatsword").is_empty(), "implicit pools come from the bases")
	var implicit := ImplicitPool.get_random_for(ring)
	_check(implicit != null and implicit.is_implicit, "Add Implicit finds one")
	var special := SpecialCorruptionPool.get_random_for(ring)
	_check(special != null and special.description.ends_with("(Corrupted)"), "Add Special Affix rolls a corrupted modifier")
	var affix := ItemAffix.new()
	affix.stat_key = "flat_strength"
	affix.tier = 3
	var r3 := ItemRoller.tier_range_for(affix, 3)
	affix.value_min = r3.x
	affix.value_max = r3.y
	affix.value = r3.y
	ItemRoller.retier(affix, 2)
	_check(affix.tier == 2 and is_equal_approx(affix.value, ItemRoller.tier_range_for(affix, 2).y), "Tier Up moves the value into the better tier")
	var sheet := _player.stat_sheet
	var saved: Dictionary = sheet.misc_bonus
	sheet.misc_bonus = {"no_ward_recovery_life_bonus": 35.0}
	var before_life := _player.health.max_health
	_player._apply_derived_stats()
	_check(_player.health.max_health > before_life * 1.3, "Pale Branded raises max Life")
	sheet.misc_bonus = saved
	_player._apply_derived_stats()
	_finished += 1

func _test_card_lines() -> void:
	var w := _sword()
	w.affixes.append(_affix("local_hybrid_weapon_damage", 20.0, "+20% increased Weapon Damage, Adds 4 to 7 Weapon Damage (Tier 6)"))
	w.affixes.append(_affix("local_flat_weapon_damage", 3.0, "Adds 3 to 5 Weapon Damage (Tier 8)"))
	w.affixes.append(_affix("local_increased_weapon_damage", 36.0, "+36% increased Weapon Damage (Tier 7)"))
	w.affixes.append(_affix("generic_of_intellect", 11.0, "+11 Intellect"))
	w.affixes.append(_affix("aetheric_of_the_invoke", 10.0, "+10 Intellect"))
	for a in w.affixes:
		a.affix_id = a.stat_key
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	var lines := card._merged_explicit_lines(w)
	_check(lines.has("+56% increased Weapon Damage") and lines.has("Adds 7 to 12 Weapon Damage"), "the hybrid splits and merges with same-stat lines: %s" % [lines])
	_check(lines.has("+21 Intellect") and lines.size() == 3, "two Intellect rolls read as one line")
	var only_hybrid := _sword()
	only_hybrid.affixes.append(w.affixes[0])
	_check(card._merged_explicit_lines(only_hybrid).size() == 2, "a lone hybrid shows as two lines")
	var base := load("res://data/armor/instances/gen_body_armour_shadow_vest.tres") as Item
	card.display_item(base)
	_check(not _card_text(card).contains("Maximum Evasion"), "base line names don't show as flavour")
	card.free()
	_finished += 1

## Requirements follow the defence (Armour Str, Evasion Agi, Ward Int); one
## rule for the card and the equip check.
func _test_requirements() -> void:
	var barrier := load("res://data/shields/instances/gen_warded_barrier_iron_warded_barrier.tres") as Item
	var req := ItemRequirements.of(barrier)
	_check(req["intellect"] > 0 and req["strength"] == 0, "a Ward shield needs Intellect: %s" % req)
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	card.display_item(barrier)
	var text := _card_text(card)
	_check(text.contains("Ward: "), "the shield card shows its Ward")
	var kite := load("res://data/shields/instances/gen_kite_shield_crude_kite_shield.tres") as Item
	if kite:
		var kite_req := ItemRequirements.of(kite)
		kite.item_level = 40
		kite_req = ItemRequirements.of(kite)
		_check(kite_req["strength"] > 0 or kite_req["agility"] > 0, "Kite Shields need their defences' stats: %s" % kite_req)
	var vest := load("res://data/armor/instances/gen_body_armour_shadow_vest.tres") as Item
	_check(ItemRequirements.of(vest)["agility"] > 0, "evasion armour needs Agility")
	var ring := load("res://data/items/instances/ember_ring.tres") as Item
	var ring_req := ItemRequirements.of(ring)
	_check(ring_req["strength"] + ring_req["agility"] + ring_req["intellect"] == 0, "jewellery needs no stats")
	var saber := load("res://data/weapons/instances/gen_saber_hussars_blade.tres") as Item
	if saber:
		card.display_item(saber)
		_check(not _card_text(card).contains("Duelist"), "implicits read as sentences, not line labels: %s" % _card_text(card))
	card.free()
	_finished += 1

## A boss hovering over the void drops onto the nearest floor, or at your feet.
func _test_void_drops() -> void:
	var arena := Node3D.new()
	add_child(arena)
	_floor(arena, Vector3(900, -0.5, 906), Vector3(4, 1, 4))
	var enemy := EnemyRoster.create_unit("hollowed_shambler")
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(900, 0.5, 900)
	await get_tree().physics_frame
	await _frames(1)
	var spot := enemy._drop_position()
	_check(absf(spot.y - Enemy.DROP_HOVER) < 0.05 and spot.z > 903.0, "over the void, drops land on the nearest floor (%s)" % spot)
	enemy.global_position = Vector3(2000, 50, 2000)
	var near_player := enemy._drop_position()
	_check(near_player.distance_to(_player.global_position) < 2.0, "with no floor in reach they land at the player")
	enemy.queue_free()
	arena.queue_free()
	await _frames(1)
	_finished += 1

func _floor(parent: Node, centre: Vector3, box_size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = centre
	return body
