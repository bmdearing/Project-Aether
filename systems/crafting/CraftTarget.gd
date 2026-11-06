extends RefCounted
class_name CraftTarget
## Uniform view of an Item or a Slate for CraftingResolver. Rarity is always
## expressed as Constants.ItemRarity; a Slate's VERY_RARE reads as RARE.

var resource: Resource
var is_slate: bool

static func wrap(target: Resource) -> CraftTarget:
	if not (target is Item or target is Slate):
		return null
	var t := CraftTarget.new()
	t.resource = target
	t.is_slate = target is Slate
	return t

func get_item_type() -> StringName:
	return &"slate" if is_slate else (resource as Item).get_item_type()

func get_slate_tags() -> Array[StringName]:
	if is_slate:
		return (resource as Slate).get_slate_tags()
	var none: Array[StringName] = []
	return none

func get_slate_size() -> int:
	return (resource as Slate).get_size() if is_slate else 0

func get_rarity() -> int:
	if not is_slate:
		return (resource as Item).rarity
	match (resource as Slate).rarity:
		Constants.SlateRarity.COMMON: return Constants.ItemRarity.COMMON
		Constants.SlateRarity.UNCOMMON: return Constants.ItemRarity.UNCOMMON
		Constants.SlateRarity.RARE, Constants.SlateRarity.VERY_RARE: return Constants.ItemRarity.RARE
		Constants.SlateRarity.UNIQUE: return Constants.ItemRarity.UNIQUE
	return Constants.ItemRarity.MYTHIC

func set_rarity(rarity: int) -> void:
	if not is_slate:
		(resource as Item).rarity = rarity
		return
	var slate := resource as Slate
	match rarity:
		Constants.ItemRarity.COMMON: slate.rarity = Constants.SlateRarity.COMMON
		Constants.ItemRarity.UNCOMMON: slate.rarity = Constants.SlateRarity.UNCOMMON
		Constants.ItemRarity.RARE:
			if slate.rarity != Constants.SlateRarity.VERY_RARE:
				slate.rarity = Constants.SlateRarity.RARE

func get_affix_limits(rarity: int) -> Vector2i:
	var table: Dictionary = Constants.AFFIX_LIMITS_GEAR
	if is_slate:
		table = Constants.AFFIX_LIMITS_SLATE
	elif resource is Lens:
		table = Constants.AFFIX_LIMITS_LENS
	elif resource is Jewel:
		table = Constants.AFFIX_LIMITS_JEWEL
	return table.get(rarity, Vector2i.ZERO)

## Highest rarity crafting can raise this to: jewels stop at Uncommon.
func max_craft_rarity() -> int:
	return Constants.ItemRarity.UNCOMMON if resource is Jewel and not resource is Lens else Constants.ItemRarity.RARE

## Most explicits `rarity` allows in total (jewels cap below prefix + suffix).
func get_total_limit(rarity: int) -> int:
	if resource is Jewel and not resource is Lens:
		return Constants.AFFIX_TOTAL_LIMITS_JEWEL.get(rarity, 0)
	var limits := get_affix_limits(rarity)
	return limits.x + limits.y

func get_explicits() -> Array[ItemAffix]:
	if is_slate:
		return (resource as Slate).explicits.duplicate()
	var result: Array[ItemAffix] = []
	for a in (resource as Item).affixes:
		if not a.is_implicit:
			result.append(a)
	return result

## Replaces the explicit modifiers, keeping an Item's implicits in place.
func set_explicits(explicits: Array[ItemAffix]) -> void:
	if is_slate:
		(resource as Slate).explicits = explicits.duplicate()
		return
	var item := resource as Item
	var merged: Array[ItemAffix] = []
	for a in item.affixes:
		if a.is_implicit:
			merged.append(a)
	merged.append_array(explicits)
	item.affixes = merged

func is_corrupted() -> bool:
	return resource.is_corrupted

## Siphon crafts made on this item; each one costs more (CraftingResolver.cost_of()).
func get_craft_count() -> int:
	return resource.craft_count

func set_craft_count(value: int) -> void:
	resource.craft_count = value

func can_temper() -> bool:
	return resource is Armor or resource is Weapon or resource is Shield

func get_quality() -> int:
	return 0 if is_slate else (resource as Item).quality

func get_quality_cap() -> int:
	return Constants.QUALITY_CAP if is_slate else (resource as Item).get_quality_cap()

func set_quality(value: int) -> void:
	if not is_slate:
		(resource as Item).quality = value

func get_sockets() -> int:
	return 0 if is_slate else (resource as Item).sockets

func get_max_sockets() -> int:
	return 0 if is_slate else (resource as Item).max_sockets
