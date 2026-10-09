extends Resource
class_name ItemAffix
## A single modifier line on an Item. value_min/max/tier are 0 for
## hand-authored implicits; ItemRoller fills them in for rolled affixes so
## the advanced tooltip can show the tier range.

@export var description: String
@export var stat_key: String    # machine key, e.g. "flat_armor"
@export var value: float = 0.0
@export var value_min: float = 0.0
@export var value_max: float = 0.0
@export var tier: int = 0       # 1 = best; 0 = not tiered (hand-authored)
@export var is_prefix: bool = true
@export var is_implicit: bool = false

@export var affix_id: String = ""
@export var display_name: String = ""
@export var min_item_level: int = 1
## Untyped "increased damage" vs a specific damage type (StatSheet.apply_affix()).
@export var is_generic: bool = false
@export var damage_type: Constants.DamageType = -1  # -1 = no damage type

## Empty rolls on any weapon. Otherwise restricts to these type keys
## (base_line_id without "_lineN", or snake_case weapon_type).
@export var weapon_type_filter: Array[String] = []

## Local mods ("local_*" stat_key) modify only their own weapon. Without a
## weapon_type_filter they roll on martial weapons only. Read at roll time
## only.
@export var is_local: bool = false

## Orb crafting. def is null for legacy AFFIX_POOL/weapon-library affixes;
## group falls back to affix_id, then stat_key, for those (see get_group()).
@export var def: ModifierDef
@export var modifier_id: StringName = &""
@export var group: StringName = &""
@export var anchored: bool = false

func get_group() -> StringName:
	if group != &"":
		return group
	return StringName(key())  # one modifier per stat, whatever it was rolled as

## The stat this modifier feeds, whatever name it was rolled under (StatKeys).
func key() -> String:
	return StatKeys.canonical(stat_key)
