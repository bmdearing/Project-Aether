extends RefCounted
class_name StatSummaryBuilder
## Stat lines shared by CharacterScreen and InventoryScreen's stats column.

## Hover text per stat row, keyed by the row's label (Patch v4.3). Rows not
## listed here get no tooltip.
const STAT_TOOLTIPS := {
	"Strength": "Strength: +1% increased Weapon Damage and +4 maximum Life per point. Gear can need a minimum Strength.",
	"Weapon Damage": "% increased weapon damage from Strength (1% per point), added to your other % increased damage.",
	"Main Hand Damage": "The damage range one hit with your main hand weapon deals before the enemy's defences, with your current stats.",
	"Main Hand Crit": "Chance for a main hand hit to be critical, and how hard critical hits land (150% base). % increased Critical Strike Chance multiplies the weapon's own base chance.",
	"Offhand Damage": "The damage range one hit with your offhand weapon deals before the enemy's defences, with your current stats.",
	"Offhand Crit": "Chance for an offhand hit to be critical, and how hard critical hits land (150% base).",
	"Agility": "Agility: +1% increased Attack Speed, Evasion and Critical Strike Chance per point. Gear can need a minimum Agility.",
	# "Evasion Rating" is built live in _evasion_tooltip() - it shows the derived percentages.
	"Max Health": "Your Life: Strength's +4 per point plus flat Life, multiplied by % increased Life. You die when it runs out. Ward takes damage before it.",
	"Life Regen": "Life recovered per second: 0.5% of maximum Life plus flat regeneration, multiplied by % increased Life Regeneration.",
	"Max Ward": "Absorbs damage of every type before Life, and refills after a short time without being hit. Comes from Ward on gear, multiplied by % increased Ward and Intellect (0.5% per point).",
	"Armor": "Reduces Physical hits by Armour / (Armour + 30 x the hit), so it stops small hits better than big ones.",
	"Intellect": "Intellect: +1% increased Spell Damage, +0.5% increased Ward and +3 Mana per point. Gear can need a minimum Intellect.",
	"Spell Damage": "% increased spell damage from Intellect (1% per point), added to your other % increased spell damage.",
	"Max Mana": "Spent on spells and auras. Intellect gives +3 per point.",
	"Mana Regen": "Mana recovered per second.",
	"Move Speed": "Walking speed in metres per second, with % increased Move Speed applied.",
	"Sprint Speed": "Sprinting speed in metres per second, with % increased Move Speed applied.",
	"Action Speed": "How fast you attack and cast compared with normal (100%).",
	"Item Quantity": "More drop rolls from every kill, so more of everything drops. Includes Magic Find.",
	"Item Rarity": "Better odds that dropped items and jewels are Uncommon or Rare. Includes Magic Find.",
	"Magic Find": "Each point gives +0.5% Item Quantity and +2% Item Rarity.",
}

## Rows that share an explanation with a stat key (resistances, Chain Bonus).
static func _tooltip_for(label_text: String) -> String:
	if STAT_TOOLTIPS.has(label_text):
		return STAT_TOOLTIPS[label_text]
	if label_text.ends_with(" Resistance"):
		return StatGlossary.explain(label_text.trim_suffix(" Resistance").to_lower() + "_resistance")
	if label_text.ends_with(" Chain Bonus"):
		return "% increased damage of this type from chains of linked Slates on the Fate Board."
	if label_text.ends_with(" Mastery"):
		return "%% more damage of this type: each Slate tile of the type gives %.1f%%, multiplied by (1 + its chain's bonus)." % (Constants.MASTERY_PER_TILE * 100.0)
	return ""

