extends RefCounted
class_name CorruptionOutcome
## Shard of Tharsis corruption outcomes (CorruptionSystem picks them). Affix
## rolls use the real gear pool; implicits come from ImplicitPool,
## corrupted-strength modifiers from SpecialCorruptionPool. An implicit a
## Shard gives replaces the item's implicits (no cap, no stacking).

var success: bool = true
var reason: String = ""
var outcome_name: String = ""
var tier: int = 1
var description: String = ""

func _init(p_success: bool = true, p_reason: String = "") -> void:
	success = p_success
	reason = p_reason

func apply(_item: Item, _power_level: int) -> void:
	pass  # Overridden per outcome below.

## The item's implicits become just `implicit`.
static func set_implicit(item: Item, implicit: ItemAffix) -> void:
	implicit.is_implicit = true
	var kept: Array[ItemAffix] = []
	for a in item.affixes:
		if not a.is_implicit:
			kept.append(a)
	kept.append(implicit)
	item.affixes = kept

static func _named_implicit(id: String, display_name: String, stat_key: String, value: float, text: String) -> ItemAffix:
	var implicit := ItemAffix.new()
	implicit.affix_id = id
	implicit.display_name = display_name
	implicit.stat_key = stat_key
	implicit.value = value
	implicit.description = text
	implicit.is_implicit = true
	return implicit

## ---- Bricks ----------------------------------------------------------------

class Unmade extends CorruptionOutcome:
	## Strip everything into a max-item-level base (91, the catalog ceiling).
	func apply(item: Item, _power_level: int) -> void:
		item.affixes.clear()
		item.rarity = Constants.ItemRarity.COMMON
		item.item_level = min(item.item_level + 10, 91)
		item.quality = 0
		item.max_sockets = 0
		EventBus.item_unmade.emit(item)

class Hollow extends CorruptionOutcome:
	## Strip all explicits, add a devastating implicit.
	func apply(item: Item, _power_level: int) -> void:
		item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
		var hollow := CorruptionOutcome._named_implicit("corruption_hollow", "Hollowed", "hollow_damage_ward_drain", 25.0,
			"25% increased damage; your hits drain Ward equal to 10% of the damage dealt")
		hollow.value_min = 10.0  # 10% ward drain
		CorruptionOutcome.set_implicit(item, hollow)

## ---- Implicits ---------------------------------------------------------------

class AddImplicit extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var implicit := ImplicitPool.get_random_for(item)
		if implicit:
			CorruptionOutcome.set_implicit(item, implicit)

class ResistanceShredAura extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		CorruptionOutcome.set_implicit(item, CorruptionOutcome._named_implicit("corruption_resistance_shred_aura", "Resistance Shred Aura",
			"resistance_shred_aura", 8.0, "Nearby enemies have 8% reduced Resistances"))

class SkillNoCooldown extends CorruptionOutcome:
	## One random skill: no cooldown, +40% Mana cost.
	func apply(item: Item, _power_level: int) -> void:
		var slot := randi_range(1, 4)  # the cursed ability bar slot
		var implicit := CorruptionOutcome._named_implicit("corruption_skill_no_cooldown", "Cursed Skill", "skill_no_cooldown_extra_cost", 40.0,
			"Ability slot %d has no cooldown, but costs 40%% more Mana" % slot)
		implicit.value_max = slot
		CorruptionOutcome.set_implicit(item, implicit)

class MawTouched extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var implicit := CorruptionOutcome._named_implicit("corruption_maw_touched", "Maw-Touched", "skill_double_trigger_chance", 8.0,
			"Skills have an 8% chance to trigger twice; the second deals 50% damage")
		implicit.value_min = 50.0  # second trigger 50% damage
		CorruptionOutcome.set_implicit(item, implicit)

class PaleBranded extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		CorruptionOutcome.set_implicit(item, CorruptionOutcome._named_implicit("corruption_pale_branded", "Pale Branded",
			"no_ward_recovery_life_bonus", 35.0, "35% increased maximum Life; Ward cannot be recovered"))

