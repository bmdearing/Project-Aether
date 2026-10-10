extends Node
class_name StatusEffectComponent
## Status effects on a Player or Enemy. Ailments (AILMENT_IDS) roll to land
## (try_apply()); stance riders always land. Numbers are placeholders.

signal effect_applied(effect_id: String)
signal effect_expired(effect_id: String)

const IGNITE_DURATION := 4.0
## Bleed: Physical DoT that ignores Armor.
const BLEED_DURATION := 4.0
## Each stack strips Armor; every new stack refreshes the duration.
const ARMOR_SHRED_PER_STACK := 0.15
const ARMOR_SHRED_MAX_STACKS := 5
const ARMOR_SHRED_DURATION := 6.0
## Machine Pistol Suppression: -8% move speed per stack, up to 5, 3 s.
const SUPPRESSED_SLOW_PER_STACK := 0.08
const SUPPRESSED_MAX_STACKS := 5
const SUPPRESSED_DURATION := 3.0
## Pallid: reduced damage dealt.
const PALLID_DAMAGE_REDUCTION := 0.2
const PALLID_DURATION := 4.0
## "enhanced:<id>" (Fetish's Status Amplifier page) lasts this much longer.
const ENHANCED_DURATION_MULTIPLIER := 1.5
const BLEED_TICK_INTERVAL := 0.5
const BLEED_DAMAGE_PERCENT := 1.0
const IGNITE_TICK_INTERVAL := 0.5
const IGNITE_DAMAGE_PERCENT := 0.9  # total DoT damage = 90% of the triggering hit, spread across the duration

const CHILL_DURATION := 2.5
const CHILL_MOVE_SLOW_PERCENT := 0.35
const CHILL_STACKS_TO_FREEZE := 3

const FREEZE_DURATION := 1.2

const ELECTROCUTE_DURATION := 1.0

const UNRAVELING_DURATION := 5.0
const UNRAVELING_DAMAGE_TAKEN_PERCENT := 0.3  # all Esoteric damage

## Aetherburn: an Aetheric DoT (the hit's share spread over its duration) that
## also burns the target's Ward (an enemy) or Mana (the player) by as much.
const AETHERBURN_DURATION := 4.0
const AETHERBURN_TICK_INTERVAL := 0.5
const AETHERBURN_DAMAGE_PERCENT := 0.8

## Caltrops' slow, refreshed every tick while standing in the field, so the
## duration only needs to outlast one tick.
const SLOW_DURATION := 0.75
const SLOW_MOVE_SLOW_PERCENT := 0.35

## Shock: increased Lightning damage taken; doesn't stun, unlike Electrocute.
const SHOCK_DURATION := 4.0
const SHOCK_DAMAGE_INCREASE := 0.25

## Scorch: stacking Fire damage taken (Ignite ticks included). Each
## application refreshes every stack.
const SCORCH_DURATION := 4.0
const SCORCH_MAX_STACKS := 5
const SCORCH_DAMAGE_PER_STACK := 0.08

## Resistance Shred: each application is an independent source.
const RESISTANCE_SHRED_DURATION := 8.0

## Effects this owner ignores (an Ascendant Juggernaut's crowd control).
var immune_to: Array = []
var _timers: Dictionary = {}  # effect_id -> float seconds remaining
var _chill_stacks: int = 0
var _scorch_stacks: int = 0
var _ignite_ticker: float = 0.0
var _ignite_tick_damage: float = 0.0
var _ignite_source: Node
var _bleed_ticker: float = 0.0
var _bleed_tick_damage: float = 0.0
var _bleed_source: Node
var _aetherburn_ticker: float = 0.0
var _aetherburn_tick_damage: float = 0.0
var _aetherburn_source: Node
## effect_id -> strength when applied (1.0 = base), from the source's
## "effectiveness" gear (effect_multiplier()).
var _magnitude: Dictionary = {}
var _armor_shred_stacks: int = 0
var _suppressed_stacks: int = 0
## Set per application from the caster's tick-rate bonus.
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
	if has_effect("bleed"):
		_tick_bleed(delta)
	if has_effect("aetherburn"):
		_tick_aetherburn(delta)
	_tick_resistance_shred(delta)

func apply_resistance_shred(percent: float) -> void:
	_resistance_shred_sources.append({"value": percent, "remaining": RESISTANCE_SHRED_DURATION})

## Largest source at full value, every other at half its own value
## (20/15/10 -> 20 + 7.5 + 5 = 32.5).
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

