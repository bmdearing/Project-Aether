extends RefCounted
class_name ItemSerializer
## Full-data (not just resource_path) serialize/deserialize for rolled
## Items. A rolled item (ItemRoller.roll(), Resource.duplicate() under
## the hood) has no resource_path for the usual path-based persistence to
## reference. Hand-authored items still use resource_path as before (see
## EquipmentComponent.get_all_equipped_refs()) - this only kicks in for
## an item whose resource_path is empty.
##
## Centralized here rather than spread across Item/Weapon/Armor/Shield -
## GDScript static funcs aren't polymorphic, so a single loader needs to
## branch on type to know which subclass to instantiate.

## v4.8 stat rename (Prowess/Finesse/Resolve -> Strength/Agility/Intellect)
## for saves written before it. Used by from_dict() here and by
## SlateSerializer. Keys are exact matches; text replaces whole capitalized
## words only, so verbs like "resolved" are untouched.
const STAT_KEY_RENAMES := {
	"flat_prowess": "flat_strength",
	"flat_finesse": "flat_agility",
	"flat_resolve": "flat_intellect",
	"generic_of_prowess": "generic_of_strength",
	"generic_of_finesse": "generic_of_agility",
	"generic_of_resolve": "generic_of_intellect",
}
const STAT_WORD_RENAMES := {"Prowess": "Strength", "Finesse": "Agility", "Resolve": "Intellect"}

static func migrate_stat_key(key: String) -> String:
	return STAT_KEY_RENAMES.get(key, key)

static func migrate_stat_text(text: String) -> String:
	for old_word in STAT_WORD_RENAMES:
		if text.contains(old_word):
			var regex := RegEx.create_from_string("\\b%s\\b" % old_word)
			text = regex.sub(text, STAT_WORD_RENAMES[old_word], true)
	return text

static func to_dict(item: Item) -> Dictionary:
	if item == null:
		return {}
	var affixes := []
	for affix in item.affixes:
		affixes.append(affix_to_dict(affix))
	var d := {
		"class": _class_tag(item),
		"item_id": item.item_id,
		"display_name": item.display_name,
		"rarity": item.rarity,
		"equip_slot": item.equip_slot,
		"max_sockets": item.max_sockets,
		"flavor_text": item.flavor_text,
		"unique_id": item.unique_id,
		"affixes": affixes,
		"is_corrupted": item.is_corrupted,
		"mark": item.mark,
		"is_craftable": item.is_craftable,
		"sockets": item.sockets,
		"sockets_rolled": item.sockets_rolled,
		"quality": item.quality,
		"tolerance": item.tolerance,
		"tolerance_max": item.tolerance_max,
		"active_edict": String(item.active_edict.id) if item.active_edict else "",
		"base_line_id": item.base_line_id,
		"item_level": item.item_level,
	}
	if not item.socketed.is_empty():
		d["socketed"] = item.socketed.map(func(j: Item): return to_dict(j))
	if item is Lens:
		d["radius"] = item.radius
		d["radius_mod"] = item.radius_mod
		d["radius_value"] = item.radius_value
		d["radius_tag"] = item.radius_tag
	if item is SkillTome:
		d["ability_id"] = item.ability_id
		d["ability_path"] = item.ability_path
	elif item is AmmoPack:
		d["ammo_type"] = item.ammo_type
		d["amount"] = item.amount
	elif item is FigmentItem:
		d["tier"] = item.tier
		d["enemy_damage_multiplier"] = item.enemy_damage_multiplier
		d["enemy_health_multiplier"] = item.enemy_health_multiplier
		d["loot_quantity_multiplier"] = item.loot_quantity_multiplier
		d["loot_rarity_multiplier"] = item.loot_rarity_multiplier
		d["tileset_id"] = item.tileset_id
	elif item is Weapon:
		d["weapon_type"] = item.weapon_type
		d["base_damage_min"] = item.base_damage_min
		d["base_damage_max"] = item.base_damage_max
		d["rolled_base_damage"] = item.rolled_base_damage
		d["scaling_grade"] = item.scaling_grade
		d["native_damage_type"] = item.native_damage_type
		d["infused_damage_type"] = item.infused_damage_type
		d["is_two_handed"] = item.is_two_handed
		d["is_ranged"] = item.is_ranged
		d["ammo_type"] = item.ammo_type
		d["magazine_size"] = item.magazine_size
		d["fire_mode"] = item.fire_mode
		d["pellet_count"] = item.pellet_count
		d["pellet_spread_degrees"] = item.pellet_spread_degrees
		d["fire_rate"] = item.fire_rate
		d["cycle_time"] = item.cycle_time
		d["reload_time"] = item.reload_time
		d["reload_per_shell"] = item.reload_per_shell
		d["skill_ids"] = item.skill_ids
	elif item is Armor:
		d["armor_value"] = item.armor_value
		d["evasion_value"] = item.evasion_value
		d["ward_value"] = item.ward_value
	elif item is Shield:
		d["block_chance"] = item.block_chance
		d["armor_value"] = item.armor_value
		d["evasion_value"] = item.evasion_value
		d["ward_value"] = item.ward_value
	return d

