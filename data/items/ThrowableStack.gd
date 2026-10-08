extends Resource
class_name ThrowableStack
## Stackable throwable consumable (Player.active_throwable/use_throwable()).

@export var throwable_type: String = ""    # matches ability_id of throwable
@export var quantity: int = 0
@export var max_stack: int = 20
@export var display_name: String = ""
@export var icon: Texture2D = null

func can_use() -> bool:
	return quantity > 0

func consume() -> void:
	quantity = max(0, quantity - 1)
