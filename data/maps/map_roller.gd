extends RefCounted
class_name MapRoller
## Rolls a fresh MapItem on demand (called by MapDevice.gd on interact -
## there's no map inventory/stash to draw pre-rolled maps from, this
## project only has the one Map anyway). Invented and undocumented: no
## map-item table exists anywhere in the referenced docs (Section 25
## covers weapon/armor item tables, not Maps), so both the affix pool and
## the tier-to-baseline-multiplier numbers here are placeholder tuning,
## not doc-sourced - same category as the other invented numbers flagged
## throughout this project.

const AFFIX_POOL := [
	{"target": "enemy_damage_multiplier", "min": 10.0, "max": 40.0, "desc": "%d%% increased Monster Damage"},
	{"target": "enemy_health_multiplier", "min": 10.0, "max": 50.0, "desc": "%d%% increased Monster Life"},
	{"target": "loot_quantity_multiplier", "min": 10.0, "max": 60.0, "desc": "%d%% increased Item Quantity"},
	{"target": "loot_rarity_multiplier", "min": 10.0, "max": 40.0, "desc": "%d%% increased Item Rarity"},
]

## affix_count: how many of the 4 pool entries to roll (no duplicates).
## Higher tiers roll more affixes and a higher rarity band, same
## increasing-danger-and-reward shape maps have in PoE, though the exact
## curve here is invented.
static func roll(tier: int) -> MapItem:
	var map := MapItem.new()
	map.item_id = "rolled_map_t%d_%d" % [tier, randi()]
	map.tier = tier
	map.display_name = "Tier %d Map" % tier
	map.flavor_text = "The device hums as it charts a path into hostile territory."

	var affix_count: int = clamp(1 + tier / 2, 1, AFFIX_POOL.size())
	map.rarity = Constants.ItemRarity.RARE if affix_count >= 3 else Constants.ItemRarity.UNCOMMON

	var pool := AFFIX_POOL.duplicate()
	pool.shuffle()
	for i in range(affix_count):
		var entry: Dictionary = pool[i]
		var roll_value: float = randf_range(entry["min"], entry["max"]) * (1.0 + tier * 0.1)
		var affix := ItemAffix.new()
		affix.stat_key = entry["target"]
		affix.value = roll_value
		affix.description = entry["desc"] % round(roll_value)
		map.affixes.append(affix)
		match entry["target"]:
			"enemy_damage_multiplier": map.enemy_damage_multiplier = 1.0 + roll_value / 100.0
			"enemy_health_multiplier": map.enemy_health_multiplier = 1.0 + roll_value / 100.0
			"loot_quantity_multiplier": map.loot_quantity_multiplier = 1.0 + roll_value / 100.0
			"loot_rarity_multiplier": map.loot_rarity_multiplier = 1.0 + roll_value / 100.0

	return map
