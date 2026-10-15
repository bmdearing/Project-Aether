extends RefCounted
class_name CorruptionSystem
## Shard of Tharsis: four equal results (TIER_WEIGHTS) - nothing happens,
## the item is bricked, it gains an implicit or a good effect, or it gains
## both. A result only picks outcomes that actually change this item
## (tried in random order until one does), so a Shard never lands as a
## silent no-op unless it rolled "nothing". CraftingSystem.corrupt() wraps
## corrupt() below.

enum OutcomeTier { NOTHING = 1, BRICKED = 2, BLESSED = 3, EXALTED = 4 }

const TIER_WEIGHTS := {
	OutcomeTier.NOTHING: 25,
	OutcomeTier.BRICKED: 25,
	OutcomeTier.BLESSED: 25,  # an implicit or a good effect
	OutcomeTier.EXALTED: 25,  # an implicit and a good effect
}
const TIER_NAMES := {1: "No Change", 2: "Bricked", 3: "Blessed", 4: "Exalted"}

const _BRICKS := ["Unmade", "Hollow"]
const _IMPLICITS := ["AddImplicit", "ResistanceShredAura", "MawTouched", "PaleBranded", "SkillNoCooldown", "ResonantEcho"]
const _GOOD := ["AddSocket", "AddExtraSocket", "TierUp", "AddSpecialAffix", "TemperedLimit", "Honed", "Overcharged", "Transcendent"]

static func corrupt(item: Item, power_level: int = 1) -> CorruptionOutcome:
	if item == null:
		return CorruptionOutcome.new(false, "Nothing to corrupt.")
	if item.is_corrupted:
		return CorruptionOutcome.new(false, "Item is already corrupted")
	if not item.is_craftable:
		return CorruptionOutcome.new(false, "This item was already corrupted beyond further chaos.")

	var tier := _roll_tier()
	var outcome := _apply_tier(tier, item, power_level)
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
	return OutcomeTier.NOTHING

static func _apply_tier(tier: int, item: Item, power_level: int) -> CorruptionOutcome:
	var applied: Array[String] = []
	match tier:
		OutcomeTier.BRICKED:
			_apply_first_that_changes(_BRICKS, item, power_level, applied)
		OutcomeTier.BLESSED:
			_apply_first_that_changes(_IMPLICITS + _GOOD, item, power_level, applied)
		OutcomeTier.EXALTED:
			# The effect first: Transcendent replaces every modifier, so an
			# implicit added before it would be lost.
			_apply_first_that_changes(_GOOD, item, power_level, applied)
			_apply_first_that_changes(_IMPLICITS, item, power_level, applied)
	var labels := PackedStringArray()
	for n in applied:
		labels.append(n.capitalize())
	var outcome := CorruptionOutcome.new()
	outcome.tier = tier
	outcome.outcome_name = " + ".join(labels) if not labels.is_empty() else "No Change"
	return outcome

## Tries `names` in random order and keeps the first that changes the item.
static func _apply_first_that_changes(names: Array, item: Item, power_level: int, applied: Array[String]) -> void:
	var order := names.duplicate()
	order.shuffle()
	for outcome_name in order:
		var before := ItemSerializer.to_dict(item)
		var outcome := _instantiate(outcome_name)
		outcome.apply(item, power_level)
		if ItemSerializer.to_dict(item) != before:
			applied.append(outcome_name)
			return

