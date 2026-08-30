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
@export var max_sockets: int = 0
@export var affixes: Array[ItemAffix] = []
@export var flavor_text: String = ""
## res:// path to a 64x64 icon (assets/sprites/) shown instead of the
## flat rarity/damage-type color square - a String (not a Texture2D
## reference) so ItemSerializer's plain-Dictionary rolled-item save data
## stays JSON-safe. Empty means no icon exists yet - callers fall back to
## the color square exactly as before.
@export var icon_path: String = ""

## Section 20 Crafting. Cleave's "second application risks destroying the
## item" needs a use-count; Sever's tag-sealing needs to persist which
## damage-type/defensive/umbrella category_tags (Brand.category_tag) are
## permanently blocked from rolling again. Both no-ops until CraftingSystem
## touches an item - 0/empty for everything else.
@export var cleave_count: int = 0
@export var sealed_tags: Array[String] = []

## Section 20: Shard of Tharsis. "Every corruption attempt has an
## independent % chance to retain craftable/corruptible status regardless
## of outcome" - is_corrupted just records that a Shard was used;
## is_craftable is what that retain-chance roll actually gates (false
## permanently blocks any further Cube craft or Corruption attempt).
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
@export var stat_requirement: Constants.Stat = -1
@export var stat_requirement_value: float = 0.0
