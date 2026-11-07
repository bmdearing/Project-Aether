extends Node
## Monster Infrequents: perk catalogue, MI rolls, saving, the gear
## Recombinator, perk stacking and the 4-line cap on drops.
## Run: Godot --headless --path . res://tests/perks/test_perks.tscn
## Exits 0 when every check passes. Never writes the save file.

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_catalog()
	_test_rolls()
	_test_recombine()
	_test_line_cap()
	print("perk tests: %d checks, %d failures" % [_checks, _failures])
	print("PERK_TESTS_DONE")
	get_tree().quit(1 if _failures > 0 else 0)

func _test_catalog() -> void:
	var sources_ok := true
	for id in PerkCatalog.PERKS:
		for source in PerkCatalog.PERKS[id]["sources"]:
			sources_ok = sources_ok and ResourceLoader.exists(MonsterInfrequent.DEFINITIONS_DIR % source)
	_check(sources_ok, "every perk source is a real enemy definition")
	_check(PerkCatalog.PERKS.keys().filter(func(id): return not PerkCatalog.is_boss(id)).size() == 30 and PerkCatalog.boss_perk("ataras") == &"falling_sun", "30 starter perks plus one per Pinnacle boss")
	_check(PerkCatalog.text_of(&"reload_on_kill", 20.0).contains("20%"), "perk text fills its value")
	_check(PerkCatalog.migrate_value(&"stench_aura", 4.0) == 25.0 and PerkCatalog.migrate_value(&"stench_aura", 20.0) == 20.0 \
			and PerkCatalog.migrate_value(&"last_round", 80.0) == 125.0, "reworked perks move old rolls into the new range, once")

func _test_rolls() -> void:
	var all_fit := true
	var all_rarity := true
	for id in PerkCatalog.PERKS:
		var mi := MonsterInfrequent.roll_perk(id, 70)
		if mi == null:
			all_fit = false
			print("  no base for ", id)
			continue
		all_fit = all_fit and PerkCatalog.fits(id, mi) and mi.perks.has(String(id))
		all_rarity = all_rarity and mi.rarity <= Constants.ItemRarity.RARE and mi.unique_id == ""
	_check(all_fit, "every perk rolls an MI on a base it fits")
	_check(all_rarity, "MIs are Uncommon or Rare, never Unique")
	var def := load(MonsterInfrequent.DEFINITIONS_DIR % "unchartered_brigand") as EnemyDefinition
	_check(MonsterInfrequent.drop_chance(def, Constants.EnemyRarity.CHAMPION, 1.0) > MonsterInfrequent.drop_chance(def, Constants.EnemyRarity.NORMAL, 1.0), "Champions drop MIs more often")
	var mi := MonsterInfrequent.roll(def, 70)
	_check(mi != null and mi.perks.has("reload_on_kill") and mi.display_name.begins_with("Unchartered Brigand"), "a Brigand drops its own perk, named after it")
	_check(mi != null and mi.display_color() == Constants.MONSTER_INFREQUENT_COLOR, "MIs show green")
	var back := ItemSerializer.from_dict(ItemSerializer.to_dict(mi))
	_check(back.perks.get("reload_on_kill", -1.0) == mi.perks["reload_on_kill"], "perks survive a save and load")
	var effects := PerkEffects.new()
	var copy := mi.duplicate(true) as Item
	copy.perks["reload_on_kill"] = 99.0
	effects.refresh([mi, copy] as Array[Item])
	_check(effects.value(&"reload_on_kill") == 99.0, "two copies of a perk count once, at the best roll")
	effects.free()

func _test_recombine() -> void:
	var base := MonsterInfrequent.roll_perk(&"opening_strike", 70)
	var donor := MonsterInfrequent.roll_perk(&"adjudicator_mark", 70)
	_check(GearRecombinator.error(base, donor) == "", "two MI gloves can recombine")
	var ring := MonsterInfrequent.roll_perk(&"element_shift", 70)
	_check(GearRecombinator.error(base, ring) != "", "different item types are refused")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var both := 0
	var lines_kept := true
	for i in 400:
		var result := GearRecombinator.recombine(base, donor, rng)
		lines_kept = lines_kept and result.affixes.size() == base.affixes.size()
		if result.perks.size() == 2:
			both += 1
		if result.perks.is_empty() or result.perks.size() > MonsterInfrequent.MAX_PERKS:
			lines_kept = false
	_check(lines_kept, "the result keeps the base's lines and holds 1-2 perks")
	_check(both > 120 and both < 220, "both perks survive about 42%% of the time (%d/400)" % both)
	var dup := base.duplicate(true) as Item
	dup.perks["opening_strike"] = 60.0
	var merged := GearRecombinator.recombine(base, dup, rng)
	_check(merged.perks.size() == 1 and merged.perks["opening_strike"] == 60.0, "the same perk merges to the better roll")
	var fused := base.duplicate(true) as Item
	fused.perks["adjudicator_mark"] = 25.0
	MonsterInfrequent.rename(fused)
	var plain := MonsterInfrequent.base_name(base)
	_check(MonsterInfrequent.is_fused(fused) and fused.display_name == "Cutthroat-Adjudicator's %s" % plain and MonsterInfrequent.base_name(fused) == plain,
			"a fused MI is named after both sources (%s)" % fused.display_name)

func _test_line_cap() -> void:
	var ok := true
	var scaled := false
	for i in 300:
		var item := ItemRoller.roll(80, 50.0)
		if item == null or item.unique_id != "":
			continue
		ok = ok and item.get_prefix_count() <= 2 and item.get_suffix_count() <= 2
	_check(ok, "drops never pass 2 prefixes / 2 suffixes")
	var r := ItemRoller.roll_tier_range("flat_life", 10.0, 10.0, 1)
	scaled = r["max"] > 10.0 * 0.5
	_check(ItemRoller.gear_line_scale("flat_life") == Constants.STAT_LINE_RESCALE and ItemRoller.gear_line_scale("move_speed") == 1.0, "rescale skips move speed")
	_check(scaled, "rolled ranges carry the rescale")
