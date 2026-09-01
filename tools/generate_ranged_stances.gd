extends Node
## One-shot generator (Implementation Brief v3.4 Section 5, 2026-08-31):
## "Create .tres instances for each weapon line" for ranged weapons -
## scans data/weapons/instances/ for every generated (is_ranged, real
## base_line_id) weapon, collects the unique set of lines, and writes one
## RangedStanceBehavior per line with weapon_type set to the LINE id
## (not the bare type) - see WeaponStance._resolve_behavior()'s own
## header for why. "Shortbow"/"Longbow" (the brief's only dual-stance
## ranged types) don't exist anywhere in this project's real weapon
## catalog (an all-firearms-plus-Wand/Staff setting, no bows) - skipped
## entirely rather than authoring orphaned data for weapons nobody can
## ever equip. Every real line gets exactly one stance (page A only),
## matching the brief's own "all other ranged weapons have one stance
## behavior only."

const WEAPON_INSTANCES_DIR := "res://data/weapons/instances/"
const OUTPUT_DIR := "res://data/stance/instances/"

## Round-robin assignment, invented - the brief gives no per-line mapping,
## just the type list and "always read from the resource." Deterministic
## by line id (sorted) so re-running this script is idempotent.
const STANCE_TYPE_CYCLE := [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,  # RangedStanceBehavior.RangedStanceType, all 14
]

var _count := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var lines := _collect_lines()
	var sorted_ids := lines.keys()
	sorted_ids.sort()
	for i in range(sorted_ids.size()):
		var line_id: String = sorted_ids[i]
		var weapon_type: String = lines[line_id]
		var behavior = load("res://data/stance/RangedStanceBehavior.gd").new()
		behavior.weapon_type = line_id
		behavior.move_speed_multiplier = 0.6
		behavior.parry_window_multiplier = 1.0
		behavior.stance_animation = ""
		behavior.stance_type = STANCE_TYPE_CYCLE[i % STANCE_TYPE_CYCLE.size()]
		var slug := line_id
		var path := "%sgen_ranged_%s.tres" % [OUTPUT_DIR, slug]
		if ResourceSaver.save(behavior, path) == OK:
			_count += 1
	print("GENERATOR DONE ranged_stance_lines=%d" % _count)
	get_tree().quit()

## weapon_type name -> {line_id -> true} collected first so a single
## anomalous file can't produce a line_id without a real (ranged) source.
func _collect_lines() -> Dictionary:
	var result := {}  # line_id -> weapon_type
	var dir := DirAccess.open(WEAPON_INSTANCES_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var weapon = load(WEAPON_INSTANCES_DIR + file_name)
			if weapon and weapon.is_ranged and weapon.base_line_id != "":
				result[weapon.base_line_id] = weapon.weapon_type
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
