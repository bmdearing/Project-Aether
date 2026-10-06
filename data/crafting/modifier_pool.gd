extends Resource
class_name ModifierPool
## pool_id is &"gear", &"slate" or &"vestige_<boss>".

@export var pool_id: StringName
@export var modifiers: Array[ModifierDef] = []
