extends Node
## One-shot data generator (user request 2026-08-30: build Section 25's
## real tiered weapon/armor/shield/throwable base-type catalog instead of
## the one-representative-per-type shortcut used earlier this session).
## Run headlessly via tools/generate_base_types.tscn, NOT part of the game
## itself - reads the design doc's Section 25 text (already extracted from
## the .docx to plain text, see SECTION25_PATH) and writes one .tres per
## tier straight into data/weapons|armor|shields/instances/ and
## data/items/instances/ (throwables), each tagged with the real
## item_level/base_line_id fields ItemRoller._pick_base_item() now reads.
##
## Parsing approach: the extracted text is one table cell's text per line
## (Word paragraph boundaries -> newlines), so a Word table with columns
## [Tier, Name, Level, Base Damage] just reads back as 4 lines per row with
## no delimiters. This walks the text as a flat token stream: a "Line N —
## ..." header is followed by a run of known column-label lines (however
## many that particular Line's table has - it varies: weapons are 4
## columns, some armor/shield lines are hybrid Armor+Evasion or add Block
## Chance/Threshold), then that many-lines-per-row repeats until the next
## line isn't a valid integer (i.e. isn't a Tier number) - which reliably
## marks the row block's end since Tier is always the first column and
## always a small int, while every real header/title line is text.

const SECTION25_PATH := "C:/Users/Ben/AppData/Local/Temp/claude/S--projects-Project-Aether/a5046a7c-5571-4173-b4cf-ab2fb2bbfc04/scratchpad/section25.txt"

const CATEGORY_MARKERS := ["Melee Weapons", "Ranged Weapons", "Shields", "Throwables"]
const ARMOR_TYPE_NAMES := ["Body Armour", "Helmet", "Gloves", "Boots"]
const KNOWN_HEADERS := ["Tier", "Name", "Level", "Base Damage", "Base Armor", "Base Evasion", "Base Ward", "Block Chance", "Block Threshold"]

const ARMOR_TYPE_SLOT := {
	"Helmet": 0, "Body Armour": 1, "Gloves": 2, "Boots": 3,
}
const SHIELD_SLOT := 6
const THROWABLE_SLOT := 8
const PRIMARY_WEAPON_SLOT := 4

## Constants.DamageType values, transcribed (not referenced live - see
## this project's own headless-testing notes on autoload compile-order
## hazards in --script/tool contexts; this script never touches the
## Constants singleton at all, by design).
const DT_KINETIC := 0
const DT_PIERCING := 1
const DT_LIGHTNING := 5
const DT_AETHERIC := 6

## Constants.Stat values, transcribed for the same reason DT_* above are -
## this script deliberately never references the Constants singleton live.
const ST_VITALITY := 0
const ST_STRENGTH := 1
const ST_ARCANE := 3
const ST_ENIGMA := 4

## Equip requirement (user request 2026-08-30, invented - no doc-sourced
## requirement system exists): every generated tier gets a stat
## requirement scaling with its own item_level, gated on whichever stat
## actually governs it - a weapon's own damage-type main stat (mirrors
## Constants.DAMAGE_TYPE_MAIN_STAT), or Vitality (a generic "physical
## toughness" gate, invented) for armor/shields, which have no damage
## type of their own to key off. Throwables get no stat requirement, just
## the item_level (= level requirement) every generated item already
## carries - no single governing stat fits a grenade or a thrown knife.
## 0.5/level keeps the requirement reachable - AFFIX_POOL's own flat_<stat>
## affixes roll 20-25 per hit at Tier 1, so 2 pieces of relevant gear
## clears even a level 91 item's ~46 requirement.
const REQUIRED_STAT_PER_LEVEL := 0.5

func _main_stat_for_damage_type(dt: int) -> int:
	match dt:
		DT_LIGHTNING:
			return ST_ARCANE
		DT_AETHERIC:
			return ST_ENIGMA
		_:
			return ST_STRENGTH

