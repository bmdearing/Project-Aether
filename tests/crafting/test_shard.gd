extends Node
## Shard of Tharsis: four equal results (nothing, bricked, an implicit or a
## good effect, both), the last three always change the item, and a Shard
## implicit replaces the item's implicits.
## Run: Godot --headless --path . res://tests/crafting/test_shard.tscn
## Exits 0 when every check passes.

const ROLLS := 2000

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _rare() -> Item:
	while true:
		var item := ItemRoller.roll(80, 1.0)
		if item and not item is Jewel and item.rarity == Constants.ItemRarity.RARE and not item.affixes.filter(func(a: ItemAffix): return not a.is_implicit).is_empty():
			return item
	return null

func _run() -> void:
	seed(4242)
	var counts := {1: 0, 2: 0, 3: 0, 4: 0}
	var unchanged := 0
	var stacked := 0
	for i in ROLLS:
		var item := _rare()
		var before := ItemSerializer.to_dict(item)
		var outcome := CorruptionSystem.corrupt(item, 80)
		counts[outcome.tier] += 1
		item.is_corrupted = before["is_corrupted"]
		item.is_craftable = before["is_craftable"]
		if outcome.tier != CorruptionSystem.OutcomeTier.NOTHING and ItemSerializer.to_dict(item) == before:
			unchanged += 1
		if outcome.tier >= CorruptionSystem.OutcomeTier.BLESSED and item.get_implicit_count() > 1:
			stacked += 1
	for tier in counts:
		_check(absf(counts[tier] / float(ROLLS) - 0.25) < 0.04, "%s is about 25%% (%d of %d)" % [CorruptionSystem.TIER_NAMES[tier], counts[tier], ROLLS])
	_check(unchanged == 0, "every result but No Change changes the item (%d didn't)" % unchanged)

	var item := _rare()
	var old := ImplicitPool.get_random_for(item)
	item.affixes.append(old)
	item.affixes.append(ImplicitPool.get_random_for(item))
	CorruptionOutcome.PaleBranded.new().apply(item, 80)
	var implicits := item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	_check(implicits.size() == 1 and implicits[0].affix_id == "corruption_pale_branded", "a Shard implicit replaces the item's implicits")

	print("shard tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
