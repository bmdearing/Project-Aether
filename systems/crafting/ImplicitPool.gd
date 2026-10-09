extends RefCounted
class_name ImplicitPool
## Per-item-type implicit pool for corruption's Add Implicit outcomes: every
## implicit some base of that type carries (Master v3 Section 25's line
## implicits and accessory implicits), one per stat, at its strongest value.

static var _by_type: Dictionary = {}  # item type -> Array[ItemAffix]

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
