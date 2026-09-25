extends Resource
class_name StatSheet
## Patch v3.8: three stats (Prowess/Finesse/Resolve), replacing the
## original six (Vitality/Strength/Instinct/Arcane/Enigma/Intellect).
## No manual allocation on level up, but v4.7 adds a fixed +0.6 to each
## stat per level (level_bonus below). The raw fields below are the
## character's permanently-fixed baseline (player_baseline.tres, 10.0
## flat each - an invented vertical-slice testing value, no doc-sourced
## baseline exists); equipment_bonus and slate_bonus are what grow a stat
## past that - gear (EquipmentComponent.compute_stat_bonuses()) and
## placed Slates (FateBoard.compute_stat_bonuses()) respectively.
## Player.gd pushes a fresh total into each on every equip/unequip or
## Slate placement/removal. Neither is persisted separately - equipment_
## bonus is re-derived from GameState.equipment_refs (already saved) on
## every load; slate_bonus would need Fate Board LAYOUT to be saved to
## survive a reload the same way, which it isn't yet (README flagged
## gap) - so it's always just re-derived from whatever's currently
## placed, same as equipment_bonus, no separate save/load path needed
## for either.

@export var prowess: float = 0.0
@export var finesse: float = 0.0
@export var resolve: float = 0.0

@export var supercharged_stat: Constants.Stat = -1  # -1 = none declared
const SUPERCHARGE_MULTIPLIER := 1.25

## Constants.Stat -> float, recomputed whenever equipment changes (see
## Player.gd). Not @export'd/persisted - always re-derived from currently
## equipped gear, never stored independently (see header).
var equipment_bonus: Dictionary = {}

## Constants.Stat -> float, recomputed whenever the Fate Board changes
## (Player._apply_fate_board_bonuses()) - the Slate-system counterpart to
## equipment_bonus, summing every PLACED Slate's flat_<stat> modifiers
## (FateBoard.compute_stat_bonuses(), Section 10's "Main Stat"/"Random
## Stat" per-tile formula, 5+ tile Slates only). Not persisted separately,
## same reasoning as equipment_bonus - Fate Board layout itself isn't
## saved yet either (README flagged gap), so there's nothing to re-derive
## FROM across a reload regardless.
var slate_bonus: Dictionary = {}

## v4.7: flat bonus to all three stats from character level
## (GameState.get_level_stat_bonus()), pushed in by Player.gd. Separate from
## the baseline fields above, which are the shared player_baseline.tres
## values and must never be mutated.
var level_bonus: float = 0.0

## Mastery: DamageType -> float bonus (e.g. 0.5 for "+0.5 Cold Mastery").
## Never universal - keyed per tag per Section 10. Sourced entirely from
## placed Slates' "mastery" modifiers (FateBoard.compute_mastery_bonuses())
## - already consumed by DamageCalculator.calculate()'s mastery_bonus
## param via Weapon/Ability._base_hit(), which read this dict but nothing
## populated it before the Slate-system stat wiring pass.
var mastery_by_tag: Dictionary = {}

## Section 10/23: "Mastery... multiplying the per-tile chain bonus rate."
## DamageType -> float fraction (e.g. 0.2375 for +23.75%), the Chain Bonus
## System's own output (ChainCalculator.amplify_by_mastery()) after
## Mastery amplification - fed into Weapon/Ability._base_hit()'s
## increased_percents pool as real "increased <category> damage".
var chain_bonus_by_tag: Dictionary = {}

## Patch v3.2 "Revision - Resistance System": String key ("fire"/"cold"/
## "lightning"/"esoteric") -> float percent (e.g. 20.0 for 20%), summed
## from equipped gear's resistance affixes (EquipmentComponent.
## compute_resistance_bonuses()). Esoteric is unified across Aetheric/
## Entropic/Pale per the patch - one value covers all three. Physical
## (Kinetic/Piercing/Explosive) has no Resistance stat; Armor still
## covers it, unchanged by this patch.
var equipment_resistance: Dictionary = {}

