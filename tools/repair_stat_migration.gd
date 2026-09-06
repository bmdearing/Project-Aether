extends Node
## One-shot data migration (Patch v3.8 Section 2) - remaps every already-
## generated item's `stat_requirement` (an int under the OLD 6-value
## Constants.Stat enum, silently reinterpreted as a different stat under
## the NEW 3-value one - the exact class of bug already caught once with
## EquipmentSlot's enum in Patch v3.5) and every weapon's `primary_
## scaling_stat`/`secondary_scaling_stat` (lowercase strings from Patch
## v3.6b, e.g. "instinct", now referring to a stat that no longer exists).
##
## User-confirmed remap (2026-09-06): Vitality/Strength -> Prowess,
## Instinct -> Finesse, Arcane/Enigma/Intellect -> Resolve - mirrors the
## brief's own DAMAGE_TYPE_MAIN_STAT reassignment for the 4 stats it
## covers, closest thematic fit for the 2 it doesn't (Vitality's Life
## focus, Intellect's caster focus).
##
## Run headlessly via tools/repair_stat_migration.tscn, not part of the
## game itself. `stat_requirement`'s field NAME/TYPE didn't change (still
## Constants.Stat on Item.gd), so a plain load()/re-save (not the raw-text
## read repair_damage_ranges.gd needed for the REMOVED base_damage field)
## is enough - Godot stores whatever raw int was in the file into the
## int-typed property without validating it against the enum's current
## range, so the OLD value round-trips through load() intact to remap.

const ITEM_DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

## OLD Constants.Stat int -> NEW Constants.Stat int.
const STAT_REMAP := {
	0: 0,  # VITALITY -> PROWESS
	1: 0,  # STRENGTH -> PROWESS
	2: 1,  # INSTINCT -> FINESSE
	3: 2,  # ARCANE -> RESOLVE
	4: 2,  # ENIGMA -> RESOLVE
	5: 2,  # INTELLECT -> RESOLVE
}

## OLD lowercase stat name string -> NEW one, for Weapon.primary_scaling_
## stat/secondary_scaling_stat (Patch v3.6b, descriptive-only metadata).
const SCALING_STRING_REMAP := {
	"vitality": "prowess",
	"strength": "prowess",
	"instinct": "finesse",
	"arcane": "resolve",
	"enigma": "resolve",
	"intellect": "resolve",
}

var _requirement_remapped := 0
var _scaling_remapped := 0
var _scanned := 0

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
	print("Scanned %d items - %d stat_requirement remapped, %d scaling_stat strings remapped." % [_scanned, _requirement_remapped, _scaling_remapped])
	get_tree().quit()

func _repair_file(path: String) -> void:
	var item := load(path) as Item
	if item == null:
		return
	_scanned += 1
	var changed := false

	if item.stat_requirement != -1 and STAT_REMAP.has(item.stat_requirement):
		item.stat_requirement = STAT_REMAP[item.stat_requirement]
		_requirement_remapped += 1
		changed = true

	if item is Weapon:
		var weapon := item as Weapon
		if SCALING_STRING_REMAP.has(weapon.primary_scaling_stat):
			weapon.primary_scaling_stat = SCALING_STRING_REMAP[weapon.primary_scaling_stat]
			_scaling_remapped += 1
			changed = true
		if SCALING_STRING_REMAP.has(weapon.secondary_scaling_stat):
			weapon.secondary_scaling_stat = SCALING_STRING_REMAP[weapon.secondary_scaling_stat]
			changed = true

	if changed and ResourceSaver.save(item, path) != OK:
		push_error("Failed to save %s" % path)