## True while a damage-over-time tick's damage_dealt is being emitted, so
## on-hit effects (GearEffects) can skip ticks.
static var emitting_dot := false

const AILMENT_IDS := ["ignite", "bleed", "chill", "shock", "electrocute", "unraveling", "pallid", "scorch", "aetherburn"]
## Ailments with no gear chance stat of their own borrow another's.
const CHANCE_STAT_ALIAS := {"scorch": "ignite"}
## Ailments a plain hit can cause from "+% chance to cause X" gear alone.
const GEAR_PROC_AILMENTS := ["ignite", "bleed", "chill", "shock", "electrocute", "unraveling", "pallid", "aetherburn"]

## The damage a hit must deal to cause each ailment from gear chance alone:
## a Kinetic Tornado can't Unravel just because the caster has Unraveling
## chance. Bleed comes from any physical hit.
const AILMENT_DAMAGE_TYPES := {
	"ignite": [Constants.DamageType.FIRE],
	"chill": [Constants.DamageType.COLD],
	"shock": [Constants.DamageType.LIGHTNING],
	"electrocute": [Constants.DamageType.LIGHTNING],
	"unraveling": [Constants.DamageType.ENTROPIC],
	"aetherburn": [Constants.DamageType.AETHERIC],
	"pallid": [Constants.DamageType.PALE],
	"bleed": [Constants.DamageType.KINETIC, Constants.DamageType.PIERCING, Constants.DamageType.EXPLOSIVE],
}

## Whether a hit of damage_type can cause effect_id through gear chance.
static func damage_can_cause(effect_id: String, damage_type: int) -> bool:
	var types: Array = AILMENT_DAMAGE_TYPES.get(effect_id.trim_prefix("enhanced:"), [])
	return types.is_empty() or types.has(damage_type)

static func is_ailment(effect_id: String) -> bool:
	return AILMENT_IDS.has(effect_id.trim_prefix("enhanced:"))

## The source's "+% chance to cause X" gear, as a fraction.
static func get_chance_bonus(source: Node, effect_id: String) -> float:
	var player := source as Player
	if player == null or player.stat_sheet == null:
		return 0.0
	return player.stat_sheet.get_misc_bonus("ailment_chance_" + CHANCE_STAT_ALIAS.get(effect_id, effect_id)) / 100.0

## Ailments roll base_chance + the source's gear chance; anything else always lands.
func try_apply(effect_id: String, source: Node, hit_damage: float, base_chance: float) -> bool:
	var base_id := effect_id.trim_prefix("enhanced:")
	if AILMENT_IDS.has(base_id) and randf() >= base_chance + get_chance_bonus(source, base_id):
		return false
	apply_effect(effect_id, source, hit_damage)
	return true

## Weapon hits (and spells, for ailments they don't already carry) proc
## ailments purely from the attacker's "+% chance to cause X" gear, but only
## those the hit's damage_type can cause (AILMENT_DAMAGE_TYPES).
func roll_gear_ailments(source: Node, hit_damage: float, damage_type: int, skip: Array = []) -> void:
	if not source is Player:
		return
	for effect_id in GEAR_PROC_AILMENTS:
		if skip.has(effect_id) or skip.has("enhanced:" + effect_id) or not damage_can_cause(effect_id, damage_type):
			continue
		var chance := get_chance_bonus(source, effect_id)
		if chance > 0.0 and randf() < chance:
			apply_effect(effect_id, source, hit_damage)

