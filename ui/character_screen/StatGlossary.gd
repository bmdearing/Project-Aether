extends RefCounted
class_name StatGlossary
## Names, number formats and explanations for character stats, keyed by
## canonical stat key (StatKeys.canonical()). Names come from the affix
## pools' description templates ("+%d%% increased Attack Speed" ->
## "Increased Attack Speed"); explanations are written per stat or per stat
## family below.

const ELEMENT_NAMES := {"fire": "Fire", "cold": "Cold", "lightning": "Lightning", "esoteric": "Esoteric"}
const AILMENT_NAMES := {
	"aetherburn": "Aetherburn", "bleed": "Bleed", "chill": "Chill", "electrocute": "Electrocute",
	"ignite": "Ignite", "pallid": "Pallid", "shock": "Shock", "unraveling": "Unraveling",
}

## Keys whose pool template is missing or reads badly as a name.
const NAME_OVERRIDES := {
	"flat_strength": "Strength", "flat_agility": "Agility", "flat_intellect": "Intellect",
	"flat_life": "Life", "flat_mana": "Mana", "flat_armor": "Armour", "flat_evasion": "Evasion",
	"flat_ward": "Ward", "flat_resilience": "Resilience", "flat_aether": "Aether Capacity",
	"life_regen_flat": "Life Regeneration per second", "mana_regen": "Mana Regeneration per second",
	"ward_delay_reduction": "Faster Ward Recharge (seconds)", "retaliate_on_block": "Chance to Retaliate on Block",
	"hybrid_defense_life": "Hybrid Defence and Life", "crit_damage": "Increased Critical Strike Bonus",
	"increased_attack_damage": "Increased Weapon Damage",
	"amulet_increased_armor": "Increased Armour (Amulet)", "amulet_increased_evasion": "Increased Evasion (Amulet)", "amulet_increased_ward": "Increased Ward (Amulet)",
}

const FLAT_DECIMALS := {"mana_regen": 1, "ward_delay_reduction": 1, "life_regen_flat": 1}

