extends Resource
class_name EdictDef
## Constrains the next resolved craft on the item it's applied to.

enum Lock { NONE, PREFIX, SUFFIX }

@export var id: StringName
@export var locks: Lock = Lock.NONE
@export var excludes_tags: Array[StringName] = []
