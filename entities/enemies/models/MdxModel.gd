extends Node3D
class_name MdxModel
## Root of a wrapper scene for a model converted by tools/mdx_pipeline/.
## Applies the per-geoset materials baked in by tools/build_mdx_wrappers.gd
## and shows/hides geosets per playing clip - WC3 hides corpse and alternate
## parts through geoset alpha animation, which the .glb doesn't carry.

@export var geoset_materials: Dictionary = {}   # geoset index -> Material
@export var hidden_geosets: Dictionary = {}     # clip name -> PackedInt32Array
@export var always_hidden: PackedInt32Array = []
@export var idle_clip: String = ""
## Clip name -> ground speed (m/s, at this wrapper's unit scale) the clip is
## authored for; from the MDX sequence MoveSpeed. Missing = unknown.
@export var clip_move_speeds: Dictionary = {}

var _geosets: Dictionary = {}  # geoset index -> MeshInstance3D
var _tree: AnimationTree
var _shown_clip: String = "<none>"

func _ready() -> void:
	for mesh in find_children("Geoset_*", "MeshInstance3D", true, false):
		var index := int(String(mesh.name).trim_prefix("Geoset_"))
		_geosets[index] = mesh
		var mat: Material = geoset_materials.get(index)
		if mat:
			for s in mesh.get_surface_override_material_count():
				mesh.set_surface_override_material(s, mat)
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	_apply_visibility(idle_clip)

func _process(_delta: float) -> void:
	var clip := get_current_clip()
	if clip != _shown_clip:
		_apply_visibility(clip)

## Clip the AnimationTree's state machine is currently in (idle_clip until it runs).
func get_current_clip() -> String:
	if _tree == null or not _tree.active:
		return idle_clip
	var playback := _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback == null:
		return idle_clip
	var state := playback.get_current_node()
	var sm := _tree.tree_root as AnimationNodeStateMachine
	if sm == null or state == &"" or not sm.has_node(state):
		return idle_clip
	var node := sm.get_node(state) as AnimationNodeAnimation
	return String(node.animation) if node else idle_clip

func get_clip_move_speed(clip: String) -> float:
	return float(clip_move_speeds.get(clip, 0.0))

func _apply_visibility(clip: String) -> void:
	_shown_clip = clip
	var hidden: PackedInt32Array = hidden_geosets.get(clip, hidden_geosets.get(idle_clip, PackedInt32Array()))
	for index in _geosets:
		_geosets[index].visible = not (index in hidden or index in always_hidden)
