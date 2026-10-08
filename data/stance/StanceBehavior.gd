extends Resource
class_name StanceBehavior
## Per-weapon-type stance tuning (Implementation Brief v3.3 Section 4).
## WeaponStance.gd resolves one of these by the active weapon's own
## weapon_type when stance is entered - null (no matching instance) falls
## back to WeaponStance's own hardcoded defaults.

@export var weapon_type: String = ""
@export var move_speed_multiplier: float = 0.75
@export var parry_window_multiplier: float = 1.0  # >1.0 = wider window
@export var stance_animation: String = ""          # animation name on ArmRig - left blank, no animation system exists yet (see PlayerArmRig.gd)
## No walking, dashing or jumping while held (StanceDefense.is_rooted()).
@export var roots: bool = false
## Seconds before this stance's special (charged/instant attack, volley,
## burst) can be used again. 0 for held stances and pure aim modifiers.
@export var cooldown_seconds: float = 0.0
