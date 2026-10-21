extends RefCounted
class_name StatSources
## Every character stat your gear, jewels, Slates and Lenses change, with
## where each part comes from. Mirrors the game's own sums (EquipmentComponent
## and ChainCalculator); whatever the total holds that none of these explain
## (Figment Tree, Unique effects...) shows as "Other effects".

const CATEGORIES := ["Attributes", "Life and Mana", "Defences", "Resistances", "Damage", "Critical Strikes",
	"Ailments and Curses", "Speed and Skills", "Minions", "Loot and Fate Board", "Other"]
const ATTRIBUTES := {"strength": Constants.Stat.STRENGTH, "agility": Constants.Stat.AGILITY, "intellect": Constants.Stat.INTELLECT}
const RESISTANCE_TYPES := {"fire": Constants.DamageType.FIRE, "cold": Constants.DamageType.COLD,
	"lightning": Constants.DamageType.LIGHTNING, "esoteric": Constants.DamageType.AETHERIC}
## Shown through flat Life and the defence it splits into instead.
const HIDDEN := ["hybrid_defense_life"]
const OTHER := "Other effects"

## [{key, name, category, total, sources: [[label, value], ...]}], sorted by
## category then name; stats at zero with no sources are left out.
static func collect(player: Player) -> Array[Dictionary]:
	var parts := {}
	if player == null:
		return []
	var sheet := player.stat_sheet
	for key in ATTRIBUTES:
		_add(parts, key, "Base", sheet.get(key))
		_add(parts, key, "Character level", sheet.level_bonus)
	if player.equipment:
		_collect_gear(parts, player.equipment)
	if player.fate_board:
		_collect_slates(parts, player.fate_board)
		_collect_stars(parts, player.fate_board)
	var keys := {}
	for key in parts:
		keys[key] = true
	for key in sheet.misc_bonus:
		keys[key] = true
	for key in sheet.slate_misc_bonus:
		keys[key] = true
	var rows: Array[Dictionary] = []
	for key in keys:
		if key in HIDDEN:
			continue
		var total := _total(player, key)
		var sources: Array = parts.get(key, []).filter(func(s): return absf(s[1]) > 0.0001)
		var explained := 0.0
		for s in sources:
			explained += s[1]
		if absf(total - explained) > 0.05:
			sources.append([OTHER, total - explained])
		if sources.is_empty() and absf(total) < 0.0001:
			continue
		sources.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
		rows.append({"key": key, "name": StatGlossary.name_of(key), "category": category_of(key), "total": total, "sources": sources})
	rows.sort_custom(func(a, b):
		var ca := CATEGORIES.find(a["category"])
		var cb := CATEGORIES.find(b["category"])
		return ca < cb if ca != cb else a["name"] < b["name"])
	return rows

## The value the game actually uses for `key`.
static func _total(player: Player, key: String) -> float:
	var sheet := player.stat_sheet
	if ATTRIBUTES.has(key):
		return sheet.get_stat(ATTRIBUTES[key])
	for element in RESISTANCE_TYPES:
		if key == element + "_resistance":
			return sheet.get_resistance(RESISTANCE_TYPES[element])
	return sheet.get_misc_bonus(key)

static func _add(parts: Dictionary, key: String, label: String, value: float) -> void:
	if not parts.has(key):
		parts[key] = []
	parts[key].append([label, value])

## ---- Gear ------------------------------------------------------------------

static func _collect_gear(parts: Dictionary, eq: EquipmentComponent) -> void:
	var slots := [["Helmet", eq.helmet], ["Body Armour", eq.body_armour], ["Gloves", eq.gloves], ["Boots", eq.boots],
		["Main Hand", eq.primary_weapon], ["Offhand", eq.offhand], ["Amulet", eq.amulet], ["Belt", eq.belt]]
	for i in eq.rings.size():
		slots.append(["Ring %d" % (i + 1), eq.rings[i]])
	for pair in slots:
		var item: Item = pair[1]
		if item == null:
			continue
		var label := "%s (%s)" % [_item_name(item), pair[0]]
		for affix in item.affixes:
			_add_gear_affix(parts, affix, label, item)
		for jewel in item.get_socketed_jewels():
			for affix in item.jewel_affixes(jewel):
				_add_gear_affix(parts, affix, "%s in %s" % [_item_name(jewel), _item_name(item)], item)
		if item.reflect_source:
			for affix in item.reflect_source._affixes_with_jewels():
				_add_gear_affix(parts, affix, "%s, reflecting %s" % [_item_name(item), _item_name(item.reflect_source)], item)

static func _add_gear_affix(parts: Dictionary, affix: ItemAffix, label: String, item: Item) -> void:
	var key := affix.key()
	if EquipmentComponent.AFFIX_STAT_KEYS.has(key):
		_add(parts, _attribute_key(EquipmentComponent.AFFIX_STAT_KEYS[key]), label, affix.value)
	elif EquipmentComponent.RESISTANCE_AFFIX_KEYS.has(key):
		_add(parts, EquipmentComponent.RESISTANCE_AFFIX_KEYS[key] + "_resistance", label, affix.value)
	elif key == EquipmentComponent.ALL_ELEMENTAL_RESISTANCE_KEY:
		for element in ["fire", "cold", "lightning"]:
			_add(parts, element + "_resistance", label + " - all Elemental", affix.value)
	elif EquipmentComponent.is_misc_key(key):
		_add(parts, key, label, affix.value)
		if key == "hybrid_defense_life":
			var split := {}
			EquipmentComponent._add_hybrid_defense(split, item, affix.value)
			for k in split:
				_add(parts, k, label + " - hybrid", split[k])