## What each stat does. Families (ailments, skill levels, penetration...)
## are handled in explain().
const EXPLAIN := {
	"strength": "Strength: +1% increased Weapon Damage and +4 maximum Life per point. Weapons and Armour can need a minimum Strength to equip.",
	"agility": "Agility: +1% increased Attack Speed, +1% increased Evasion and +1% increased Critical Strike Chance per point. Some gear needs a minimum Agility.",
	"intellect": "Intellect: +1% increased Spell Damage, +0.5% increased Ward and +3 maximum Mana per point. Some gear needs a minimum Intellect.",
	"flat_life": "Added to maximum Life (with Strength's Life) before % increased Life multiplies the total.",
	"life_increased": "Multiplies maximum Life. All % increased Life you have is added together first.",
	"life_regen_flat": "Life recovered every second, added to your base regeneration. % increased Life Regeneration multiplies the total.",
	"life_regen_increased": "Multiplies all Life Regeneration: the base share of maximum Life plus any flat regeneration.",
	"flat_mana": "Added to maximum Mana (with Intellect's Mana) before % increased Mana multiplies it.",
	"mana_increased": "Multiplies maximum Mana.",
	"mana_regen": "Mana recovered every second, added to your base regeneration. % increased Mana Regeneration multiplies the total.",
	"mana_regen_increased": "Multiplies all Mana Regeneration.",
	"mana_cost_reduction": "Your skills and spells cost this much less Mana. Also lowers the drain of auras.",
	"damage_from_mana": "This share of damage you take is paid from Mana before Life. Once Mana runs out, Life takes it all.",
	"flat_armor": "Added to the Armour on your gear before % increased Armour multiplies it.",
	"increased_armor": "Multiplies your total Armour. Armour reduces Physical hits by Armour / (Armour + 30 x the hit), so it stops small hits better than big ones.",
	"flat_evasion": "Added to the Evasion on your gear before % increased Evasion (and Agility's) multiplies it.",
	"increased_evasion": "Multiplies your total Evasion. Evasion gives a chance to Dodge attack hits entirely (up to 65%) and to Deflect hits for reduced damage (up to 75%).",
	"flat_ward": "Added to your Ward pool before % increased Ward (and Intellect's) multiplies it. Ward absorbs damage of every type before Life and recharges after a short delay.",
	"increased_ward": "Multiplies your Ward pool.",
	"ward_recovery_increased": "Ward refills faster once it starts recharging.",
	"ward_delay_reduction": "Ward starts recharging this many seconds sooner after you take damage.",
	"ward_on_parry": "A successful Parry restores this share of your maximum Ward, on top of the base restore.",
	"flat_resilience": "Reduces damage over time you take (Ignite, Bleed and the like): Resilience / (Resilience + 2000), at most 50%.",
	"stamina": "Raises your Composure, the pool that blocking with a shield spends.",
	"block_chance_bonus": "Added to your shield's chance to Block a melee hit. Block chance has a hard cap.",
	"increased_block_chance": "Multiplies your total Block chance.",
	"armor_to_elemental": "This share of your Armour also reduces Fire, Cold and Lightning hits.",
	"evasion_to_spells": "This share of your Evasion's Dodge chance also works against spell hits (normally only attacks can be Dodged).",
	"reduced_physical_taken": "Physical damage you take is reduced by this much, on top of Armour.",
	"reduced_elemental_taken": "Fire, Cold and Lightning damage you take is reduced by this much, on top of Resistance.",
	"reduced_esoteric_taken": "Aetheric, Entropic and Pale damage you take is reduced by this much, on top of Resistance.",
	"ailment_ignore_chance": "Chance to ignore an Ailment that would be applied to you.",
	"parry_window_duration": "Your Parry window lasts longer, making Parries easier to time.",
	"all_elemental_resistance": "Added to Fire, Cold and Lightning Resistance.",
	"attack_speed": "Weapon attacks are faster. All % increased Attack Speed (with Agility's) is added together.",
	"cast_speed": "Spells with a cast time cast faster.",
	"move_speed": "You move faster, sprinting included.",
	"dash_speed": "Your dash covers ground faster.",
	"reload_speed": "Ranged weapons reload faster.",
	"cooldown_recovery_rate": "Skill cooldowns recover faster.",
	"skill_effect_duration": "Skill effects (fields, buffs, summons) last longer.",
	"increased_aoe_radius": "Area skills cover a larger area.",
	"reduced_projectile_speed": "Your projectiles fly slower. Slower projectiles stay longer in an area.",
	"projectile_speed": "Your projectiles fly faster.",
	"increased_attack_damage": "Multiplies weapon attack damage. All % increased damage that applies to a hit is added together, then multiplies it.",
	"increased_spell_damage": "Multiplies spell damage. All % increased damage that applies to a hit is added together, then multiplies it.",
	"increased_physical_damage": "Multiplies Kinetic, Piercing and Explosive damage.",
	"elemental_dmg_increased": "Multiplies Fire, Cold and Lightning damage.",
	"esoteric_dmg_increased": "Multiplies Aetheric, Entropic and Pale damage.",
	"increased_generic_damage": "Multiplies all damage you deal.",
	"increased_area_damage": "Multiplies damage dealt by area skills.",
	"increased_riposte_damage": "Multiplies the damage of your Ripostes (the counter after a successful Parry).",
	"increased_retaliation_damage": "Multiplies the damage of retaliation effects that hit back when you're struck or Block.",
	"retaliate_on_block": "Chance that blocking a hit strikes the attacker back with the blocked damage (scaled by increased Retaliation damage).",
	"crit_chance_increased": "Multiplies your base Critical Strike Chance (the weapon's or the spell's). It doesn't add percentage points.",
	"crit_damage_increased": "Multiplies the base Critical Strike Bonus of 150%: +50% here makes critical hits deal 225%.",
	"crit_damage": "Multiplies the base Critical Strike Bonus of 150%.",
	"riposte_crit_chance": "Ripostes are more likely to be critical hits.",
	"physical_shred": "Your hits treat the enemy's Armour as this much lower.",
	"dot_multiplier": "Adds to the multiplier on damage over time you deal (Ignite, Bleed, Aetherburn and the like). Separate from % increased damage, so it stacks multiplicatively with it.",
	"ailment_tick_rate": "Damaging Ailments deal their damage faster: the same total, sooner.",
	"debuff_effectiveness": "Debuffs you apply to enemies (slows, Shock, Chill and the like) are stronger.",
	"curse_effect": "Your curses (including curse auras) and debuffs (slows, Chill, Shock and the like) are stronger.",
	"damaging_ailment_chance": "Chance for your hits to inflict Bleed, Ignite or Aetherburn, whichever the hit's damage type causes.",
	"control_ailment_chance": "Chance for your hits to inflict Chill, Shock, Electrocute, Unraveling or Pallid, whichever the hit's damage type causes.",
	"ailment_duration": "Every Ailment you inflict lasts longer.",
	"control_ailment_effect": "Chill, Shock, Electrocute, Unraveling and Pallid you inflict are stronger.",
	"mana_on_kill": "Mana restored each time you kill an enemy.",
	"ward_percent_on_kill": "This share of your maximum Ward is restored each time you kill an enemy, on top of the base restore.",
	"mana_on_ailment": "Mana restored each time you inflict an Ailment.",
	"ward_percent_on_ailment": "This share of your maximum Ward is restored each time you inflict an Ailment.",
	"amulet_increased_armor": "Raises all of your Armour (from every item). Adds to the increased Armour on your armour pieces.",
	"amulet_increased_evasion": "Raises all of your Evasion (from every item). Adds to the increased Evasion on your armour pieces.",
	"amulet_increased_ward": "Raises all of your Ward (from every item). Adds to the increased Ward on your armour pieces.",
	"esoteric_penetration": "Your Aetheric, Entropic and Pale hits treat the enemy's Esoteric Resistance as this much lower.",
	"phys_as_elemental": "This share of Physical damage you take arrives split evenly as Fire, Cold and Lightning, so Resistances apply to it rather than Armour.",
	"hybrid_defense_life": "Adds this much Life, plus Armour (200% of it), Evasion (300%) or Ward (120%), whichever the item mainly has.",
	"additional_curses": "Enemies can hold this many more of your curses at once (normally one).",
	"minion_damage": "Your minions deal more damage.",
	"minion_attack_speed": "Your minions attack faster.",
	"minion_duration": "Your minions last longer.",
	"item_quantity": "More drop rolls from every kill, so more of everything drops. Magic Find adds to this.",
	"item_rarity": "Better odds that dropped items and jewels are Uncommon or Rare. Magic Find adds to this.",
	"magic_find": "Each point gives +0.5% Item Quantity and +2% Item Rarity.",
	"flat_aether": "Adds to the Aether you can spend placing Slates on the Fate Board.",
	"skill_level_all": "Raises the level of every active skill you use. Higher-level skills hit harder.",
	"skill_level_spells": "Raises the level of every spell you use. Higher-level spells hit harder.",
}