## hit_damage sets Ignite/Bleed's DoT total; other effects ignore it.
func apply_effect(effect_id: String, source: Node = null, hit_damage: float = 0.0) -> void:
	if immune_to.has(effect_id.trim_prefix("enhanced:")):
		return
	if _owner is Player and is_ailment(effect_id) and randf() < _owner.stat_sheet.get_ailment_ignore_chance():
		return
	if effect_id.begins_with("enhanced:"):
		var base_id := effect_id.trim_prefix("enhanced:")
		apply_effect(base_id, source, hit_damage)
		if _timers.has(base_id):
			_timers[base_id] *= ENHANCED_DURATION_MULTIPLIER
		return
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
		"bleed":
			_bleed_source = source
			_bleed_tick_damage = hit_damage * BLEED_DAMAGE_PERCENT * _ailment_damage_multiplier(source, "bleed") * effect_multiplier(source, "bleed") / (BLEED_DURATION / BLEED_TICK_INTERVAL)
			_bleed_ticker = BLEED_TICK_INTERVAL
			_timers["bleed"] = BLEED_DURATION * _duration_multiplier(source, "bleed")
			_emit_applied("bleed")
		"armor_shred":
			_armor_shred_stacks = mini(_armor_shred_stacks + 1, ARMOR_SHRED_MAX_STACKS)
			_magnitude["armor_shred"] = effect_multiplier(source, "armor_shred")
			_timers["armor_shred"] = ARMOR_SHRED_DURATION
			_emit_applied("armor_shred", _armor_shred_stacks)
		"suppressed":
			_suppressed_stacks = mini(_suppressed_stacks + 1, SUPPRESSED_MAX_STACKS)
			_timers["suppressed"] = SUPPRESSED_DURATION
			_emit_applied("suppressed", _suppressed_stacks)
		"pallid":
			_apply_timed("pallid", PALLID_DURATION, source)
			_emit_applied("pallid")
		"aetherburn":
			_aetherburn_source = source
			_aetherburn_tick_damage = hit_damage * AETHERBURN_DAMAGE_PERCENT * _ailment_damage_multiplier(source, "aetherburn") * effect_multiplier(source, "aetherburn") / (AETHERBURN_DURATION / AETHERBURN_TICK_INTERVAL)
			_aetherburn_ticker = AETHERBURN_TICK_INTERVAL
			_timers["aetherburn"] = AETHERBURN_DURATION * _duration_multiplier(source, "aetherburn")
			_emit_applied("aetherburn")
		"guard_break":
			_timers["guard_break"] = ShieldBlock.GUARD_BREAK_STUN
			_emit_applied("guard_break")
		"scorch":
			_scorch_stacks = mini(_scorch_stacks + 1, SCORCH_MAX_STACKS)
			_timers["scorch"] = SCORCH_DURATION * _duration_multiplier(source, "scorch")
			_emit_applied("scorch", _scorch_stacks)

## Fixed-length effects with no other logic (Whip's Entangle root).
func apply_timed_effect(effect_id: String, duration: float) -> void:
	if immune_to.has(effect_id):
		return
	_timers[effect_id] = maxf(_timers.get(effect_id, 0.0), duration)
	_emit_applied(effect_id)

## Intimidating Shout: takes more damage of every type.
const INTIMIDATED_DAMAGE_TAKEN := 0.2

## Pallid enemies deal less damage.
func get_outgoing_damage_multiplier() -> float:
	return 1.0 - minf(PALLID_DAMAGE_REDUCTION * get_magnitude("pallid"), 0.9) if has_effect("pallid") else 1.0

func get_armor_multiplier() -> float:
	return maxf(1.0 - ARMOR_SHRED_PER_STACK * _armor_shred_stacks * get_magnitude("armor_shred"), 0.0) if has_effect("armor_shred") else 1.0

func has_effect(effect_id: String) -> bool:
	return _timers.has(effect_id)

## Shatter: every ailment on this owner and what breaking it is worth,
## [effect_id, weight, damage type], removing each. Harder-to-apply ailments
## weigh more; Scorch counts per stack.
const SHATTER_VALUES := {
	"freeze": [3.0, Constants.DamageType.COLD],
	"chill": [1.0, Constants.DamageType.COLD],
	"ignite": [1.2, Constants.DamageType.FIRE],
	"scorch": [0.4, Constants.DamageType.FIRE],
	"shock": [1.0, Constants.DamageType.LIGHTNING],
	"electrocute": [2.0, Constants.DamageType.LIGHTNING],
	"unraveling": [1.5, Constants.DamageType.ENTROPIC],
	"bleed": [1.0, Constants.DamageType.KINETIC],
	"pallid": [1.5, Constants.DamageType.PALE],
	"aetherburn": [1.5, Constants.DamageType.AETHERIC],
}

func shatter_ailments() -> Array:
	var broken: Array = []
	for effect_id in SHATTER_VALUES:
		if not has_effect(effect_id):
			continue
		var value: Array = SHATTER_VALUES[effect_id]
		var weight: float = value[0] * (_scorch_stacks if effect_id == "scorch" else 1)
		broken.append([effect_id, weight, value[1]])
		_expire(effect_id)
	return broken

## Purge: expires every effect (firing the normal expiry signals).
func clear_all_effects() -> void:
	for effect_id in _timers.keys().duplicate():
		_expire(effect_id)
	_resistance_shred_sources.clear()