## Doc-sourced type -> {native_damage_type, two_handed, ranged}. Damage
## type per weapon isn't doc-specified anywhere Section 25 or the crit
## table give it explicitly, so this is an invented-but-consistent guess
## per type's real-world weapon shape: thrusting/piercing blades and
## polearms -> Piercing, slashing/blunt/firearms -> Kinetic, Shock Lance ->
## Lightning (explicit in the name), Wand/Staff -> Aetheric (matches the
## Staff base already hand-authored earlier this session).
const WEAPON_TYPE_META := {
	"Rapier": {"dt": DT_PIERCING, "two_handed": false, "ranged": false},
	"Dagger": {"dt": DT_PIERCING, "two_handed": false, "ranged": false},
	"Shortsword": {"dt": DT_PIERCING, "two_handed": false, "ranged": false},
	"Saber": {"dt": DT_KINETIC, "two_handed": false, "ranged": false},
	"Cutlass": {"dt": DT_KINETIC, "two_handed": false, "ranged": false},
	"Greatsword": {"dt": DT_KINETIC, "two_handed": true, "ranged": false},
	"Claymore": {"dt": DT_KINETIC, "two_handed": true, "ranged": false},
	"Halberd": {"dt": DT_PIERCING, "two_handed": true, "ranged": false},
	"Spear": {"dt": DT_PIERCING, "two_handed": true, "ranged": false},
	"Mace": {"dt": DT_KINETIC, "two_handed": false, "ranged": false},
	"War Pick": {"dt": DT_PIERCING, "two_handed": false, "ranged": false},
	"Shock Lance": {"dt": DT_LIGHTNING, "two_handed": true, "ranged": false},
	"Whip": {"dt": DT_KINETIC, "two_handed": false, "ranged": false},
	"Pressure Fist": {"dt": DT_KINETIC, "two_handed": false, "ranged": false},
	"Service Pistol": {"dt": DT_KINETIC, "two_handed": false, "ranged": true},
	"Revolver": {"dt": DT_KINETIC, "two_handed": false, "ranged": true},
	"Machine Pistol": {"dt": DT_KINETIC, "two_handed": false, "ranged": true},
	"Crossbow": {"dt": DT_PIERCING, "two_handed": true, "ranged": true},
	"Battle Rifle": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Bolt Action Rifle": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Lever Action Rifle": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Loaded Shotgun": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Pump Action Shotgun": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Submachine Gun": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Machine Gun": {"dt": DT_KINETIC, "two_handed": true, "ranged": true},
	"Wand": {"dt": DT_AETHERIC, "two_handed": false, "ranged": true},
	"Staff": {"dt": DT_AETHERIC, "two_handed": true, "ranged": true},
}

var _counts := {"weapon": 0, "armor": 0, "shield": 0, "throwable": 0, "skipped_rows": 0}
var _unknown_weapon_types := {}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var lines := _read_nonempty_lines(SECTION25_PATH)
	if lines.is_empty():
		print("GENERATOR FAILED: could not read ", SECTION25_PATH)
		get_tree().quit()
		return
	_parse(lines)
	print("GENERATOR DONE weapon=%d armor=%d shield=%d throwable=%d skipped_rows=%d" % [
		_counts["weapon"], _counts["armor"], _counts["shield"], _counts["throwable"], _counts["skipped_rows"]
	])
	if not _unknown_weapon_types.is_empty():
		print("UNKNOWN WEAPON TYPES (used fallback meta): ", _unknown_weapon_types.keys())
	get_tree().quit()

func _read_nonempty_lines(path: String) -> Array[String]:
	var result: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return result
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			result.append(line)
	f.close()
	return result

func _parse(lines: Array[String]) -> void:
	var category := ""
	var current_type := ""
	var i := 0
	while i < lines.size():
		var line := lines[i]

		if CATEGORY_MARKERS.has(line):
			category = line
			i += 1
			continue

		var type_header := _looks_like_type_header(line)
		if not type_header.is_empty():
			current_type = type_header["name"]
			if ARMOR_TYPE_NAMES.has(current_type):
				category = "Armor"
			i += 1
			continue

		var line_header := _looks_like_line_header(line)
		if not line_header.is_empty():
			i += 1
			var meta := _parse_line_header_rest(line_header["rest"])
			var headers: Array[String] = []
			while i < lines.size() and KNOWN_HEADERS.has(lines[i]):
				headers.append(lines[i])
				i += 1
			var tier_num := 0
			while i < lines.size() and lines[i].is_valid_int():
				if i + headers.size() > lines.size():
					break
				var row: Array[String] = []
				for k in range(headers.size()):
					row.append(lines[i + k])
				i += headers.size()
				tier_num += 1
				var is_final: bool = tier_num == meta["total_items"]
				var apply_implicit: bool = meta["implicit_throughout"] or (not meta["implicit_throughout"] and is_final)
				_emit_tier(category, current_type, line_header["num"], meta["line_name"],
					meta["implicit_text"] if apply_implicit else "", headers, row, tier_num)
			continue

		i += 1

