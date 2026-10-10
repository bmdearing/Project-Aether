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
	_apply_loop_modes()
	_read_clip_speeds()
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_lod_frame = randi() % FAR_STEP
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

## Imported clips (MDX-converted .glb) default to LOOP_NONE: locomotion must
## loop, one-shot states must not, or Attack/HitReact never reach their end
## transition back to Idle. Set on the shared Animation resource, so every
## enemy using the model agrees.
const LOOPING_STATES := ["Idle", "Walk", "Run"]
const ONE_SHOT_STATES := ["Attack", "HitReact", "Stagger", "Death"]

func _apply_loop_modes() -> void:
	if _player == null:
		return
	for state in LOOPING_STATES + ONE_SHOT_STATES:
		var node := _tree.tree_root.get_node(state) as AnimationNodeAnimation
		if node == null or not _player.has_animation(node.animation):
			continue
		var looping: bool = state in LOOPING_STATES
		# A one-shot state can fall back to the idle clip; leave that one looping.
		if not looping and _is_locomotion_clip(node.animation):
			continue
		_player.get_animation(node.animation).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE

func _is_locomotion_clip(clip: StringName) -> bool:
	for state in LOOPING_STATES:
		var node := _tree.tree_root.get_node(state) as AnimationNodeAnimation
		if node and node.animation == clip:
			return true
	return false

func _set_anim(node_name: String, anim_name: String, fallback: String) -> void:
	var chosen := anim_name if not anim_name.is_empty() else fallback
	if _player and not _player.has_animation(chosen):
		push_warning("EnemyAnimationController: clip '%s' (state %s) not found on %s" % [chosen, node_name, _player.get_path()])
		return
	var node := _tree.tree_root.get_node(node_name) as AnimationNodeAnimation
	if node:
		node.animation = chosen

## Attack playback speed is clamped so very short or long wind-ups don't
## turn the swing into a blur or a crawl.
const MIN_ATTACK_SPEED := 0.4
const MAX_ATTACK_SPEED := 2.0

## Stretches the Attack clip so its hit frame (AnimationSet.attack_hit_fraction)
## lands windup_sec from now, then plays it - restarting it if a previous
## swing's follow-through is still playing.
func play_attack(windup_sec: float) -> void:
	if _tree == null or _dead:
		return
	var node := _tree.tree_root.get_node("Attack") as AnimationNodeAnimation
	if node and _player and _player.has_animation(node.animation) and windup_sec > 0.0:
		var length := _player.get_animation(node.animation).length
		var speed := clampf(length * animation_set.attack_hit_fraction / windup_sec, MIN_ATTACK_SPEED, MAX_ATTACK_SPEED)
		node.use_custom_timeline = true
		node.stretch_time_scale = true
		node.timeline_length = length / speed
	# Jumped to directly: a pulsed trigger only fires from locomotion states,
	# so a swing that began mid hit-reaction used to land with no animation.
	if _state_machine:
		_state_machine.start(&"Attack", true)
		_enter_one_shot(&"Attack")
	else:
		_pulse("attack_triggered")

## No-ops when the set has no clip for them: the idle fallback loops, so the
## state would never reach its end transition back to Idle.
func play_hit_react() -> void:
	if animation_set and not animation_set.hit_reaction.is_empty():
		_pulse("hit_triggered")

func play_stagger() -> void:
	if animation_set and not (animation_set.stagger.is_empty() and animation_set.hit_reaction.is_empty()):
		_pulse("stagger_triggered")

func play_death() -> void:
	if _tree == null or _dead:
		return
	_dead = true
	if animation_set and not animation_set.death_alt.is_empty() and randf() < 0.5 and (_player == null or _player.has_animation(animation_set.death_alt)):
		(_tree.tree_root.get_node("Death") as AnimationNodeAnimation).animation = animation_set.death_alt
	_tree.set(CONDITION_PATH + "is_dead", true)
	# Death interrupts: drop pending one-shot triggers (an attack pulsed this
	# frame would win the transition order) and jump straight to the clip
	# instead of waiting on a transition or a swing's follow-through.
	for condition in ["attack_triggered", "hit_triggered", "stagger_triggered"]:
		_tree.set(CONDITION_PATH + condition, false)
	if _state_machine:
		_state_machine.start(&"Death", true)

func set_speed(speed: float) -> void:
	if _tree == null or _dead:
		return
	var moving := speed > MOVE_SPEED_THRESHOLD
	var running := speed > RUN_SPEED_THRESHOLD
	_tree.set(CONDITION_PATH + "moving", moving)
	_tree.set(CONDITION_PATH + "stopped", not moving)
	_tree.set(CONDITION_PATH + "running", running)
	_tree.set(CONDITION_PATH + "walking", not running)
	if moving:
		_match_playback_speed("Run" if running else "Walk", speed)

## Locomotion playback rate is ground speed / the clip's authored speed, so
## feet keep pace with the ground instead of sliding.
const MIN_LOCOMOTION_RATE := 0.8
const MAX_LOCOMOTION_RATE := 2.5
const RATE_CHANGE_THRESHOLD := 0.08  # retiming restarts the cycle's phase mapping, so skip tiny changes

## Clip speeds measured from MDX model data run high (units walked at half
## pace or less); hand-set AnimationSet speeds are used as given.
const MEASURED_SPEED_FACTOR := 0.7