static func refresh(offense_list: VBoxContainer, defense_list: VBoxContainer, misc_list: VBoxContainer, player: Player) -> void:
	_clear(offense_list)
	_clear(defense_list)
	_clear(misc_list)
	if player == null:
		return
	var stats: StatSheet = player.stat_sheet

	_add(offense_list, "Strength", "%.1f" % stats.get_stat(Constants.Stat.STRENGTH))
	_add(offense_list, "Weapon Damage", "+%.0f%%" % (stats.get_strength_weapon_multiplier() * 100.0))
	_add(offense_list, "Main Hand Damage", _predict_damage(player, Constants.EquipmentSlot.PRIMARY_WEAPON))
	_add(offense_list, "Main Hand Crit", _crit_summary(player, Constants.EquipmentSlot.PRIMARY_WEAPON))
	var offhand := _weapon_in(player, Constants.EquipmentSlot.OFFHAND)
	if offhand == null or offhand.can_attack():  # an offhand Conduit never hits
		_add(offense_list, "Offhand Damage", _predict_damage(player, Constants.EquipmentSlot.OFFHAND))
		_add(offense_list, "Offhand Crit", _crit_summary(player, Constants.EquipmentSlot.OFFHAND))

	_add(defense_list, "Agility", "%.1f" % stats.get_stat(Constants.Stat.AGILITY))
	var evasion := stats.get_total_evasion(player.equipment)
	_add(defense_list, "Evasion Rating", "%.1f" % evasion, _evasion_tooltip(evasion))
	_add(defense_list, "Max Health", "%.0f" % player.health.max_health)
	_add(defense_list, "Life Regen", "%.1f/s" % player.health.regen_per_second)
	_add(defense_list, "Max Ward", "%.0f" % player.ward.max_ward)
	_add(defense_list, "Armor", "%.0f" % (player.equipment.get_total_armor() if player.equipment else 0.0))
	# StatSheet.get_resistance() already includes gear and the all-elemental
	# bonus; Esoteric is one shared bucket, so any of its 3 damage types reads it.
	for pair in [["Fire", Constants.DamageType.FIRE], ["Cold", Constants.DamageType.COLD], ["Lightning", Constants.DamageType.LIGHTNING], ["Esoteric", Constants.DamageType.AETHERIC]]:
		# The capped value that applies, with the uncapped total beside it when over.
		var total := int(stats.get_resistance(pair[1]))
		var applied := mini(total, int(stats.get_max_resistance(pair[1])))
		_add(defense_list, "%s Resistance" % pair[0], "%d%% (%d%%)" % [applied, total] if total > applied else "%d%%" % total)

	_add(misc_list, "Intellect", "%.1f" % stats.get_stat(Constants.Stat.INTELLECT))
	_add(misc_list, "Spell Damage", "+%.0f%%" % (stats.get_spell_power_from_stats() * 100.0))
	_add(misc_list, "Max Mana", "%.0f" % player.mana.max_mana)
	_add(misc_list, "Mana Regen", "%.1f/s" % player.mana.regen_per_second)
	_add(misc_list, "Move Speed", "%.1f m/s" % (player.move_speed * player.get_move_speed_multiplier()))
	_add(misc_list, "Sprint Speed", "%.1f m/s" % (player.sprint_speed * player.get_move_speed_multiplier()))
	_add(misc_list, "Action Speed", "%.0f%%" % (player.get_action_speed_multiplier() * 100.0))
	var loot: Dictionary = player.equipment.compute_misc_bonuses() if player.equipment else {}
	_add(misc_list, "Item Quantity", "+%.1f%%" % Loot.quantity_percent(loot))
	_add(misc_list, "Item Rarity", "+%.0f%%" % Loot.rarity_percent(loot))
	_add(misc_list, "Magic Find", "%.0f" % loot.get(Loot.MAGIC_FIND_KEY, 0.0))
	for tag in stats.chain_bonus_by_tag:
		var bonus: float = stats.chain_bonus_by_tag[tag]
		if bonus != 0.0:
			_add(misc_list, "%s Chain Bonus" % Constants.DAMAGE_TYPE_NAME.get(tag, "?"), "+%.1f%%" % (bonus * 100.0))
	for tag in stats.mastery_by_tag:
		var mastery: float = stats.mastery_by_tag[tag]
		if mastery != 0.0:
			_add(misc_list, "%s Mastery" % Constants.DAMAGE_TYPE_NAME.get(tag, "?"), "+%.1f%% more" % (mastery * 100.0))

## Deaths, kills and each Pinnacle boss's clears.
static func refresh_record(list: VBoxContainer) -> void:
	if list == null:
		return
	_clear(list)
	_add(list, "Deaths", "%d" % GameState.deaths)
	_add(list, "Monsters Slain", "%d" % GameState.kills)
	for boss_id in Pinnacle.offered_bosses():
		_add(list, Pinnacle.BOSSES[boss_id]["name"], "%d defeated" % int(GameState.pinnacle_clears.get(boss_id, 0)))

## Null for a Shield in OFFHAND.
static func _weapon_in(player: Player, slot: Constants.EquipmentSlot) -> Weapon:
	if player.equipment == null:
		return null
	return player.equipment.primary_weapon if slot == Constants.EquipmentSlot.PRIMARY_WEAPON else player.equipment.offhand as Weapon

## Uses the same motion value the melee/ranged attack script would, so the
## prediction matches real hits.
static func _predict_damage(player: Player, slot: Constants.EquipmentSlot) -> String:
	var weapon := _weapon_in(player, slot)
	if weapon == null:
		return "None equipped"
	var motion_value: float = player.ranged_attack.base_motion_value if weapon.is_ranged else player.melee_attack._effective_motion_value(weapon)
	var range := weapon.predict_damage_range(motion_value, player.stat_sheet)
	return "%s to %s" % [ItemCard.damage_text(range.x), ItemCard.damage_text(range.y)]

static func _crit_summary(player: Player, slot: Constants.EquipmentSlot) -> String:
	var weapon := _weapon_in(player, slot)
	if weapon == null:
		return "None equipped"
	var chance := DamageCalculator.get_crit_chance(weapon.get_local_crit_chance(), player.stat_sheet.finesse_crit_bonus)
	var multiplier := player.stat_sheet.get_crit_damage_multiplier()
	return "%.0f%% chance / %.0f%% dmg" % [clamp(chance, 0.0, 1.0) * 100.0, multiplier * 100.0]

## Patch v4.4: Evasion's tooltip states what the rating actually means.
static func _evasion_tooltip(evasion: float) -> String:
	return "Evasion Rating: Reduces chance of being hit by attacks.\nDodge Chance: %.1f%% (cap %d%%) - fully negates an attack hit.\nDeflection Chance: %.1f%% (cap %d%%) - reduces attack and spell damage by %.1f%%." % [
		DamageCalculator.player_dodge_chance(evasion) * 100.0, int(DamageCalculator.DODGE_CHANCE_CAP * 100.0),
		DamageCalculator.player_deflection_chance(evasion) * 100.0, int(DamageCalculator.DEFLECTION_CHANCE_CAP * 100.0),
		DamageCalculator.player_deflection_mitigation(evasion) * 100.0,
	]

static func _add(list: VBoxContainer, label_text: String, value_text: String, tooltip_override: String = "") -> void:
	# Every other row is faintly lit so long columns stay easy to follow.
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", AetherStyle.row_box(list.get_child_count() % 2 == 1))
	plate.tooltip_text = tooltip_override if tooltip_override != "" else _tooltip_for(label_text)
	plate.mouse_filter = Control.MOUSE_FILTER_STOP  # a tooltip needs a Control that receives the mouse
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_override("font", AetherStyle.numbers())
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", AetherStyle.TEXT)
	row.add_child(value)
	list.add_child(plate)

static func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
