extends RefCounted
class_name BrandRoller
## Rolls a random Brand (Section 20's crafting currency) for loot drops -
## see Enemy._maybe_drop_loot(). Every Brand is a fixed, hand-authored
## identity (no affix rolling like ItemRoller.roll() does for gear) -
## dropping one just duplicates the chosen instance so separate drops
## don't share one Resource.
##
## Patch v3.5: weighted by Constants.BRAND_RARITIES/BRAND_DROP_WEIGHTS
## instead of picking uniformly among every Brand - roll a rarity tier
## first (weighted), then pick uniformly among that tier's own Brands.

const BRAND_DIR := "res://data/brands/instances/"

static func roll() -> Brand:
	var candidates: Array[String] = []
	var dir := DirAccess.open(BRAND_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			candidates.append(BRAND_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	if candidates.is_empty():
		return null

	var by_rarity: Dictionary = {}
	for path in candidates:
		var brand_id := path.get_file().get_basename()
		var rarity: Constants.BrandRarity = Constants.BRAND_RARITIES.get(brand_id, Constants.BrandRarity.COMMON)
		if not by_rarity.has(rarity):
			by_rarity[rarity] = []
		by_rarity[rarity].append(path)

	var total_weight := 0.0
	for rarity in by_rarity:
		total_weight += Constants.BRAND_DROP_WEIGHTS.get(rarity, 0)
	var roll := randf() * total_weight
	var chosen_rarity: Constants.BrandRarity = Constants.BrandRarity.COMMON
	for rarity in by_rarity:
		var weight: float = Constants.BRAND_DROP_WEIGHTS.get(rarity, 0)
		if roll < weight:
			chosen_rarity = rarity
			break
		roll -= weight

	var pool: Array = by_rarity[chosen_rarity]
	var base := load(pool[randi() % pool.size()]) as Brand
	return base.duplicate(true) as Brand
