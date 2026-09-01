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
