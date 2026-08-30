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
## nothing for a caster branch to key off yet. The `conduit` equipment
## slot exists but nothing reads it. Add a Mode.CASTER branch here once a
## real caster weapon item exists.

enum Mode { NONE, MELEE, RANGED }

const READY_POSE_DURATION := 0.28
const EXIT_POSE_DURATION := 0.15
const AIM_FOV := 55.0
const AIM_ZOOM_DURATION := 0.2

var is_active: bool = false

var _player: Player
var _mode: Mode = Mode.NONE
var _base_fov: float = 80.0
var _fov_tween: Tween

func _ready() -> void:
	_player = get_parent()
	if _player.camera:
		_base_fov = _player.camera.fov

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("stance"):
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
