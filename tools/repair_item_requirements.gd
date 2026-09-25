extends Node
## One-shot data migration (Implementation Brief v3.8d) - run headlessly
## via tools/repair_item_requirements.tscn, not part of the game itself.
## GDScript + Resource load()/ResourceSaver.save(), same as every other
## repair_*.gd in this directory - NOT the brief's own "Python, batch
## approach" snippet, which has no way to read/write a Godot .tres
## Resource at all.
##
## Populates the 4 new DISPLAY-ONLY fields added to Item.gd this patch
## (level_requirement, strength/agility/intellect_requirement) from each
## item's own item_level, via the brief's own tier tables. Does NOT touch
## the pre-existing stat_requirement/stat_requirement_value pair, which
## remains the actual ENFORCED equip gate (EquipmentComponent.
## _requirement_block_reason()) - these 4 new fields are cosmetic only
## this pass, per the brief's own "enforcement is a separate pass" DO NOT.
##
## Weapon type is read from base_line_id first (strip the trailing
## "_lineN"), falling back to weapon_type (normalized to snake_case) for
## the 7 hand-authored weapons with no base_line_id, falling back further
## to an item_id substring match for the one file with neither
## (crude_greatsword.tres has no weapon_type field either). Same 3-step
## fallback for the one hand-authored shield (guardians_kite_shield.tres).
##
## Two corrections to the brief's own WEAPON_STAT_MAP: (1) "gauntlet" is
## missing from every one of the brief's lists entirely - mapped here to
## single Intellect, matching Worn Gauntlet's own established v3.8 identity
## as this project's first conduit-flavored weapon (Aetheric damage,
## flat_resolve implicit) and consistent with every other main-hand
## conduit (wand/staff/athame/spell_gauntlet) already being single-
## Intellect. (2) the brief's prose calls out "battle_rifle (high damage
## line)" and "crossbow (bleed line)" as Strength+Agility dual, contradicting
## its own single-Strength/single-Agility WEAPON_STAT_MAP entries for the
## same two ids - no per-line table exists to actually resolve which
## specific lines would differ (unlike repair_weapon_lines.gd's real
## LINES table), so this follows the brief's own literal, executable
## dict: battle_rifle stays single Strength, crossbow stays single Agility,
## uniformly across every line of each.

const ITEM_DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

## (item_level_min, item_level_max, level_requirement, primary, secondary)
const TIERS := [
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

## base_line_id/weapon_type key -> [primary_stat, secondary_stat] ("" = none).
const WEAPON_STAT_MAP := {
	# Single Strength
	"greatsword": ["strength", ""], "claymore": ["strength", ""], "mace": ["strength", ""],
	"war_pick": ["strength", ""], "pressure_fist": ["strength", ""], "shortsword": ["strength", ""],
	"loaded_shotgun": ["strength", ""], "pump_action_shotgun": ["strength", ""],
	"machine_gun": ["strength", ""], "battle_rifle": ["strength", ""],
	# Single Agility
	"dagger": ["agility", ""], "whip": ["agility", ""], "service_pistol": ["agility", ""],
	"revolver": ["agility", ""], "machine_pistol": ["agility", ""], "submachine_gun": ["agility", ""],
	"shortbow": ["agility", ""], "longbow": ["agility", ""], "bow": ["agility", ""],
	"lever_action_rifle": ["agility", ""], "bolt_action_rifle": ["agility", ""], "crossbow": ["agility", ""],
	# Single Intellect (main-hand conduits + gauntlet, see header note)
	"wand": ["intellect", ""], "staff": ["intellect", ""], "athame": ["intellect", ""],
	"spell_gauntlet": ["intellect", ""], "gauntlet": ["intellect", ""],
	# Single Intellect (offhand conduits)
	"rod": ["intellect", ""], "grimoire": ["intellect", ""], "tome": ["intellect", ""],
	"talisman": ["intellect", ""], "fetish": ["intellect", ""],
	# Agility primary + Strength secondary
	"rapier": ["agility", "strength"], "saber": ["agility", "strength"],
	# Strength primary + Agility secondary
	"cutlass": ["strength", "agility"], "halberd": ["strength", "agility"], "spear": ["strength", "agility"],
	# Agility primary + Intellect secondary
	"shock_lance": ["agility", "intellect"],
	# Shields - single Strength
	"tower_shield": ["strength", ""], "great_shield": ["strength", ""], "kite_shield": ["strength", ""],
	"pavise": ["strength", ""], "rune_shield": ["strength", ""], "warded_barrier": ["strength", ""],
	# Shields - single Agility
	"buckler": ["agility", ""],
	# Shields - Strength primary + Agility secondary
	"spiked_shield": ["strength", "agility"],
}

var _scanned := 0
var _weapon_stats_set := 0
var _weapon_unmapped := 0
var _level_only_set := 0

func _ready() -> void:
	for dir_path in ITEM_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				_repair_file(dir_path + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	print("Scanned %d items - %d weapons/shields got stat requirements, %d weapons/shields had no type mapping (level only), %d armor/accessories got level_requirement only." % [_scanned, _weapon_stats_set, _weapon_unmapped, _level_only_set])
	get_tree().quit()

func _tier_for(item_level: int) -> Array:
	for tier in TIERS:
		if item_level >= tier[0] and item_level <= tier[1]:
			return tier
	return TIERS[0]

func _repair_file(path: String) -> void:
	var item: Item = load(path)
	if item == null:
		return
	_scanned += 1
	var tier := _tier_for(item.item_level)
	item.level_requirement = tier[2]

	if item is Weapon or item is Shield:
		var stat_key := _resolve_type_key(item)
		if WEAPON_STAT_MAP.has(stat_key):
			var mapping: Array = WEAPON_STAT_MAP[stat_key]
			_set_stat_requirement(item, mapping[0], tier[3])
			if mapping[1] != "":
				_set_stat_requirement(item, mapping[1], tier[4])
			_weapon_stats_set += 1
		else:
			_weapon_unmapped += 1
			push_warning("No weapon/shield stat mapping for %s (base_line_id=%s, item_id=%s)" % [path, item.base_line_id, item.item_id])
	else:
		# Armor and accessories (Item.gd directly, e.g. rings/amulets/belts)
		# get level_requirement only, per the brief - no stat commitment.
		_level_only_set += 1

	if ResourceSaver.save(item, path) != OK:
		push_error("Failed to save %s" % path)

func _set_stat_requirement(item: Item, stat_name: String, value: int) -> void:
	match stat_name:
		"strength": item.strength_requirement = value
		"agility": item.agility_requirement = value
		"intellect": item.intellect_requirement = value

## base_line_id (stripped of its trailing "_lineN") first, then weapon_type
## normalized to snake_case, then an item_id substring match against every
## known key - covers every real weapon/shield .tres in the project (see
## header for exactly which files need each fallback level).
func _resolve_type_key(item: Item) -> String:
	if item.base_line_id != "":
		var underscore := item.base_line_id.rfind("_line")
		return item.base_line_id.substr(0, underscore) if underscore != -1 else item.base_line_id
	if item is Weapon and (item as Weapon).weapon_type != "":
		return (item as Weapon).weapon_type.to_lower().replace(" ", "_")
	for key in WEAPON_STAT_MAP:
		if item.item_id.contains(key):
			return key
	return ""
