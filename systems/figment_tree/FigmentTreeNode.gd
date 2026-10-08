extends Resource
class_name FigmentTreeNode
## One Figment Tree node. effect_key (e.g. "loot_quantity_increase") isn't
## read by anything yet.

@export var node_id: String
@export var display_name: String
@export var description: String
@export var point_cost: int = 1
## "" = a root-tier node, unlockable with no prerequisite.
@export var prerequisite_node_id: String = ""
@export var effect_key: String = ""
