extends Node
## One-shot data migration (Patch v3.8b Priority 1c/4) - run headlessly via
## tools/repair_implicit_affixes.tscn, not part of the game itself.
##
## Two independent bugs found while investigating the brief's "Frayed Belt
## shows +18 Strength (implicit)" / "Tarnished Ring has no implicit"
## reports, same pattern as repair_weapon_lines.gd:
##
## 1. Every hand-authored item with a single affix (the 7 starter weapons,
##    the 5 named rings, Frayed Belt, Vitality Pendant, Worn Gauntlet - 14
##    files total) never actually set ItemAffix.is_implicit = true on that
##    affix, despite its own description text saying "(implicit)" - it
##    defaulted to false, so ItemCard's implicit/explicit split (which
##    reads is_implicit, not the description string) rendered every one of
##    them as an EXPLICIT mod. This is the real cause of "Tarnished Ring
##    has no implicit" - it has one, it just never rendered as one.
## 2. Patch v3.8's repair_stat_migration.gd only remapped Item.
##    stat_requirement/Weapon.scaling_stat - it never touched ItemAffix.
##    stat_key/description on these same hand-authored implicits, so 4 of
##    them (Frayed Belt/Vitality Pendant/Tarnished Ring/Worn Gauntlet)
##    still carry an OLD six-stat key (flat_strength etc.) that
##    EquipmentComponent.AFFIX_STAT_KEYS no longer recognizes - contributes
##    nothing to any stat while still displaying stale text.
##
## Per the brief: remap value/key/description text only for these 4 (do
## NOT change the value) - EXCEPT Tarnished Ring, which the brief also
## calls out under Priority 4's ring-implicit value spec ("+3 to +8
## depending on item level") as needing a fresh implicit under that range,
## superseding the "preserve value" rule for this one ring specifically.
## Tarnished Ring's item_level defaults to 1 (Low tier: +3 to +5) - 4.0
## picked as the tier's midpoint.
##
## display_name is renamed only for items whose CURRENT name is itself an
## old stat's name (brief's own examples: Vitality Pendant -> Prowess
## Pendant) - Frayed Belt/Tarnished Ring/Worn Gauntlet are not stat-named
## and keep their names. gen_rune_shield_arcane_rune_shield.tres surfaced
## during the same directory scan (display_name "Arcane Rune Shield",
## Section 25 generated shield, no affix) - "Arcane" is an old Resolve-
## mapped stat name here, not the (nonexistent) Arcane damage type, so it
## renames the same way.

const ITEM_DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

## Old flat_<stat> ItemAffix.stat_key -> {new key, new description word}.
const STAT_KEY_REMAP := {
	"flat_strength": {"key": "flat_prowess", "word": "Prowess"},
	"flat_vitality": {"key": "flat_prowess", "word": "Prowess"},
	"flat_instinct": {"key": "flat_finesse", "word": "Finesse"},
	"flat_arcane": {"key": "flat_resolve", "word": "Resolve"},
	"flat_enigma": {"key": "flat_resolve", "word": "Resolve"},
	"flat_intellect": {"key": "flat_resolve", "word": "Resolve"},
}

## Old stat word -> new, for the description string replace.
const WORD_REMAP := {
	"Strength": "Prowess",
	"Vitality": "Prowess",
	"Instinct": "Finesse",
	"Arcane": "Resolve",
	"Enigma": "Resolve",
	"Intellect": "Resolve",
}

## item_id -> new display_name, for items literally named after an old stat.
const DISPLAY_NAME_REMAP := {
	"vitality_pendant": "Prowess Pendant",
	"gen_rune_shield_arcane_rune_shield": "Resolve Rune Shield",
}

## Priority 4: Tarnished Ring's stale flat_instinct implicit is replaced
## (not just remapped) with a fresh implicit under the ring-implicit value
## spec - item_level 1 falls in the "Low tier (1-30): +3 to +5" band.
const RING_IMPLICIT_VALUE_OVERRIDE := {
	"tarnished_ring": 4.0,
}

var _scanned := 0
var _is_implicit_fixed := 0
var _stat_key_remapped := 0
var _names_renamed := 0

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
	print("Scanned %d items - %d affixes fixed to is_implicit=true, %d stat_key remapped, %d display_names renamed." % [_scanned, _is_implicit_fixed, _stat_key_remapped, _names_renamed])
	get_tree().quit()

func _repair_file(path: String) -> void:
	var item := load(path) as Item
	if item == null:
		return
	_scanned += 1
	var changed := false

	if DISPLAY_NAME_REMAP.has(item.item_id):
		item.display_name = DISPLAY_NAME_REMAP[item.item_id]
		_names_renamed += 1
		changed = true

	for affix in item.affixes:
		var affix_changed := false

		if not affix.is_implicit and affix.description.ends_with("(implicit)"):
			affix.is_implicit = true
			_is_implicit_fixed += 1
			affix_changed = true

		if STAT_KEY_REMAP.has(affix.stat_key):
			var remap: Dictionary = STAT_KEY_REMAP[affix.stat_key]
			affix.stat_key = remap["key"]
			_stat_key_remapped += 1
			affix_changed = true

			if RING_IMPLICIT_VALUE_OVERRIDE.has(item.item_id):
				affix.value = RING_IMPLICIT_VALUE_OVERRIDE[item.item_id]
				affix.description = "+%s %s (implicit)" % [_format_value(affix.value), remap["word"]]
			else:
				for old_word in WORD_REMAP:
					if affix.description.find(old_word) != -1:
						affix.description = affix.description.replace(old_word, WORD_REMAP[old_word])
						break

		if affix_changed:
			changed = true

	if changed and ResourceSaver.save(item, path) != OK:
		push_error("Failed to save %s" % path)

func _format_value(v: float) -> String:
	return str(int(v)) if v == floor(v) else str(v)
