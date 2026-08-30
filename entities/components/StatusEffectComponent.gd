extends Node
class_name StatusEffectComponent
## Section 09 - Status Effects, bidirectional (Player and Enemy both carry
## one, per "Status effects apply bidirectionally"). Scope: Ignite/Chill/
## Freeze/Electrocute/Unraveling - the 5 effects with a real applier today
## (Ability.applies_status_effects on the elemental/esoteric spells).
## Bleed/Armor Shred/Stagger-Stun and Scorch/Aetherburn/Pallid have no
## weapon-side proc mechanic or Fire-channel/Aetheric/Pale ability yet -
## left for this component to grow into later (README flagged gap).
##
## Durations/magnitudes/stack thresholds below are invented - the doc
## names each effect and its qualitative behavior only ("Slows movement
## and action speed", "Advanced Chill stage - full immobilization"), no
## numbers, matching this project's existing convention for unspecified
## tuning (README flagged gap).

signal effect_applied(effect_id: String)
signal effect_expired(effect_id: String)

const IGNITE_DURATION := 4.0
const IGNITE_TICK_INTERVAL := 0.5
const IGNITE_DAMAGE_PERCENT := 0.5  # total DoT damage = 50% of the triggering hit, spread across the duration

const CHILL_DURATION := 2.5
const CHILL_MOVE_SLOW_PERCENT := 0.3
const CHILL_STACKS_TO_FREEZE := 3  # 3rd Chill application within its own window upgrades to Freeze

const FREEZE_DURATION := 1.2

const ELECTROCUTE_DURATION := 0.8

const UNRAVELING_DURATION := 5.0
const UNRAVELING_DAMAGE_TAKEN_PERCENT := 0.25  # "Increased Esoteric damage taken" - applies to the whole category, not just Entropic

## Section 12: Intellect -> "+1.5% Debuff effectiveness" per point, keyed
## off the APPLYING side's Intellect (source), extending non-DoT effect
## durations. Vitality's Resilience/DoT mitigation is the DoT-side
## counterpart - see Player.get_dot_mitigation(), applied in _tick_ignite().
const DEBUFF_EFFECTIVENESS_PER_INTELLECT := 0.015

## Patch v3.2 ADDITION - Resistance Shred: "Temporarily reduces a target's
## Resistance values by a flat percentage for 8 seconds... Stacks from
## multiple sources with diminishing returns." No current applier exists
## in this project - the doc introduces it via The Cartographer of Ruin,
## a Throwable-focused unique, and Throwables aren't built yet (README) -
## the mechanic itself is real and tested, just unreachable from any real
## content for now, same shape as several Brand categories already here.
const RESISTANCE_SHRED_DURATION := 8.0

var _timers: Dictionary = {}  # effect_id -> float seconds remaining
var _chill_stacks: int = 0
var _ignite_ticker: float = 0.0
var _ignite_tick_damage: float = 0.0
var _ignite_source: Node
var _resistance_shred_sources: Array = []  # each {"value": float, "remaining": float}

@onready var _owner: Node = get_parent()

func _process(delta: float) -> void:
	for effect_id in _timers.keys().duplicate():
		_timers[effect_id] -= delta
		if _timers[effect_id] <= 0.0:
			_expire(effect_id)
	if has_effect("ignite"):
		_tick_ignite(delta)
	_tick_resistance_shred(delta)

## Independent-source stacking with a hard duration (not the _timers'
## single-value-refresh model above) - each application is its own
## instance, all contributing simultaneously via get_resistance_shred().
func apply_resistance_shred(percent: float) -> void:
	_resistance_shred_sources.append({"value": percent, "remaining": RESISTANCE_SHRED_DURATION})

## Doc-exact stacking rule, verified against the doc's own worked example
## (20%/15%/10% -> 20 + 7.5 + 5 = 32.5%): the single largest active source
## applies at full value, every OTHER active source contributes at half
## of ITS OWN value - not a compounding chain (10% halved is 5%, not a
## further halving of an already-halved 15%).
func get_resistance_shred() -> float:
	if _resistance_shred_sources.is_empty():
		return 0.0
	var values: Array = []
	for entry in _resistance_shred_sources:
		values.append(entry["value"])
	values.sort()
	values.reverse()
	var total: float = values[0]
	for i in range(1, values.size()):
		total += values[i] * 0.5
	return total

func _tick_resistance_shred(delta: float) -> void:
	for i in range(_resistance_shred_sources.size() - 1, -1, -1):
		_resistance_shred_sources[i]["remaining"] -= delta
		if _resistance_shred_sources[i]["remaining"] <= 0.0:
			_resistance_shred_sources.remove_at(i)

## hit_damage is only used by Ignite (its DoT total is a percent of the
## triggering hit) - irrelevant for the others.
func apply_effect(effect_id: String, source: Node = null, hit_damage: float = 0.0) -> void:
	match effect_id:
		"ignite":
			_apply_ignite(source, hit_damage)
		"chill":
			_apply_chill(source)
		"electrocute":
			_apply_timed("electrocute", ELECTROCUTE_DURATION, source)
			_emit_applied("electrocute")
		"unraveling":
			_apply_timed("unraveling", UNRAVELING_DURATION, source)
			_emit_applied("unraveling")

