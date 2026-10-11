extends Resource
class_name EdictDef
## Constrains the next resolved craft on the item it's applied to.

enum Lock { NONE, PREFIX, SUFFIX }

@export var id: StringName
@export var locks: Lock = Lock.NONE
@export var excludes_tags: Array[StringName] = []
## Item-level Edicts (gear only): a modifier the next craft adds must be a
## tier needing at least this item level, and only modifiers whose tier
## needs less can be removed. 0 = no level rule.
@export var item_level: int = 0
