extends Node
## Regenerates entities/enemies/base/HumanoidAnimTree.tscn - the shared
## AnimationTree every humanoid enemy uses (see EnemyAnimationController).
## Run: Godot --headless --path . res://tools/generate_humanoid_anim_tree.tscn --quit-after 5
##
## Godot's AnimationNodeStateMachine has no "Any" state, so "Any -> X" is
## expressed as one condition-gated transition from every other state. Speed
## isn't a parameter a transition can read, so EnemyAnimationController turns it
## into the four boolean conditions used below (moving/stopped/running/walking).

const OUT_PATH := "res://entities/enemies/base/HumanoidAnimTree.tscn"
const STATES := ["Idle", "Walk", "Run", "Attack", "HitReact", "Stagger", "Death"]
const LOCOMOTION := ["Idle", "Walk", "Run"]
const XFADE := 0.12

func _ready() -> void:
	call_deferred("_run")

func _transition(mode: int, switch_mode: int, condition: String = "") -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.advance_mode = mode
	t.switch_mode = switch_mode
	t.xfade_time = XFADE
	if condition != "":
		t.advance_condition = condition
	return t

func _run() -> void:
	var sm := AnimationNodeStateMachine.new()
	for i in STATES.size():
		var anim_node := AnimationNodeAnimation.new()
		anim_node.animation = STATES[i]  # placeholder - EnemyAnimationController.setup() swaps in the real clip
		sm.add_node(STATES[i], anim_node, Vector2(200 * (i % 4), 140 * (i / 4)))

	var auto := AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	var immediate := AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	var at_end := AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END

	sm.add_transition("Start", "Idle", _transition(auto, immediate))
	sm.add_transition("Idle", "Walk", _transition(auto, immediate, "moving"))
	sm.add_transition("Walk", "Idle", _transition(auto, immediate, "stopped"))
	sm.add_transition("Walk", "Run", _transition(auto, immediate, "running"))
	sm.add_transition("Run", "Walk", _transition(auto, immediate, "walking"))

	# "Any" -> one-shot states. Death has no exit; the rest return to Idle at
	# clip end and locomotion re-selects from there on the next frame.
	var one_shots := {"Attack": "attack_triggered", "HitReact": "hit_triggered", "Stagger": "stagger_triggered", "Death": "is_dead"}
	for target in one_shots:
		for source in STATES:
			if source == target or source == "Death":
				continue
			sm.add_transition(source, target, _transition(auto, immediate, one_shots[target]))
	for source in ["Attack", "HitReact", "Stagger"]:
		sm.add_transition(source, "Idle", _transition(auto, at_end))

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = sm
	tree.active = false
	var packed := PackedScene.new()
	print("pack: ", packed.pack(tree))
	print("save: ", ResourceSaver.save(packed, OUT_PATH))
	tree.free()
	get_tree().quit()