func is_stunned() -> bool:
	return has_effect("electrocute") or has_effect("freeze") or has_effect("guard_break") or has_effect("stun")

func get_move_speed_multiplier() -> float:
	if is_stunned() or has_effect("entangle"):
		return 0.0
	var multiplier := 1.0
	if has_effect("chill"):
		multiplier *= 1.0 - minf(CHILL_MOVE_SLOW_PERCENT * get_magnitude("chill"), 0.9)
	if has_effect("slow"):
		multiplier *= 1.0 - SLOW_MOVE_SLOW_PERCENT
	if has_effect("suppressed"):
		multiplier *= 1.0 - SUPPRESSED_SLOW_PER_STACK * _suppressed_stacks
	return multiplier

func get_action_speed_multiplier() -> float:
	return get_move_speed_multiplier()

func get_damage_taken_multiplier(damage_type: Constants.DamageType) -> float:
	var multiplier := 1.0
	if has_effect("unraveling") and Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.ESOTERIC:
		multiplier *= 1.0 + UNRAVELING_DAMAGE_TAKEN_PERCENT * get_magnitude("unraveling")
	if has_effect("intimidated"):
		multiplier *= 1.0 + INTIMIDATED_DAMAGE_TAKEN
	if damage_type == Constants.DamageType.FIRE:
		multiplier *= get_scorch_multiplier()
	return multiplier

func get_scorch_stacks() -> int:
	return _scorch_stacks if has_effect("scorch") else 0

func get_scorch_multiplier() -> float:
	return 1.0 + SCORCH_DAMAGE_PER_STACK * get_scorch_stacks()

## Lightning only; the caller applies it on top of get_damage_taken_multiplier().
func get_shock_multiplier() -> float:
	if has_effect("shock"):
		return 1.0 + SHOCK_DAMAGE_INCREASE * get_magnitude("shock")
	return 1.0

func _apply_timed(effect_id: String, base_duration: float, source: Node) -> void:
	var duration := base_duration * _duration_multiplier(source, effect_id)
	_magnitude[effect_id] = effect_multiplier(source, effect_id)
	_timers[effect_id] = max(_timers.get(effect_id, 0.0), duration)

## The CHILL_STACKS_TO_FREEZE-th Chill upgrades to Freeze.
func _apply_chill(source: Node) -> void:
	if has_effect("freeze"):
		return
	_chill_stacks += 1
	if _chill_stacks >= freeze_stacks_needed(source):
		if has_effect("chill"):
			_timers.erase("chill")
			_emit_expired("chill")
		_chill_stacks = 0
		_apply_timed("freeze", FREEZE_DURATION, source)
		_emit_applied("freeze")
	else:
		_apply_timed("chill", CHILL_DURATION, source)
		_emit_applied("chill")

## Re-applying refreshes rather than stacking. Damage and tick-rate bonuses
## come from the source's gear; faster ticks keep the same total damage.
func _apply_ignite(source: Node, hit_damage: float) -> void:
	_ignite_source = source
	var source_stats: StatSheet = source.stat_sheet if source is Player else null
	var total_damage := hit_damage * IGNITE_DAMAGE_PERCENT
	total_damage *= effect_multiplier(source, "ignite")
	if source_stats:
		total_damage *= _ailment_damage_multiplier(source, "ignite")
	var tick_interval := IGNITE_TICK_INTERVAL
	if source_stats:
		tick_interval /= 1.0 + source_stats.get_ailment_tick_rate_bonus()
	var ticks := IGNITE_DURATION / tick_interval
	_ignite_tick_damage = total_damage / ticks
	_ignite_ticker = tick_interval
	_ignite_tick_interval = tick_interval
	var duration := IGNITE_DURATION * _duration_multiplier(source, "ignite")
	_timers["ignite"] = duration
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
		# is_spell: ticks skip the Composure Break bonus, like spell hits.
		_owner.take_damage(dmg, Constants.DamageType.FIRE, true, false, true)
	emitting_dot = true
	EventBus.damage_dealt.emit(_ignite_source, _owner, dmg, Constants.DamageType.FIRE, false, false)
	emitting_dot = false