static func _attribute_key(stat: Constants.Stat) -> String:
	for key in ATTRIBUTES:
		if ATTRIBUTES[key] == stat:
			return key
	return ""

static func _item_name(item: Item) -> String:
	return item.display_name if item.display_name != "" else "Unnamed item"

## ---- Slates and Lenses ------------------------------------------------------

static func _collect_slates(parts: Dictionary, board: FateBoard) -> void:
	for placement_id in board.placements:
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]
		var slate: Slate = data.slate
		var label := "%s (Slate)" % (slate.display_name if slate.display_name != "" else "Slate")
		var attribute_mult := ChainCalculator.attribute_multiplier(board, placement_id)
		var misc_mult := ChainCalculator.lens_multiplier(board, data, false)
		for modifier in slate.modifiers:
			var key := StatKeys.canonical(modifier.stat_key)
			if EquipmentComponent.AFFIX_STAT_KEYS.has(modifier.stat_key):
				_add(parts, _attribute_key(EquipmentComponent.AFFIX_STAT_KEYS[modifier.stat_key]), label, modifier.value * attribute_mult)
			elif EquipmentComponent.is_misc_key(key):
				_add(parts, key, label, modifier.value * misc_mult)
		for affix in slate.explicits:
			if EquipmentComponent.is_misc_key(affix.key()):
				_add(parts, affix.key(), label, affix.value * misc_mult)
		for lens in slate.lenses:
			var lens_label := "%s (Lens on %s)" % [_item_name(lens), slate.display_name]
			for affix in lens.affixes:
				var key := affix.key()
				if EquipmentComponent.AFFIX_STAT_KEYS.has(key):
					_add(parts, _attribute_key(EquipmentComponent.AFFIX_STAT_KEYS[key]), lens_label, affix.value)
				elif EquipmentComponent.is_misc_key(key):
					_add(parts, key, lens_label, affix.value)

## Claimed Star sites and the jewel lines of Lenses in lit Stars. Mastery
## isn't a listed stat, so it's left out.
static func _collect_stars(parts: Dictionary, board: FateBoard) -> void:
	for site in board.claimed_sites():
		var label := "%s bonus" % FateStars.NAMES[site.star]
		var key: String = site.bonus["key"]
		if key == "type_damage":
			_add(parts, StatKeys.type_damage_key(site.tag), label, site.bonus["value"])
		elif EquipmentComponent.AFFIX_STAT_KEYS.has(key):
			_add(parts, _attribute_key(EquipmentComponent.AFFIX_STAT_KEYS[key]), label, site.bonus["value"])
		elif key != "mastery":
			_add(parts, key, label, site.bonus["value"])
	for star in board.lit_stars():
		var lens: Lens = board.star_lenses[star]
		var lens_label := "%s (Lens in %s)" % [_item_name(lens), FateStars.NAMES[star]]
		for affix in lens.affixes:
			if EquipmentComponent.AFFIX_STAT_KEYS.has(affix.key()):
				_add(parts, _attribute_key(EquipmentComponent.AFFIX_STAT_KEYS[affix.key()]), lens_label, affix.value)
			elif EquipmentComponent.is_misc_key(affix.key()):
				_add(parts, affix.key(), lens_label, affix.value)

## ---- Grouping ----------------------------------------------------------------

static func category_of(key: String) -> String:
	if ATTRIBUTES.has(key):
		return "Attributes"
	if key.contains("resistance"):
		return "Resistances"
	if key.contains("ailment") or key.contains("curse") or key == "debuff_effectiveness" or key == "dot_multiplier":
		return "Ailments and Curses"
	if key.begins_with("minion_"):
		return "Minions"
	if key.contains("crit"):
		return "Critical Strikes"
	if key.contains("life") or key.contains("mana"):
		return "Life and Mana"
	for word in ["armor", "evasion", "ward", "block", "taken", "phys_as_", "resilience", "stamina", "parry"]:
		if key.contains(word):
			return "Defences"
	for word in ["speed", "cooldown", "duration", "skill_level", "aoe", "projectile"]:
		if key.contains(word):
			return "Speed and Skills"
	for word in ["damage", "dmg", "penetration", "shred", "riposte", "retaliat"]:
		if key.contains(word):
			return "Damage"
	if key in ["item_quantity", "item_rarity", "magic_find"] or key.contains("aether"):
		return "Loot and Fate Board"
	return "Other"

## Hover text for a value: the total, then each source.
static func breakdown_text(row: Dictionary) -> String:
	var key: String = row["key"]
	var lines := ["%s: %s" % [row["name"], StatGlossary.format(key, row["total"])], ""]
	for s in row["sources"]:
		lines.append("%s   %s" % [StatGlossary.format(key, s[1]), s[0]])
	return "\n".join(lines)
