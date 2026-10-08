extends RefCounted
class_name UniqueRoller
## Builds Unique and Mythic items from UniqueCatalog. ItemRoller.roll() hands
## a Unique/Mythic rarity roll here, and falls back to Rare when nothing of
## that rarity can drop.

## Weighted pick among the droppable entries of `rarity`, built at item_level.
## Null if there are none.
static func roll(rarity: int, item_level: int = 1) -> Item:
	var defs := droppable(rarity)
	var total := 0.0
	for def in defs:
		total += float(def["weight"])
	var pick := randf() * total
	for def in defs:
		pick -= float(def["weight"])
		if pick < 0.0:
			return build(def, item_level)
	return null

static func droppable(rarity: int) -> Array:
	return UniqueCatalog.DEFS.filter(func(d): return d["rarity"] == rarity and not d.get("corrupted_only", false))

## The unique on the best `base_type` base item_level allows. Pass `base` to
## put it on a given item instead (corrupted uniques keep the item's base).
static func build(def: Dictionary, item_level: int = 1, base: Item = null) -> Item:
	var from_catalog := base == null
	if from_catalog:
		base = base_for(def["base_type"], item_level)
	if base == null:
		return null
	var item: Item = base.duplicate(true)
	if from_catalog:
		item.item_id = "%s_rolled_%d" % [base.item_id, randi()]
	item.unique_id = def["id"]
	item.display_name = def["name"]
	item.rarity = def["rarity"]
	item.flavor_text = def.get("flavor", "")
	var affixes: Array[ItemAffix] = []
	for a in base.affixes:
		if a.is_implicit:
			affixes.append(a)
	for mod in def["mods"]:
		affixes.append(make_affix(mod))
	item.affixes = affixes
	if item is Weapon:
		var weapon := item as Weapon
		if def.has("damage_type"):
			weapon.native_damage_type = def["damage_type"]
			weapon.infused_damage_type = -1
		# Grade Equivalent Bonus (Mythics): one grade better than the base.
		weapon.scaling_grade = maxi(weapon.scaling_grade - int(def.get("grade_bonus", 0)), 0)
	if from_catalog:
		item.max_sockets = mini(item.max_sockets, ItemRoller.get_socket_cap(item))
		item.sockets = randi() % (item.max_sockets + 1)
	return item

## One fixed unique modifier, rolled within its range.
static func make_affix(mod: Array) -> ItemAffix:
	var affix := ItemAffix.new()
	affix.stat_key = mod[0]
	affix.value_min = mod[1]
	affix.value_max = mod[2]
	affix.value = roundf(randf_range(mod[1], mod[2]))
	affix.affix_id = "unique:" + String(mod[0])
	affix.description = ItemRoller.format_desc(mod[3], absf(affix.value))
	affix.is_local = String(mod[0]).begins_with("local_")
	return affix

## Highest-level base of the type the level allows, else its lowest.
static func base_for(base_type: String, item_level: int) -> Item:
	if ItemRoller._candidate_meta_cache.is_empty():
		ItemRoller._build_candidate_meta_cache()
	var best_path := ""
	var best_level := -1
	var lowest_path := ""
	var lowest_level := 1 << 30
	for path in ItemRoller._candidate_meta_cache:
		var meta: Dictionary = ItemRoller._candidate_meta_cache[path]
		if meta.get("item_type", "") != base_type:
			continue
		var level: int = meta["item_level"]
		if level <= item_level and level > best_level:
			best_level = level
			best_path = path
		if level < lowest_level:
			lowest_level = level
			lowest_path = path
	var chosen := best_path if best_path != "" else lowest_path
	return load(chosen) as Item if chosen != "" else null
