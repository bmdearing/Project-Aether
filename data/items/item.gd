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
