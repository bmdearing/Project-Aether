extends Resource
class_name ModifierDef
## A rollable modifier for the Orb crafting system. An item can't hold two
## modifiers that share a group. Empty item_types means any item type.

enum AffixType { PREFIX, SUFFIX }

@export var id: StringName
@export var group: StringName
@export var affix_type: AffixType = AffixType.PREFIX
@export var tags: Array[StringName] = []
@export var item_types: Array[StringName] = []
@export var tiers: Array[ModifierTier] = []
@export var stat_key: String = ""
## Format string for the rolled line, e.g. "+%d Strength" (see ItemRoller.format_desc()).
@export var text: String = ""
## Copied onto the rolled ItemAffix for StatSheet/weapon-local handling.
@export var damage_type: int = -1
@export var is_generic: bool = false
@export var is_local: bool = false
