extends Node
class_name ExperienceComponent
## Player-only progression: kill enemies for XP, level up. Doesn't touch
## StatSheet itself - Player._on_leveled_up() applies the per-level stat
## gain (GameState.get_level_stat_bonus()).
##
## Player is a fresh instance every Hub<->Map transition, so Player.gd
## reads GameState.player_level/player_xp at _ready() and writes back on
## every change here, same pattern as sync_equipment()/sync_ability_loadout().

signal leveled_up(new_level: int)
signal xp_changed(current: float, needed: float)

## Growth is solved so level 99's requirement is exactly 4294967294
## (100 * growth^98), one below the uint32 limit.
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