func _tick_bleed(delta: float) -> void:
	_bleed_ticker -= delta
	if _bleed_ticker > 0.0:
		return
	_bleed_ticker += BLEED_TICK_INTERVAL
	if _owner is Player:
		_owner.take_damage(_bleed_tick_damage * (1.0 - _owner.get_dot_mitigation()), Constants.DamageType.KINETIC, _bleed_source, Player.HitKind.DOT)
	elif _owner is Enemy:
		_owner.take_damage(_bleed_tick_damage, Constants.DamageType.KINETIC, false, false, true)
	emitting_dot = true
	EventBus.damage_dealt.emit(_bleed_source, _owner, _bleed_tick_damage, Constants.DamageType.KINETIC, false, false)
	emitting_dot = false

## "+% increased X duration" from the source's gear.
func _duration_multiplier(source: Node, effect_id: String) -> float:
	var player := source as Player
	if player == null or player.stat_sheet == null:
		return 1.0
	return 1.0 + player.stat_sheet.get_ailment_duration_bonus(CHANCE_STAT_ALIAS.get(effect_id, effect_id))

## "+% increased X damage" and the DoT multiplier from the source's gear.
func _ailment_damage_multiplier(source: Node, effect_id: String) -> float:
	var player := source as Player
	if player == null or player.stat_sheet == null:
		return 1.0
	return (1.0 + player.stat_sheet.get_ailment_damage_bonus(effect_id)) * (1.0 + player.stat_sheet.get_dot_multiplier())

func _expire(effect_id: String) -> void:
	_timers.erase(effect_id)
	if effect_id == "armor_shred":
		_armor_shred_stacks = 0
	elif effect_id == "suppressed":
		_suppressed_stacks = 0
	if effect_id == "freeze":
		_chill_stacks = 0
	elif effect_id == "scorch":
		_scorch_stacks = 0
	_emit_expired(effect_id)

func _emit_applied(effect_id: String, stacks: int = 1) -> void:
	EventBus.status_effect_applied.emit(_owner, effect_id, stacks)
	effect_applied.emit(effect_id)

func _emit_expired(effect_id: String) -> void:
	EventBus.status_effect_expired.emit(_owner, effect_id)
	effect_expired.emit(effect_id)

func _tick_aetherburn(delta: float) -> void:
	_aetherburn_ticker -= delta
	if _aetherburn_ticker > 0.0:
		return
	_aetherburn_ticker += AETHERBURN_TICK_INTERVAL
	var dmg := _aetherburn_tick_damage
	if _owner is Player:
		dmg *= 1.0 - _owner.get_dot_mitigation()
		_owner.take_damage(dmg, Constants.DamageType.AETHERIC, _aetherburn_source, Player.HitKind.DOT)
		_owner.mana.spend(dmg)
	elif _owner is Enemy:
		_owner.take_damage(dmg, Constants.DamageType.AETHERIC, true, false, true)
		_owner.drain_ward(dmg)
	emitting_dot = true
	EventBus.damage_dealt.emit(_aetherburn_source, _owner, dmg, Constants.DamageType.AETHERIC, false, false)
	emitting_dot = false

## Debuffs whose strength scales with "debuff effectiveness"; every ailment
## also scales with "ailment effectiveness".
const DEBUFF_IDS := ["chill", "shock", "unraveling", "pallid", "electrocute", "slow", "suppressed", "intimidated"]

## How strong an effect the source applies: 1 + its "<id>_effect" gear
## (Chill/Shock/Unraveling/Pallid effectiveness), plus ailment and debuff
## effectiveness where they apply.
static func effect_multiplier(source: Node, effect_id: String) -> float:
	var player := source as Player
	if player == null or player.stat_sheet == null:
		return 1.0
	var sheet := player.stat_sheet
	var percent := sheet.get_misc_bonus(effect_id + "_effect")
	if is_ailment(effect_id):
		percent += sheet.get_misc_bonus("ailment_effectiveness")
	if DEBUFF_IDS.has(effect_id):
		percent += sheet.get_misc_bonus("debuff_effectiveness")
	return 1.0 + percent / 100.0

func get_magnitude(effect_id: String) -> float:
	return _magnitude.get(effect_id, 1.0)

## Chill stacks that Freeze, lowered by the source's "reduced Freeze threshold".
static func freeze_stacks_needed(source: Node) -> int:
	var player := source as Player
	var reduction := player.stat_sheet.get_misc_bonus("freeze_threshold_reduction") / 100.0 if player and player.stat_sheet else 0.0
	return maxi(1, roundi(CHILL_STACKS_TO_FREEZE * (1.0 - reduction)))
