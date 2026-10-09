extends RefCounted
class_name ItemRequirements
## What an item needs to be equipped, worked out from the item itself so the
## card and the equip check always agree (Brief v3.8d's tables):
##   - character level from item level (LEVEL_TIERS)
##   - weapons: their type's stat(s) (WEAPON_STATS)
##   - armour and shields: the stat behind their defence - Armour needs
##     Strength, Evasion Agility, Ward Intellect; hybrids need both, the
##     larger defence as the primary
##   - accessories, jewels: level only
## Primary stat requirement uses the tier's primary value, a second stat the
## smaller secondary value.

## [min item level, max item level, character level, primary stat, secondary stat]
const LEVEL_TIERS := [
	[1, 10, 1, 0, 0],
	[11, 20, 8, 5, 3],
	[21, 30, 16, 10, 6],
	[31, 40, 24, 18, 11],
	[41, 50, 34, 28, 17],
	[51, 60, 44, 40, 24],
	[61, 70, 56, 55, 33],
	[71, 80, 68, 72, 43],
	[81, 90, 80, 92, 55],
	[91, 999999, 92, 115, 69],
]

const WEAPON_STATS := {
	"greatsword": ["strength", ""], "claymore": ["strength", ""], "mace": ["strength", ""],
	"war_pick": ["strength", ""], "pressure_fist": ["strength", ""], "shortsword": ["strength", ""],
	"greataxe": ["strength", ""],
	"loaded_shotgun": ["strength", ""], "pump_action_shotgun": ["strength", ""],
	"machine_gun": ["strength", ""], "battle_rifle": ["strength", ""],
	"dagger": ["agility", ""], "whip": ["agility", ""], "service_pistol": ["agility", ""],
	"revolver": ["agility", ""], "machine_pistol": ["agility", ""], "submachine_gun": ["agility", ""],
	"shortbow": ["agility", ""], "longbow": ["agility", ""], "bow": ["agility", ""],
	"lever_action_rifle": ["agility", ""], "bolt_action_rifle": ["agility", ""], "crossbow": ["agility", ""],
	"wand": ["intellect", ""], "staff": ["intellect", ""], "athame": ["intellect", ""],
	"spell_gauntlet": ["intellect", ""], "gauntlet": ["intellect", ""],
	"rod": ["intellect", ""], "grimoire": ["intellect", ""], "tome": ["intellect", ""],
	"talisman": ["intellect", ""], "fetish": ["intellect", ""],
	"rapier": ["agility", "strength"], "saber": ["agility", "strength"],
	"cutlass": ["strength", "agility"], "halberd": ["strength", "agility"], "spear": ["strength", "agility"],
	"shock_lance": ["agility", "intellect"],
}

static func _tier(item_level: int) -> Array:
	for tier in LEVEL_TIERS:
		if item_level >= tier[0] and item_level <= tier[1]:
			return tier
	return LEVEL_TIERS[0]

## {"level": int, "strength": int, "agility": int, "intellect": int}
static func of(item: Item) -> Dictionary:
	var tier := _tier(item.item_level)
	var result := {"level": tier[2], "strength": 0, "agility": 0, "intellect": 0}
	var stats := _stats_for(item)
	if stats.size() > 0 and stats[0] != "":
		result[stats[0]] = tier[3]
	if stats.size() > 1 and stats[1] != "":
		result[stats[1]] = tier[4]
	return result

## [primary stat, secondary stat] names ("" for none).
static func _stats_for(item: Item) -> Array:
	if item is Weapon:
		return WEAPON_STATS.get(ItemRoller._weapon_type_key(item as Weapon), ["", ""])
	var defences: Array = []
	for pair in [["armor_value", "strength"], ["evasion_value", "agility"], ["ward_value", "intellect"]]:
		var value = item.get(pair[0])
		if value != null and float(value) > 0.0:
			defences.append([float(value), pair[1]])
	defences.sort_custom(func(a, b): return a[0] > b[0])
	var stats: Array = defences.map(func(d): return d[1])
	stats.resize(2)
	return stats.map(func(s): return s if s != null else "")

## "" when the player meets every requirement, else why not.
static func block_reason(item: Item, player_level: int, stat_sheet: StatSheet) -> String:
	var req := of(item)
	if player_level < req["level"]:
		return "Requires character level %d" % req["level"]
	if stat_sheet == null:
		return ""
	for pair in [["strength", Constants.Stat.STRENGTH], ["agility", Constants.Stat.AGILITY], ["intellect", Constants.Stat.INTELLECT]]:
		var need: int = req[pair[0]]
		var have := stat_sheet.get_stat(pair[1])
		if need > 0 and have < need:
			return "Requires %d %s (have %.0f)" % [need, String(pair[0]).capitalize(), have]
	return ""
