extends StanceBehavior
class_name RangedStanceBehavior
## Implementation Brief v3.4 Section 5 (2026-08-31). stance_type is purely
## descriptive for now - "DO NOT implement behavioral logic yet for
## stances beyond Rapier, Dagger stealth, and Cutlass Water Slices" (that
## line is under Section 6/melee, but Section 5 gives no per-type formula
## at all, so the same "data only" treatment applies here by default -
## nothing in this project reads stance_type for any real per-type effect
## yet). Only move_speed_multiplier is real (inherited from StanceBehavior,
## already wired into WeaponStance.get_move_speed_multiplier() - NOT
## redeclared here despite the brief's own snippet doing so, since GDScript
## doesn't support a subclass re-declaring a parent's exported var just to
## change its default; each .tres instance sets its own value directly on
## the inherited field instead, same as any other resource).

enum RangedStanceType {
	STEADY_AIM,       # tightens accuracy, increases crit chance
	FAN_THE_HAMMER,   # rapid fire all chambers, forced reload after
	SUPPRESSION,      # hits apply stacking movement slow
	FULL_AUTO_BURST,  # continuous stream, staggers on repeated hits
	POINT_BLANK,      # damage scales with proximity
	BRACE,            # roots, double spread cone
	RAPID_FIRE,       # one arrow per LMB tap at high speed
	KITING_SHOT,      # no movement penalty moving away from target
	SNIPE,            # high MV, pierces all enemies in line
	RAIN_OF_ARROWS,   # arc shot, rains on targeted area
	MARKSMAN,         # longer aim = more damage
	BREATH_CONTROL,   # no movement, removes falloff, pierces one
	DIG_IN,           # roots completely, massively increased fire rate
	TRACER_ROUND,     # marks target, increased damage for 4s
}

@export var stance_type: RangedStanceType = RangedStanceType.STEADY_AIM