static var _names: Dictionary = {}
static var _templates: Dictionary = {}

static func _load_templates() -> void:
	if not _templates.is_empty():
		return
	for entry in ItemRoller.AFFIX_POOL:
		var key := StatKeys.canonical(String(entry.get("stat_key", "")))
		if key != "" and not _templates.has(key) and entry.has("desc"):
			_templates[key] = String(entry["desc"])

## The template an affix pool uses for `key`, or "".
static func template(key: String) -> String:
	_load_templates()
	return _templates.get(StatKeys.canonical(key), "")

## "Increased Attack Speed" for "attack_speed".
static func name_of(key: String) -> String:
	key = StatKeys.canonical(key)
	if _names.has(key):
		return _names[key]
	var label := ""
	if NAME_OVERRIDES.has(key):
		label = NAME_OVERRIDES[key]
	else:
		var t := template(key)
		label = _name_from_template(t) if t != "" else key.replace("_", " ").capitalize()
	_names[key] = label
	return label

static func _name_from_template(t: String) -> String:
	var s := t.replace("%%", "").replace("%d", "").replace("%.1f", "").replace("%s", "")
	s = s.strip_edges()
	for lead in ["+", "-", "to ", "Regenerate "]:
		if s.begins_with(lead):
			s = s.substr(lead.length()).strip_edges()
	s = s.replace("  ", " ")
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else t

