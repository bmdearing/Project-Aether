extends Resource
class_name FigmentTreeNode
## One node in the (not-yet-built) Figment Tree - user request: "prepare
## legs for a Figment Tree to complete figments to get points, increasing
## the yield and type of content seen on Figments." This is scaffolding
## only, per that framing ("prepare legs," not "build it") - see
## FigmentTree.gd's own header for exactly what that means and doesn't
## mean.
##
## effect_key is a stub identifier for what unlocking this node is
## SUPPOSED to eventually do (e.g. "loot_quantity_increase") - nothing in
## this project reads effect_key yet. Wiring real effects (into
## FigmentRoller's rolls, most likely) is future work this data model
## exists to make possible, not something this pass implements.

@export var node_id: String
@export var display_name: String
@export var description: String
@export var point_cost: int = 1
## "" = a root-tier node, unlockable with no prerequisite.
@export var prerequisite_node_id: String = ""
@export var effect_key: String = ""
