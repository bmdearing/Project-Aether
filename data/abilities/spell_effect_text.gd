extends RefCounted
## What a spell does to enemies or to you, with the real numbers at the
## spell's level and the caster's gear, for the spell card (ItemCard).
## Every figure is read from the constants the spell code itself uses.


## Lines for ability, or [] when the damage line already says it all.
static func lines(ability: Ability, sheet: StatSheet, player: Player = null) -> Array[String]:
	var out: Array[String] = []
	var duration := ability.get_duration_multiplier(sheet)
	match ability.ability_id:
		"meager", "fracturing", "decompose", "elemental_fragility":
			var effect: String = PlayerAbilityCast.CURSE_EFFECTS[ability.ability_id]
			var s := PlayerAbilityCast.curse_strength(ability, sheet) * _effectiveness(sheet, effect)
			out.append("Curses every enemy in the area for %ss" % _num(PlayerAbilityCast.curse_duration(ability, sheet)))
			match effect:
				"meager":
					out.append("Cursed enemies deal %s less damage" % _pct(minf(StatusEffectComponent.MEAGER_DAMAGE_DEALT * s, 0.9)))
					out.append("Cursed enemies have %s less Evasion" % _pct(minf(StatusEffectComponent.MEAGER_EVASION * s, 1.0)))
				"fracturing":
					out.append("Cursed enemies have %s less Armour" % _pct(minf(StatusEffectComponent.FRACTURING_ARMOR * s, 1.0)))
					out.append("Cursed enemies take %s more Physical damage" % _pct(StatusEffectComponent.FRACTURING_PHYSICAL_TAKEN * s))
				"decompose":
					out.append(_resistance_line("Entropic", StatusEffectComponent.DECOMPOSE_RESISTANCE * s))
				"elemental_fragility":
					out.append(_resistance_line("Fire, Cold and Lightning", StatusEffectComponent.ELEMENTAL_FRAGILITY_RESISTANCE * s))
			out.append(_strength_line(ability, sheet, effect))
			if ability.has_twist("hex_aura"):
				out.append("Hex Aura: cast to switch on; enemies within %sm stay cursed at %s strength (+%s)" % [_num(ability.get_radius(sheet)), _pct(s * PlayerAbilityCast.HEX_AURA_STRENGTH), _pct(PlayerAbilityCast.HEX_AURA_STRENGTH - 1.0)])
				out.append(_drain_line(ability, sheet, player))
			var limit := StatusEffectComponent.CURSE_LIMIT + (maxi(int(sheet.get_misc_bonus("additional_curses")), 0) if sheet else 0)
			out.append("Enemies hold %d curse%s at a time; a new curse replaces the oldest" % [limit, "" if limit == 1 else "s"])
		"linger":
			var r := ability.predict_damage_range(sheet) if sheet else ability.get_base_damage_range()
			var secs := PlayerAbilityCast.LINGER_DURATION * duration
			out.append("Afflicts the enemy at your crosshair for %ss" % _num(secs))
			var base_secs := PlayerAbilityCast.LINGER_DURATION
			out.append("Deals %s Pale damage per second (%s in all)" % [_range(r.x / base_secs, r.y / base_secs), _range(r.x / base_secs * secs, r.y / base_secs * secs)])
			out.append("Boggled: %s slower movement and actions" % _pct(minf(StatusEffectComponent.LINGER_SLOW * _effectiveness(sheet, "linger"), 0.9)))
			out.append("If the enemy dies while afflicted, Linger moves to the %d nearest enemies within %sm" % [PlayerAbilityCast.linger_spread_count(ability), _num(ability.radius)])
		"pale_thread":
			var r := ability.predict_damage_range(sheet) if sheet else ability.get_base_damage_range()
			out.append("Links you to the enemy at your crosshair for %ss" % _num(PlayerAbilityCast.PALE_THREAD_DURATION * duration))
			out.append("Deals %s Pale damage per second (every %ss)" % [_range(r.x, r.y), _num(PlayerAbilityCast.PALE_THREAD_TICK)])
			var ward_line := "Restores %s of your maximum Ward per second" % _pct(PlayerAbilityCast.PALE_THREAD_WARD_PER_SEC)
			if player and player.ward and player.ward.max_ward > 0.0:
				ward_line += " (%s Ward/s)" % _num(player.ward.max_ward * PlayerAbilityCast.PALE_THREAD_WARD_PER_SEC)
			out.append(ward_line)
			out.append("Breaks if the enemy gets more than %sm away" % _num(PlayerAbilityCast.pale_thread_range(ability)))
		"death_shroud":
			var s := _effectiveness(sheet, "pallid") * PlayerAbilityCast.DEATH_SHROUD_STRENGTH
			out.append("Aura: cast to wear it, cast again to take it off (free)")
			out.append("Enemies within %sm are Pallid: they deal %s less damage" % [_num(ability.get_radius(sheet)), _pct(minf(StatusEffectComponent.PALLID_DAMAGE_REDUCTION * s, 0.9))])
			out.append(_drain_line(ability, sheet, player))
			out.append("Pallid fades %ss after they leave" % _num(PlayerAbilityCast.AURA_LINGER))
			if ability.has_twist("grave_chill"):
				out.append("Grave Chill: they're also %s slower" % _pct(StatusEffectComponent.SLOW_MOVE_SLOW_PERCENT))
		"battle_cry":
			var more := PlayerAbilityCast.BATTLE_CRY_MORE_DAMAGE + (ability.get_effective_level(sheet) - 1)
			out.append("You deal %s%% more damage for %ss" % [_num(more), _num(PlayerAbilityCast.BATTLE_CRY_DURATION * duration)])
			out.append("(%s%% at level 1, +1%% per level)" % _num(PlayerAbilityCast.BATTLE_CRY_MORE_DAMAGE))
		"intimidating_shout":
			out.append("Enemies within %sm take %s more damage of every type" % [_num(ability.get_radius(sheet)), _pct(StatusEffectComponent.INTIMIDATED_DAMAGE_TAKEN)])
			out.append("Lasts %ss" % _num(PlayerAbilityCast.INTIMIDATE_DURATION * duration))
		"seismic_cry":
			out.append("Damages and knocks back enemies within %sm" % _num(ability.get_radius(sheet)))
		"frost_armor":
			out.append("For %ss, an enemy melee hit on you sets off a frost burst" % _num(PlayerAbilityCast.FROST_ARMOR_DURATION * duration))
			out.append("Bursts hit everything within %sm, at most once every %ss" % [_num(ability.get_radius(sheet)), _num(PlayerAbilityCast.FROST_ARMOR_BURST_COOLDOWN)])
			out.append("Retaliation damage bonuses apply to the burst")
		"booming_blade":
			out.append("Cast to switch on, cast again to switch off (free)")
			var line := "Each trigger drains %s of its Mana cost" % _pct(PlayerAbilityCast.BOOMING_BLADE_TRIGGER_COST)
			if sheet:
				line += " (%s Mana)" % _num(ability.get_mana_cost(sheet) * PlayerAbilityCast.BOOMING_BLADE_TRIGGER_COST)
			out.append(line + "; it switches off when your Mana runs dry")
		"thunderstorm":
			out.append("Cast to switch on, cast again to switch off (free)")
			out.append("Every %ss, lightning strikes each enemy within %sm" % [_num(PlayerAbilityCast.STORM_INTERVAL), _num(ability.get_radius(sheet))])
			var storm := "Each round of strikes drains %s of its Mana cost" % _pct(PlayerAbilityCast.STORM_DRAIN)
			if sheet:
				storm += " (%s Mana)" % _num(ability.get_mana_cost(sheet) * PlayerAbilityCast.STORM_DRAIN)
			out.append(storm + "; it switches off when your Mana runs dry")
			out.append("Enemies within its radius are Drenched")
		"inner_power":
			out.append("Cast to switch on, cast again to switch off (free)")
			out.append("While on: your Mana doesn't regenerate, and you regenerate %s its regeneration as Life" % ("%sx" % _num(PlayerAbilityCast.FOCUSED_MIND_LIFE_SHARE if ability.has_twist("focused_mind") else PlayerAbilityCast.INNER_POWER_LIFE_SHARE)))
			out.append("While on: you deal %s more Aetheric damage" % _pct(StatSheet.INNER_POWER_AETHERIC_MORE * (2.0 if ability.has_twist("still_waters") else 1.0)))
			out.append("While it is on your bar, on or off, you deal no Physical damage")
		"charged_reflexes":
			out.append("Cast to switch on, cast again to switch off (free)")
			out.append("Ranged weapons attack %s faster and reload %s faster" % [_pct((player.ability_cast.charged_reflexes_fire_rate() if player else PlayerAbilityCast.CHARGED_REFLEXES_FIRE_RATE) - 1.0), _pct((player.ability_cast.charged_reflexes_reload() if player else PlayerAbilityCast.CHARGED_REFLEXES_RELOAD) - 1.0)])
			var shot := "Each shot drains %s of its Mana cost" % _pct(PlayerAbilityCast.CHARGED_REFLEXES_SHOT_DRAIN)
			if sheet:
				shot += " (%s Mana)" % _num(ability.get_mana_cost(sheet) * PlayerAbilityCast.CHARGED_REFLEXES_SHOT_DRAIN)
			out.append(shot + "; it switches off when your Mana runs dry")
		"manasaber":
			out.append("Costs %s of your maximum Mana" % _pct(PlayerAbilityCast.MANASABER_SHARE))
			out.append("Sweeps a %s-degree arc within %sm with your weapon's hit, as Aetheric damage" % [_num(PlayerAbilityCast.MANASABER_HALF_ANGLE * 2.0), _num(ability.get_radius(sheet))])
			out.append("1%% more damage for every %s Mana spent, up to %s%% more" % [_num(PlayerAbilityCast.AETHER_REBUKE_MANA_PER_MORE), _num(PlayerAbilityCast.AETHER_REBUKE_MAX_MORE)])
			if player and player.mana:
				var spent := PlayerAbilityCast.manasaber_cost(player.mana.max_mana)
				out.append("Now: %s Mana for %s more damage" % [_num(spent), _pct(PlayerAbilityCast.aether_rebuke_more(spent) - 1.0)])
		"puncture":
			out.append("Thrusts your weapon into the nearest enemy in front of you within %sm, as Piercing damage" % _num(ability.get_radius(sheet)))
			out.append("Punctured for %ss: Bleeding deals %s more damage to it" % [_num(PlayerAbilityCast.PUNCTURE_DURATION * duration), _pct(StatusEffectComponent.PUNCTURED_BLEED_TAKEN)])
		"invocation_of_arach":
			out.append("Marks the enemy at your crosshair for %ss" % _num(PlayerAbilityCast.ARACH_MARK_DURATION * duration))
			out.append("If it dies while marked, a spider rises to fight for you (at most %d at once)" % SpiderMinion.LIMIT)
			out.append("While on your bar, hits on bosses, Ascendants and marked enemies have a %s chance to bring a spider" % _pct(PlayerAbilityCast.ARACH_HIT_CHANCE))
			out.append("Spiders bite for this spell's Entropic damage and last %ss" % _num(SpiderMinion.BASE_DURATION * duration))
		"purge":
			out.append("Removes every status effect on you")
		"blizzard":
			out.append("Icicles fall on a random enemy in the area every %ss for %ss" % [_num(BlizzardField.ICICLE_INTERVAL), _num(BlizzardField.DURATION * duration)])
			out.append("Up to %d storms at once" % ability.get_limit(sheet))
		"triangulation", "dark_arts":
			var which := "Fire, Cold and Lightning Resistance" if ability.ability_id == "triangulation" else "Esoteric Resistance"
			out.append("Cast to switch on, cast again to switch off (free)")
			out.append("While on: +%s%% to %s" % [_num(PlayerAbilityCast.resist_spell_amount(ability, sheet)), which])
			var extra := ability.web_value(SkillWeb.MAX_RESISTANCE)
			if extra > 0.0:
				out.append("While on: +%s%% to maximum %s" % [_num(extra), which])
			out.append(_toggle_drain_line(ability, sheet, player))
		"enchantment":
			var r := PlayerAbilityCast.enchant_range(ability, sheet)
			var split := "Cold" if ability.has_twist("frost_enchant") else ("Lightning" if ability.has_twist("storm_enchant") else "")
			out.append("Cast to switch on, cast again to switch off (free)")
			if split == "":
				out.append("While on: your hits deal %s-%s added Fire damage" % [_num(r.x), _num(r.y)])
			else:
				out.append("While on: your hits deal %s-%s added damage, half Fire and half %s" % [_num(r.x), _num(r.y), split])
			out.append(_toggle_drain_line(ability, sheet, player))
		"black_hole":
			out.append("Swallows projectiles that fly into it, yours and enemies'; it fires them back out in a nova as it collapses, each dealing %s of a Black Hole hit" % _pct(PlayerAbilityCast.BLACK_HOLE_NOVA_DAMAGE))
		"blink":
			out.append("Teleports you %sm forward" % _num(PlayerAbilityCast.BLINK_DISTANCE * (PlayerAbilityCast.LONG_STEP if ability.has_twist("long_step") else 1.0)))
	for effect_id in ability.applies_status_effects:
		var text := status_text(effect_id.trim_prefix("enhanced:"), sheet)
		if text != "":
			out.append(text)
	if ability.is_skill:
		var needs := "any melee weapon" if ability.skill_weapon_types.is_empty() else ", ".join(ability.skill_weapon_types)
		var skill := "Skill: deals your weapon's hit at %s of its motion value (+%s per level), and takes %s of its attack time; needs %s" % [_pct(ability.skill_motion_value), _pct(Ability.SKILL_MOTION_PER_LEVEL), _pct(ability.attack_time_multiplier), needs]
		if player and player.ability_cast and player.get_active_weapon():
			skill += " (now %ss)" % _num(player.ability_cast.skill_swing_time(ability))
		out.insert(0, skill)
	return out

