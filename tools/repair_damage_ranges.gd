extends Node
## One-shot repair script (Patch v3.7 Section 5) - splits every weapon
## .tres's single `base_damage` into a real roll range (`base_damage_min`/
## `base_damage_max`, ±15% of the original value), removing the old
## field. Conduit weapons (is_conduit) ALSO get `spell_power_min`/
## `spell_power_max` set the same way, from that same original value -
## Patch v3.6b's Conduit generator used `base_damage` to represent Spell
## Power (Weapon.gd had no dedicated field for it yet), so that number is
## the right source for both new fields on a Conduit specifically.
## `rolled_base_damage`/`rolled_spell_power` are left at 0.0 - set at
## runtime only, by ItemRoller.roll() on an actual drop.
##
## Run headlessly via tools/repair_damage_ranges.tscn, not part of the
## game itself.

const WEAPON_DIR := "res://data/weapons/instances/"
const RANGE_FACTOR_MIN := 0.85
const RANGE_FACTOR_MAX := 1.15

## Weapon.gd's own OLD default (before this repair removed the field) -
## a .tres whose base_damage happened to equal exactly this never got it
## serialized at all (Godot omits @export values matching the class
## default), so "no base_damage line in the file" means 10.0, not 0 -
## 17 of 651 real files hit this exactly.
const OLD_DEFAULT_BASE_DAMAGE := 10.0

var _repaired := 0
var _used_implicit_default := 0

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
	print("Repaired %d weapon damage ranges (%d had no explicit base_damage line, used the old class default of %.1f)." % [_repaired, _used_implicit_default, OLD_DEFAULT_BASE_DAMAGE])
	get_tree().quit()

func _repair_file(path: String) -> void:
	# Read the raw file text first - base_damage no longer exists as an
	# @export on Weapon.gd (removed alongside this repair), so load()
	# would silently drop any value still sitting in an old .tres. This
	# reads it directly out of the resource text instead.
	var raw := FileAccess.get_file_as_string(path)
	var base_damage := _extract_base_damage(raw)

	var weapon := load(path) as Weapon
	if weapon == null:
		return

	weapon.base_damage_min = floor(base_damage * RANGE_FACTOR_MIN)
	weapon.base_damage_max = ceil(base_damage * RANGE_FACTOR_MAX)
	if weapon.is_conduit:
		weapon.spell_power_min = floor(base_damage * RANGE_FACTOR_MIN)
		weapon.spell_power_max = ceil(base_damage * RANGE_FACTOR_MAX)

	if ResourceSaver.save(weapon, path) == OK:
		_repaired += 1
	else:
		push_error("Failed to save %s" % path)

func _extract_base_damage(raw: String) -> float:
	for line in raw.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("base_damage = "):
			var value_str := trimmed.substr("base_damage = ".length())
			if value_str.is_valid_float():
				return value_str.to_float()
			break
	_used_implicit_default += 1
	return OLD_DEFAULT_BASE_DAMAGE
