extends Node
class_name WardComponent
## Patch v3.2 "Revision - Ward System": Ward is a universal secondary
## life pool absorbing ALL damage types (Physical/Elemental/Esoteric)
## after Armor/Resistance mitigation, before Health - a pure buffer, no
## mitigation percentage of its own. Replaces the old Esoteric-only,
## non-regenerating Ward this project shipped before the patch.
##
## Restoration: a 4s delay after any hit (Patch v4.0, was 2s - reset by
## every subsequent hit, reducible toward a 2s floor by gear), then 4% of
## max Ward/second passive regen. restoration_multiplier
## (Enigma's "+1% Ward Restoration per point," Section 12/patch, set by
## Player._apply_derived_stats()) scales EVERY restoration source -
## passive regen, on-kill, Parry - uniformly, per the patch's "unified
## stat" framing.

signal ward_changed(current: float, max: float)

## Patch v4.0 "Ward Delay Increased to 4 Seconds": baseline 2.0 -> 4.0,
## reduced toward a hard 2.0 floor by Faster Ward Delay gear
## (ward_delay_reduction, set by Player._apply_derived_stats() from
## StatSheet - same "Player pushes a value in" pattern restoration_
## multiplier below already uses, not a Constants.gd constant/live
## StatSheet reference on this component the way an earlier draft of this
## patch assumed - WardComponent has no reference to its owner's
## StatSheet at all).
const BASE_REGEN_DELAY_SECONDS := 4.0
const REGEN_DELAY_FLOOR_SECONDS := 2.0
const REGEN_PERCENT_PER_SECOND := 0.04
## Patch-exact: "On kill: 5% Ward Restoration baseline."
const ON_KILL_RESTORE_PERCENT := 0.05
## Patch: "Parry, Riposte, skill use, status effect application" restore
## Ward - exact ratios aren't given for any of them (only the passive/
## on-kill baselines are numeric), so this stays the same invented flat
## ratio it always was, just now routed through restore()'s Enigma scaling.
const PARRY_RESTORE_PERCENT := 0.15

@export var max_ward: float = 0.0
var current_ward: float = 0.0
## Set by Player._apply_derived_stats() from Enigma - "+1% Ward
## Restoration per point," applied multiplicatively to every restore().
var restoration_multiplier: float = 1.0
## Patch v4.0 - set by Player._apply_derived_stats() from StatSheet.
## ward_delay_reduction (Faster Ward Delay gear, seconds). get_regen_
## delay() clamps the result to REGEN_DELAY_FLOOR_SECONDS regardless of
## how much is invested - "cannot reduce below 2 seconds."
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
		# "4% of max Ward per second" is a flat rate off max_ward, not a
		# compounding percent-of-current-ward one - it works the same
		# starting from empty as it does from any partial amount. Scaled
		# by restoration_multiplier same as every other source - "Ward
		# Restoration is a unified stat" per the patch, and passive regen
		# is explicitly listed under that same heading, distinct from Ward
		# POOL SIZE's own (separate) Enigma scaling.
		restore(max_ward * REGEN_PERCENT_PER_SECOND * delta)

## Absorbs any damage type (Patch v3.2 removes the old Esoteric-only
## restriction) - pure buffer, no mitigation of its own. Every hit resets
## the passive-regen delay, whether or not it actually touched Ward
## (matches the patch's "any hit resets the 2 second delay").
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

## Every restoration source (passive regen, on-kill, Parry, ...) routes
## through here and gets restoration_multiplier's Enigma scaling - "Ward
## Restoration is a unified stat" per the patch.
func restore(amount: float) -> void:
	if amount <= 0.0 or recovery_blocked:
		return
	var final_amount := amount * restoration_multiplier
	current_ward = min(max_ward, current_ward + final_amount)
	ward_changed.emit(current_ward, max_ward)
	EventBus.ward_restored.emit(get_parent(), final_amount)

## Mirrors HealthComponent.set_max_health()'s missing-value-preserving
## behavior - heals by the delta on an increase (so gearing more Enigma
## doesn't just inflate the denominator), clamps on a decrease.
func set_max_ward(new_max: float) -> void:
	var delta := new_max - max_ward
	max_ward = new_max
	current_ward = clamp(current_ward + max(delta, 0.0), 0.0, max_ward)
	ward_changed.emit(current_ward, max_ward)

func restore_on_kill() -> void:
	restore(max_ward * ON_KILL_RESTORE_PERCENT)

func restore_on_parry_success() -> void:
	restore(max_ward * PARRY_RESTORE_PERCENT)
