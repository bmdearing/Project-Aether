extends RefCounted
class_name CorruptionSystem
## Shard of Tharsis: rolls a severity tier, then a named outcome from it
## (CorruptionOutcome). CraftingSystem.corrupt() wraps corrupt() below.

## Outcome tier weights - adjust after playtesting.
const TIER_WEIGHTS := {
	1: 55,   # Minor - most common
	2: 30,   # Significant
	3: 12,   # Major
	4: 3,    # Extreme
}

enum OutcomeTier { MINOR = 1, SIGNIFICANT = 2, MAJOR = 3, EXTREME = 4 }

const _MINOR := [
	"AddImplicit", "RerandomizeValues", "AddSocket", "RemoveSocket", "TierUp", "TierDown",
]
const _SIGNIFICANT := [
	"AddSpecialAffix", "AddExtraSocket", "ConvertAffix", "AddSecondImplicit",
	"ResistanceShredAura", "SkillNoCooldown",
]
const _MAJOR := [
	"Veiltouch", "Hollow", "Inversion", "MawTouched", "PaleBranded", "Overcharged",
	"Ascendant",
]
const _EXTREME := [
	"Transcendent", "Unmade", "ResonantEcho", "AethericSurge",
]

static func corrupt(item: Item, power_level: int = 1) -> CorruptionOutcome:
	if item == null:
		return CorruptionOutcome.new(false, "Nothing to corrupt.")
	if item.is_corrupted:
		return CorruptionOutcome.new(false, "Item is already corrupted")
	if not item.is_craftable:
		return CorruptionOutcome.new(false, "This item was already corrupted beyond further chaos.")

	var tier := _roll_tier()
	var outcome := _roll_outcome(tier, item, power_level)
	item.is_corrupted = true
	# Rev2: a corrupted item can't be crafted further (Orbs gate on
	# is_corrupted; the legacy Cube gates on is_craftable).
	item.is_craftable = false
	EventBus.corruption_applied.emit(item, outcome.outcome_name, outcome.tier)
	return outcome

static func _roll_tier() -> int:
	var total := 0
	for w in TIER_WEIGHTS.values():
		total += w
	var roll := randi() % total
	var cumulative := 0
	for tier in TIER_WEIGHTS:
		cumulative += TIER_WEIGHTS[tier]
		if roll < cumulative:
			return tier
	return 1

static func _roll_outcome(tier: int, item: Item, power_level: int) -> CorruptionOutcome:
	var names: Array
	match tier:
		1: names = _MINOR
		2: names = _SIGNIFICANT
		3: names = _MAJOR
		4: names = _EXTREME
		_: names = _MINOR
	var outcome_name: String = names[randi() % names.size()]
	var outcome := _instantiate(outcome_name)
	outcome.outcome_name = outcome_name
	outcome.tier = tier
	outcome.apply(item, power_level)
	return outcome

static func _instantiate(outcome_name: String) -> CorruptionOutcome:
	match outcome_name:
		"AddImplicit": return CorruptionOutcome.AddImplicit.new()
		"RerandomizeValues": return CorruptionOutcome.RerandomizeValues.new()
		"AddSocket": return CorruptionOutcome.AddSocket.new()
		"RemoveSocket": return CorruptionOutcome.RemoveSocket.new()
		"TierUp": return CorruptionOutcome.TierUp.new()
		"TierDown": return CorruptionOutcome.TierDown.new()
		"AddSpecialAffix": return CorruptionOutcome.AddSpecialAffix.new()
		"AddExtraSocket": return CorruptionOutcome.AddExtraSocket.new()
		"ConvertAffix": return CorruptionOutcome.ConvertAffix.new()
		"AddSecondImplicit": return CorruptionOutcome.AddSecondImplicit.new()
		"ResistanceShredAura": return CorruptionOutcome.ResistanceShredAura.new()
		"SkillNoCooldown": return CorruptionOutcome.SkillNoCooldown.new()
		"Veiltouch": return CorruptionOutcome.Veiltouch.new()
		"Hollow": return CorruptionOutcome.Hollow.new()
		"Inversion": return CorruptionOutcome.Inversion.new()
		"MawTouched": return CorruptionOutcome.MawTouched.new()
		"PaleBranded": return CorruptionOutcome.PaleBranded.new()
		"Overcharged": return CorruptionOutcome.Overcharged.new()
		"Ascendant": return CorruptionOutcome.Ascendant.new()
		"Transcendent": return CorruptionOutcome.Transcendent.new()
		"Unmade": return CorruptionOutcome.Unmade.new()
		"ResonantEcho": return CorruptionOutcome.ResonantEcho.new()
		"AethericSurge": return CorruptionOutcome.AethericSurge.new()
	return CorruptionOutcome.new()

