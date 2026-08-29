extends Item
class_name Shield
## Offhand shields per Section 13/25. Data only - no BlockComponent exists
## yet to consume block_chance/block_threshold; the Block System (Section
## 07) isn't implemented anywhere in the current combat code.

@export var block_chance: float = 0.0
@export var block_threshold: float = 0.0
@export var armor_value: float = 0.0