class ResonantEcho extends CorruptionOutcome:
	## Duplicate one mod at 60% value as the implicit.
	func apply(item: Item, _power_level: int) -> void:
		var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
		if explicit.is_empty():
			return
		var source: ItemAffix = explicit[randi() % explicit.size()]
		var echo := source.duplicate() as ItemAffix
		echo.value = source.value * 0.6
		echo.display_name = source.display_name + " (Echo)"
		echo.affix_id = source.affix_id + "_echo"
		CorruptionOutcome.set_implicit(item, echo)

## ---- Good effects ------------------------------------------------------------

class AddSocket extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var max_s: int = ItemRoller.get_socket_cap(item)
		if item.max_sockets < max_s:
			item.max_sockets += 1
			EventBus.item_sockets_changed.emit(item)

class AddExtraSocket extends CorruptionOutcome:
	## Adds a socket beyond the base cap - up to +1 over.
	func apply(item: Item, _power_level: int) -> void:
		var max_s: int = ItemRoller.get_socket_cap(item)
		if max_s > 0 and item.max_sockets <= max_s:
			item.max_sockets += 1
			EventBus.item_sockets_changed.emit(item)

class TierUp extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var upgradeable := item.affixes.filter(
			func(a: ItemAffix): return not a.is_implicit and a.tier > 1 and ItemRoller.tier_range_for(a, a.tier - 1, item.equip_slot).x >= 0.0
		)
		if upgradeable.is_empty():
			return
		var target: ItemAffix = upgradeable[randi() % upgradeable.size()]
		ItemRoller.retier(target, target.tier - 1, item.equip_slot)

class AddSpecialAffix extends CorruptionOutcome:
	## A corrupted-strength modifier (SpecialCorruptionPool).
	func apply(item: Item, _power_level: int) -> void:
		if not item.can_add_prefix() and not item.can_add_suffix():
			return
		var special := SpecialCorruptionPool.get_random_for(item)
		if special:
			item.affixes.append(special)

## Tempered Limit: the item's quality cap rises by CORRUPT_QUALITY_CAP_BONUS
## (Orbs of Tempering still work on corrupted items).
class TemperedLimit extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item is Weapon or item is Armor:
			item.quality_cap_bonus += Constants.CORRUPT_QUALITY_CAP_BONUS

class Ascendant extends CorruptionOutcome:
	## Raises a Weapon's scaling_grade one step (S grade is the top).
	func apply(item: Item, _power_level: int) -> void:
		if not (item is Weapon):
			return
		var weapon := item as Weapon
		if weapon.scaling_grade <= 0:
			return
		weapon.scaling_grade -= 1
		EventBus.grade_ascended.emit(weapon, weapon.primary_scaling_stat, weapon.scaling_grade)

class Overcharged extends CorruptionOutcome:
	## Force all values to the top 20% of their tier range, delete one
	## random affix.
	func apply(item: Item, _power_level: int) -> void:
		var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
		for affix in explicit:
			if affix.value_max > affix.value_min:
				var top_20_min: float = lerp(affix.value_min, affix.value_max, 0.8)
				affix.value = randf_range(top_20_min, affix.value_max)
		if explicit.size() > 1:
			var to_remove: ItemAffix = explicit[randi() % explicit.size()]
			item.affixes.erase(to_remove)

class Transcendent extends CorruptionOutcome:
	## Reroll as a Corrupted Unique (UniquePool) - all existing mods lost.
	func apply(item: Item, _power_level: int) -> void:
		var corrupted_uniques := UniquePool.get_corrupted_uniques_for_type(item.equip_slot)
		if corrupted_uniques.is_empty():
			return
		var new_unique: Item = (corrupted_uniques[randi() % corrupted_uniques.size()] as Item).duplicate()
		item.affixes = new_unique.affixes
		item.rarity = Constants.ItemRarity.UNIQUE
		item.display_name = new_unique.display_name
		item.unique_id = new_unique.unique_id
		item.flavor_text = new_unique.flavor_text
		EventBus.item_transcended.emit(item)