func get_stat(stat: Constants.Stat) -> float:
	var base := 0.0
	match stat:
		Constants.Stat.PROWESS: base = prowess
		Constants.Stat.FINESSE: base = finesse
		Constants.Stat.RESOLVE: base = resolve
	base += level_bonus
	base += equipment_bonus.get(stat, 0.0)
	base += slate_bonus.get(stat, 0.0)
	if stat == supercharged_stat:
		base *= SUPERCHARGE_MULTIPLIER
	return base

func set_equipment_bonus(bonus: Dictionary) -> void:
	equipment_bonus = bonus

func set_slate_bonus(bonus: Dictionary) -> void:
	slate_bonus = bonus

## Derived values - callers should always go through these, never read
## prowess/finesse/resolve directly for a gameplay effect (matches the
## brief's own "call these, don't read raw stats" framing).
func get_max_life_bonus() -> float:
	return get_stat(Constants.Stat.PROWESS) * 2.0

func get_attack_power_from_stats() -> float:
	return get_stat(Constants.Stat.PROWESS) * 1.0

func get_evasion_from_stats() -> float:
	return get_stat(Constants.Stat.FINESSE) * 2.0

## Patch v4.4. Total Evasion Rating: gear (base + flat affixes, times
## increased%) plus Finesse's +2 per point, added after that multiplier.
## Fed to DamageCalculator.dodge_chance()/deflection_chance()/
## deflection_mitigation().
func get_total_evasion(equipment: EquipmentComponent) -> float:
	var gear_base := equipment.get_total_evasion() if equipment else 0.0
	return gear_base + get_evasion_from_stats()

## A flat, additive fraction (e.g. 0.10 for +10%) - added directly to a
## weapon/ability's own base_crit_chance, replacing the old multiplicative
## "x(1 + instinct*0.03)" formula (DamageCalculator.get_crit_chance()).
func get_crit_chance_from_stats() -> float:
	return get_stat(Constants.Stat.FINESSE) * 0.01

func get_spell_power_from_stats() -> float:
	return get_stat(Constants.Stat.RESOLVE) * 1.0

## A flat fraction (e.g. 0.05 for +5%) - applied as an INCREASED%
## multiplier on top of gear's own Ward value, not an additive flat bonus.
func get_ward_increased_from_stats() -> float:
	return get_stat(Constants.Stat.RESOLVE) * 0.005

func get_mastery(tag: Constants.DamageType) -> float:
	return mastery_by_tag.get(tag, 0.0)

func set_mastery(tag: Constants.DamageType, value: float) -> void:
	mastery_by_tag[tag] = value

func get_chain_bonus(tag: Constants.DamageType) -> float:
	return chain_bonus_by_tag.get(tag, 0.0)

func set_chain_bonus_by_tag(bonus: Dictionary) -> void:
	chain_bonus_by_tag = bonus

## Maps a DamageType to which of the 4 unified Resistance stats covers it
## (Patch v3.2) - null for Physical types, which Armor covers instead.
static func resistance_key_for(damage_type: Constants.DamageType):
	match damage_type:
		Constants.DamageType.FIRE: return "fire"
		Constants.DamageType.COLD: return "cold"
		Constants.DamageType.LIGHTNING: return "lightning"
		Constants.DamageType.AETHERIC, Constants.DamageType.ENTROPIC, Constants.DamageType.PALE: return "esoteric"
	return null

func get_resistance(damage_type: Constants.DamageType) -> float:
	var key = resistance_key_for(damage_type)
	return equipment_resistance.get(key, 0.0) if key else 0.0

func set_equipment_resistance(resistance: Dictionary) -> void:
	equipment_resistance = resistance

## Patch v3.5 Section 4. Generic "increased damage" affixes (no damage
## type) vs type-specific ones (Constants.DamageType -> float) - kept
## separate since a generic bonus should apply on top of every damage
## type, not get bucketed under one. Not consumed by DamageCalculator
## yet (no ItemRoller affix generation produces "increased_damage" affixes
## yet, that's a separate pass per the brief) - scaffolding only.
var increased_damage_generic: float = 0.0
var increased_damage_by_type: Dictionary = {}