## Percent stats show "%"; the rest are flat numbers.
static func is_percent(key: String) -> bool:
	key = StatKeys.canonical(key)
	if key in ["strength", "agility", "intellect"] or key.begins_with("flat_") or key.begins_with("skill_level_"):
		return false
	var t := template(key)
	if t != "":
		return t.contains("%%")
	for word in ["increased", "chance", "speed", "resistance", "reduced", "penetration", "multiplier", "quantity", "rarity", "effect", "duration", "shred"]:
		if key.contains(word):
			return true
	return false

## "+12.5%" / "+40" / "-10%".
static func format(key: String, value: float) -> String:
	var decimals: int = FLAT_DECIMALS.get(StatKeys.canonical(key), 1 if absf(value - roundf(value)) > 0.05 else 0)
	var number := ("%." + str(decimals) + "f") % absf(value)
	return ("-" if value < 0.0 else "+") + number + ("%" if is_percent(key) else "")

## What the stat is and how it works.
static func explain(key: String) -> String:
	key = StatKeys.canonical(key)
	if EXPLAIN.has(key):
		return EXPLAIN[key]
	for element in ELEMENT_NAMES:
		var element_name: String = ELEMENT_NAMES[element]
		var covers := "Aetheric, Entropic and Pale" if element == "esoteric" else element_name
		if key == element + "_resistance" or key == element + "_resistance_pct":
			return "Reduces %s damage you take by this percentage, up to your maximum %s Resistance (75%% base). Resistance over the maximum still counts against Resistance Shred, which is taken off first. Negative Resistance makes you take more." % [covers, element_name]
		if key == "max_" + element + "_resistance":
			return "Raises the most %s Resistance that counts (75%% base, never above %d%%)." % [element_name, int(DamageCalculator.RESISTANCE_CEILING)]
		if key == element + "_penetration":
			return "Your %s hits treat the enemy's %s Resistance as this much lower." % [covers, element_name]
		if key == "phys_as_" + element:
			return "This share of Physical damage you take arrives as %s instead, so %s Resistance applies to it rather than Armour." % [element_name, element_name]
	if key == "elemental_penetration":
		return "Your Fire, Cold and Lightning hits treat the enemy's Resistance as this much lower."
	for ailment in AILMENT_NAMES:
		var ailment_name: String = AILMENT_NAMES[ailment]
		if key == "ailment_chance_" + ailment:
			return "Chance for your hits to inflict %s." % ailment_name
		if key == "increased_ailment_damage_" + ailment:
			return "%s you inflict is stronger (more damage, or a stronger effect for non-damaging Ailments)." % ailment_name
		if key == "increased_ailment_duration_" + ailment:
			return "%s you inflict lasts longer." % ailment_name
	if key.begins_with("skill_level_spell_"):
		return "Raises the level of your %s spells. Higher-level spells hit harder." % key.trim_prefix("skill_level_spell_").capitalize()
	if key.begins_with("skill_level_"):
		return "Raises the level of your %s skills. Higher-level skills hit harder." % key.trim_prefix("skill_level_").capitalize()
	if key.ends_with("_dmg_increased") or (key.begins_with("increased_") and key.ends_with("_damage")):
		return "Multiplies %s. All %% increased damage that applies to a hit is added together, then multiplies it." % name_of(key).trim_prefix("Increased ").to_lower()
	if key.contains("increased"):
		return "Raises %s. Every %% increased source of the same stat is added together before it applies." % name_of(key).trim_prefix("Increased ").to_lower()
	if key.contains("reduced"):
		return "Lowers %s." % name_of(key).trim_prefix("Reduced ").to_lower()
	return name_of(key) + "."
