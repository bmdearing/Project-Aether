extends RefCounted
class_name SlateAffixPool
## Patch v3.6 Section 1. A static, lazily-scanned pool of SlateAffix
## stubs (data/slates/affix_pool/*.tres) organized by tag - same
## directory-scan-and-cache convention as ItemRoller/BrandRoller's own
## static pools, rather than a true autoload (nothing here needs to be a
## persistent Node - this project's other Roller/Pool classes are all
## static-method RefCounted utilities).

const POOL_DIR := "res://data/slates/affix_pool/"

## tag -> Array[SlateAffix]
static var _pool: Dictionary = {}
static var _scanned: bool = false

static func register(affix: SlateAffix) -> void:
	_ensure_scanned()
	if not _pool.has(affix.tag):
		_pool[affix.tag] = []
	_pool[affix.tag].append(affix)

static func get_pool_for_tag(tag: String) -> Array[SlateAffix]:
	_ensure_scanned()
	var result: Array[SlateAffix] = []
	for affix in _pool.get(tag, []):
		result.append(affix)
	return result

static func get_random_affix(tag: String, min_item_level: int) -> SlateAffix:
	var eligible := get_pool_for_tag(tag).filter(
		func(a: SlateAffix): return a.min_item_level <= min_item_level
	)
	if eligible.is_empty():
		return null
	return eligible[randi() % eligible.size()]

static func get_all_tags() -> Array[String]:
	_ensure_scanned()
	var tags: Array[String] = []
	for tag in _pool.keys():
		tags.append(tag)
	return tags

static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	var dir := DirAccess.open(POOL_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var affix := load(POOL_DIR + file_name) as SlateAffix
			if affix:
				if not _pool.has(affix.tag):
					_pool[affix.tag] = []
				_pool[affix.tag].append(affix)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()