## Single dispatch point for a rolled ItemAffix - routes to whichever
## bucket its stat_key means. Reuses EquipmentComponent's own stat_key
## tables rather than duplicating them, so there's one source of truth
## for what each key means.
func apply_affix(affix: ItemAffix) -> void:
	if EquipmentComponent.AFFIX_STAT_KEYS.has(affix.stat_key):
		var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[affix.stat_key]
		equipment_bonus[stat] = equipment_bonus.get(stat, 0.0) + affix.value
		return
	if EquipmentComponent.RESISTANCE_AFFIX_KEYS.has(affix.stat_key):
		var key: String = EquipmentComponent.RESISTANCE_AFFIX_KEYS[affix.stat_key]
		equipment_resistance[key] = equipment_resistance.get(key, 0.0) + affix.value
		return
	if affix.stat_key == "increased_damage":
		if affix.is_generic or affix.damage_type == -1:
			increased_damage_generic += affix.value
		else:
			var dt: Constants.DamageType = affix.damage_type
			increased_damage_by_type[dt] = increased_damage_by_type.get(dt, 0.0) + affix.value

## Recomputes increased_damage_generic/increased_damage_by_type from every
## equipped item's affixes - additive alongside set_equipment_bonus()/
## set_equipment_resistance() above (Player._on_equipment_changed() calls
## both), not a replacement for them.
func apply_equipment_affixes(items: Array[Item]) -> void:
	increased_damage_generic = 0.0
	increased_damage_by_type = {}
	for item in items:
		for affix in item.affixes:
			if affix.stat_key == "increased_damage":
				apply_affix(affix)

## Patch v3.7 Section 3. Additive pools, percentage totals (e.g. 20.0 for
## +20%) - not @export'd/persisted, same "always re-derived from currently
## equipped gear" footing as equipment_bonus/increased_damage_generic
## above. Recalculated on every stat refresh, never cached across one.
var cast_speed_bonus: float = 0.0
var cooldown_recovery_rate: float = 0.0

func get_effective_cast_time(base_cast_time: float) -> float:
	return base_cast_time / (1.0 + cast_speed_bonus / 100.0)

func get_effective_cooldown(base_cooldown: float) -> float:
	return base_cooldown / (1.0 + cooldown_recovery_rate / 100.0)

## Section 20 Slate affix: converts a fraction of the player's current
## Cast Speed into Cooldown Recovery Rate. conversion_percent is 15-25
## depending on the Slate's own tier. Recalculate on every stat refresh
## alongside cast_speed_bonus itself - not cached, so a change in Cast
## Speed from gear/Slates always propagates through immediately rather
## than freezing whatever conversion applied last time this ran.
func apply_cast_speed_to_cooldown_conversion(conversion_percent: float) -> void:
	var converted := cast_speed_bonus * (conversion_percent / 100.0)
	cooldown_recovery_rate += converted

## Patch v3.7 Section 1: the equipped Conduit's own spell power - the
## base floor Ability._base_hit() adds so spell damage doesn't collapse
## to single digits at low stats/grades (Weapon.base_damage's role, but
## for spells). Recomputed by Player._on_equipment_changed() from
## equipment.primary_weapon.get_spell_power() when it's a Conduit, 0.0
## otherwise - same "cache on StatSheet, no signature changes anywhere"
## pattern as equipment_bonus, so every existing Ability.predict_damage()/
## roll_damage() call site (15+ across PlayerAbilityCast.gd and several
## entities/effects/*_field/*.gd scripts) needed zero changes.
var conduit_spell_power: float = 0.0

func set_conduit_spell_power(value: float) -> void:
	conduit_spell_power = value

## Patch v3.8 Section 2. Player._apply_derived_stats() computes these from
## Finesse and stores them here (same "Player pushes a fresh total in"
## convention as equipment_bonus/conduit_spell_power) - Evasion has no
## mitigation formula anywhere in this project until Patch v4.4:
## stat_evasion_bonus is now the real total Evasion Rating (gear + Finesse,
## see get_total_evasion()), refreshed here for display; the hit roll in
## Player.take_damage() reads get_total_evasion() live. finesse_crit_bonus
## is real, read by Weapon/Ability._base_hit() as an additive fraction on
## top of base_crit_chance.
var stat_evasion_bonus: float = 0.0
var finesse_crit_bonus: float = 0.0