## One status: what it does and for how long, scaled by the caster's
## effectiveness and duration gear.
static func status_text(effect_id: String, sheet: StatSheet) -> String:
	var s := _effectiveness(sheet, effect_id)
	var d := 1.0 + (sheet.get_ailment_duration_bonus(StatusEffectComponent.CHANCE_STAT_ALIAS.get(effect_id, effect_id)) if sheet else 0.0)
	match effect_id:
		"chill":
			return "Chill: %s slower for %ss; %d Chills Freeze for %ss" % [_pct(minf(StatusEffectComponent.CHILL_MOVE_SLOW_PERCENT * s, 0.9)), _num(StatusEffectComponent.CHILL_DURATION * d), StatusEffectComponent.CHILL_STACKS_TO_FREEZE, _num(StatusEffectComponent.FREEZE_DURATION * d)]
		"freeze":
			return "Freeze: can't move or act for %ss" % _num(StatusEffectComponent.FREEZE_DURATION * d)
		"shock":
			return "Shock: %s more damage taken for %ss" % [_pct(StatusEffectComponent.SHOCK_DAMAGE_INCREASE * s), _num(StatusEffectComponent.SHOCK_DURATION * d)]
		"electrocute":
			return "Electrocute: stunned for %ss" % _num(StatusEffectComponent.ELECTROCUTE_DURATION * d)
		"unraveling":
			return "Unraveling: %s more Esoteric damage taken for %ss" % [_pct(StatusEffectComponent.UNRAVELING_DAMAGE_TAKEN_PERCENT * s), _num(StatusEffectComponent.UNRAVELING_DURATION * d)]
		"pallid":
			return "Pallid: deals %s less damage for %ss" % [_pct(minf(StatusEffectComponent.PALLID_DAMAGE_REDUCTION * s, 0.9)), _num(StatusEffectComponent.PALLID_DURATION * d)]
		"ignite":
			return "Ignite: burns for %s of the hit as Fire over %ss" % [_pct(StatusEffectComponent.IGNITE_DAMAGE_PERCENT * s * _dot_bonus(sheet, "ignite")), _num(StatusEffectComponent.IGNITE_DURATION * d)]
		"bleed":
			return "Bleed: %s of the hit as Physical over %ss, ignoring Armour" % [_pct(StatusEffectComponent.BLEED_DAMAGE_PERCENT * s * _dot_bonus(sheet, "bleed")), _num(StatusEffectComponent.BLEED_DURATION * d)]
		"aetherburn":
			return "Aetherburn: %s of the hit as Aetheric over %ss, burning as much Ward" % [_pct(StatusEffectComponent.AETHERBURN_DAMAGE_PERCENT * s * _dot_bonus(sheet, "aetherburn")), _num(StatusEffectComponent.AETHERBURN_DURATION * d)]
		"scorch":
			return "Scorch: %s more Fire damage taken per stack (up to %d) for %ss" % [_pct(StatusEffectComponent.SCORCH_DAMAGE_PER_STACK), StatusEffectComponent.SCORCH_MAX_STACKS, _num(StatusEffectComponent.SCORCH_DURATION * d)]
		"slow":
			return "Slow: %s slower" % _pct(StatusEffectComponent.SLOW_MOVE_SLOW_PERCENT)
	return ""

