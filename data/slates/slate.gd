extends Resource
class_name Slate
## A Fate Board Slate: tag, shape, size and modifiers. Shape is a list of local cell
## offsets from (0,0); rotation/flip are applied at placement time,
## not baked into the resource.

@export var slate_id: String
@export var display_name: String
@export var tag: Constants.DamageType
@export var is_hybrid: bool = false
@export var secondary_tag: Constants.DamageType   # only meaningful if is_hybrid

## Some documented Slates use a non-damage-type tag like "Spell" -
## confirmed intentional, not a taxonomy gap. If set, overrides `tag` for
## display and chain-matching.
@export var category_tag_override: String = ""

## Local grid cell offsets defining the footprint, e.g. [(0,0),(1,0),(1,1)] for an L-shape.
@export var shape_cells: Array[Vector2i] = [Vector2i.ZERO]

@export var aether_cost: int = 1
@export var rarity: Constants.SlateRarity = Constants.SlateRarity.COMMON
@export var modifiers: Array[SlateModifier] = []
@export var implicit_flavor_text: String = ""

## The Slate acts on a player-chosen spell; FateBoardEditor asks which one
## before placement.
@export var requires_spell_designation: bool = false

## Orb crafting state - same meaning as the matching Item fields. modifiers
## above are the tile-derived lines; explicits are the crafted ones.
@export var explicits: Array[ItemAffix] = []
@export var tolerance: int = 0
@export var tolerance_max: int = 0
@export var active_edict: EdictDef
@export var is_corrupted: bool = false

## Lowercase tag names the Orb crafting system matches Category Brands against.
func get_slate_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	if category_tag_override != "":
		tags.append(StringName(category_tag_override.to_lower()))
	else:
		tags.append(StringName(Constants.DAMAGE_TYPE_NAME.get(tag, "").to_lower()))
	if is_hybrid:
		tags.append(StringName(Constants.DAMAGE_TYPE_NAME.get(secondary_tag, "").to_lower()))
	return tags

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
