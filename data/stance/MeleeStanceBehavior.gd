extends StanceBehavior
class_name MeleeStanceBehavior
## Implementation Brief v3.4 Section 6 (2026-08-31). stance_type tags
## which named stance a .tres represents; per the brief, only Rapier
## (already real since v3.3 - move_speed_multiplier/parry_window_
## multiplier), and Cutlass's WATER_SLICES (see PlayerMeleeAttack's own
## Gain-As implementation) have real behavioral logic. Every other type
## here is data + enum tag only, stubbed for a later pass - "the system
## already supports these, just add the data files."
##
## Dagger's STEALTH (page B) is explicitly allowed to have real logic per
## the brief's own wording, but the brief gives no formula/mechanic for
## it (unlike Water Slices, which comes with exact code) - a real
## "stealth" effect would mean touching Enemy's chase/aggro detection,
## which doesn't have a hook for a per-player detection-radius modifier
## today. Left as data-only rather than inventing an ungrounded mechanic -
## flagged in README, not silently skipped.

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
	# PRESSURE_FIST_STANCE_B - deferred, do not add yet (per the brief)
}

@export var stance_type: MeleeStanceType = MeleeStanceType.GUARD

## Charge-and-release stances (hold LMB in stance, release to fire - see
## StanceAttack). charge_time 0 = no charge: LMB plays the instant special.
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
## No walking, dashing or jumping while held.
@export var roots: bool = false
## Frontal barrier pool as a share of max life (Spear Phalanx).
@export var barrier_fraction: float = 0.0
@export var barrier_half_angle: float = 70.0
## Halberd Brace: enemies closing to this range in front get struck.
@export var brace_range: float = 0.0
@export var brace_motion_value: float = 1.2