## "Drains 6% of your maximum Mana per second (6/s)"; switches off when Mana runs dry.
static func _toggle_drain_line(ability: Ability, sheet: StatSheet, player: Player) -> String:
	var text := "Drains %s of your maximum Mana per second" % _pct(PlayerAbilityCast.TOGGLE_SPELL_DRAIN * ability.get_mana_cost_multiplier(sheet))
	if player and player.mana:
		text += " (%s/s)" % _num(PlayerAbilityCast.toggle_spell_drain_per_second(ability, player.mana.max_mana, sheet))
	return text + "; it switches off when your Mana runs dry"

static func _drain_line(ability: Ability, sheet: StatSheet, player: Player) -> String:
	var share := PlayerAbilityCast.DEATH_SHROUD_DRAIN if ability.ability_id == "death_shroud" else PlayerAbilityCast.HEX_AURA_DRAIN
	var text := "Drains %s of your maximum Mana per second" % _pct(share * ability.get_mana_cost_multiplier(sheet))
	if player and player.mana:
		text += " (%s/s)" % _num(PlayerAbilityCast.aura_drain_per_second(ability, player.mana.max_mana, sheet))
	return text + " while on; it switches off when your Mana runs dry"

## StatusEffectComponent.effect_multiplier() for a stat sheet instead of a Player.
static func _effectiveness(sheet: StatSheet, effect_id: String) -> float:
	if sheet == null:
		return 1.0
	var percent := sheet.get_misc_bonus(effect_id + "_effect")
	if StatusEffectComponent.is_ailment(effect_id):
		percent += sheet.get_misc_bonus("ailment_effectiveness")
	if StatusEffectComponent.DEBUFF_IDS.has(effect_id):
		percent += sheet.get_misc_bonus("debuff_effectiveness")
	if StatusEffectComponent.CURSE_IDS.has(effect_id):
		percent += sheet.get_misc_bonus("curse_effect")
	return 1.0 + percent / 100.0

