extends RefCounted
class_name ImplicitPool
## Per-item-type implicit pool for corruption's Add Implicit outcomes: every
## implicit some base of that type carries (Master v3 Section 25's line
## implicits and accessory implicits), one per stat, at its strongest value.

static var _by_type: Dictionary = {}  # item type -> Array[ItemAffix]
## Item type -> [stat_key, value, text]: implicits only corruption grants.
const CORRUPTION_ONLY := {
	&"amulet": [["additional_curses", 1.0, "Enemies can have +1 additional Curse"]],
	&"quiver": [["fire_rate", 8.0, "+8% increased Fire Rate"], ["crit_chance_increased", 15.0, "+15% increased Critical Strike Chance"]],
	&"pouch": [["fire_rate", 8.0, "+8% increased Fire Rate"], ["added_attack_damage", 6.0, "Adds 6 Damage to Attacks"]],
	&"throwing_knife": [["fire_rate", 8.0, "+8% increased Fire Rate"], ["projectile_speed", 20.0, "+20% increased Projectile Speed"]],
	&"throwing_axe": [["stagger_effect", 22.0, "+22% increased Stagger effect"], ["projectile_speed", 20.0, "+20% increased Projectile Speed"]],
	&"javelin": [["crit_chance_increased", 15.0, "+15% increased Critical Strike Chance"], ["projectile_speed", 20.0, "+20% increased Projectile Speed"]],
	&"grenade": [["fire_rate", 8.0, "+8% increased Fire Rate"], ["crit_damage_increased", 20.0, "+20% increased Critical Strike Damage"]],
}

## The implicits an item of `item_type` can gain from corruption.
static func pool_for_type(item_type: StringName) -> Array[ItemAffix]:
	if _by_type.is_empty():
		_build()
	var pool: Array[ItemAffix] = []
	pool.assign(_by_type.get(item_type, []))
	return pool

## A copy of a random implicit for this item, skipping stats it already has.
static func get_random_for(item: Item) -> ItemAffix:
	var have := item.affixes.map(func(a: ItemAffix): return a.key())
	var options := pool_for_type(item.get_item_type()).filter(func(a: ItemAffix): return not have.has(a.key()))
	if options.is_empty():
		return null
	var implicit := (options[randi() % options.size()] as ItemAffix).duplicate() as ItemAffix
	implicit.is_implicit = true
	return implicit

static func _build() -> void:
	if ItemRoller._candidate_meta_cache.is_empty():
		ItemRoller._build_candidate_meta_cache()
	var best: Dictionary = {}  # type -> {stat -> ItemAffix}
	for path in ItemRoller._candidate_meta_cache:
		var base := load(path) as Item
		if base == null:
			continue
		var type := base.get_item_type()
		for affix in base.affixes:
			if not affix.is_implicit:
				continue
			var by_stat: Dictionary = best.get(type, {})
			var current: ItemAffix = by_stat.get(affix.key())
			if current == null or absf(affix.value) > absf(current.value):
				by_stat[affix.key()] = affix
			best[type] = by_stat
	for type in best:
		var list: Array[ItemAffix] = []
		list.assign(best[type].values())
		_by_type[type] = list
	# Corruption-only implicits no base carries.
	for type in CORRUPTION_ONLY:
		var list: Array[ItemAffix] = _by_type.get(type, [] as Array[ItemAffix])
		for entry in CORRUPTION_ONLY[type]:
			var affix := ItemAffix.new()
			affix.stat_key = entry[0]
			affix.value = entry[1]
			affix.value_min = entry[1]
			affix.value_max = entry[1]
			affix.description = entry[2]
			affix.is_implicit = true
			list.append(affix)
		_by_type[type] = list
