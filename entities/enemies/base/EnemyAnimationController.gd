extends Node
class_name EnemyAnimationController
## Drives HumanoidAnimTree (a state machine of Idle/Walk/Run/Attack/HitReact/
## Stagger/Death) for one enemy, with clip names supplied by an AnimationSet
## instead of hardcoded - see tools/generate_humanoid_anim_tree.gd for the
## transition layout this depends on.
##
## Godot's state machine transitions can only read boolean conditions, not a
## float speed, so set_speed() converts speed into the moving/stopped/running/
## walking conditions the tree's locomotion transitions use. One-shot states
## (attack/hit/stagger) are pulsed: their condition goes true just long enough
## for the transition to fire, then back to false.

const MOVE_SPEED_THRESHOLD := 0.5
const RUN_SPEED_THRESHOLD := 3.5
const CONDITION_PULSE_SEC := 0.1
const CONDITION_PATH := "parameters/conditions/"

@export var animation_set: AnimationSet = null

var _tree: AnimationTree
var _player: AnimationPlayer
var _state_machine: AnimationNodeStateMachinePlayback
var _dead: bool = false

func setup(tree: AnimationTree, anim_set: AnimationSet) -> void:
	_tree = tree
	animation_set = anim_set
	# HumanoidAnimTree's state machine is a resource shared by every instance
	# of the scene - each enemy needs its own, or setting one enemy's clip
	# names would change every other enemy's.
	_tree.tree_root = _tree.tree_root.duplicate(true)
	_player = _find_animation_player()
	if _player:
		_tree.anim_player = _tree.get_path_to(_player)
	_apply_animation_set()
	_tree.active = true
	_state_machine = _tree.get("parameters/playback")

func _find_animation_player() -> AnimationPlayer:
	var siblings := _tree.get_parent().find_children("*", "AnimationPlayer") if _tree.get_parent() else []
	return siblings[0] if not siblings.is_empty() else null

## Empty AnimationSet slots fall back so a state never points at a clip that
## doesn't exist - stagger reuses hit_reaction, anything else reuses idle.
func _apply_animation_set() -> void:
	if animation_set == null or _tree == null:
		return
	var hit := animation_set.hit_reaction if not animation_set.hit_reaction.is_empty() else animation_set.idle
	_set_anim("Idle", animation_set.idle, animation_set.idle)
	_set_anim("Walk", animation_set.walk, animation_set.idle)
	_set_anim("Run", animation_set.run, animation_set.walk)
	_set_anim("Attack", animation_set.attack_light, animation_set.idle)
	_set_anim("HitReact", hit, animation_set.idle)
	_set_anim("Stagger", animation_set.stagger, hit)
	_set_anim("Death", animation_set.death, animation_set.idle)

func _set_anim(node_name: String, anim_name: String, fallback: String) -> void:
	var chosen := anim_name if not anim_name.is_empty() else fallback
	if _player and not _player.has_animation(chosen):
		push_warning("EnemyAnimationController: clip '%s' (state %s) not found on %s" % [chosen, node_name, _player.get_path()])
		return
	var node := _tree.tree_root.get_node(node_name) as AnimationNodeAnimation
	if node:
		node.animation = chosen

func play_attack() -> void:
	_pulse("attack_triggered")

func play_hit_react() -> void:
	_pulse("hit_triggered")

func play_stagger() -> void:
	_pulse("stagger_triggered")

func play_death() -> void:
	if _tree == null or _dead:
		return
	_dead = true
	if animation_set and not animation_set.death_alt.is_empty() and randf() < 0.5 and (_player == null or _player.has_animation(animation_set.death_alt)):
		(_tree.tree_root.get_node("Death") as AnimationNodeAnimation).animation = animation_set.death_alt
	_tree.set(CONDITION_PATH + "is_dead", true)

func set_speed(speed: float) -> void:
	if _tree == null or _dead:
		return
	var moving := speed > MOVE_SPEED_THRESHOLD
	var running := speed > RUN_SPEED_THRESHOLD
	_tree.set(CONDITION_PATH + "moving", moving)
	_tree.set(CONDITION_PATH + "stopped", not moving)
	_tree.set(CONDITION_PATH + "running", running)
	_tree.set(CONDITION_PATH + "walking", not running)

func is_playing_death() -> bool:
	return _state_machine != null and _state_machine.get_current_node() == "Death"

## Length of the clip Death will play, for callers that need to wait before
## freeing the enemy. 0.0 if unknown.
func get_death_duration() -> float:
	if _player == null or _tree == null:
		return 0.0
	var node := _tree.tree_root.get_node("Death") as AnimationNodeAnimation
	return _player.get_animation(node.animation).length if node and _player.has_animation(node.animation) else 0.0

func _pulse(condition: String) -> void:
	if _tree == null or _dead:
		return
	_tree.set(CONDITION_PATH + condition, true)
	get_tree().create_timer(CONDITION_PULSE_SEC).timeout.connect(_clear_condition.bind(condition))

func _clear_condition(condition: String) -> void:
	if is_instance_valid(_tree):
		_tree.set(CONDITION_PATH + condition, false)