func has_effect(effect_id: String) -> bool:
	return _timers.has(effect_id)

## "26 - Ability Staging Ground", Utility - Purge: "stripping buffs from
## surrounding enemies while simultaneously clearing debuffs from the
## caster." Only the caster-side half is implemented - no enemy buff
## system exists in this project to strip (every enemy-facing mechanic
## here is a debuff already), so that half of the doc description has
## nothing to act on yet. Ends every active timed effect immediately
## (each via _expire() so effect_expired/EventBus fire normally, same as
## a natural timeout) and clears Resistance Shred sources too, even
## though Shred is something a target of the player's own casts carries,
## not the player - harmless no-op when called on the player, and correct
## if this is ever called on an Enemy's own StatusEffectComponent instead.
func clear_all_effects() -> void:
	for effect_id in _timers.keys().duplicate():
		_expire(effect_id)
	_resistance_shred_sources.clear()

## Electrocute's "Stun / stagger effect" and Freeze's "full immobilization"
## both disrupt action - Chill alone (a slow) does not.
func is_stunned() -> bool:
	return has_effect("electrocute") or has_effect("freeze")

func get_move_speed_multiplier() -> float:
	if is_stunned():
		return 0.0
	if has_effect("chill"):
		return 1.0 - CHILL_MOVE_SLOW_PERCENT
	return 1.0

func get_action_speed_multiplier() -> float:
	return get_move_speed_multiplier()

func get_damage_taken_multiplier(damage_type: Constants.DamageType) -> float:
	if has_effect("unraveling") and Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.ESOTERIC:
		return 1.0 + UNRAVELING_DAMAGE_TAKEN_PERCENT
	return 1.0

func _apply_timed(effect_id: String, base_duration: float, source: Node) -> void:
	var duration := base_duration * _debuff_effectiveness_multiplier(source)
	_timers[effect_id] = max(_timers.get(effect_id, 0.0), duration)

## 3 Chill applications without a Freeze already active upgrade to Freeze
## (Section 09: "Advanced Chill stage") instead of just refreshing Chill's
## own timer indefinitely.
func _apply_chill(source: Node) -> void:
	if has_effect("freeze"):
		return
	_chill_stacks += 1
	if _chill_stacks >= CHILL_STACKS_TO_FREEZE:
		if has_effect("chill"):
			_timers.erase("chill")
			_emit_expired("chill")
		_chill_stacks = 0
		_apply_timed("freeze", FREEZE_DURATION, source)
		_emit_applied("freeze")
	else:
		_apply_timed("chill", CHILL_DURATION, source)
		_emit_applied("chill")

## Re-applying Ignite refreshes it (new tick damage/duration/source) rather
## than stacking independent instances - simplest behavior the doc doesn't
## specify either way.
func _apply_ignite(source: Node, hit_damage: float) -> void:
	_ignite_source = source
	var ticks := IGNITE_DURATION / IGNITE_TICK_INTERVAL
	_ignite_tick_damage = hit_damage * IGNITE_DAMAGE_PERCENT / ticks
	_ignite_ticker = IGNITE_TICK_INTERVAL
	_timers["ignite"] = IGNITE_DURATION
	_emit_applied("ignite")

func _tick_ignite(delta: float) -> void:
	_ignite_ticker -= delta
	if _ignite_ticker > 0.0:
		return
	_ignite_ticker += IGNITE_TICK_INTERVAL
	var dmg := _ignite_tick_damage
	if _owner is Player:
		dmg *= 1.0 - _owner.get_dot_mitigation()
		_owner.take_damage(dmg, Constants.DamageType.FIRE, _ignite_source)
	elif _owner is Enemy:
		# is_spell=true: Ignite only ever comes from a spell hit (Inferno/
		# Cinder Lance), and Section 07 excludes spells from the Composure
		# Break damage bonus - the DoT tick should follow the same rule as
		# the hit that applied it.
		_owner.take_damage(dmg, Constants.DamageType.FIRE, true)
	EventBus.damage_dealt.emit(_ignite_source, _owner, dmg, Constants.DamageType.FIRE, false, false)

func _debuff_effectiveness_multiplier(source: Node) -> float:
	if source is Player:
		return 1.0 + source.stat_sheet.get_stat(Constants.Stat.INTELLECT) * DEBUFF_EFFECTIVENESS_PER_INTELLECT
	return 1.0

func _expire(effect_id: String) -> void:
	_timers.erase(effect_id)
	if effect_id == "freeze":
		_chill_stacks = 0
	_emit_expired(effect_id)

func _emit_applied(effect_id: String) -> void:
	EventBus.status_effect_applied.emit(_owner, effect_id, 1)
	effect_applied.emit(effect_id)

func _emit_expired(effect_id: String) -> void:
	EventBus.status_effect_expired.emit(_owner, effect_id)
	effect_expired.emit(effect_id)