## What each outcome does, for the Wiki.
const DESCRIPTIONS := {
	"AddImplicit": "Adds an implicit from the item type's implicit pool (up to 3).",
	"RerandomizeValues": "Rerolls every explicit modifier's value within its tier.",
	"AddSocket": "Adds a socket, up to the item's maximum.",
	"RemoveSocket": "Removes a socket.",
	"TierUp": "One modifier moves up a tier (Tier 3 becomes Tier 2).",
	"TierDown": "One modifier moves down a tier.",
	"AddSpecialAffix": "Adds a corrupted modifier: one of the item's own at 130% of its Tier 1 maximum.",
	"AddExtraSocket": "Adds a socket beyond the maximum (up to +1).",
	"ConvertAffix": "Replaces one modifier with a random modifier of the same pool.",
	"AddSecondImplicit": "Adds a second implicit from the item type's pool.",
	"ResistanceShredAura": "Implicit: nearby enemies have 8% reduced Resistances.",
	"SkillNoCooldown": "Implicit: one ability bar slot has no cooldown but costs 40% more Mana.",
	"Veiltouch": "Replaces one modifier with a Slate modifier (once per item).",
	"Hollow": "Removes every explicit. Implicit: 25% increased damage, your hits drain Ward equal to 10% of their damage.",
	"Inversion": "One resistance becomes a vulnerability; every other modifier is 20% stronger.",
	"MawTouched": "Implicit: skills have an 8% chance to trigger twice (the second at 50% damage).",
	"PaleBranded": "Implicit: 35% increased maximum Life, but Ward cannot be recovered.",
	"Overcharged": "Every modifier rolls in the top 20% of its tier; one modifier is removed.",
	"Ascendant": "The weapon's scaling grade improves by one.",
	"Transcendent": "The item becomes a corrupted-only Unique; every modifier is lost.",
	"Unmade": "Strips everything; the base gains 10 item levels (up to 91).",
	"ResonantEcho": "Copies one modifier as an implicit at 60% strength.",
	"AethericSurge": "Doubles an Esoteric modifier, or replaces a modifier with an Aetheric one.",
}

## Outcome names by tier (1-4).
static func outcomes_in_tier(tier: int) -> Array:
	return [_MINOR, _SIGNIFICANT, _MAJOR, _EXTREME][clampi(tier, 1, 4) - 1]

## Chance a Shard of Tharsis rolls this outcome.
static func outcome_chance(outcome_name: String) -> float:
	var total := 0.0
	for w in TIER_WEIGHTS.values():
		total += w
	for tier in TIER_WEIGHTS:
		var names := outcomes_in_tier(tier)
		if names.has(outcome_name):
			return TIER_WEIGHTS[tier] / total / names.size()
	return 0.0

## Whether an outcome can change an item of this base (it otherwise lands
## with no effect).
static func can_change(outcome_name: String, base: Item) -> bool:
	match outcome_name:
		"AddImplicit", "AddSecondImplicit":
			return not ImplicitPool.pool_for_type(base.get_item_type()).is_empty()
		"AddSocket", "RemoveSocket", "AddExtraSocket":
			return ItemRoller.get_socket_cap(base) > 0
		"Ascendant":
			return base is Weapon
		"Inversion":
			return SpecialCorruptionPool.defs_for(base).any(func(d: ModifierDef): return d.stat_key.contains("resistance"))
		"Transcendent":
			return not UniquePool.get_corrupted_uniques_for_type(base.equip_slot).is_empty()
	return true