func _looks_like_type_header(line: String) -> Dictionary:
	var idx := line.find(" — ")
	if idx == -1:
		return {}
	var rest := line.substr(idx + 3)
	if not (rest.ends_with(" Lines") or rest.ends_with(" Line")):
		return {}
	var num_str := rest.split(" ")[0]
	if not num_str.is_valid_int():
		return {}
	return {"name": line.substr(0, idx), "count": int(num_str)}

func _looks_like_line_header(line: String) -> Dictionary:
	if not line.begins_with("Line "):
		return {}
	var idx := line.find(" — ")
	if idx == -1:
		return {}
	var num_str := line.substr(5, idx - 5)
	if not num_str.is_valid_int():
		return {}
	return {"num": int(num_str), "rest": line.substr(idx + 3)}

func _parse_line_header_rest(rest: String) -> Dictionary:
	var parts := rest.split("|")
	var line_name := parts[0].strip_edges()
	var implicit_text := ""
	var implicit_throughout := false
	var total_items := 0
	for p in parts:
		var t := p.strip_edges()
		if t.begins_with("Implicit throughout:"):
			implicit_text = t.trim_prefix("Implicit throughout:").strip_edges()
			implicit_throughout = true
		elif t.begins_with("Final tier implicit:"):
			implicit_text = t.trim_prefix("Final tier implicit:").strip_edges()
			implicit_throughout = false
		elif t.ends_with(" items") or t.ends_with(" item"):
			var num_str: String = t.split(" ")[0]
			if num_str.is_valid_int():
				total_items = int(num_str)
	return {"line_name": line_name, "implicit_text": implicit_text, "implicit_throughout": implicit_throughout, "total_items": total_items}

func _emit_tier(category: String, type_name: String, line_num: int, line_name: String, implicit_text: String, headers: Array[String], row: Array[String], tier_num: int) -> void:
	if row.size() < 3:
		_counts["skipped_rows"] += 1
		return
	var tier_name := row[1]
	var tier_level: int = int(row[2]) if row[2].is_valid_int() else 1
	var base_line_id := "%s_line%d" % [_slug(type_name), line_num]
	var item_id := "gen_%s_%s" % [_slug(type_name), _slug(tier_name)]
	var flavor := line_name if implicit_text == "" else "%s - Implicit: %s" % [line_name, implicit_text]

	match category:
		"Melee Weapons", "Ranged Weapons":
			_emit_weapon(type_name, headers, row, tier_num, tier_name, tier_level, base_line_id, item_id, flavor)
		"Armor":
			_emit_armor(type_name, headers, row, tier_num, tier_name, tier_level, base_line_id, item_id, flavor)
		"Shields":
			_emit_shield(type_name, headers, row, tier_num, tier_name, tier_level, base_line_id, item_id, flavor)
		"Throwables":
			_emit_throwable(headers, row, tier_name, tier_level, base_line_id, item_id, flavor)
		_:
			_counts["skipped_rows"] += 1

func _emit_weapon(type_name: String, headers: Array[String], row: Array[String], tier_num: int, tier_name: String, tier_level: int, base_line_id: String, item_id: String, flavor: String) -> void:
	if not WEAPON_TYPE_META.has(type_name):
		_unknown_weapon_types[type_name] = true
	var meta: Dictionary = WEAPON_TYPE_META.get(type_name, {"dt": DT_KINETIC, "two_handed": false, "ranged": false})
	var w = load("res://data/weapons/weapon.gd").new()
	w.item_id = item_id
	w.display_name = tier_name
	w.rarity = 0
	w.equip_slot = PRIMARY_WEAPON_SLOT
	w.max_sockets = clampi(2 + tier_num / 2, 2, 6)
	w.flavor_text = flavor
	w.weapon_type = type_name
	w.scaling_grade = 4
	w.native_damage_type = meta["dt"]
	w.infused_damage_type = -1
	w.is_two_handed = meta["two_handed"]
	w.is_ranged = meta["ranged"]
	w.item_level = tier_level
	w.base_line_id = base_line_id
	w.stat_requirement = _main_stat_for_damage_type(meta["dt"])
	w.stat_requirement_value = tier_level * REQUIRED_STAT_PER_LEVEL
	for k in range(3, headers.size()):
		if headers[k] == "Base Damage":
			w.base_damage = _parse_range_avg(row[k])
	var path := "res://data/weapons/instances/%s.tres" % item_id
	if ResourceSaver.save(w, path) == OK:
		_counts["weapon"] += 1
	else:
		_counts["skipped_rows"] += 1

