extends Resource
class_name Slate
## A Slate as defined in Section 10 - evaluated on tag, shape, size,
## modifier count, and modifier values. Shape is a list of local cell
## offsets from (0,0); rotation/flip are applied at placement time,
## not baked into the resource.

@export var slate_id: String
@export var display_name: String
@export var tag: Constants.DamageType
@export var is_hybrid: bool = false
@export var secondary_tag: Constants.DamageType   # only meaningful if is_hybrid

## Some documented Slates (e.g. "The Unbound Chorus") use a non-damage-type
## tag like "Spell" - confirmed intentional by Patch v3.1's Flame Wall example
## ("A Spell Slate modifier..." alongside Fire Slate modifiers), not a taxonomy
## gap. If set, this overrides `tag` for display and chain-matching purposes.
@export var category_tag_override: String = ""

## Local grid cell offsets defining the footprint, e.g. [(0,0),(1,0),(1,1)] for an L-shape.
@export var shape_cells: Array[Vector2i] = [Vector2i.ZERO]

@export var aether_cost: int = 1
@export var rarity: Constants.SlateRarity = Constants.SlateRarity.COMMON
@export var modifiers: Array[SlateModifier] = []
@export var implicit_flavor_text: String = ""

func get_size() -> int:
	return shape_cells.size()

## Returns shape_cells rotated 90deg clockwise `times` times, then flipped
## horizontally if flip is true. Used by FateBoard placement preview.
func get_transformed_shape(rotation_steps: int = 0, flip: bool = false) -> Array[Vector2i]:
	var cells := shape_cells.duplicate()
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		if flip:
			c.x = -c.x
		for r in range(rotation_steps % 4):
			c = Vector2i(-c.y, c.x)
		cells[i] = c
	return cells
