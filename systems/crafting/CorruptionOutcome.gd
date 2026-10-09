extends RefCounted
class_name CorruptionOutcome
## Shard of Tharsis corruption outcomes, grouped Minor/Significant/Major/
## Extreme. Affix rolls use the real gear pool; implicits come from
## ImplicitPool, corrupted-strength modifiers from SpecialCorruptionPool.

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

## ---- Tier 1: Minor ---------------------------------------------------

class AddImplicit extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 3:
			return
		var implicit := ImplicitPool.get_random_for(item)
		if implicit:
			item.affixes.append(implicit)

class RerandomizeValues extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		for affix in item.affixes:
			if not affix.is_implicit and not affix.anchored and affix.value_max > affix.value_min:
				affix.value = randf_range(affix.value_min, affix.value_max)

class AddSocket extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var max_s: int = ItemRoller.get_socket_cap(item)
		if item.max_sockets < max_s:
			item.max_sockets += 1
			EventBus.item_sockets_changed.emit(item)

class RemoveSocket extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item.max_sockets > 0:
			item.max_sockets -= 1
			EventBus.item_sockets_changed.emit(item)

class TierUp extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var upgradeable := item.affixes.filter(
			func(a: ItemAffix): return not a.is_implicit and a.tier > 1 and ItemRoller.tier_range_for(a, a.tier - 1).x >= 0.0
		)
		if upgradeable.is_empty():
			return
		var target: ItemAffix = upgradeable[randi() % upgradeable.size()]
		ItemRoller.retier(target, target.tier - 1)

class TierDown extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		var downgradeable := item.affixes.filter(
			func(a: ItemAffix): return not a.is_implicit and a.tier > 0 and a.tier < ItemRoller.tier_count_for(a) and ItemRoller.tier_range_for(a, a.tier + 1).x >= 0.0
		)
		if downgradeable.is_empty():
			return
		var target: ItemAffix = downgradeable[randi() % downgradeable.size()]
		ItemRoller.retier(target, target.tier + 1)

## ---- Tier 2: Significant -----------------------------------------------

class AddSpecialAffix extends CorruptionOutcome:
	## A corrupted-strength modifier (SpecialCorruptionPool).
	func apply(item: Item, _power_level: int) -> void:
		if not item.can_add_prefix() and not item.can_add_suffix():
			return
		var special := SpecialCorruptionPool.get_random_for(item)
		if special:
			item.affixes.append(special)

class AddExtraSocket extends CorruptionOutcome:
	## Adds a socket beyond the base cap - up to +1 over.
	func apply(item: Item, _power_level: int) -> void:
		var max_s: int = ItemRoller.get_socket_cap(item)
		if item.max_sockets <= max_s:
			item.max_sockets += 1
			EventBus.item_sockets_changed.emit(item)

class ConvertAffix extends CorruptionOutcome:
	func apply(item: Item, power_level: int) -> void:
		var convertible := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
		if convertible.is_empty():
			return
		var target: ItemAffix = convertible[randi() % convertible.size()]
		var pool := ItemRoller._pool_for(item)
		var replacement := CraftingSystem._random_affix_for(item, pool, power_level)
		if replacement:
			item.affixes.erase(target)
			item.affixes.append(replacement)
			EventBus.item_stats_changed.emit(item)

class AddSecondImplicit extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 2:
			return
		var implicit := ImplicitPool.get_random_for(item)
		if implicit:
			item.affixes.append(implicit)

class ResistanceShredAura extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 3:
			return
		var aura := ItemAffix.new()
		aura.affix_id = "corruption_resistance_shred_aura"
		aura.display_name = "Resistance Shred Aura"
		aura.stat_key = "resistance_shred_aura"
		aura.value = 8.0  # 8% shred to all resistances
		aura.description = "Nearby enemies have 8% reduced Resistances"
		aura.is_implicit = true
		item.affixes.append(aura)

class SkillNoCooldown extends CorruptionOutcome:
	## One random skill: no cooldown, +40% Mana cost.
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 3:
			return
		var implicit := ItemAffix.new()
		implicit.affix_id = "corruption_skill_no_cooldown"
		implicit.display_name = "Cursed Skill"
		implicit.stat_key = "skill_no_cooldown_extra_cost"
		implicit.value = 40.0
		implicit.value_max = randi_range(1, 4)  # the cursed ability bar slot
		implicit.description = "Ability slot %d has no cooldown, but costs 40%% more Mana" % int(implicit.value_max)
		implicit.is_implicit = true
		item.affixes.append(implicit)

## ---- Tier 3: Major -----------------------------------------------------

class Veiltouch extends CorruptionOutcome:
	## Replace one explicit with a Slate-pool modifier - the only real
	## gear/Slate affix crossover in this project.
	func apply(item: Item, _power_level: int) -> void:
		if item.has_meta("veiltouch_applied"):
			return  # once per item
		var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
		if explicit.is_empty():
			return
		var target: ItemAffix = explicit[randi() % explicit.size()]
		var slate_mod := SlateAffixPool.get_random_affix("generic", item.item_level)
		if slate_mod == null:
			var tags := Constants.DAMAGE_TYPE_TAGS.keys()
			slate_mod = SlateAffixPool.get_random_affix(tags[randi() % tags.size()], item.item_level)
		if slate_mod:
			item.affixes.erase(target)
			var gear_copy := slate_mod.duplicate() as SlateAffix
			gear_copy.is_implicit = false
			item.affixes.append(gear_copy)
			item.set_meta("veiltouch_applied", true)

