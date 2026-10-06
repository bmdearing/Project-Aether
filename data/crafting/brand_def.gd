extends Resource
class_name BrandDef
## A Directive Brand. Category Brands carry tags, positional Brands restrict
## the affix type, a Vestige swaps the pool for the Orbs in applies_to_orbs,
## and Preservation keeps every other applied Brand.

enum Positional { NONE, PREFIX_ONLY, SUFFIX_ONLY }

@export var id: StringName
@export var tags: Array[StringName] = []
@export var positional: Positional = Positional.NONE
@export var vestige_pool: StringName = &""
@export var applies_to_orbs: Array[StringName] = []
@export var is_preservation: bool = false

func is_category() -> bool:
	return not tags.is_empty()

func is_vestige() -> bool:
	return vestige_pool != &""
