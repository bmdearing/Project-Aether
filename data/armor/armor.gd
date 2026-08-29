extends Item
class_name Armor
## Helmet/Body Armour/Gloves/Boots per Section 13. Section 16's gear tables
## show hybrid rolls across Armor/Evasion/Ward on the same piece, so all
## three are plain fields here rather than an exclusive "line" choice.

@export var armor_value: float = 0.0
@export var evasion_value: float = 0.0
@export var ward_value: float = 0.0