## Patch v3.8 Section 2 "Removed expressions": max_life/life_regen/
## max_mana/mana_regen/resilience/cast_speed used to derive from a
## character stat (Vitality/Intellect) - now purely gear-affix-driven.
## String stat_key -> summed float, recomputed by EquipmentComponent.
## compute_misc_bonuses() alongside equipment_bonus/equipment_resistance.
## attack_speed/move_speed/crit_damage/debuff_effectiveness/stamina are
## also in the pool but have no consumer yet (same "real affix, no
## formula to feed it into yet" gap flat_evasion/flat_resistance/flat_
## resilience/skill_cooldown_reduced already had before this patch).
var misc_bonus: Dictionary = {}

func get_misc_bonus(key: String) -> float:
	return misc_bonus.get(key, 0.0)

## Patch v3.8c bug fix: ItemRoller.AFFIX_POOL's "crit_damage" entry (+15-20%
## increased Critical Strike Damage) rolled onto gear but was never summed
## anywhere - EquipmentComponent.MISC_BONUS_KEYS didn't include it, so
## DamageCalculator.get_crit_damage_multiplier() was always called with its
## default 0.0 bonus regardless of equipped gear. misc_bonus stores the
## raw percent-unit affix total (same units the "+%d%%" affix description
## uses) - divided by 100 here so the caller gets a fraction to add
## directly to get_crit_damage_multiplier()'s base 1.5x.
## Patch v4.0 "Increased Critical Strike Bonus" (crit_damage_increased) is
## the same effect as the pre-existing v3.8c "crit_damage" key under a new
## name - summed together rather than treated as a second, separate bonus.
func get_crit_damage_bonus() -> float:
	return (get_misc_bonus("crit_damage") + get_misc_bonus("crit_damage_increased")) / 100.0

func set_misc_bonus(bonus: Dictionary) -> void:
	misc_bonus = bonus

## --- Patch v4.0 "Full Mod Pool Framework" -------------------------------
## Everything below reads from misc_bonus (see EquipmentComponent.
## MISC_BONUS_KEYS' own v4.0 comment for why no new dedicated fields were
## added for most of these) - grouped by the doc's own mod pool sections.

## Gear's own "increased Critical Strike Chance" - combined with Finesse's
## contribution the same multiplicative way (DamageCalculator.
## get_crit_chance()'s 2026-09-07 fix), not added on top separately.
func get_gear_crit_chance_bonus() -> float:
	return get_misc_bonus("crit_chance_increased") / 100.0

## Ailment Build Mod Pool - ailment_id matches StatusEffectComponent's own
## effect_id strings ("bleed"/"ignite"/"chill"/"electrocute"/"shock"/
## "aetherburn"/"unraveling"/"pallid").
func get_ailment_chance_bonus(ailment_id: String) -> float:
	return get_misc_bonus("ailment_chance_%s" % ailment_id) / 100.0

func get_ailment_damage_bonus(ailment_id: String) -> float:
	return get_misc_bonus("increased_ailment_damage_%s" % ailment_id) / 100.0

func get_ailment_duration_bonus(ailment_id: String) -> float:
	return get_misc_bonus("increased_ailment_duration_%s" % ailment_id) / 100.0

func get_dot_multiplier() -> float:
	return get_misc_bonus("dot_multiplier") / 100.0

func get_ailment_tick_rate_bonus() -> float:
	return get_misc_bonus("ailment_tick_rate") / 100.0

func get_ailment_ignore_chance() -> float:
	return get_misc_bonus("ailment_ignore_chance") / 100.0

