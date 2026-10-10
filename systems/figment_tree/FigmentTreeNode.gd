extends Resource
class_name FigmentTreeNode
## One Figment Tree node: what it does (effects: effect key -> value, summed
## by FigmentTree.effect()), where it sits (position, in tree units from the
## root) and which nodes it connects to (links, both ways).

@export var node_id: String
@export var display_name: String
@export var description: String
@export var point_cost: int = 1
@export var notable: bool = false
@export var effects: Dictionary = {}
@export var position: Vector2 = Vector2.ZERO
@export var links: Array[String] = []
## Sector name the node belongs to (for the screen's labels).
@export var sector: String = ""
