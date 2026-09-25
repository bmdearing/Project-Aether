extends Node
## One-shot data generator (Patch v3.6b Priority 3) - writes Shortbow/
## Longbow .tres tiers into data/weapons/instances/, matching the same
## field conventions tools/generate_base_types.gd already established for
## every other generated weapon (base_damage = tier range average,
## native_damage_type = Piercing per worn_bow.tres's own precedent,
## stat_requirement = Strength at 0.5/item_level, max_sockets ramping to
## the PRIMARY_WEAPON cap of 6). Run headlessly via tools/
## generate_bow_lines.tscn, not part of the game itself.
##
## Per-tier display names are simple, utilitarian placeholders - the
## brief this came from explicitly scopes naming polish to a separate pass.

const OUT_DIR := "res://data/weapons/instances/"
const ITEM_LEVELS := [1, 12, 23, 34, 46, 58, 72, 84]
const REQUIRED_STAT_PER_LEVEL := 0.5
const SOCKET_CAP := 6
const ST_STRENGTH := 0  # Constants.Stat.STRENGTH (pre-v3.8 six-stat STRENGTH was 1)
const DT_PIERCING := 1  # Constants.DamageType.PIERCING

const LINES := [
	{
		"weapon_type": "Shortbow", "base_line_id": "shortbow_line1", "type_suffix": "shortbow",
		"flavor_text": "Rapid Fire",
		"grades": [["instinct", 0]], "implicit_stat": null, "value": 0.0,
		"damage_ranges": [[8, 10], [14, 18], [22, 28], [32, 40], [44, 55], [58, 72], [74, 92], [92, 115]],
		"tier_names": ["Crude", "Quick", "Swift", "Rapid", "Barrage", "Fusillade", "Hailstorm", "Tempest"],
	},
	{
		"weapon_type": "Shortbow", "base_line_id": "shortbow_line2", "type_suffix": "shortbow",
		"flavor_text": "Kiting",
		"grades": [["instinct", 1]], "implicit_stat": "increased_damage_while_moving", "value": 16.0,
		"damage_ranges": [[7, 9], [12, 16], [19, 25], [28, 36], [38, 49], [50, 64], [64, 82], [80, 102]],
		"tier_names": ["Worn", "Nimble", "Fleet", "Evasive", "Skirmisher's", "Strider's", "Phantom", "Windwalker's"],
	},
	{
		"weapon_type": "Longbow", "base_line_id": "longbow_line1", "type_suffix": "longbow",
		"flavor_text": "Snipe",
		"grades": [["instinct", 0]], "implicit_stat": null, "value": 0.0,
		"damage_ranges": [[14, 18], [24, 30], [38, 48], [56, 70], [76, 96], [100, 126], [128, 160], [160, 200]],
		"tier_names": ["Rough", "Steady", "Marksman's", "Sniper's", "Deadeye's", "Longshot", "Farstrike", "Apex"],
	},
	{
		"weapon_type": "Longbow", "base_line_id": "longbow_line2", "type_suffix": "longbow",
		"flavor_text": "Rain of Arrows",
		"grades": [["instinct", 1], ["strength", 2]], "implicit_stat": "increased_aoe_radius", "value": 14.0,
		"damage_ranges": [[12, 15], [20, 26], [32, 40], [47, 59], [64, 80], [84, 106], [108, 136], [136, 170]],
		"tier_names": ["Crude", "Volley", "Barrage", "Storm", "Deluge", "Hailstorm", "Tempest's", "Cataclysm's"],
	},
]

var _count := 0

func _ready() -> void:
	for line in LINES:
		for i in range(ITEM_LEVELS.size()):
			_write_tier(line, i)
	print("Wrote %d bow weapon tiers across %d lines." % [_count, LINES.size()])
	get_tree().quit()

func _write_tier(line: Dictionary, tier_index: int) -> void:
	var w := Weapon.new()
	var item_level: int = ITEM_LEVELS[tier_index]
	var tier_name: String = line["tier_names"][tier_index]
	var range_pair: Array = line["damage_ranges"][tier_index]

	w.weapon_type = line["weapon_type"]
	w.base_damage = (float(range_pair[0]) + float(range_pair[1])) / 2.0
	var grades: Array = line["grades"]
	w.scaling_grade = grades[0][1] as int
	w.primary_scaling_stat = grades[0][0]
	w.secondary_scaling_stat = (grades[1][0] as String) if grades.size() > 1 else ""
	w.native_damage_type = DT_PIERCING
	w.is_two_handed = true
	w.is_ranged = true

	var slug := _slugify(tier_name)
	w.item_id = "gen_%s_%s_%s" % [line["base_line_id"].split("_line")[0], slug, line["type_suffix"]]
	w.display_name = "%s %s" % [tier_name, line["weapon_type"]]
	w.equip_slot = 4  # Constants.EquipmentSlot.PRIMARY_WEAPON
	w.max_sockets = clamp(tier_index + 2, 1, SOCKET_CAP)
	w.flavor_text = line["flavor_text"]
	w.item_level = item_level
	w.base_line_id = line["base_line_id"]
	w.stat_requirement = ST_STRENGTH
	w.stat_requirement_value = item_level * REQUIRED_STAT_PER_LEVEL

	if line["implicit_stat"] != null:
		var affix := ItemAffix.new()
		affix.stat_key = line["implicit_stat"]
		affix.value = line["value"]
		affix.is_implicit = true
		affix.display_name = _humanize(line["implicit_stat"])
		affix.description = "+%s%% %s" % [_format_value(line["value"]), affix.display_name]
		w.affixes = [affix]

	var path := "%s%s.tres" % [OUT_DIR, w.item_id]
	if ResourceSaver.save(w, path) == OK:
		_count += 1
	else:
		push_error("Failed to save %s" % path)

func _slugify(s: String) -> String:
	return s.to_lower().replace("'", "").replace(" ", "_")

func _humanize(stat_key: String) -> String:
	var words := stat_key.replace("increased_", "").split("_")
	var capitalized := PackedStringArray()
	for word in words:
		capitalized.append(word.capitalize())
	return " ".join(capitalized)

func _format_value(v: float) -> String:
	return str(int(v)) if v == floor(v) else str(v)
