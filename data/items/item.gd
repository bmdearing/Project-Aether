extends Resource
class_name Item
## Shared base for equippable gear (Section 13 Equipment Slots, Section 18
## Item Rarity & Affixes). Used directly for Amulet/Belt/Ring - Section 25
## calls accessories "single tier items... implicit is the item identity",
## no extra mechanical fields needed beyond what's here. Armor/Shield/Weapon
## extend this for their category-specific stats.
##
## Procedural affix rolling, Gem/Jewel socket effects, and the full
## Section 25 item tables are explicitly deferred design (Section 24) - only
## the shape is modeled here, not a loot system.

@export var item_id: String
@export var display_name: String
@export var rarity: Constants.ItemRarity = Constants.ItemRarity.COMMON
@export var equip_slot: Constants.EquipmentSlot
## max_sockets is the item's overall CAP (Constants.MAX_SOCKETS_BY_CATEGORY-capped,
## raised by Bore/Corruption exactly as before - see CraftingSystem._bore()/
## CorruptionOutcome.AddSocket/RemoveSocket/AddExtraSocket, none of which
## changed for this). sockets (Patch v3.8) is how many of those slots
## this specific rolled instance actually has - rolled 0..max_sockets on
## drop (ItemRoller.roll()), independent of max_sockets, which is what
## ItemCard's new socket art (Section 3) actually draws filled vs. empty.
@export var max_sockets: int = 0
@export var sockets: int = 0
## Jewels set into this item, at most `sockets` of them. Their modifiers
## count as the item's own (get_effective_affixes()).
@export var socketed: Array[Item] = []
## 0 to Constants.QUALITY_CAP, raised by the Orb of Tempering. Not yet
## applied to modifier values.
@export var quality: int = 0
## Orb crafting state (see CraftingResolver). sockets_rolled marks the one
## Orb of Opening use; tolerance is the lifetime crafting budget, rolled on drop.
@export var sockets_rolled: bool = false
@export var tolerance: int = 0
@export var tolerance_max: int = 0
@export var active_edict: EdictDef
## Overrides the derived type key (see get_item_type()).
@export var item_type: StringName = &""
@export var affixes: Array[ItemAffix] = []
@export var flavor_text: String = ""
## Set on Uniques and Mythics: their UniqueCatalog id.
@export var unique_id: String = ""

## Shard of Tharsis. is_corrupted records that a Shard was used (Orbs then
## only allow Opening and Tempering); is_craftable goes false with it and
## blocks a second corruption.
@export var is_corrupted: bool = false
@export var is_craftable: bool = true

## Section 25's real per-tier data (user request 2026-08-30: build the
## actual tiered base-type system, not just one representative item per
## type). item_level is the tier's authored "Level" column - the
## character/area level at which this exact base becomes the best
## available. base_line_id groups every tier of one doc "Line" (e.g.
## "rapier_line1") so ItemRoller can pick the single highest-item_level
## tier within a line that's still <= the roll's target level, instead of
## treating all ~750 generated tiers as independent candidates. Empty
## string (every hand-authored pre-existing base item) means "not part of
## a tiered line" - always its own standalone candidate, gated only by
## its own item_level (which defaults to 1, i.e. always available).
@export var item_level: int = 1
@export var base_line_id: String = ""

## Equip gate (user request 2026-08-30, invented - no doc-sourced
## requirement system exists). item_level doubles as the level
## requirement (the same field ItemRoller's drop-tier selection already
## reads) rather than a separate field - one number, one meaning.
## stat_requirement is -1 for "none" (every pre-Section-25 hand-authored
## item, and every generated throwable - no single governing stat to
## require). See EquipmentComponent._requirement_block_reason().
##
## STILL the real, ENFORCED equip gate - unchanged by the 4 fields below.
@export var stat_requirement: Constants.Stat = -1
@export var stat_requirement_value: float = 0.0

## Patch v3.8d, DISPLAY ONLY for now (explicitly not wired into
## EquipmentComponent._requirement_block_reason() this pass - "enforcement
## is a separate pass" per the brief). A second, more lenient level gate
## plus up to two simultaneous stat gates (item_level/stat_requirement
## above can only express ONE stat) - tools/repair_item_requirements.gd
## populates these from item_level via the brief's own tier tables.
## level_requirement intentionally reads LOWER than item_level for every
## bracket except the last (item_level 91 -> level_requirement 92, per the
## brief's own table) - the two numbers are independent and will keep
## disagreeing with whatever EquipmentComponent actually enforces until a
## future pass repoints enforcement at these fields (flagged to the user).
@export var level_requirement: int = 1
@export var strength_requirement: int = 0
@export var agility_requirement: int = 0
@export var intellect_requirement: int = 0

