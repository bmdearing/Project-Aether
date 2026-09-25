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
		affixes.append({
			"description": affix.description,
			"stat_key": affix.stat_key,
			"value": affix.value,
			"value_min": affix.value_min,
			"value_max": affix.value_max,
			"tier": affix.tier,
			"is_prefix": affix.is_prefix,
		})
	var d := {
		"class": _class_tag(item),
		"item_id": item.item_id,
		"display_name": item.display_name,
		"rarity": item.rarity,
		"equip_slot": item.equip_slot,
		"max_sockets": item.max_sockets,
		"flavor_text": item.flavor_text,
		"icon_path": item.icon_path,
		"affixes": affixes,
		"cleave_count": item.cleave_count,
		"sealed_tags": item.sealed_tags,
		"is_corrupted": item.is_corrupted,
		"is_craftable": item.is_craftable,
	}
	if item is Brand:
		d["brand_function"] = item.brand_function
		d["category_tag"] = item.category_tag
	elif item is FigmentItem:
		d["tier"] = item.tier
		d["enemy_damage_multiplier"] = item.enemy_damage_multiplier
		d["enemy_health_multiplier"] = item.enemy_health_multiplier
		d["loot_quantity_multiplier"] = item.loot_quantity_multiplier
		d["loot_rarity_multiplier"] = item.loot_rarity_multiplier
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
	return d

static func from_dict(d: Dictionary) -> Item:
	if d.is_empty():
		return null
	var item: Item
	match d.get("class", "Item"):
		"Weapon": item = Weapon.new()
		"Armor": item = Armor.new()
		"Shield": item = Shield.new()
		"Brand": item = Brand.new()
		"FigmentItem": item = FigmentItem.new()
		_: item = Item.new()

	item.item_id = d.get("item_id", "")
	item.display_name = d.get("display_name", "")
	item.rarity = d.get("rarity", 0)
	item.equip_slot = d.get("equip_slot", 0)
	item.max_sockets = d.get("max_sockets", 0)
	item.flavor_text = d.get("flavor_text", "")
	item.icon_path = d.get("icon_path", "")
	item.cleave_count = d.get("cleave_count", 0)
	var sealed: Array[String] = []
	for tag in d.get("sealed_tags", []):
		sealed.append(str(tag))
	item.sealed_tags = sealed
	item.is_corrupted = d.get("is_corrupted", false)
	item.is_craftable = d.get("is_craftable", true)

	var affixes: Array[ItemAffix] = []
	for a in d.get("affixes", []):
		var affix := ItemAffix.new()
		affix.description = migrate_stat_text(a.get("description", ""))
		affix.stat_key = migrate_stat_key(a.get("stat_key", ""))
		affix.value = a.get("value", 0.0)
		affix.value_min = a.get("value_min", 0.0)
		affix.value_max = a.get("value_max", 0.0)
		affix.tier = a.get("tier", 0)
		affix.is_prefix = a.get("is_prefix", true)
		affixes.append(affix)
	item.affixes = affixes

	if item is Brand:
		item.brand_function = d.get("brand_function", 0)
		item.category_tag = d.get("category_tag", "")
	elif item is FigmentItem:
		item.tier = d.get("tier", 1)
		item.enemy_damage_multiplier = d.get("enemy_damage_multiplier", 1.0)
		item.enemy_health_multiplier = d.get("enemy_health_multiplier", 1.0)
		item.loot_quantity_multiplier = d.get("loot_quantity_multiplier", 1.0)
		item.loot_rarity_multiplier = d.get("loot_rarity_multiplier", 1.0)
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

	return item

static func _class_tag(item: Item) -> String:
	if item is Weapon:
		return "Weapon"
	if item is Armor:
		return "Armor"
	if item is Shield:
		return "Shield"
	if item is Brand:
		return "Brand"
	if item is FigmentItem:
		return "FigmentItem"
	return "Item"
