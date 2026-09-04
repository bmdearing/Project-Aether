extends RefCounted
class_name CorruptionSystem
## Patch v3.6 Section 3 - Shard of Tharsis. Replaces the flat 8-outcome
## weighted list CraftingSystem.corrupt() used before this (Section 24
## "Deferred Design" always flagged that as an invented placeholder
## pending a real pass) with the brief's 4-tier x named-outcome model.
## CraftingSystem.corrupt() is now a thin wrapper around corrupt() below,
## so CraftingScreen.gd's own Dictionary-based call site needs no changes.

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
	"Ascendant",  # Patch v3.6b
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
	# Section 20 Shard of Tharsis: "Every corruption attempt has an
	# independent % chance to retain craftable/corruptible status" - this
	# existing gate (Item.is_craftable, already wired into the Cube too)
	# stays alongside the brief's own tiered-outcome model rather than
	# being replaced by it; the brief's own corrupt() only checked
	# is_corrupted, not this separate, already-integrated restriction.
	# Referenced inline (not a top-level const) to avoid a circular
	# const-evaluation dependency with CraftingSystem.gd, which now calls
	# into this class too.
	if randf() >= CraftingSystem.RETAIN_CRAFTABLE_CHANCE:
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
