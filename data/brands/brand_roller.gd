extends RefCounted
class_name BrandRoller
## Rolls a random Brand (Section 20's crafting currency) for loot drops -
## see Enemy._maybe_drop_loot(). Every Brand is a fixed, hand-authored
## identity (no rarity/affix rolling like ItemRoller.roll() does for
## gear) - dropping one just duplicates the chosen instance so separate
## drops don't share one Resource.

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
	var base := load(candidates[randi() % candidates.size()]) as Brand
	return base.duplicate(true) as Brand
