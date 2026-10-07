extends StanceBehavior
class_name RangedStanceBehavior
## A ranged weapon's aim stance (Patch v3.4 ranged stance table), resolved
## by weapon_type ("Shortbow_b"/"Longbow_b" for the bows' second page).
## PlayerRangedAttack applies these while RMB aims, on top of the base aim
## bonus (more damage, half the spread).

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

@export_group("Aim stance")
## Multiplies the shot's damage / spread on top of the base aim bonus.
@export var damage_multiplier: float = 1.0
@export var spread_multiplier: float = 1.0
## Extra spread for weapons with none (Fan the Hammer), degrees.
@export var spread_add_degrees: float = 0.0
## Increased crit chance (1.0 = double).
@export var crit_chance_increase: float = 0.0
@export var fire_rate_multiplier: float = 1.0
## > 0: fixed time between shots, skipping draw/cycle (Rapid Fire, Fan the Hammer).
@export var shot_interval: float = 0.0
## Extra enemies a shot passes through.
@export var pierce: int = 0
## Fan the Hammer: one press empties the magazine.
@export var dump_magazine: bool = false
## Point Blank: damage multiplier at point_blank_near, falling to 1x at point_blank_far.
@export var point_blank_max_multiplier: float = 1.0
@export var point_blank_near: float = 2.0
@export var point_blank_far: float = 10.0
## Suppression: slow stacks per hit.
@export var slow_stacks_per_hit: int = 0
## Full Auto Burst: this many hits on one enemy within stagger_window staggers it.
@export var stagger_hits: int = 0
@export var stagger_window: float = 1.0
## Pump Brace: the first shot in stance hits everything in its (widened) cone.
@export var braced_cone_shot: bool = false
@export var cone_range: float = 12.0
## Marksman: damage ramps to aim_ramp_max_multiplier over aim_ramp_time of aiming.
@export var aim_ramp_time: float = 0.0
@export var aim_ramp_max_multiplier: float = 1.0
## Tracer Round: a hit marks the target; your shots deal +mark_damage_bonus to it.
@export var mark_duration: float = 0.0
@export var mark_damage_bonus: float = 0.0
## Kiting Shot: full speed while moving away from where you aim.
@export var backpedal_full_speed: bool = false
## Rain of Arrows: area (m) and number of volleys at the aimed spot.
@export var rain_radius: float = 0.0
@export var rain_waves: int = 0
