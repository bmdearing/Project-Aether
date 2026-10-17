extends VBoxContainer
class_name DefenceWiki
## Wiki page: how a hit on you is resolved and every defence that changes it,
## with the real formulas and caps (read from the constants the game uses)
## and worked examples, so defensive builds can be planned.

const WIDTH := 980.0
const LIST_HEIGHT := 590.0
const HEAD_COLOR := Color(0.6, 0.85, 0.75)
const ARMOUR_VALUES := [250.0, 750.0, 1500.0, 3000.0]
## Hits in level-1 units: [label, size].
const HIT_SIZES := [["Standard hit", 14.0], ["Elite hit", 36.0], ["Big slam", 100.0]]
const EVASION_VALUES := [750.0, 2250.0, 4500.0, 9000.0]

## Section titles in the order shown, for tests.
var shown: Array[String] = []

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("Your Life does not grow with level. Monsters hit %d%% harder per Area Level, so surviving late Figments comes from avoiding hits and mitigating the ones that land." % roundi((AreaLevel.DAMAGE_GROWTH - 1.0) * 100.0), 13, ModifierWiki.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for section in sections():
		shown.append(section["title"])
		list.add_child(_section(section))

static func _pct(f: float) -> String:
	return "%d%%" % roundi(f * 100.0)

## {"title", "text", "table" (optional rows of cells, first row the header)}.
static func sections() -> Array:
	var armour_table: Array = [["Armour"] + HIT_SIZES.map(func(h): return h[0])]
	for a in ARMOUR_VALUES:
		armour_table.append(["%d" % roundi(a)] + HIT_SIZES.map(func(h): return _pct(DamageCalculator.player_physical_mitigation(a, h[1], 1))))
	var parry := ParryRiposteHandler.new()
	var parry_window := parry.parry_window_seconds
	var riposte_invuln := parry.riposte_invuln_duration
	parry.free()
	var evasion_table: Array = [["Evasion", "Dodge", "Deflect chance", "Deflect reduces by"]]
	for e in EVASION_VALUES:
		evasion_table.append(["%d" % roundi(e), _pct(DamageCalculator.player_dodge_chance(e)), _pct(DamageCalculator.player_deflection_chance(e)), _pct(DamageCalculator.player_deflection_mitigation(e))])
	return [
		{"title": "Order of a hit", "text": "1. Parry (invulnerable while a riposte plays)  2. Raised shield  3. Held stance (Guard, Phalanx, Fortify)  4. Dodge, then Deflection (Evasion)  5. Armour for Physical, Resistance for Elemental and Esoteric  6. Reduced damage taken  7. Damage taken from Mana  8. Ward  9. Life. Damage over time (Ignite, Bleed...) skips blocking, stances and Evasion, and is reduced by Resilience. A hit that catches you in the air deals %d%% more, and jumping doesn't clear attacks marked on the ground (only a few low sweeps can be jumped)." % roundi((Player.AIRBORNE_DAMAGE_TAKEN - 1.0) * 100.0)},
		{"title": "Life", "text": "%d base, +4 per Strength, plus flat Life from gear, times increased Life. Every level gives %.2f to each attribute, so Strength is the only way levels add Life. You regenerate %.1f%% of maximum Life per second, plus gear regeneration." % [150, GameState.STAT_GAIN_PER_LEVEL, Player.BASE_REGEN_PERCENT]},
		{"title": "Armour", "text": "Reduces Physical hits (Kinetic, Piercing, Explosive...) by Armour / (Armour + %d x hit), capped at %s. The hit is measured against the attacker's level: a standard monster hit counts as about %d at every Area Level, so the table below holds anywhere. Monsters above your level and Figment Tiers hit harder than their level, and get through more. Strong against many small hits, weak against one big one. Bleed ignores Armour. \"% of Armour applies to Elemental\" uses the same curve against Elemental hits, on top of Resistance." % [roundi(DamageCalculator.PLAYER_ARMOUR_HIT_FACTOR), _pct(DamageCalculator.PLAYER_ARMOUR_CAP), roundi(DamageCalculator.STANDARD_RELATIVE_HIT)], "table": armour_table},
		{"title": "Evasion", "text": "Dodge: Evasion / (Evasion + %d), capped at %s. A dodged hit deals nothing. Only attacks (melee and projectiles) can be dodged, unless gear lets part of your Evasion apply to spell hits.\nDeflection: rolled if you don't dodge, against attacks and spells. Chance Evasion / (Evasion + %d), capped at %s; a deflected hit is reduced by Evasion / (Evasion + %d), capped at %s. Agility gives 1%% increased Evasion per point." % [roundi(DamageCalculator.PLAYER_DODGE_DIVISOR), _pct(DamageCalculator.DODGE_CHANCE_CAP), roundi(DamageCalculator.PLAYER_DEFLECTION_CHANCE_DIVISOR), _pct(DamageCalculator.DEFLECTION_CHANCE_CAP), roundi(DamageCalculator.PLAYER_DEFLECTION_MITIGATION_DIVISOR), _pct(DamageCalculator.DEFLECTION_MITIGATION_CAP)], "table": evasion_table},
		{"title": "Resistances", "text": "Fire, Cold, Lightning, and Esoteric (one resistance for Aetheric, Entropic and Pale). Each point removes 1%% of that damage, up to your maximum: %d%%, raised by \"+1%% to maximum\" jewels to at most %d%%. Pinnacles expect every maximum reached. Resistance above the maximum does nothing except soak Shred first. You have none without gear. Negative Resistance (from Shred) makes you take more, down to %d%%." % [roundi(StatSheet.BASE_MAX_RESISTANCE), roundi(DamageCalculator.RESISTANCE_CEILING), roundi(DamageCalculator.RESISTANCE_FLOOR)]},
		{"title": "Ward", "text": "A second pool from the Ward on your armour, with %s%% increased Ward per Intellect. It absorbs every damage type after mitigation, before Life. It regenerates %s of maximum per second once you go %.0fs without being hit (gear shortens the delay, to at least %.0fs). Kills restore %s and a successful parry %s." % [String.num(StatSheet.WARD_PER_INTELLECT * 100.0), _pct(WardComponent.REGEN_PERCENT_PER_SECOND), WardComponent.BASE_REGEN_DELAY_SECONDS, WardComponent.REGEN_DELAY_FLOOR_SECONDS, _pct(WardComponent.ON_KILL_RESTORE_PERCENT), _pct(WardComponent.PARRY_RESTORE_PERCENT)]},
		{"title": "Block", "text": "Passive: a shield's block chance negates enemy melee swings outright, capped at %s. Increased Block Chance multiplies the shield's chance.\nRaised shield (hold RMB with Raise Shield set in Behaviors): every hit from the front (%d degrees each side), spells included, is negated. It costs Composure: %d per hit plus up to %d more for a hit as big as your Life, and %d per second while held. Composure (%d) refills %.0fs after the last block. Running out breaks your guard and stuns you for %.0fs." % [_pct(Player.BLOCK_CHANCE_CAP), roundi(ShieldBlock.BLOCK_HALF_ANGLE), roundi(ShieldBlock.HIT_COST_FLAT), roundi(ShieldBlock.HIT_COST_PER_MAX_HEALTH), roundi(ShieldBlock.HOLD_DRAIN_PER_SEC), roundi(ShieldBlock.BASE_COMPOSURE), ShieldBlock.REGEN_DELAY, ShieldBlock.GUARD_BREAK_STUN]},
		{"title": "Parry and Riposte", "text": "Parrying (melee weapons only, not ranged weapons or conduits) raises your weapon or swings your shield over %.2fs, then holds a short window (%.2fs, widened by some stances and gear). A whiffed parry takes %.2fs to recover, during which you can't parry or attack; a landed one recovers instantly, so each blow of a combo can be parried. A melee swing or projectile that lands in the window is negated, damages the attacker's stance and restores Ward. Break an enemy's stance and your next melee hit is a Riposte, a visceral attack: you drive the weapon in and tear it out for %s of the swing's motion value, invulnerable throughout and for %.0fs after. A charged attack into the back of a rank-and-file enemy is a visceral too. Glints warn of a blow about to land: dodge or parry then." % [ParryRiposteHandler.PARRY_STARTUP, parry_window, ParryRiposteHandler.WHIFF_RECOVERY, _pct(ParryRiposteHandler.RIPOSTE_MOTION_VALUE_MULTIPLIER), riposte_invuln]},
		{"title": "Held stances", "text": "Some weapons' RMB stance defends while held. Guard (Greatsword) negates part of every melee hit. Fortify (Mace) roots you and reduces all damage. Phalanx (Spear) raises a frontal barrier that soaks hits until its pool (a share of your Life) runs out, refilling out of stance. Brace (Halberd) roots you and strikes and staggers enemies that close in front."},
		{"title": "Other mitigation", "text": "Reduced Physical / Elemental / Esoteric damage taken: a flat percent off after Armour or Resistance.\nPhysical damage taken as Elemental: part of a Physical hit arrives split evenly as Fire, Cold and Lightning, so Resistance handles it instead of Armour.\nDamage taken from Mana before Life: that share of each hit drains Mana first.\nResilience: reduces damage over time by Resilience / (Resilience + %d), capped at 50%%." % roundi(DamageCalculator.RESILIENCE_DIVISOR)},
		{"title": "Avoidance", "text": "Ranged attacks and spells can be outrun or sidestepped: tap Sprint to dash (%.1fs cooldown; hits pass through you for its first %.2fs), or slide by crouching while sprinting. Monsters past your XP zone (more than %d + %d%% of your level above you) also hit %s harder per level beyond it." % [Player.DASH_COOLDOWN, Player.DASH_IFRAMES, AreaLevel.XP_ZONE_BASE, roundi(AreaLevel.XP_ZONE_PER_LEVEL * 100.0), _pct(AreaLevel.GAP_DAMAGE_GROWTH - 1.0)]},
	]

func _section(section: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(HEAD_COLOR, 0.35), Color(0.05, 0.05, 0.08, 0.85), 1, 8.0))
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(ModifierWiki._text(section["title"], 17, HEAD_COLOR))
	var text := ModifierWiki._text(section["text"], 13, AetherStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	box.add_child(text)
	if section.has("table"):
		var grid := GridContainer.new()
		grid.columns = section["table"][0].size()
		grid.add_theme_constant_override("h_separation", 28)
		for r in section["table"].size():
			for cell in section["table"][r]:
				var label := ModifierWiki._text(cell, 13, AetherStyle.GOLD if r == 0 else AetherStyle.TEXT)
				label.custom_minimum_size = Vector2(110, 0)
				grid.add_child(label)
		box.add_child(grid)
	return panel