static func _instantiate(outcome_name: String) -> CorruptionOutcome:
	match outcome_name:
		"AddImplicit": return CorruptionOutcome.AddImplicit.new()
		"AddSocket": return CorruptionOutcome.AddSocket.new()
		"TierUp": return CorruptionOutcome.TierUp.new()
		"AddSpecialAffix": return CorruptionOutcome.AddSpecialAffix.new()
		"AddExtraSocket": return CorruptionOutcome.AddExtraSocket.new()
		"ResistanceShredAura": return CorruptionOutcome.ResistanceShredAura.new()
		"SkillNoCooldown": return CorruptionOutcome.SkillNoCooldown.new()
		"Hollow": return CorruptionOutcome.Hollow.new()
		"MawTouched": return CorruptionOutcome.MawTouched.new()
		"PaleBranded": return CorruptionOutcome.PaleBranded.new()
		"Overcharged": return CorruptionOutcome.Overcharged.new()
		"Honed": return CorruptionOutcome.Honed.new()
		"Transcendent": return CorruptionOutcome.Transcendent.new()
		"Unmade": return CorruptionOutcome.Unmade.new()
		"ResonantEcho": return CorruptionOutcome.ResonantEcho.new()
		"TemperedLimit": return CorruptionOutcome.TemperedLimit.new()
	return CorruptionOutcome.new()

## What each outcome does, for the Wiki.
const DESCRIPTIONS := {
	"NoChange": "Nothing happens; the item is still corrupted.",
	"Unmade": "Strips everything; the base gains 10 item levels (up to 91).",
	"Hollow": "Removes every explicit. Implicit: 25% increased damage, your hits drain Ward equal to 10% of their damage.",
	"AddImplicit": "Adds an implicit from the item type's implicit pool (up to 3).",
	"ResistanceShredAura": "Implicit: nearby enemies have 8% reduced Resistances.",
	"MawTouched": "Implicit: skills have an 8% chance to trigger twice (the second at 50% damage).",
	"PaleBranded": "Implicit: 35% increased maximum Life, but Ward cannot be recovered.",
	"SkillNoCooldown": "Implicit: one ability bar slot has no cooldown but costs 40% more Mana.",
	"ResonantEcho": "Copies one modifier as an implicit at 60% strength.",
	"AddSocket": "Adds a socket, up to the item's maximum.",
	"AddExtraSocket": "Adds a socket beyond the maximum (up to +1).",
	"TierUp": "One modifier moves up a tier (Tier 3 becomes Tier 2).",
	"AddSpecialAffix": "Adds a corrupted modifier: one of the item's own at 130% of its Tier 1 maximum.",
	"TemperedLimit": "The item's maximum quality rises by 15% (Orbs of Tempering still work on corrupted items).",
	"Honed": "The weapon's base damage rises by 20%.",
	"Overcharged": "Every modifier rolls in the top 20% of its tier; one modifier is removed.",
	"Transcendent": "The item becomes a corrupted-only Unique; every modifier is lost.",
	"ImplicitAndEffect": "One of the Blessed implicits and one of the Blessed good effects, both.",
}

## Outcome names by tier (1-4), as the Wiki lists them. Exalted is one
## combined entry.
static func outcomes_in_tier(tier: int) -> Array:
	match tier:
		OutcomeTier.NOTHING: return ["NoChange"]
		OutcomeTier.BRICKED: return _BRICKS
		OutcomeTier.BLESSED: return _IMPLICITS + _GOOD
		OutcomeTier.EXALTED: return ["ImplicitAndEffect"]
	return []

## Chance a Shard of Tharsis rolls this outcome, before outcomes that
## can't change the item hand their share to the rest of their tier.
static func outcome_chance(outcome_name: String) -> float:
	var total := 0.0
	for w in TIER_WEIGHTS.values():
		total += w
	for tier in TIER_WEIGHTS:
		var names := outcomes_in_tier(tier)
		if names.has(outcome_name):
			return TIER_WEIGHTS[tier] / total / names.size()
	return 0.0

## Whether an outcome can change an item of this base.
static func can_change(outcome_name: String, base: Item) -> bool:
	match outcome_name:
		"AddImplicit":
			return not ImplicitPool.pool_for_type(base.get_item_type()).is_empty()
		"TemperedLimit":
			return base is Weapon or base is Armor
		"AddSocket", "AddExtraSocket":
			return ItemRoller.get_socket_cap(base) > 0
		"Honed":
			return base is Weapon
		"Transcendent":
			return not UniquePool.get_corrupted_uniques_for_type(base.equip_slot).is_empty()
	return true