var _clip_speeds: Dictionary = {}   # state -> m/s the clip is authored for
var _clip_rates: Dictionary = {}    # state -> playback rate currently applied

func _read_clip_speeds() -> void:
	var model := _tree.get_parent() as Node3D
	var model_scale: float = model.scale.x if model else 1.0
	for state in ["Walk", "Run"]:
		var node := _tree.tree_root.get_node(state) as AnimationNodeAnimation
		if node == null:
			continue
		var authored: float = animation_set.walk_clip_speed if state == "Walk" else animation_set.run_clip_speed
		if authored <= 0.0 and model and model.has_method("get_clip_move_speed"):
			authored = model.get_clip_move_speed(String(node.animation)) * MEASURED_SPEED_FACTOR
		if authored > 0.0:
			_clip_speeds[state] = authored * model_scale

func _match_playback_speed(state: String, speed: float) -> void:
	var authored: float = _clip_speeds.get(state, 0.0)
	if authored <= 0.0 or _player == null:
		return
	var node := _tree.tree_root.get_node(state) as AnimationNodeAnimation
	if node == null or not _player.has_animation(node.animation):
		return
	var rate := clampf(speed / authored, MIN_LOCOMOTION_RATE, MAX_LOCOMOTION_RATE)
	var current: float = _clip_rates.get(state, 1.0)
	if _clip_rates.has(state) and absf(rate - current) / current < RATE_CHANGE_THRESHOLD:
		return
	_clip_rates[state] = rate
	node.use_custom_timeline = true
	node.stretch_time_scale = true
	node.loop_mode = Animation.LOOP_LINEAR
	node.timeline_length = _player.get_animation(node.animation).length / rate

## True from the attack's wind-up until its clip finishes, never longer than
## the clip plus a margin: a one-shot state that doesn't end (a set whose
## Attack falls back to a looping clip) used to root the enemy in place for
## good while its attacks kept landing.
func is_playing_attack() -> bool:
	return _state_machine != null and _state_machine.get_current_node() == &"Attack" and Time.get_ticks_msec() < _one_shot_until

const ONE_SHOT_MARGIN_MSEC := 250
var _one_shot_state: StringName = &""
var _one_shot_until: int = 0

func _enter_one_shot(state: StringName) -> void:
	_one_shot_state = state
	_one_shot_until = Time.get_ticks_msec() + int(_state_length(state) * 1000.0) + ONE_SHOT_MARGIN_MSEC

## Seconds the state's clip runs at its current timeline.
func _state_length(state: StringName) -> float:
	var node := _tree.tree_root.get_node(state) as AnimationNodeAnimation if _tree else null
	if node == null or _player == null or not _player.has_animation(node.animation):
		return 1.0
	return node.timeline_length if node.use_custom_timeline else _player.get_animation(node.animation).length

## Sends a one-shot state that outstays its clip back to Idle.
func _watch_one_shot() -> void:
	if _state_machine == null or _dead:
		return
	var current := _state_machine.get_current_node()
	if current == &"Death" or LOCOMOTION_STATES.has(current):
		_one_shot_state = &""
		return
	if current != _one_shot_state:
		_enter_one_shot(current)  # reached through a pulsed transition
	elif Time.get_ticks_msec() > _one_shot_until:
		_one_shot_state = &""
		_state_machine.start(&"Idle", true)

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
	_pulses += 1
	get_tree().create_timer(CONDITION_PULSE_SEC).timeout.connect(_clear_condition.bind(condition))

func _clear_condition(condition: String) -> void:
	_pulses = maxi(_pulses - 1, 0)
	if is_instance_valid(_tree):
		_tree.set(CONDITION_PATH + condition, false)

## ---- Level of detail ----------------------------------------------------
## The tree is advanced by hand: every frame near the camera, every few
## frames further out, and not at all while off screen or past the draw
## distance, where nobody sees the pose. Anything gameplay waits on (an
## attack, hit, stagger or death state, or a trigger about to fire) always
## runs at full rate, so attack locks and death timings are unaffected.
const LOD_NEAR := 20.0
const LOD_FAR := 45.0
const MID_STEP := 2
const FAR_STEP := 4
## A frozen enemy catches up at most this much time when it reappears.
const MAX_CATCH_UP := 0.25
const LOCOMOTION_STATES: Array[StringName] = [&"Idle", &"Walk", &"Run"]

var _pending_delta: float = 0.0
var _lod_frame: int = 0
var _pulses: int = 0

func _process(delta: float) -> void:
	if _tree == null:
		return
	_watch_one_shot()
	_pending_delta = minf(_pending_delta + delta, MAX_CATCH_UP)
	var step := lod_step()
	if step <= 0:
		return
	_lod_frame += 1
	if _lod_frame % step != 0:
		return
	_tree.advance(_pending_delta)
	_pending_delta = 0.0

## Frames between updates: 1 = every frame, 0 = frozen.
func lod_step() -> int:
	if _dead or _pulses > 0 or (_state_machine and not LOCOMOTION_STATES.has(_state_machine.get_current_node())):
		return 1
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var model := _tree.get_parent() as Node3D
	if camera == null or model == null:
		return 1
	var dist := camera.global_position.distance_to(model.global_position)
	if dist < LOD_NEAR:
		return 1
	if dist > DrawDistance.ACTOR_RANGE or not camera.is_position_in_frustum(model.global_position + Vector3.UP):
		return 0
	return MID_STEP if dist < LOD_FAR else FAR_STEP