func _emit_armor(type_name: String, headers: Array[String], row: Array[String], tier_num: int, tier_name: String, tier_level: int, base_line_id: String, item_id: String, flavor: String) -> void:
	var a = load("res://data/armor/armor.gd").new()
	a.item_id = item_id
	a.display_name = tier_name
	a.rarity = 0
	a.equip_slot = ARMOR_TYPE_SLOT.get(type_name, 1)
	a.max_sockets = clampi(1 + tier_num / 3, 1, 4)
	a.flavor_text = flavor
	a.item_level = tier_level
	a.base_line_id = base_line_id
	a.stat_requirement = ST_VITALITY
	a.stat_requirement_value = tier_level * REQUIRED_STAT_PER_LEVEL
	_apply_defensive_columns(a, headers, row)
	var path := "res://data/armor/instances/%s.tres" % item_id
	if ResourceSaver.save(a, path) == OK:
		_counts["armor"] += 1
	else:
		_counts["skipped_rows"] += 1

func _emit_shield(type_name: String, headers: Array[String], row: Array[String], tier_num: int, tier_name: String, tier_level: int, base_line_id: String, item_id: String, flavor: String) -> void:
	var s = load("res://data/shields/shield.gd").new()
	s.item_id = item_id
	s.display_name = tier_name
	s.rarity = 0
	s.equip_slot = SHIELD_SLOT
	s.max_sockets = clampi(1 + tier_num / 3, 1, 4)
	s.flavor_text = flavor
	s.item_level = tier_level
	s.base_line_id = base_line_id
	s.stat_requirement = ST_VITALITY
	s.stat_requirement_value = tier_level * REQUIRED_STAT_PER_LEVEL
	_apply_defensive_columns(s, headers, row)
	var path := "res://data/shields/instances/%s.tres" % item_id
	if ResourceSaver.save(s, path) == OK:
		_counts["shield"] += 1
	else:
		_counts["skipped_rows"] += 1

func _emit_throwable(headers: Array[String], row: Array[String], tier_name: String, tier_level: int, base_line_id: String, item_id: String, flavor: String) -> void:
	var it = load("res://data/items/item.gd").new()
	it.item_id = item_id
	it.display_name = tier_name
	it.rarity = 0
	it.equip_slot = THROWABLE_SLOT
	it.max_sockets = 0
	it.item_level = tier_level
	it.base_line_id = base_line_id
	var damage_note := ""
	for k in range(3, headers.size()):
		if headers[k] == "Base Damage":
			damage_note = " Base Damage: %s." % row[k]
	it.flavor_text = "%s%s" % [flavor, damage_note]
	var path := "res://data/items/instances/%s.tres" % item_id
	if ResourceSaver.save(it, path) == OK:
		_counts["throwable"] += 1
	else:
		_counts["skipped_rows"] += 1

## Shared Armor/Shield defensive-stat column dispatch - Shield only gained
## evasion_value/ward_value fields alongside its original armor_value as
## part of this same pass (see shield.gd), so both classes now have an
## identical hybrid Armor/Evasion/Ward shape to write into. `"x" in obj`
## checks property existence, so block_chance/block_threshold are simply
## skipped on Armor (which has no such fields) rather than erroring.
func _apply_defensive_columns(target: Object, headers: Array[String], row: Array[String]) -> void:
	for k in range(3, headers.size()):
		var label: String = headers[k]
		var raw: String = row[k]
		if label == "Base Armor":
			target.armor_value = _parse_range_avg(raw)
		elif label == "Base Evasion":
			target.evasion_value = _parse_range_avg(raw)
		elif label == "Base Ward":
			target.ward_value = _parse_range_avg(raw)
		elif label == "Block Chance" and "block_chance" in target:
			target.block_chance = _parse_percent(raw) / 100.0
		elif label == "Block Threshold" and "block_threshold" in target:
			target.block_threshold = _parse_range_avg(raw)

func _parse_range_avg(s: String) -> float:
	var t := s.strip_edges()
	if t.find("-") != -1:
		var parts := t.split("-")
		if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			return (parts[0].to_float() + parts[1].to_float()) / 2.0
	if t.is_valid_float():
		return t.to_float()
	return 0.0

func _parse_percent(s: String) -> float:
	var t := s.strip_edges()
	if t.ends_with("%"):
		t = t.substr(0, t.length() - 1)
	if t.is_valid_float():
		return t.to_float()
	return 0.0

func _slug(s: String) -> String:
	var lower := s.to_lower().replace("'", "").replace("’", "")
	var result := ""
	for c in lower:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
		else:
			result += "_"
	while result.find("__") != -1:
		result = result.replace("__", "_")
	return result.trim_suffix("_").trim_prefix("_")
