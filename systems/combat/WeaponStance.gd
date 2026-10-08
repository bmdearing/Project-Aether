extends Node
class_name WeaponStance
## Holding the "stance" input (RMB) readies the weapon: melee preps special
## attacks, ranged aims. Unrelated to StanceComponent, the enemy poise bar.

enum Mode { NONE, MELEE, RANGED, CASTER }

## Per-weapon tuning comes from a StanceBehavior resource (_resolve_behavior()).
signal stance_entered
signal stance_exited

## Second stance page, toggled by holding the weapon-swap key. Page B looks
## up a "<type>_b" StanceBehavior first, falling back to page A's.
enum StancePage { A, B }
signal stance_page_changed(page: StancePage)
var active_page: StancePage = StancePage.A

func toggle_stance_page() -> void:
	set_stance_page(StancePage.B if active_page == StancePage.A else StancePage.A)

func set_stance_page(page: StancePage) -> void:
	if page == active_page:
		return
	active_page = page
	GameState.stance_page = page
	stance_page_changed.emit(active_page)
	EventBus.stance_page_changed.emit(active_page)

const STANCE_INSTANCES_DIR := "res://data/stance/instances/"
## Brief's own fallback value, used only when no StanceBehavior exists for
## the active weapon's type (e.g. every type except Rapier right now).
const DEFAULT_MOVE_SPEED_MULTIPLIER := 0.75

const AIM_FOV := 55.0
const AIM_ZOOM_DURATION := 0.2

var is_active: bool = false
var current_behavior: StanceBehavior = null

var _player: Player
var _mode: Mode = Mode.NONE
var _fov_tween: Tween
## weapon_type -> StanceBehavior, lazily scanned from STANCE_INSTANCES_DIR.
var _behavior_by_weapon_type: Dictionary = {}
## StanceBehavior -> seconds until its special is ready again.
var _cooldowns: Dictionary = {}

func _ready() -> void:
	_player = get_parent()
	active_page = GameState.stance_page as StancePage

## The StanceBehavior's move speed penalty while active.
func get_move_speed_multiplier() -> float:
	if not is_active:
		return 1.0
	if current_behavior is RangedStanceBehavior and current_behavior.backpedal_full_speed and _is_backpedaling():
		return 1.0
	if current_behavior:
		return current_behavior.move_speed_multiplier
	return DEFAULT_MOVE_SPEED_MULTIPLIER

## Kiting Shot: moving away from where you aim.
func _is_backpedaling() -> bool:
	var forward := -_player.camera.global_transform.basis.z
	var flat := Vector2(forward.x, forward.z).normalized()
	return Vector2(_player.velocity.x, _player.velocity.z).dot(flat) < -0.5

## Tries the weapon's base_line_id first (ranged behaviors are authored per
## line, e.g. "service_pistol_line1"), then its weapon_type. Line ids are
## lowercase, so they never collide with Capitalized type names.
func _resolve_behavior(weapon: Weapon) -> StanceBehavior:
	if _behavior_by_weapon_type.is_empty():
		_scan_behaviors()
	if active_page == StancePage.B:
		var page_b_key := weapon.weapon_type + "_b"
		if _behavior_by_weapon_type.has(page_b_key):
			return _behavior_by_weapon_type[page_b_key]
	if weapon.base_line_id != "" and _behavior_by_weapon_type.has(weapon.base_line_id):
		return _behavior_by_weapon_type[weapon.base_line_id]
	return _behavior_by_weapon_type.get(weapon.weapon_type)

func _scan_behaviors() -> void:
	var dir := DirAccess.open(STANCE_INSTANCES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var behavior: StanceBehavior = load(STANCE_INSTANCES_DIR + file_name) as StanceBehavior
			if behavior:
				_behavior_by_weapon_type[behavior.weapon_type] = behavior
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()

func _physics_process(delta: float) -> void:
	for behavior in _cooldowns.keys():
		_cooldowns[behavior] = maxf(_cooldowns[behavior] - delta, 0.0)
	if Input.is_action_just_pressed("stance") and not _player.is_input_blocked() \
			and not _player.shield_block.overrides_stance():
		_enter_stance()
	elif Input.is_action_just_released("stance"):
		_exit_stance()

func _enter_stance() -> void:
	if is_active:
		return
	if _player.status_effects.is_stunned():
		return
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return
	is_active = true
	current_behavior = _resolve_behavior(weapon)
	stance_entered.emit()
	if _player.caster_stance.get_source() != null:
		# A conduit's stance replaces the weapon's own (see CasterStance).
		_mode = Mode.CASTER
		current_behavior = null
		_player.caster_stance.on_stance_entered()
	elif weapon.is_ranged:
		_mode = Mode.RANGED
		_tween_fov(AIM_FOV)
	else:
		_mode = Mode.MELEE
	if _player.arm_rig:
		_player.arm_rig.set_aiming(_mode == Mode.RANGED)
		_player.arm_rig.set_guard(_mode == Mode.MELEE)

func get_cooldown_remaining(behavior: StanceBehavior) -> float:
	return _cooldowns.get(behavior, 0.0) if behavior else 0.0

func is_ready(behavior: StanceBehavior) -> bool:
	return get_cooldown_remaining(behavior) <= 0.0

func start_cooldown(behavior: StanceBehavior) -> void:
	if behavior and behavior.cooldown_seconds > 0.0:
		_cooldowns[behavior] = behavior.cooldown_seconds

## The stance RMB would enter right now (page and weapon aware), for the HUD.
func get_ready_behavior() -> StanceBehavior:
	if is_active:
		return current_behavior
	var weapon := _player.get_active_weapon() if _player else null
	return _resolve_behavior(weapon) if weapon else null

## Drops out of stance without waiting for RMB release (shield raised).
func cancel() -> void:
	_exit_stance()

func _exit_stance() -> void:
	if not is_active:
		return
	is_active = false
	current_behavior = null
	stance_exited.emit()
	if _mode == Mode.RANGED:
		_tween_fov(GameState.field_of_view)
	if _player.arm_rig:
		_player.arm_rig.set_aiming(false)
		_player.arm_rig.set_guard(false)
	_mode = Mode.NONE

func _tween_fov(target: float) -> void:
	if _fov_tween and _fov_tween.is_valid():
		_fov_tween.kill()
	if _player.camera == null:
		return
	_fov_tween = create_tween()
	_fov_tween.tween_property(_player.camera, "fov", target, AIM_ZOOM_DURATION)