## A rolled item's id is "<base id>_rolled_<n>" (ItemRoller.roll()). Its
## base supplies every field this file doesn't save - requirements, and on
## saves older than v4.23 the base line (which sets a shield's inventory
## size), item level and shield evasion/ward.
static func _base_for(item_id: String) -> Item:
	var cut := item_id.find("_rolled_")
	var base_id := item_id.substr(0, cut) if cut != -1 else item_id
	if base_id == "":
		return null
	for dir_path in ItemRoller.BASE_ITEM_DIRS:
		var path: String = dir_path + base_id + ".tres"
		if ResourceLoader.exists(path):
			return load(path) as Item
	return null

static func from_dict(d: Dictionary) -> Item:
	if d.is_empty():
		return null
	var item: Item
	var base := _base_for(d.get("item_id", ""))
	if base != null and _class_tag(base) == d.get("class", "Item"):
		item = base.duplicate(true)
	else:
		item = _new_of_class(d.get("class", "Item"))

	item.item_id = d.get("item_id", "")
	item.display_name = d.get("display_name", "")
	item.base_line_id = d.get("base_line_id", item.base_line_id)
	item.item_level = d.get("item_level", item.item_level)
	item.rarity = d.get("rarity", 0)
	item.equip_slot = d.get("equip_slot", 0)
	item.max_sockets = d.get("max_sockets", 0)
	item.flavor_text = d.get("flavor_text", "")
	item.unique_id = d.get("unique_id", "")
	item.is_corrupted = d.get("is_corrupted", false)
	item.mark = clampi(int(d.get("mark", 0)), 0, Item.Mark.size() - 1) as Item.Mark
	item.is_craftable = d.get("is_craftable", true)

	var affixes: Array[ItemAffix] = []
	for a in d.get("affixes", []):
		affixes.append(affix_from_dict(a))
	item.affixes = affixes
	item.sockets = d.get("sockets", 0)
	item.sockets_rolled = d.get("sockets_rolled", false)
	var jewels: Array[Item] = []
	for j in d.get("socketed", []):
		var jewel := from_dict(j)
		if jewel:
			jewels.append(jewel)
	item.socketed = jewels
	item.quality = d.get("quality", 0)
	read_craft_state(item, d)

	if item is Lens:
		item.radius = int(d.get("radius", 2))
		item.radius_mod = d.get("radius_mod", "")
		item.radius_value = float(d.get("radius_value", 0.0))
		item.radius_tag = int(d.get("radius_tag", -1))
	if item is SkillTome:
		item.ability_id = d.get("ability_id", "")
		item.ability_path = d.get("ability_path", "")
	elif item is AmmoPack:
		item.ammo_type = int(d.get("ammo_type", 0))
		item.amount = int(d.get("amount", 0))
	elif item is FigmentItem:
		item.tier = d.get("tier", 1)
		item.enemy_damage_multiplier = d.get("enemy_damage_multiplier", 1.0)
		item.enemy_health_multiplier = d.get("enemy_health_multiplier", 1.0)
		item.loot_quantity_multiplier = d.get("loot_quantity_multiplier", 1.0)
		item.loot_rarity_multiplier = d.get("loot_rarity_multiplier", 1.0)
		item.tileset_id = d.get("tileset_id", "")
	elif item is Weapon:
		item.weapon_type = d.get("weapon_type", "")
		item.base_damage_min = d.get("base_damage_min", 0.0)
		item.base_damage_max = d.get("base_damage_max", 0.0)
		item.rolled_base_damage = d.get("rolled_base_damage", 0.0)
		item.scaling_grade = d.get("scaling_grade", 0)
		item.native_damage_type = d.get("native_damage_type", 0)
		item.infused_damage_type = d.get("infused_damage_type", -1)
		item.is_two_handed = d.get("is_two_handed", false)
		item.is_ranged = d.get("is_ranged", false)
		if d.has("magazine_size"):
			item.ammo_type = d.get("ammo_type", 0)
			item.magazine_size = d.get("magazine_size", 12)
			item.fire_mode = d.get("fire_mode", 0)
			item.pellet_count = d.get("pellet_count", 1)
			item.pellet_spread_degrees = d.get("pellet_spread_degrees", 0.0)
			item.fire_rate = d.get("fire_rate", 0.0)
			item.cycle_time = d.get("cycle_time", 0.0)
			item.reload_time = d.get("reload_time", 1.4)
			item.reload_per_shell = d.get("reload_per_shell", false)
		elif item.is_ranged:
			item.apply_ranged_profile()  # save from before the ammo fields existed
		var ids: Array[String] = []
		for s in d.get("skill_ids", []):
			ids.append(str(s))
		item.skill_ids = ids
	elif item is Armor:
		item.armor_value = d.get("armor_value", 0.0)
		item.evasion_value = d.get("evasion_value", 0.0)
		item.ward_value = d.get("ward_value", 0.0)
	elif item is Shield:
		item.block_chance = d.get("block_chance", 0.0)
		item.armor_value = d.get("armor_value", 0.0)
		item.evasion_value = d.get("evasion_value", item.evasion_value)
		item.ward_value = d.get("ward_value", item.ward_value)

	return item

