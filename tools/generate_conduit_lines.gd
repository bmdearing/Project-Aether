extends Node
## One-shot data generator (Patch v3.6b Priority 4) - writes Conduit
## (caster weapon) .tres tiers into data/weapons/instances/. "Spell
## power" maps onto Weapon.base_damage - the same field every other
## weapon uses, since Conduits are still real Weapon instances routed
## through the same equip system even though actual spellcasting is
## independent of the weapon slot (see WeaponStance.gd's own header).
## Run headlessly via tools/generate_conduit_lines.tscn, not part of the
## game itself.
##
## native_damage_type/is_two_handed follow the one real precedent already
## in this project (data/weapons/instances/worn_staff.tres: Aetheric,
## two-handed) rather than inventing a new scheme - every Conduit here
## uses Aetheric; only Staff (matching worn_staff.tres) is two-handed,
## every other type stays one-handed so a main-hand + offhand Conduit
## pair is actually possible to equip together.
##
## Only Rod line1 is explicitly called "lower spell power" in the brief -
## every other offhand line uses the same full per-tier spell power table
## as main-hand lines, since the brief didn't say otherwise for them.
## LOWER_SPELL_POWER_FACTOR (0.6) is this project's own invented number
## for that one reduction, same "flag it, pick one, document it"
## convention used for every other unspecified number in this project.
##
## Per-tier display names are simple, shared placeholders (Line 1 vs
## Line 2 get their own 6-word set, reused across all 9 conduit types) -
## the brief this came from explicitly scopes naming polish to a
## separate pass.

const OUT_DIR := "res://data/weapons/instances/"
const ITEM_LEVELS := [1, 16, 32, 50, 68, 84]
const SPELL_POWER_RANGES := [[8, 12], [18, 24], [34, 44], [58, 74], [88, 112], [128, 160]]
const LOWER_SPELL_POWER_FACTOR := 0.6
const REQUIRED_STAT_PER_LEVEL := 0.5
const ST_STRENGTH := 0  # Constants.Stat.STRENGTH (pre-v3.8 six-stat STRENGTH was 1) - matches this project's one non-Arcane/Enigma requirement precedent isn't used here; see _requirement_stat_for()
const DT_AETHERIC := 6  # Constants.DamageType.AETHERIC - matches worn_staff.tres precedent

const LINE1_TIER_NAMES := ["Novice", "Adept", "Skilled", "Veteran", "Master", "Grand"]
const LINE2_TIER_NAMES := ["Lesser", "Common", "Charged", "Empowered", "Resonant", "Transcendent"]

## weapon_type -> {"suffix": item_id/base_line_id slug, "two_handed": bool}
const TYPE_META := {
	"Wand": {"suffix": "wand", "two_handed": false, "offhand": false},
	"Staff": {"suffix": "staff", "two_handed": true, "offhand": false},
	"Athame": {"suffix": "athame", "two_handed": false, "offhand": false},
	"Spell Gauntlet": {"suffix": "spell_gauntlet", "two_handed": false, "offhand": false},
	"Rod": {"suffix": "rod", "two_handed": false, "offhand": true},
	"Grimoire": {"suffix": "grimoire", "two_handed": false, "offhand": true},
	"Tome": {"suffix": "tome", "two_handed": false, "offhand": true},
	"Talisman": {"suffix": "talisman", "two_handed": false, "offhand": true},
	"Fetish": {"suffix": "fetish", "two_handed": false, "offhand": true},
}

