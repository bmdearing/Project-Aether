extends Node
class_name ExperienceComponent
## Player-only progression: kill enemies for XP, level up. Per Section 12,
## stats come only from gear/Slates/Jewels/infusions, not level-up growth
## - leveling here doesn't touch StatSheet directly.
##
## Player is a fresh instance every Hub<->Map transition, so Player.gd
## reads GameState.player_level/player_xp at _ready() and writes back on
## every change here, same pattern as sync_equipment()/sync_ability_loadout().

signal leveled_up(new_level: int)
signal xp_changed(current: float, needed: float)

## Invented curve, no doc-sourced leveling design exists. Started at 6%/
## level growth (see PATCH_NOTES.md for why - that pass replaced an
## original 25%/level that compounded to an unreachable ~10^11 XP by
## level 100). User feedback (2026-08-30): 6% made leveling "too easy" -
## and a specific, deliberately absurd target for the endgame grind:
## "Make level 99's requirement 1 below the unsigned integer limit," i.e.
## xp_to_next_level() at level=99 (the last real requirement this system
## ever computes - level 100 is MAX_LEVEL, no further threshold needed)
## should equal 4294967295 - 1 = 4294967294 exactly. Solved for growth
## algebraically (100 * growth^98 = 4294967294) rather than picked by
## feel - works out to ~19.64%/level.
const XP_BASE := 100.0
const XP_GROWTH := 1.196430141231720
const MAX_LEVEL := 100

@export var level: int = 1
@export var xp: float = 0.0

func xp_to_next_level() -> float:
	return XP_BASE * pow(XP_GROWTH, level - 1)

func is_max_level() -> bool:
	return level >= MAX_LEVEL

## Loops so one large XP gain can cross multiple level thresholds at once.
## Stops dead at MAX_LEVEL - any XP gained past the cap is simply
## discarded (no overflow banking), same as most ARPGs at their cap.
func add_xp(amount: float) -> void:
	if amount <= 0.0 or is_max_level():
		return
	xp += amount
	var needed := xp_to_next_level()
	while xp >= needed and not is_max_level():
		xp -= needed
		level += 1
		leveled_up.emit(level)
		if is_max_level():
			xp = 0.0
			break
		needed = xp_to_next_level()
	xp_changed.emit(xp, needed)
