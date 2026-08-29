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

## Invented curve, no doc-sourced leveling design exists.
const XP_BASE := 100.0
const XP_GROWTH := 1.25

@export var level: int = 1
@export var xp: float = 0.0

func xp_to_next_level() -> float:
	return XP_BASE * pow(XP_GROWTH, level - 1)

## Loops so one large XP gain can cross multiple level thresholds at once.
func add_xp(amount: float) -> void:
	if amount <= 0.0:
		return
	xp += amount
	var needed := xp_to_next_level()
	while xp >= needed:
		xp -= needed
		level += 1
		leveled_up.emit(level)
		needed = xp_to_next_level()
	xp_changed.emit(xp, needed)