static func _dot_bonus(sheet: StatSheet, effect_id: String) -> float:
	if sheet == null:
		return 1.0
	return (1.0 + sheet.get_ailment_damage_bonus(effect_id)) * (1.0 + sheet.get_dot_multiplier())

## Enemies have no resistance of their own, so lowering it by N adds N% to
## the damage they take (within the resistance floor).
static func _resistance_line(types: String, shred: float) -> String:
	var taken := -DamageCalculator.resistance_mitigation(-shred)
	return "Cursed enemies have -%s%% %s Resistance (they take %s more %s damage)" % [_num(shred), types, _pct(taken), types]

static func _strength_line(ability: Ability, sheet: StatSheet, effect_id: String) -> String:
	var level_bonus := PlayerAbilityCast.curse_strength(ability, sheet) - 1.0
	var gear := _effectiveness(sheet, effect_id) - 1.0
	var text := "Curse strength: %s (+%s per level above 1)" % [_pct(1.0 + level_bonus), _pct(PlayerAbilityCast.CURSE_STRENGTH_PER_LEVEL)]
	var web := ability.web_value(SkillWeb.CURSE_STRENGTH)
	if web > 0.0:
		text += ", +%s%% from Hex Potency" % _num(web)
	if gear > 0.0:
		text += ", %s from Curse Effect and Debuff Effectiveness" % ("+" + _pct(gear))
	return text

static func _pct(fraction: float) -> String:
	return "%s%%" % _num(fraction * 100.0)

static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	var text := "%.2f" % v
	return text.rstrip("0").rstrip(".")

## "5-8", or "5" when both ends match.
static func _range(lo: float, hi: float) -> String:
	return _num(lo) if _num(lo) == _num(hi) else "%s-%s" % [_num(lo), _num(hi)]
