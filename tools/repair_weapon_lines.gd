extends Node
## One-shot repair script (Patch v3.6b Priority 1/2) - run headlessly via
## tools/repair_weapon_lines.tscn, not part of the game itself. Fixes two
## systemic problems across every Section-25-generated weapon .tres
## (tools/generate_base_types.gd's own output):
##
## 1. scaling_grade was hardcoded to C (4) for every weapon regardless of
##    line identity - set here from LINES' own per-line grade instead.
## 2. A weapon's implicit was baked into flavor_text as display-only
##    prose ("Line Name - Implicit: +8% increased Physical damage",
##    tools/generate_base_types.gd's own "%s - Implicit: %s" format) with
##    no mechanical effect - converted here into a real ItemAffix
##    sub-resource (is_implicit = true) in the affixes array, and the
##    "- Implicit: ..." suffix is stripped back off flavor_text so it
##    isn't duplicated as both prose and data.
##
## User direction (2026-09-02) on the brief's own multi-stat "grades"
## list per line: only the FIRST tuple's grade sets Weapon.scaling_grade
## (the only field damage calculation actually reads); every tuple's stat
## name is stored as new, purely descriptive Weapon.primary_scaling_stat/
## secondary_scaling_stat metadata - NOT wired into DamageCalculator.gd
## or Weapon._base_hit()'s existing damage-type-based stat resolution,
## which stay untouched. A real per-line stat override is a future system.
##
## Idempotent - safe to re-run (strips any implicit ItemAffix a previous
## run already added before re-adding it).

const WEAPON_DIR := "res://data/weapons/instances/"

## base_line_id -> {"grades": [[stat_name, grade_int], ...], "implicit_stat":
## String or null (null = S grade, no implicit), "value": float, "rename":
## optional String display name override}. Transcribed from Implementation
## Brief v3.6b's own Line Definition Table - covers all 64 real lines
## (verified against every base_line_id actually present in data/weapons/
## instances/*.tres before writing this).
const LINES := {
	"rapier_line1": {"grades": [["instinct", 1], ["strength", 3]], "implicit_stat": "increased_riposte_damage", "value": 12.0},
	"rapier_line2": {"grades": [["instinct", 0]], "implicit_stat": null},
	"rapier_line3": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_physical_damage", "value": 8.0},
	"rapier_line4": {"grades": [["instinct", 1]], "implicit_stat": "increased_attack_speed", "value": 18.0},

	"dagger_line1": {"grades": [["instinct", 0]], "implicit_stat": null},
	"dagger_line2": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_bleed_duration", "value": 20.0},
	"dagger_line3": {"grades": [["instinct", 1]], "implicit_stat": "increased_attack_speed", "value": 22.0},

	"greatsword_line1": {"grades": [["strength", 0]], "implicit_stat": null},
	"greatsword_line2": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 14.0},
	"greatsword_line3": {"grades": [["strength", 2], ["instinct", 3]], "implicit_stat": "increased_armor_shred_effectiveness", "value": 13.0, "rename": "Armor Shred"},
	"greatsword_line4": {"grades": [["strength", 1]], "implicit_stat": "increased_damage_vs_broken", "value": 13.0, "rename": "Executioner"},

	"claymore_line1": {"grades": [["strength", 0]], "implicit_stat": null},
	"claymore_line2": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 16.0},

	"mace_line1": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 14.0},
	"mace_line2": {"grades": [["strength", 0]], "implicit_stat": null},
	"mace_line3": {"grades": [["strength", 2], ["vitality", 3]], "implicit_stat": "increased_retaliation_damage", "value": 20.0},

	"halberd_line1": {"grades": [["strength", 1]], "implicit_stat": "increased_physical_damage", "value": 10.0},
	"halberd_line2": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_bleed_damage", "value": 18.0},
	"halberd_line3": {"grades": [["strength", 2], ["instinct", 3]], "implicit_stat": "increased_aoe_radius", "value": 20.0},

	"spear_line1": {"grades": [["instinct", 1], ["strength", 2]], "implicit_stat": "increased_piercing_damage", "value": 15.0},
	"spear_line2": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_bleed_damage", "value": 20.0},
	"spear_line3": {"grades": [["strength", 1]], "implicit_stat": "increased_damage_outside_melee_range", "value": 16.0, "rename": "Reach"},

	"cutlass_line1": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_physical_damage", "value": 10.0},
	"cutlass_line2": {"grades": [["instinct", 1], ["strength", 3]], "implicit_stat": "increased_bleed_damage", "value": 18.0},

	"saber_line1": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_physical_damage", "value": 9.0},
	"saber_line2": {"grades": [["instinct", 1]], "implicit_stat": "increased_parry_window_duration", "value": 14.0, "rename": "Duelist"},
	"saber_line3": {"grades": [["instinct", 1], ["strength", 3]], "implicit_stat": "increased_riposte_damage", "value": 11.0},

	"shortsword_line1": {"grades": [["strength", 2], ["instinct", 2]], "implicit_stat": "increased_physical_damage", "value": 6.0},
	"shortsword_line2": {"grades": [["instinct", 1]], "implicit_stat": "increased_parry_effectiveness", "value": 12.0},
	"shortsword_line3": {"grades": [["instinct", 0]], "implicit_stat": null},

	"war_pick_line1": {"grades": [["strength", 1]], "implicit_stat": "armor_penetration", "value": 20.0},
	"war_pick_line2": {"grades": [["strength", 0]], "implicit_stat": null},

	"shock_lance_line1": {"grades": [["arcane", 1], ["instinct", 2]], "implicit_stat": "increased_lightning_damage", "value": 18.0},
	"shock_lance_line2": {"grades": [["arcane", 0]], "implicit_stat": null},

	"whip_line1": {"grades": [["instinct", 2], ["strength", 2]], "implicit_stat": "increased_bleed_damage", "value": 22.0},
	"whip_line2": {"grades": [["instinct", 1]], "implicit_stat": "increased_aoe_radius", "value": 24.0},

	"pressure_fist_line1": {"grades": [["strength", 0]], "implicit_stat": null},
	"pressure_fist_line2": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 18.0},

	"service_pistol_line1": {"grades": [["instinct", 0]], "implicit_stat": null},
	"service_pistol_line2": {"grades": [["instinct", 1]], "implicit_stat": "increased_physical_damage", "value": 10.0},
	"service_pistol_line3": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 18.0},

	"revolver_line1": {"grades": [["instinct", 1]], "implicit_stat": "increased_physical_damage", "value": 11.0},
	"revolver_line2": {"grades": [["instinct", 0]], "implicit_stat": null},

	"machine_pistol_line1": {"grades": [["instinct", 0]], "implicit_stat": null},
	"machine_pistol_line2": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 20.0},

	"submachine_gun_line1": {"grades": [["instinct", 0]], "implicit_stat": null},
	"submachine_gun_line2": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 22.0},

	"loaded_shotgun_line1": {"grades": [["strength", 1], ["instinct", 2]], "implicit_stat": "increased_aoe_radius", "value": 14.0},
	"loaded_shotgun_line2": {"grades": [["strength", 0]], "implicit_stat": null},

	"pump_action_shotgun_line1": {"grades": [["strength", 1], ["instinct", 2]], "implicit_stat": "increased_aoe_radius", "value": 15.0},
	"pump_action_shotgun_line2": {"grades": [["strength", 0]], "implicit_stat": null},

	"lever_action_rifle_line1": {"grades": [["instinct", 1]], "implicit_stat": "increased_physical_damage", "value": 12.0},
	"lever_action_rifle_line2": {"grades": [["instinct", 0]], "implicit_stat": null},

	"bolt_action_rifle_line1": {"grades": [["instinct", 0]], "implicit_stat": null},
	"bolt_action_rifle_line2": {"grades": [["instinct", 1]], "implicit_stat": "increased_physical_damage", "value": 13.0},
	"bolt_action_rifle_line3": {"grades": [["strength", 0]], "implicit_stat": null},

	"battle_rifle_line1": {"grades": [["strength", 1], ["instinct", 2]], "implicit_stat": "increased_physical_damage", "value": 11.0},
	"battle_rifle_line2": {"grades": [["strength", 0]], "implicit_stat": null},
	"battle_rifle_line3": {"grades": [["strength", 1]], "implicit_stat": "increased_stagger_effect", "value": 16.0},

	"crossbow_line1": {"grades": [["instinct", 1]], "implicit_stat": "increased_physical_damage", "value": 12.0},
	"crossbow_line2": {"grades": [["instinct", 0]], "implicit_stat": null},
	"crossbow_line3": {"grades": [["instinct", 2], ["strength", 2]], "implicit_stat": "increased_bleed_damage", "value": 18.0, "rename": "Bleed"},

	"machine_gun_line1": {"grades": [["strength", 1], ["instinct", 2]], "implicit_stat": "increased_attack_speed", "value": 30.0},
	"machine_gun_line2": {"grades": [["strength", 0]], "implicit_stat": null},
}