static func _new_of_class(tag: String) -> Item:
	match tag:
		"Weapon": return Weapon.new()
		"Armor": return Armor.new()
		"Shield": return Shield.new()
		"FigmentItem": return FigmentItem.new()
		"SkillTome": return SkillTome.new()
		"AmmoPack": return AmmoPack.new()
		"Lens": return Lens.new()
		"Jewel": return Jewel.new()
	return Item.new()

static func _class_tag(item: Item) -> String:
	if item is Lens:
		return "Lens"
	if item is Jewel:
		return "Jewel"
	if item is SkillTome:
		return "SkillTome"
	if item is AmmoPack:
		return "AmmoPack"
	if item is Weapon:
		return "Weapon"
	if item is Armor:
		return "Armor"
	if item is Shield:
		return "Shield"
	if item is FigmentItem:
		return "FigmentItem"
	return "Item"

## Orb-crafting fields shared with SlateSerializer. Saves from before
## tolerance existed get a fresh roll.
static func read_craft_state(target: Resource, d: Dictionary) -> void:
	if d.has("tolerance"):
		target.tolerance = d["tolerance"]
		target.tolerance_max = d.get("tolerance_max", d["tolerance"])
	else:
		CraftingResolver.roll_tolerance(target)
	var edict_id: String = d.get("active_edict", "")
	if edict_id != "" and ResourceLoader.exists(CraftingResolver.EDICTS_DIR + edict_id + ".tres"):
		target.active_edict = load(CraftingResolver.EDICTS_DIR + edict_id + ".tres")

static func affix_to_dict(affix: ItemAffix) -> Dictionary:
	return {
		"description": affix.description,
		"stat_key": affix.stat_key,
		"value": affix.value,
		"value_min": affix.value_min,
		"value_max": affix.value_max,
		"tier": affix.tier,
		"is_prefix": affix.is_prefix,
		"modifier_id": String(affix.modifier_id),
		"group": String(affix.group),
		"anchored": affix.anchored,
		"affix_id": affix.affix_id,
		"damage_type": affix.damage_type,
		"is_generic": affix.is_generic,
		"is_local": affix.is_local,
		"is_implicit": affix.is_implicit,
	}

static func affix_from_dict(a: Dictionary) -> ItemAffix:
	var affix := ItemAffix.new()
	affix.description = migrate_stat_text(a.get("description", ""))
	affix.stat_key = migrate_stat_key(a.get("stat_key", ""))
	affix.value = a.get("value", 0.0)
	affix.value_min = a.get("value_min", 0.0)
	affix.value_max = a.get("value_max", 0.0)
	affix.tier = a.get("tier", 0)
	affix.is_prefix = a.get("is_prefix", true)
	affix.modifier_id = StringName(a.get("modifier_id", ""))
	affix.group = StringName(a.get("group", ""))
	affix.anchored = a.get("anchored", false)
	affix.affix_id = a.get("affix_id", "")
	affix.damage_type = int(a.get("damage_type", -1))
	affix.is_generic = a.get("is_generic", false)
	affix.is_local = a.get("is_local", false)
	affix.is_implicit = a.get("is_implicit", false)
	affix.def = CraftingResolver.find_def(affix.modifier_id)
	return affix

## Old Cube Brand (removed in Rev2) item_id -> the currency it becomes when
## a save holding one loads.
const LEGACY_BRAND_CURRENCY := {
	"impel": &"brand_kinetic", "lancet": &"brand_piercing", "deflagrate": &"brand_explosive",
	"calcine": &"brand_fire", "quench": &"brand_cold", "galvanic": &"brand_lightning",
	"invoke": &"brand_aetheric", "efface": &"brand_entropic", "hollow": &"brand_pale",
	"anneal": &"brand_armor", "attenuate": &"brand_evasion", "occlude": &"brand_ward",
	"temper": &"brand_resistance", "inure": &"brand_resilience",
	"distill": &"brand_mana", "inscribe": &"brand_spell", "hone": &"brand_attack", "quicken": &"brand_speed",
	"render": &"recasting", "refine": &"tempering", "cleave": &"anchoring", "excise": &"severance",
	"bore": &"opening", "rectify": &"reckoning", "sever": &"absolution", "binder": &"brand_preservation",
}

## True if this saved item is an old Cube Brand (see legacy_brand_currency()).
static func is_legacy_brand(d: Dictionary) -> bool:
	return d.get("class", "") == "Brand"

static func legacy_brand_currency(d: Dictionary) -> StringName:
	return LEGACY_BRAND_CURRENCY.get(d.get("item_id", ""), &"")