## Offensive Mod Pool - Penetration. Elemental Penetration applies to all
## three Elemental types on top of that type's own specific Penetration
## (additive, per the doc: "Stacks additively with other Penetration
## sources"). Esoteric/Physical have no Penetration mods in this patch.
func get_penetration(damage_type: Constants.DamageType) -> float:
	match damage_type:
		Constants.DamageType.FIRE:
			return get_misc_bonus("fire_penetration") + get_misc_bonus("elemental_penetration")
		Constants.DamageType.COLD:
			return get_misc_bonus("cold_penetration") + get_misc_bonus("elemental_penetration")
		Constants.DamageType.LIGHTNING:
			return get_misc_bonus("lightning_penetration") + get_misc_bonus("elemental_penetration")
	return 0.0

func get_physical_shred() -> float:
	return get_misc_bonus("physical_shred") / 100.0

## Defensive Mod Pool - % Physical Damage taken as Elemental (Helmet/Body
## Armour/Amulet only per the doc, not enforced here - that's an item-
## slot-eligibility concern for the affix pool, this just reads whatever
## ended up in misc_bonus). Returns [[fraction, DamageType], ...] for
## each nonzero shift.
func get_phys_damage_shift() -> Array:
	var shifts := []
	if get_misc_bonus("phys_as_fire") > 0.0:
		shifts.append([get_misc_bonus("phys_as_fire") / 100.0, Constants.DamageType.FIRE])
	if get_misc_bonus("phys_as_cold") > 0.0:
		shifts.append([get_misc_bonus("phys_as_cold") / 100.0, Constants.DamageType.COLD])
	if get_misc_bonus("phys_as_lightning") > 0.0:
		shifts.append([get_misc_bonus("phys_as_lightning") / 100.0, Constants.DamageType.LIGHTNING])
	return shifts

func get_damage_from_mana_percent() -> float:
	return get_misc_bonus("damage_from_mana") / 100.0

func get_reduced_damage_taken(category: Constants.DamageCategory) -> float:
	match category:
		Constants.DamageCategory.PHYSICAL:
			return get_misc_bonus("reduced_physical_taken") / 100.0
		Constants.DamageCategory.ELEMENTAL:
			return get_misc_bonus("reduced_elemental_taken") / 100.0
		Constants.DamageCategory.ESOTERIC:
			return get_misc_bonus("reduced_esoteric_taken") / 100.0
	return 0.0

func get_ward_delay_reduction() -> float:
	return get_misc_bonus("ward_delay_reduction")

## Amulet Exclusive Mod Pool - Skill Level. Doc: "applies to active bar
## skills and Slate auto-casts only - not passives" (this project has no
## passive-Ability system for a gear-rolled Ability to accidentally match,
## so every Ability object already qualifies). is_spell is effectively
## always true for this project's Ability objects (they ARE this
## project's "spells" - weapon melee/ranged attacks are a separate,
## unrelated damage path with no Ability involved), so skill_level_spells/
## skill_level_spell_[type] apply unconditionally rather than needing a
## real is_spell flag Ability.gd doesn't have.
const _V40_DAMAGE_TYPE_KEYS := {
	Constants.DamageType.KINETIC: "kinetic", Constants.DamageType.PIERCING: "piercing",
	Constants.DamageType.EXPLOSIVE: "explosive", Constants.DamageType.FIRE: "fire",
	Constants.DamageType.COLD: "cold", Constants.DamageType.LIGHTNING: "lightning",
	Constants.DamageType.AETHERIC: "aetheric", Constants.DamageType.ENTROPIC: "entropic",
	Constants.DamageType.PALE: "pale",
}

func get_skill_level_bonus(damage_type: Constants.DamageType) -> int:
	var bonus: int = int(get_misc_bonus("skill_level_all")) + int(get_misc_bonus("skill_level_spells"))
	var type_key: String = _V40_DAMAGE_TYPE_KEYS.get(damage_type, "")
	if type_key != "":
		bonus += int(get_misc_bonus("skill_level_%s" % type_key))
		bonus += int(get_misc_bonus("skill_level_spell_%s" % type_key))
	return bonus

## Patch v4.3 - "of Steadying" shield affix ("block_chance_bonus", in whole
## percent points) as a fraction, added flat to the equipped shield's own
## block_chance in Player.try_block_melee_hit().
func get_block_chance_bonus() -> float:
	return get_misc_bonus("block_chance_bonus") / 100.0