## Each entry: weapon_type, line index (1/2), stance, grades, implicit_stat
## (null = S grade, no implicit), value, optional spell_page_tag, optional
## unleash_copy_count, optional lower_power flag.
const LINES := [
	{"type": "Wand", "line": 1, "stance": "spell_library", "grades": [["arcane", 0]], "implicit_stat": null, "value": 0.0},
	{"type": "Wand", "line": 2, "stance": "unleash", "grades": [["arcane", 1], ["intellect", 2]], "implicit_stat": "increased_spell_damage", "value": 14.0},
	{"type": "Staff", "line": 1, "stance": "unleash", "grades": [["arcane", 0]], "implicit_stat": null, "value": 0.0, "unleash_copy_count": 3},
	{"type": "Staff", "line": 2, "stance": "battlemage", "grades": [["arcane", 1], ["strength", 2]], "implicit_stat": "increased_physical_damage_reach", "value": 12.0},
	{"type": "Athame", "line": 1, "stance": "spell_library", "spell_page_tag": "esoteric", "grades": [["enigma", 0]], "implicit_stat": null, "value": 0.0},
	{"type": "Athame", "line": 2, "stance": "stance_buff", "grades": [["enigma", 1], ["intellect", 2]], "implicit_stat": "increased_esoteric_damage", "value": 16.0},
	{"type": "Spell Gauntlet", "line": 1, "stance": "mana_stars", "grades": [["arcane", 0]], "implicit_stat": null, "value": 0.0},
	{"type": "Spell Gauntlet", "line": 2, "stance": "battlemage", "grades": [["arcane", 1], ["strength", 2]], "implicit_stat": "increased_damage_after_melee", "value": 14.0},

	{"type": "Rod", "line": 1, "stance": "passive", "grades": [["arcane", 1]], "implicit_stat": "increased_spell_damage", "value": 12.0, "lower_power": true},
	{"type": "Rod", "line": 2, "stance": "passive", "grades": [["enigma", 1]], "implicit_stat": "increased_esoteric_damage", "value": 14.0},
	{"type": "Grimoire", "line": 1, "stance": "spell_library", "spell_page_tag": "esoteric", "grades": [["enigma", 1], ["intellect", 2]], "implicit_stat": "increased_esoteric_damage", "value": 16.0},
	{"type": "Grimoire", "line": 2, "stance": "spell_library", "grades": [["intellect", 1]], "implicit_stat": "increased_debuff_effectiveness", "value": 12.0},
	{"type": "Tome", "line": 1, "stance": "spell_library", "spell_page_tag": "generic", "grades": [["arcane", 1]], "implicit_stat": "increased_spell_damage", "value": 10.0},
	{"type": "Tome", "line": 2, "stance": "spell_library", "spell_page_tag": "elemental", "grades": [["arcane", 1], ["intellect", 2]], "implicit_stat": "increased_elemental_damage", "value": 14.0},
	{"type": "Talisman", "line": 1, "stance": "stance_buff", "grades": [["arcane", 1]], "implicit_stat": "increased_spell_damage_in_stance", "value": 12.0},
	{"type": "Talisman", "line": 2, "stance": "stance_buff", "grades": [["enigma", 1]], "implicit_stat": "increased_ward_restoration_rate", "value": 14.0},
	{"type": "Fetish", "line": 1, "stance": "spell_library", "grades": [["intellect", 1]], "implicit_stat": "increased_ailment_effectiveness", "value": 20.0},
	{"type": "Fetish", "line": 2, "stance": "spell_library", "spell_page_tag": "esoteric", "grades": [["enigma", 1], ["intellect", 2]], "implicit_stat": "increased_pale_damage", "value": 16.0},
]

var _count := 0

func _ready() -> void:
	for line in LINES:
		for i in range(ITEM_LEVELS.size()):
			_write_tier(line, i)
	print("Wrote %d conduit weapon tiers across %d lines." % [_count, LINES.size()])
	get_tree().quit()

func _write_tier(line: Dictionary, tier_index: int) -> void:
	var meta: Dictionary = TYPE_META[line["type"]]
	var w := Weapon.new()
	var item_level: int = ITEM_LEVELS[tier_index]
	var tier_names: Array = LINE1_TIER_NAMES if line["line"] == 1 else LINE2_TIER_NAMES
	var tier_name: String = tier_names[tier_index]
	var range_pair: Array = SPELL_POWER_RANGES[tier_index]
	var spell_power: float = (float(range_pair[0]) + float(range_pair[1])) / 2.0
	if line.get("lower_power", false):
		spell_power *= LOWER_SPELL_POWER_FACTOR

	w.weapon_type = line["type"]
	w.base_damage = spell_power
	var grades: Array = line["grades"]
	w.scaling_grade = grades[0][1] as int
	w.primary_scaling_stat = grades[0][0]
	w.secondary_scaling_stat = (grades[1][0] as String) if grades.size() > 1 else ""
	w.native_damage_type = DT_AETHERIC
	w.is_two_handed = meta["two_handed"]
	w.is_ranged = false
	w.is_conduit = true
	w.conduit_stance_type = line["stance"]
	w.spell_page_tag = line.get("spell_page_tag", "")
	w.unleash_copy_count = line.get("unleash_copy_count", 0)
	w.is_main_hand = not meta["offhand"]
	w.is_offhand = meta["offhand"]

	var slug := _slugify(tier_name)
	w.item_id = "gen_%s_%s_%s" % [meta["suffix"], slug, meta["suffix"]]
	w.display_name = "%s %s" % [tier_name, line["type"]]
	w.equip_slot = 4  # Constants.EquipmentSlot.PRIMARY_WEAPON - inert for weapons since Patch v3.5, real routing is is_main_hand/is_offhand
	var socket_cap: int = 3 if meta["offhand"] else 6
	w.max_sockets = clamp(tier_index + 2, 1, socket_cap)
	w.flavor_text = "%s (Line %d)" % [line["type"], line["line"]]
	w.item_level = item_level
	w.base_line_id = "%s_line%d" % [meta["suffix"], line["line"]]
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
