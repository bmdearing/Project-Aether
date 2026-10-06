extends Resource
class_name ItemAffix
## A single rolled modifier line on an Item. is_prefix/is_implicit follow
## Section 18's prefix/suffix/implicit split. value_min/max/tier are 0
## for hand-authored implicits (no tier range); ItemRoller.gd fills them
## in for rolled affixes so the advanced tooltip can show the full tier
## range.
##
## Patch v3.5 Section 4: affix_id/display_name/min_item_level/is_generic/
## damage_type added for the Cube/Brand crafting pass this data feeds -
## no consumer reads them yet (no ItemRoller affix generation exists for
## this shape, that's explicitly a separate pass), pure scaffolding.

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
## Generic increased-damage affixes ("increased damage" with no type)
## vs type-specific ones (e.g. "increased Fire damage") - StatSheet.
## apply_affix() buckets stat_key == "increased_damage" affixes by this.
@export var is_generic: bool = false
@export var damage_type: Constants.DamageType = -1  # -1 = no damage type

## Patch v3.9 Weapon Affix Library - empty means "rolls on any weapon
## type" (every damage-type/generic affix); non-empty restricts to those
## base-type keys only (base_line_id stripped of its "_lineN" suffix, or
## Weapon.weapon_type normalized to snake_case for the 7 hand-authored
## weapons with no base_line_id - same type-key resolution tools/
## repair_item_requirements.gd already uses). Checked by ItemRoller
## against the rolling item's own resolved type key.
@export var weapon_type_filter: Array[String] = []

## v4.10 local weapon mods (stat_key "local_*"): modify only the weapon
## they're on, never the global StatSheet pools. A generic local mod
## (empty weapon_type_filter) rolls on martial weapons only; conduit locals
## are gated by weapon_type_filter. Only read at roll time - rolled/saved
## affixes are recognized by their "local_" stat_key.
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
	return StringName(affix_id) if affix_id != "" else StringName(stat_key)
