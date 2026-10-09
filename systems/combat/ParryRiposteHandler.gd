extends Node
class_name ParryRiposteHandler
## Parry -> Stance damage -> Composure Break -> Riposte. Attach to the Player.
##
## EnemyMeleeAttack calls attempt_parry() when a swing resolves.
## PlayerMeleeAttack triggers a riposte on any melee hit against a broken
## enemy, however it was broken.

@export var parry_window_seconds: float = 0.25
@export var parry_stance_damage: float = 25.0
## On top of the swing's motion value. The broken-state damage bonus also
## applies, since the break ends after the hit. Never evadable.
const RIPOSTE_MOTION_VALUE_MULTIPLIER := 1.4
@export var riposte_invuln_duration: float = 1.0

var is_invulnerable: bool = false
var _parry_active: bool = false
var _parry_timer: float = 0.0
var _invuln_timer: float = 0.0

func _process(delta: float) -> void:
	if _parry_active:
		_parry_timer -= delta
		if _parry_timer <= 0.0:
			_parry_active = false
	if is_invulnerable:
		_invuln_timer -= delta
		if _invuln_timer <= 0.0:
			is_invulnerable = false

## The active stance and gear can widen the window (duration only).
func start_parry_window() -> void:
	var player := get_parent() as Player
	var window_mult := 1.0
	if player and player.weapon_stance and player.weapon_stance.is_active and player.weapon_stance.current_behavior:
		window_mult = player.weapon_stance.current_behavior.parry_window_multiplier
	if player and player.stat_sheet:
		window_mult *= 1.0 + player.stat_sheet.get_misc_bonus("parry_window_duration") / 100.0
	_parry_active = true
	_parry_timer = parry_window_seconds * window_mult

## Call when an incoming attack from `attacker` would land while the parry
## window is open. Returns true if the parry succeeded.
func attempt_parry(attacker: Node, ward: WardComponent) -> bool:
	if not _parry_active:
		return false
	_parry_active = false

	var stance: StanceComponent = attacker.get_node_or_null("StanceComponent")
	if stance:
		stance.apply_parry_damage(parry_stance_damage)

	if ward:
		ward.restore_on_parry_success()
		# Gear Ward-on-parry, on top of the base restore.
		var player := get_parent() as Player
		if player and player.stat_sheet:
			var ward_on_parry_pct := player.stat_sheet.get_misc_bonus("ward_on_parry") / 100.0
			if ward_on_parry_pct > 0.0:
				ward.restore(ward.max_ward * ward_on_parry_pct)

	EventBus.parry_successful.emit(get_parent(), attacker)
	return true

func can_riposte(target: Node) -> bool:
	var composure: ComposureComponent = target.get_node_or_null("ComposureComponent") if target else null
	return composure != null and composure.is_broken

## Big hit plus brief invulnerability. Ends the target's broken state.
func execute_riposte(target: Enemy, weapon: Weapon, base_motion_value: float, damage_type: Constants.DamageType) -> void:
	if not can_riposte(target):
		return
	var player: Player = get_parent()
	# Riposte crit chance gear: bump finesse_crit_bonus for this one roll.
	var riposte_crit_bonus := player.stat_sheet.get_misc_bonus("riposte_crit_chance") / 100.0
	var original_crit_bonus := player.stat_sheet.finesse_crit_bonus
	if riposte_crit_bonus > 0.0:
		player.stat_sheet.finesse_crit_bonus = original_crit_bonus * (1.0 + riposte_crit_bonus)
	var hit := weapon.roll_damage(base_motion_value * RIPOSTE_MOTION_VALUE_MULTIPLIER, player.stat_sheet)
	player.stat_sheet.finesse_crit_bonus = original_crit_bonus

	# Patch v4.0 "Increased Riposte Damage" - flat % on top of the whole roll.
	var final_damage: float = hit["final_damage"] * (1.0 + player.stat_sheet.get_misc_bonus("increased_riposte_damage") / 100.0)
	# Counterstrike: bonus damage equal to a share of the Riposte's own hit.
	final_damage += hit["final_damage"] * player.stat_sheet.get_misc_bonus("riposte_counter_damage") / 100.0

	target.take_damage(final_damage, damage_type)
	EventBus.damage_dealt.emit(player, target, final_damage, damage_type, false, hit["is_critical"])

	target.composure.end_broken_state()
	is_invulnerable = true
	_invuln_timer = riposte_invuln_duration
	EventBus.riposte_executed.emit(player, target)