## Patch v3.5 Section 4: prefix/suffix/implicit counts, read off the
## single `affixes` array above (tagged by ItemAffix.is_prefix/
## is_implicit) rather than three separate arrays - every existing
## `affixes` reader (ItemRoller, EquipmentComponent, StatSheet,
## CraftingSystem, tooltip UI, dozens of .tres instances) keeps working
## unchanged. Data architecture only, per the brief - no crafting UI or
## ItemRoller affix generation reads these yet.
const MAX_PREFIXES := 3
const MAX_SUFFIXES := 3
const MAX_IMPLICITS := 3

func get_all_affixes() -> Array[ItemAffix]:
	return affixes

## The item's own modifiers plus those of the jewels in its sockets, and
## for the Band of Wishes the other ring's too: what the stat totals read.
func get_effective_affixes() -> Array[ItemAffix]:
	var own := _affixes_with_jewels()
	if reflect_source == null:
		return own
	var all: Array[ItemAffix] = own.duplicate()
	all.append_array(reflect_source._affixes_with_jewels())
	return all

func _affixes_with_jewels() -> Array[ItemAffix]:
	var jewels := get_socketed_jewels()
	if jewels.is_empty():
		return affixes
	var all: Array[ItemAffix] = affixes.duplicate()
	for jewel in jewels:
		all.append_array(jewel.affixes)
	return all

## Band of Wishes: copies the other equipped ring (set by EquipmentComponent).
const REFLECT_RING_KEY := "unique_reflect_ring"
var reflect_source: Item

func reflects_other_ring() -> bool:
	return affixes.any(func(a: ItemAffix): return a.stat_key == REFLECT_RING_KEY)

## Socketed jewels that still have a socket (a Corruption can take one away).
func get_socketed_jewels() -> Array[Item]:
	return socketed.slice(0, maxi(sockets, 0))

func free_sockets() -> int:
	return maxi(sockets - socketed.size(), 0)

func get_affix_limits() -> Vector2i:
	return Constants.AFFIX_LIMITS_GEAR.get(rarity, Vector2i.ZERO)

func get_prefix_count() -> int:
	return affixes.filter(func(a: ItemAffix): return a.is_prefix and not a.is_implicit).size()

func get_suffix_count() -> int:
	return affixes.filter(func(a: ItemAffix): return not a.is_prefix and not a.is_implicit).size()

func get_implicit_count() -> int:
	return affixes.filter(func(a: ItemAffix): return a.is_implicit).size()

func can_add_prefix() -> bool:
	var limits := get_affix_limits()
	return get_prefix_count() < limits.x

func can_add_suffix() -> bool:
	var limits := get_affix_limits()
	return get_suffix_count() < limits.y

## Figments, Skill Tomes, ammo and crafting currency are Items too, but
## never equipped - their equip_slot is left at the default (HELMET), so
## nothing may read it as a real slot.
func is_equipment() -> bool:
	if self is Jewel or self is FigmentItem or self is SkillTome or self is AmmoPack:
		return false
	return not Constants.CRAFTING_CONSUMABLE_IDS.has(item_id)

## snake_case type key used by modifier item_types, tolerance ranges and
## inventory footprints: weapon_type for weapons, the base line for
## shields, the slot for gear, and a category for non-equipment.
func get_item_type() -> StringName:
	if item_type != &"":
		return item_type
	if self is Lens:
		return &"lens"
	if self is Jewel:
		return &"jewel"
	if self is FigmentItem:
		return &"figment"
	if self is SkillTome:
		return &"skill_tome"
	if not is_equipment():
		return &"currency"
	if self is Weapon:
		return StringName(String(get("weapon_type")).to_lower().replace(" ", "_"))
	if self is Shield and base_line_id != "":
		var regex := RegEx.create_from_string("_line\\d+$")
		return StringName(regex.sub(base_line_id, ""))
	match equip_slot:
		Constants.EquipmentSlot.HELMET: return &"helmet"
		Constants.EquipmentSlot.BODY_ARMOUR: return &"body_armour"
		Constants.EquipmentSlot.GLOVES: return &"gloves"
		Constants.EquipmentSlot.BOOTS: return &"boots"
		Constants.EquipmentSlot.AMULET: return &"amulet"
		Constants.EquipmentSlot.BELT: return &"belt"
		Constants.EquipmentSlot.RING: return &"ring"
		Constants.EquipmentSlot.OFFHAND: return &"shield"
	return &""
