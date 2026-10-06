extends Node
class_name WeaponStance
## User request (2026-08-30): "I'm also hoping to add a stance for melee
## weapons, holding right click puts you in a stance that preps you for
## heavier or special attacks... This will also work for ranged weapons
## to aim their weapons." Right-click (the "stance" input action, free
## until now) enters this mode; left-click (the existing "attack" action)
## while active fires the weapon's special instead of a normal swing/shot
## - see Player._physics_process()'s attack dispatch.
##
## Naming note: this is completely unrelated to StanceComponent.gd, which
## is an ENEMY posture/poise bar (Composure/Riposte loop). Deliberately
## named differently (WeaponStance, not e.g. PlayerStance) to keep that
## distinction obvious in code search - see StanceComponent.gd's own
## header if this still reads confusingly.
##
## Caster weapons ("This can also work for caster weapons to do an innate
## ability") are NOT wired up here - no equippable item in this project
## currently identifies as a caster weapon (spellcasting is entirely
## independent of the weapon slot, see PlayerAbilityCast.gd), so there is
## nothing for a caster branch to key off yet. Add a Mode.CASTER branch
## here once a real caster weapon item exists.

enum Mode { NONE, MELEE, RANGED }

## Implementation Brief v3.3 Section 3 additions (2026-08-31): a
## StanceBehavior resource per weapon type (move speed penalty, parry
## window multiplier, a still-unused animation name slot), resolved from
## data/stance/instances/ by the active weapon's weapon_type - see
## _resolve_behavior(). Merged onto the existing stance system rather than
## a rewrite (user direction) - the brief's own signals/get_move_speed_
## multiplier() are additive, everything else here (FOV zoom, arm ready-
## pose, ranged-vs-melee mode) is unchanged.
signal stance_entered
signal stance_exited

## Implementation Brief v3.4 Section 4 (2026-08-31) - a second "page" of
## stance behavior, toggled by HOLDING the weapon-swap key (tapping it
## instead swaps weapon SETS - see Player._handle_weapon_swap_input()).
## Named toggle_stance_page() rather than the brief's own "toggle_stance()" -
## this file already uses "stance" for the RMB-hold is_active concept above,
## reusing that word for something else here would read as conflicting
## with it. Section 7's caster page-2 routing (user direction: route by
## the active weapon's own weapon_type rather than a dedicated Conduit
## slot/offhand field - "Conduits are not a slot" per an earlier decision
## this session) is folded into _resolve_behavior() below: page B looks
## for a StanceBehavior whose own weapon_type is "<Type>_b" first, falling
## back to the plain page-A lookup. No such resource exists yet - per the
## brief, spell page CONTENT is explicitly deferred, this is the toggle
## architecture only.
enum StancePage { A, B }
signal stance_page_changed(page: StancePage)
var active_page: StancePage = StancePage.A

func toggle_stance_page() -> void:
	active_page = StancePage.B if active_page == StancePage.A else StancePage.A
	stance_page_changed.emit(active_page)
	EventBus.stance_page_changed.emit(active_page)

const STANCE_INSTANCES_DIR := "res://data/stance/instances/"
## Brief's own fallback value, used only when no StanceBehavior exists for
## the active weapon's type (e.g. every type except Rapier right now).
const DEFAULT_MOVE_SPEED_MULTIPLIER := 0.75

const READY_POSE_DURATION := 0.28
const EXIT_POSE_DURATION := 0.15
const AIM_FOV := 55.0
const AIM_ZOOM_DURATION := 0.2

var is_active: bool = false
var current_behavior: StanceBehavior = null

var _player: Player
var _mode: Mode = Mode.NONE
var _base_fov: float = 80.0
var _fov_tween: Tween
## weapon_type -> StanceBehavior, lazily scanned once from
## STANCE_INSTANCES_DIR - same dir-scan-and-cache convention as
## PlayerAbilityCast._resolve_ability_by_id()/TomeRoller.
var _behavior_by_weapon_type: Dictionary = {}

func _ready() -> void:
	_player = get_parent()
	if _player.camera:
		_base_fov = _player.camera.fov

## User request (2026-08-31): "Apply movement speed penalty while active
## (read from StanceBehavior resource)." Consumed by Player._effective_
## speed() alongside every other move-speed multiplier source.
func get_move_speed_multiplier() -> float:
	if not is_active:
		return 1.0
	if current_behavior:
		return current_behavior.move_speed_multiplier
	return DEFAULT_MOVE_SPEED_MULTIPLIER

## Implementation Brief v3.4 Section 5: ranged behaviors are authored per
## doc "Line" (Section 25's own base_line_id, e.g. "service_pistol_line1"),
## not per bare weapon_type - a single weapon_type key can't hold more
## than one StanceBehavior in _behavior_by_weapon_type (a Dictionary
## overwrite would silently drop every line but the last one scanned), so
## resolution now takes the whole Weapon and tries its own base_line_id
## first (set by tools/generate_base_types.gd - "" for every hand-
## authored single, which never matches, falling through to the
## weapon_type lookup exactly as before). Ranged .tres instances store
## their line id directly in the inherited weapon_type field to be found
## this way - safe to share one dict/key space with melee's plain type
## names since line ids are lowercase_with_underscores and never collide
## with a Capitalized type name.
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

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("stance") and not _player.is_input_blocked():
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
	if weapon.is_ranged:
		_mode = Mode.RANGED
		_tween_fov(AIM_FOV)
	else:
		_mode = Mode.MELEE
		if _player.melee_attack.is_idle() and _player.arm_rig:
			# GUARD, not the weapon's special-attack windup pose - user
			# feedback (2026-08-30 follow-up): reusing the special's own
			# pose here, further scaled up by SPECIAL_INTENSITY_MULTIPLIER,
			# is what swung the sword and arm off to the side out of frame
			# instead of a held "ready" ready. GUARD is deliberately small
			# and always played at intensity 1.0 (no per-weapon scaling) so
			# this can't recur regardless of how big future specials get.
			_player.arm_rig.enter_ready_pose(PlayerArmRig.PoseSet.GUARD, READY_POSE_DURATION, 1.0)

func _exit_stance() -> void:
	if not is_active:
		return
	is_active = false
	current_behavior = null
	stance_exited.emit()
	if _mode == Mode.RANGED:
		_tween_fov(_base_fov)
	elif _mode == Mode.MELEE and _player.melee_attack.is_idle() and _player.arm_rig:
		# Only reset the pose if no swing is in progress - a special attack
		# already owns the arm rig's tween via its own windup/strike/
		# recovery sequence (see PlayerArmRig.play_attack_swing()), which
		# already ends back at rest on its own. Resetting here too would
		# just kill and restart that tween mid-swing.
		_player.arm_rig.exit_ready_pose(EXIT_POSE_DURATION)
	_mode = Mode.NONE

func _tween_fov(target: float) -> void:
	if _fov_tween and _fov_tween.is_valid():
		_fov_tween.kill()
	if _player.camera == null:
		return
	_fov_tween = create_tween()
	_fov_tween.tween_property(_player.camera, "fov", target, AIM_ZOOM_DURATION)