class Hollow extends CorruptionOutcome:
	## Strip all explicits, add a devastating implicit.
	func apply(item: Item, _power_level: int) -> void:
		item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
		var hollow_implicit := ItemAffix.new()
		hollow_implicit.affix_id = "corruption_hollow"
		hollow_implicit.display_name = "Hollowed"
		hollow_implicit.stat_key = "hollow_damage_ward_drain"
		hollow_implicit.value = 25.0       # 25% increased damage
		hollow_implicit.value_min = 10.0   # 10% ward drain
		hollow_implicit.description = "25% increased damage; your hits drain Ward equal to 10% of the damage dealt"
		hollow_implicit.is_implicit = true
		item.affixes.append(hollow_implicit)

class Inversion extends CorruptionOutcome:
	## Flip one resistance suffix to vulnerability, amplify all other
	## stats 20%.
	func apply(item: Item, _power_level: int) -> void:
		var resistances := item.affixes.filter(
			func(a: ItemAffix): return a.stat_key.contains("resistance") and not a.is_implicit
		)
		if resistances.is_empty():
			return
		var target: ItemAffix = resistances[randi() % resistances.size()]
		target.value = -abs(target.value)
		target.display_name = "Inverted " + target.display_name
		for affix in item.affixes:
			if affix != target and not affix.is_implicit:
				affix.value *= 1.2

class MawTouched extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 3:
			return
		var implicit := ItemAffix.new()
		implicit.affix_id = "corruption_maw_touched"
		implicit.display_name = "Maw-Touched"
		implicit.stat_key = "skill_double_trigger_chance"
		implicit.value = 8.0        # 8% chance to trigger twice
		implicit.value_min = 50.0   # second trigger 50% damage
		implicit.description = "Skills have an 8% chance to trigger twice; the second deals 50% damage"
		implicit.is_implicit = true
		item.affixes.append(implicit)

class PaleBranded extends CorruptionOutcome:
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 3:
			return
		var implicit := ItemAffix.new()
		implicit.affix_id = "corruption_pale_branded"
		implicit.display_name = "Pale Branded"
		implicit.stat_key = "no_ward_recovery_life_bonus"
		implicit.value = 35.0  # 35% max life increase
		implicit.description = "35% increased maximum Life; Ward cannot be recovered"
		implicit.is_implicit = true
		item.affixes.append(implicit)

class Ascendant extends CorruptionOutcome:
	## Raises a Weapon's scaling_grade one step. Non-weapons and S-grade
	## weapons are a logged no-op.
	func apply(item: Item, _power_level: int) -> void:
		if not (item is Weapon):
			print("Ascendant: near miss - %s has no scaling grade to ascend." % item.display_name)
			return
		var weapon := item as Weapon
		if weapon.scaling_grade <= 0:
			print("Ascendant: near miss - %s is already S grade." % weapon.display_name)
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

## ---- Tier 4: Extreme -----------------------------------------------------

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

class Unmade extends CorruptionOutcome:
	## Strip everything into a max-item-level base (91, the catalog ceiling).
	func apply(item: Item, _power_level: int) -> void:
		item.affixes.clear()
		item.rarity = Constants.ItemRarity.COMMON
		item.item_level = min(item.item_level + 10, 91)
		item.quality = 0
		item.max_sockets = 0
		EventBus.item_unmade.emit(item)

class ResonantEcho extends CorruptionOutcome:
	## Duplicate one mod at 60% value as an implicit.
	func apply(item: Item, _power_level: int) -> void:
		if item.get_implicit_count() >= 3:
			return
		var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
		if explicit.is_empty():
			return
		var source: ItemAffix = explicit[randi() % explicit.size()]
		var echo := source.duplicate() as ItemAffix
		echo.value = source.value * 0.6
		echo.is_implicit = true
		echo.display_name = source.display_name + " (Echo)"
		echo.affix_id = source.affix_id + "_echo"
		item.affixes.append(echo)

class AethericSurge extends CorruptionOutcome:
	func apply(item: Item, power_level: int) -> void:
		var esoteric := item.affixes.filter(
			func(a: ItemAffix): return not a.is_implicit and (
				a.damage_type == Constants.DamageType.AETHERIC or
				a.damage_type == Constants.DamageType.ENTROPIC or
				a.damage_type == Constants.DamageType.PALE
			)
		)
		if esoteric.is_empty():
			# No Esoteric mod - delete one random explicit, add an
			# Aetheric one instead.
			var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
			if explicit.size() > 0:
				item.affixes.erase(explicit[randi() % explicit.size()])
			var pool := ItemRoller._pool_for_brand_tag(item, "aetheric")
			var esoteric_mod := CraftingSystem._random_affix_for(item, pool, power_level)
			if esoteric_mod:
				item.affixes.append(esoteric_mod)
		else:
			var target: ItemAffix = esoteric[0]
			target.value *= 2.0
