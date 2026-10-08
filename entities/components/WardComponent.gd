extends Node
class_name WardComponent
## Secondary life pool that absorbs all damage types after mitigation,
## before Health. Regenerates a percent of max per second after a delay that
## every hit resets. restoration_multiplier scales every restore source.

signal ward_changed(current: float, max: float)

## Reduced by gear (regen_delay_reduction) down to REGEN_DELAY_FLOOR_SECONDS.
const BASE_REGEN_DELAY_SECONDS := 4.0
const REGEN_DELAY_FLOOR_SECONDS := 2.0
const REGEN_PERCENT_PER_SECOND := 0.04
const ON_KILL_RESTORE_PERCENT := 0.05
## Placeholder.
const PARRY_RESTORE_PERCENT := 0.15

@export var max_ward: float = 0.0
var current_ward: float = 0.0
## Pushed in by Player._apply_derived_stats(); scales every restore().
var restoration_multiplier: float = 1.0
## Seconds, pushed in by Player._apply_derived_stats().
var regen_delay_reduction: float = 0.0
## Set by UniqueEffects (The Pale Eye, Stride of the Unwound): no restoration at all.
var recovery_blocked: bool = false

var _regen_delay_timer: float = 0.0

func get_regen_delay() -> float:
	return max(REGEN_DELAY_FLOOR_SECONDS, BASE_REGEN_DELAY_SECONDS - regen_delay_reduction)

func _process(delta: float) -> void:
	if _regen_delay_timer > 0.0:
		_regen_delay_timer -= delta
		return
	if current_ward < max_ward:
		restore(max_ward * REGEN_PERCENT_PER_SECOND * delta)

## Returns the damage left over. Every hit resets the regen delay, even
## with Ward empty.
func absorb(incoming_damage: float) -> float:
	_regen_delay_timer = get_regen_delay()
	if current_ward <= 0.0:
		return incoming_damage

	var absorbed: float = min(current_ward, incoming_damage)
	current_ward -= absorbed
	ward_changed.emit(current_ward, max_ward)
	if current_ward <= 0.0:
		EventBus.ward_depleted.emit(get_parent())
	return incoming_damage - absorbed

## Every restoration source routes through here.
func restore(amount: float) -> void:
	if amount <= 0.0 or recovery_blocked:
		return
	var final_amount := amount * restoration_multiplier
	current_ward = min(max_ward, current_ward + final_amount)
	ward_changed.emit(current_ward, max_ward)
	EventBus.ward_restored.emit(get_parent(), final_amount)

## Gains the delta on an increase, clamps on a decrease.
func set_max_ward(new_max: float) -> void:
	var delta := new_max - max_ward
	max_ward = new_max
	current_ward = clamp(current_ward + max(delta, 0.0), 0.0, max_ward)
	ward_changed.emit(current_ward, max_ward)

func restore_on_kill() -> void:
	restore(max_ward * ON_KILL_RESTORE_PERCENT)

func restore_on_parry_success() -> void:
	restore(max_ward * PARRY_RESTORE_PERCENT)