var _weapons_updated := 0
var _affixes_added := 0
var _s_grade_cleared := 0
var _skipped_no_line := 0

func _ready() -> void:
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		push_error("Cannot open %s" % WEAPON_DIR)
		get_tree().quit()
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			_repair_file(WEAPON_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("Repaired %d weapons - %d implicit affixes added, %d S-grade lines confirmed clean, %d files skipped (no matching line - hand-authored)." % [_weapons_updated, _affixes_added, _s_grade_cleared, _skipped_no_line])
	get_tree().quit()

func _repair_file(path: String) -> void:
	var weapon := load(path) as Weapon
	if weapon == null:
		return
	if weapon.base_line_id == "" or not LINES.has(weapon.base_line_id):
		_skipped_no_line += 1
		return

	var line: Dictionary = LINES[weapon.base_line_id]
	var grades: Array = line["grades"]
	weapon.scaling_grade = grades[0][1] as int
	weapon.primary_scaling_stat = grades[0][0]
	weapon.secondary_scaling_stat = (grades[1][0] as String) if grades.size() > 1 else ""

	var split_index := weapon.flavor_text.find(" - Implicit:")
	if split_index != -1:
		weapon.flavor_text = weapon.flavor_text.substr(0, split_index)

	# Idempotency - drop any implicit ItemAffix a previous run already added.
	weapon.affixes = weapon.affixes.filter(func(a: ItemAffix): return not a.is_implicit)

	if line.get("implicit_stat") == null:
		_s_grade_cleared += 1
	else:
		var affix := ItemAffix.new()
		affix.stat_key = line["implicit_stat"]
		affix.value = line["value"]
		affix.is_implicit = true
		affix.display_name = line.get("rename", _humanize(line["implicit_stat"]))
		affix.description = "+%s%% %s" % [_format_value(line["value"]), affix.display_name]
		weapon.affixes.append(affix)
		_affixes_added += 1

	if ResourceSaver.save(weapon, path) == OK:
		_weapons_updated += 1
	else:
		push_error("Failed to save %s" % path)

func _humanize(stat_key: String) -> String:
	var words := stat_key.replace("increased_", "").split("_")
	var capitalized := PackedStringArray()
	for w in words:
		capitalized.append(w.capitalize())
	return " ".join(capitalized)

func _format_value(v: float) -> String:
	return str(int(v)) if v == floor(v) else str(v)
