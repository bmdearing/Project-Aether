extends Resource
class_name DamageTypeDef
## Descriptive wrapper around a Constants.DamageType enum value.
## Used for UI display; gameplay math should reference Constants.DamageType directly.

@export var type_id: Constants.DamageType
@export var display_name: String
@export var category: Constants.DamageCategory
@export var world_origin_note: String
