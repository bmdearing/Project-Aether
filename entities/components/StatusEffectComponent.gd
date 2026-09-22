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

## Generic movement slow, independent of Chill - user request (2026-08-30):
## "Caltrops should slow... enemies that continue to stand on it." Reusing
## Chill for this would be a thematic mismatch (Chill is explicitly Cold-
## flavored per Constants.STATUS_EFFECT_DAMAGE_TYPE, Caltrops is Physical/
## Piercing) - this is its own effect instead. Refreshed continuously by
## CaltropsField while an enemy stands in the field (not a one-shot
## application), so SLOW_DURATION just needs to outlast one tick interval
## comfortably, not model a real "how long does this linger" duration.
const SLOW_DURATION := 0.75
const SLOW_MOVE_SLOW_PERCENT := 0.35

## Patch v3.8b: Spark's new proc, replacing Electrocute on that ability only
## (Thunder Javelin/Thunder Sweep keep Electrocute). Non-stacking, duration
## refreshes on reapplication (same _apply_timed model as Electrocute/
## Unraveling/Slow above) - does not stun/interrupt, unlike Electrocute.
const SHOCK_DURATION := 4.0
const SHOCK_DAMAGE_INCREASE := 0.20

## Patch v3.8: Debuff Effectiveness is a "removed expression" - no longer
## derived from a character stat (Intellect, its old source, is gone).
## debuff_effectiveness exists as a real ItemRoller.AFFIX_POOL entry but
## has no consumer wired up yet (same "real affix, no formula to feed it"
## footing several other Patch v3.8 gear-only stats share) - this always
## returns 1.0 (no bonus) until that wiring exists.

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
## Patch v4.0 Faster Ailment Tick Rate - per-application, since the
## caster's tick-rate bonus can change between one Ignite application and
## the next (unlike IGNITE_TICK_INTERVAL, which was always a fixed constant).
var _ignite_tick_interval: float = IGNITE_TICK_INTERVAL
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
		"slow":
			_apply_timed("slow", SLOW_DURATION, source)
			_emit_applied("slow")
		"shock":
			_apply_timed("shock", SHOCK_DURATION, source)
			_emit_applied("shock")

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
	var multiplier := 1.0
	if has_effect("chill"):
		multiplier *= 1.0 - CHILL_MOVE_SLOW_PERCENT
	if has_effect("slow"):
		multiplier *= 1.0 - SLOW_MOVE_SLOW_PERCENT
	return multiplier

func get_action_speed_multiplier() -> float:
	return get_move_speed_multiplier()

func get_damage_taken_multiplier(damage_type: Constants.DamageType) -> float:
	if has_effect("unraveling") and Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.ESOTERIC:
		return 1.0 + UNRAVELING_DAMAGE_TAKEN_PERCENT
	return 1.0

## Lightning damage only - applied on top of get_damage_taken_multiplier()
## by the caller (Enemy.take_damage()), not folded into it, since that
## method is category-keyed (Elemental/Esoteric) and Shock is a single-
## damage-type effect.
func get_shock_multiplier() -> float:
	if has_effect("shock"):
		return 1.0 + SHOCK_DAMAGE_INCREASE
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
##
## Patch v4.0 Ailment Build Mod Pool - Increased Ailment Damage/DoT
## Multiplier/Faster Tick Rate all come from the CASTER's own gear
## (source's StatSheet, not this component's owner - a Player casting
## Ignite onto an Enemy scales it by the Player's own stats, not the
## Enemy's, and Enemy has no StatSheet to read regardless). Faster Tick
## Rate preserves total damage and shortens the interval, per the doc:
## "same total damage, faster delivery."
func _apply_ignite(source: Node, hit_damage: float) -> void:
	_ignite_source = source
	var source_stats: StatSheet = source.stat_sheet if source is Player else null
	var total_damage := hit_damage * IGNITE_DAMAGE_PERCENT
	if source_stats:
		total_damage *= 1.0 + source_stats.get_ailment_damage_bonus("ignite")
		total_damage *= 1.0 + source_stats.get_dot_multiplier()
	var tick_interval := IGNITE_TICK_INTERVAL
	if source_stats:
		tick_interval /= 1.0 + source_stats.get_ailment_tick_rate_bonus()
	var ticks := IGNITE_DURATION / tick_interval
	_ignite_tick_damage = total_damage / ticks
	_ignite_ticker = tick_interval
	_ignite_tick_interval = tick_interval
	_timers["ignite"] = IGNITE_DURATION
	_emit_applied("ignite")

func _tick_ignite(delta: float) -> void:
	_ignite_ticker -= delta
	if _ignite_ticker > 0.0:
		return
	_ignite_ticker += _ignite_tick_interval
	var dmg := _ignite_tick_damage
	if _owner is Player:
		dmg *= 1.0 - _owner.get_dot_mitigation()
		_owner.take_damage(dmg, Constants.DamageType.FIRE, _ignite_source, Player.HitKind.DOT)  # ticks are never evaded
	elif _owner is Enemy:
		# is_spell=true: Ignite only ever comes from a spell hit (Inferno/
		# Cinder Lance), and Section 07 excludes spells from the Composure
		# Break damage bonus - the DoT tick should follow the same rule as
		# the hit that applied it.
		_owner.take_damage(dmg, Constants.DamageType.FIRE, true)
	EventBus.damage_dealt.emit(_ignite_source, _owner, dmg, Constants.DamageType.FIRE, false, false)

func _debuff_effectiveness_multiplier(_source: Node) -> float:
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
