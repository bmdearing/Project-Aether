extends RefCounted
class_name GearRecombinator
## The Recombinator's gear mode: a base item and a donor of the same type go
## in, both are consumed, and one item comes out. The result is the base
## (its modifiers, implicits, sockets and quality untouched); the donor gives
## perks only. Each perk on either item survives at KEEP_CHANCE, at most
## MonsterInfrequent.MAX_PERKS, and at least one always does. A perk both
## items carry is one perk that keeps the better roll. Numbers are placeholders.

const COST := 100
const KEEP_CHANCE := 0.65

static func error(base: Item, donor: Item) -> String:
	if base == null or donor == null:
		return "Place a base item and a donor."
	if base == donor:
		return "Needs two different items."
	if base.unique_id != "" or donor.unique_id != "":
		return "Uniques and Mythics can't be recombined."
	if base.is_corrupted or donor.is_corrupted:
		return "Corrupted items can't be recombined."
	if not base.socketed.is_empty() or not donor.socketed.is_empty():
		return "Take their jewels out first."
	if base.get_item_type() != donor.get_item_type():
		return "Needs two items of the same type."
	if base.perks.is_empty() and donor.perks.is_empty():
		return "Neither item has a perk."
	return ""

## Every perk the pair could pass on, with its best roll.
static func pooled_perks(base: Item, donor: Item) -> Dictionary:
	var pool := {}
	for item in [base, donor]:
		for id in item.perks:
			pool[id] = maxf(pool.get(id, 0.0), float(item.perks[id]))
	return pool

## The result. The inputs are left untouched; the caller consumes them.
static func recombine(base: Item, donor: Item, rng: RandomNumberGenerator = null) -> Item:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var pool := pooled_perks(base, donor)
	var ids: Array = pool.keys()
	var kept: Array = ids.filter(func(_id) -> bool: return rng.randf() < KEEP_CHANCE)
	if kept.is_empty() and not ids.is_empty():
		kept.append(ids[rng.randi() % ids.size()])
	while kept.size() > MonsterInfrequent.MAX_PERKS:
		kept.remove_at(rng.randi() % kept.size())
	var result := base.duplicate(true) as Item
	result.item_id = "%s_recombined_%d" % [base.item_id.get_slice("_rolled_", 0), rng.randi()]
	var perks := {}
	for id in kept:
		perks[id] = pool[id]
	result.perks = perks
	result.mark = Item.Mark.NONE
	return result
