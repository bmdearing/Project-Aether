extends StanceBehavior
class_name MeleeStanceBehavior
## A melee weapon's stance page (Patch v3.4 melee stance table). stance_type
## picks the mechanic; the export groups below hold its numbers - see
## StanceAttack (charged and instant attacks) and StanceDefense (held
## stances). Pressure Fist's Stance B is not designed yet.

enum MeleeStanceType {
	CHARGED_THRUST,
	PARRY_READY,
	SLICE_AND_DICE,
	STEALTH,
	EXECUTE,
	GUARD,
	OVERHEAD_SLAM,
	FORTIFY,
	WATER_SLICES,
	HOOKING_STRIKE,
	ARMOR_PIERCE,
	SWEEP,
	BRACE_HALBERD,
	LUNGE,
	PHALANX,
	DISCHARGE,
	REPULSE,
	CRACK,
	ENTANGLE,
	PRESSURE_BLAST,
	EARTHQUAKE,
	SHATTER,
	# PRESSURE_FIST_STANCE_B - deferred, do not add yet (per the brief)
}

@export var stance_type: MeleeStanceType = MeleeStanceType.GUARD

## Charge-and-release stances (holding RMB charges, full charge or letting go fires - see
## StanceAttack). charge_time 0 = no charge: LMB in stance plays the instant special.
@export_group("Charged attack")
@export var charge_time: float = 0.0
## Holding less than this counts as zero charge.
@export var charge_min_time: float = 0.0
## Releasing before full charge cancels instead of attacking.
@export var require_full_charge: bool = false
@export var charge_move_multiplier: float = 0.6
## Multiplier on the weapon's motion value, from zero to full charge.
@export var motion_value_min: float = 1.6
@export var motion_value_max: float = 1.6
## Lunge distance, shockwave length, impact distance or strike range (m).
@export var reach_min: float = 0.0
@export var reach_max: float = 0.0
## Impact radius / shockwave half-width (m).
@export var radius: float = 0.0
## Cone or strike half-angle (degrees).
@export var half_angle: float = 0.0
@export var stance_damage_multiplier: float = 1.0
## Recovery length multiplier at full charge.
@export var recovery_multiplier_max: float = 1.0

## Held stances: passive effects for as long as RMB is held (see StanceDefense).
@export_group("Held stance")
## Share of each incoming melee hit negated (Greatsword Guard).
@export var melee_damage_blocked: float = 0.0
## Share of all incoming damage negated (Mace Fortify).
@export var damage_reduction: float = 0.0
## Frontal barrier pool as a share of max life (Spear Phalanx).
@export var barrier_fraction: float = 0.0
@export var barrier_half_angle: float = 70.0
## Halberd Brace: enemies closing to this range in front get struck.
@export var brace_range: float = 0.0
@export var brace_motion_value: float = 1.2

## Instant stances: LMB fires straight away (see StanceAttack.try_instant()).
## motion_value_min, reach_min, half_angle and radius above apply here too.
@export_group("Instant stance")
## Slice and Dice: hits in the flurry, and the last hit's multiplier when it completes.
@export var hits: int = 1
@export var finisher_multiplier: float = 1.0
## Push (Sweep, Repulse) in m/s.
@export var knockback: float = 0.0
## Entangle's root (s).
@export var status_duration: float = 0.0
## Water Slices projectile.
@export var projectile_speed: float = 0.0
@export var projectile_pierce: int = 1
@export var gain_as_cold: float = 0.0
## Armor Pierce: Armor Shred stacks per hit.
@export var armor_shred_stacks: int = 0
## Stealth: enemy detection range multiplier while hidden, the speed above
## which you're seen, and the first attack's damage multiplier.
@export var stealth_detection_multiplier: float = 1.0
@export var stealth_max_speed: float = 0.0
@export var stealth_damage_multiplier: float = 1.0
