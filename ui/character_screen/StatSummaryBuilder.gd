extends RefCounted
class_name StatSummaryBuilder
## Shared stat-line builder for CharacterScreen and InventoryScreen's
## stats column (equipping gear there now updates stats live in place).
## One source of truth so both stay in sync.

## Hover text per stat row, keyed by the row's label (Patch v4.3). Rows not
## listed here get no tooltip.
const STAT_TOOLTIPS := {
	"Strength": "+1% increased Weapon Damage, +4 Life per point.",
	"Weapon Damage": "Increased weapon base damage from Strength.",
	"Main Hand Damage": "Estimated damage range for your main hand weapon.",
	"Agility": "+1% increased Attack Speed, Evasion, and Critical Strike Chance per point.",
	# "Evasion Rating" is built live in _evasion_tooltip() - it shows the derived percentages.
	"Max Health": "Total Life pool. Depleted by incoming damage.",
	"Life Regen": "Life recovered per second passively.",
	"Max Ward": "Secondary buffer that absorbs all damage before Health.",
	"Armor": "Reduces Physical damage taken.",
	"Intellect": "+1% increased Spell Damage and Ward, +3 Mana per point.",
	"Spell Damage": "Increased Conduit spell power from Intellect.",
	"Max Mana": "Resource pool for casting spells.",
	"Mana Regen": "Mana recovered per second passively.",
	"Move Speed": "Base movement speed in meters per second.",
	"Sprint Speed": "Movement speed while sprinting.",
	"Action Speed": "Multiplier applied to attack speed and cast speed.",
	"Fire Resistance": "Reduces Fire damage and Ignite tick damage taken.",
	"Cold Resistance": "Reduces Cold damage and Chill/Freeze effects.",
	"Lightning Resistance": "Reduces Lightning damage and Electrocute.",
	"Esoteric Resistance": "Reduces Aetheric, Entropic, and Pale damage taken.",
}

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
	_add(defense_list, "Fire Resistance", "%d%%" % int(stats.get_resistance(Constants.DamageType.FIRE)))
	_add(defense_list, "Cold Resistance", "%d%%" % int(stats.get_resistance(Constants.DamageType.COLD)))
	_add(defense_list, "Lightning Resistance", "%d%%" % int(stats.get_resistance(Constants.DamageType.LIGHTNING)))
	_add(defense_list, "Esoteric Resistance", "%d%%" % int(stats.get_resistance(Constants.DamageType.AETHERIC)))

	_add(misc_list, "Level", "%d" % player.experience.level)
	_add(misc_list, "XP", "%.0f / %.0f" % [player.experience.xp, player.experience.xp_to_next_level()])
	_add(misc_list, "Intellect", "%.1f" % stats.get_stat(Constants.Stat.INTELLECT))
	_add(misc_list, "Spell Damage", "+%.0f%%" % (stats.get_spell_power_from_stats() * 100.0))
	_add(misc_list, "Max Mana", "%.0f" % player.mana.max_mana)
	_add(misc_list, "Mana Regen", "%.1f/s" % player.mana.regen_per_second)
	_add(misc_list, "Move Speed", "%.1f m/s" % (player.move_speed * player.get_move_speed_multiplier()))
	_add(misc_list, "Sprint Speed", "%.1f m/s" % (player.sprint_speed * player.get_move_speed_multiplier()))
	_add(misc_list, "Action Speed", "%.0f%%" % (player.get_action_speed_multiplier() * 100.0))
	for tag in stats.chain_bonus_by_tag:
		var bonus: float = stats.chain_bonus_by_tag[tag]
		if bonus != 0.0:
			_add(misc_list, "%s Chain Bonus" % Constants.DAMAGE_TYPE_NAME.get(tag, "?"), "+%.1f%%" % (bonus * 100.0))

## OFFHAND can hold a Shield (no damage - `as Weapon` returns null,
## reading as "None equipped" below) or an offhand-type Weapon since
## Patch v3.5 dropped Sidearm as its own slot.
static func _weapon_in(player: Player, slot: Constants.EquipmentSlot) -> Weapon:
	if player.equipment == null:
		return null
	return player.equipment.primary_weapon if slot == Constants.EquipmentSlot.PRIMARY_WEAPON else player.equipment.offhand as Weapon

## motion_value comes from whichever attack script would actually use
## this slot (melee vs ranged), matching Player's own dispatch by
## Weapon.is_ranged rather than assuming Primary=melee/Offhand=ranged.
## Melee reads PlayerMeleeAttack._effective_motion_value(weapon) rather
## than its own flat base_motion_value now that motion value varies per
## weapon_type (2026-08-30) - README/this file's own convention is this
## number can never drift from what a real swing actually deals, so it
## has to follow that change too, not just PlayerMeleeAttack.gd itself.
static func _predict_damage(player: Player, slot: Constants.EquipmentSlot) -> String:
	var weapon := _weapon_in(player, slot)
	if weapon == null:
		return "None equipped"
	var motion_value: float = player.ranged_attack.base_motion_value if weapon.is_ranged else player.melee_attack._effective_motion_value(weapon)
	var range := weapon.predict_damage_range(motion_value, player.stat_sheet)
	return "%.0f to %.0f" % [range.x, range.y]

static func _crit_summary(player: Player, slot: Constants.EquipmentSlot) -> String:
	var weapon := _weapon_in(player, slot)
	if weapon == null:
		return "None equipped"
	var chance := DamageCalculator.get_crit_chance(weapon.get_local_crit_chance(), player.stat_sheet.finesse_crit_bonus)
	var multiplier := DamageCalculator.get_crit_damage_multiplier(player.stat_sheet.get_crit_damage_bonus())
	return "%.0f%% chance / %.0f%% dmg" % [clamp(chance, 0.0, 1.0) * 100.0, multiplier * 100.0]

## Patch v4.4: Evasion's tooltip states what the rating actually means.
static func _evasion_tooltip(evasion: float) -> String:
	return "Evasion Rating: Reduces chance of being hit by attacks.\nDodge Chance: %.1f%% (cap %d%%) - fully negates an attack hit.\nDeflection Chance: %.1f%% (cap %d%%) - reduces attack and spell damage by %.1f%%." % [
		DamageCalculator.dodge_chance(evasion) * 100.0, int(DamageCalculator.DODGE_CHANCE_CAP * 100.0),
		DamageCalculator.deflection_chance(evasion) * 100.0, int(DamageCalculator.DEFLECTION_CHANCE_CAP * 100.0),
		DamageCalculator.deflection_mitigation(evasion) * 100.0,
	]

static func _add(list: VBoxContainer, label_text: String, value_text: String, tooltip_override: String = "") -> void:
	var row := HBoxContainer.new()
	row.tooltip_text = tooltip_override if tooltip_override != "" else STAT_TOOLTIPS.get(label_text, "")
	row.mouse_filter = Control.MOUSE_FILTER_STOP  # a tooltip needs a Control that receives the mouse
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(value)
	list.add_child(row)

static func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
