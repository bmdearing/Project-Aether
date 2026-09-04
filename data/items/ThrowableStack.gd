extends Resource
class_name ThrowableStack
## Patch v3.5 Section 3: throwables are no longer an equipment slot - a
## stackable inventory consumable instead, consumed on use. See
## Player.active_throwable/use_throwable().

@export var throwable_type: String = ""    # matches ability_id of throwable
@export var quantity: int = 0
@export var max_stack: int = 20
@export var display_name: String = ""
@export var icon: Texture2D = null

func can_use() -> bool:
	return quantity > 0

func consume() -> void:
	quantity = max(0, quantity - 1)
