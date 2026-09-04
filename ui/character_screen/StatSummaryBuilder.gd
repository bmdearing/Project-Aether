extends RefCounted
class_name StatSummaryBuilder
## Shared stat-line builder for CharacterScreen and InventoryScreen's
## stats column (equipping gear there now updates stats live in place).
## One source of truth so both stay in sync.

static func refresh(offense_list: VBoxContainer, defense_list: VBoxContainer, misc_list: VBoxContainer, player: Player) -> void:
	_clear(offense_list)
	_clear(defense_list)
	_clear(misc_list)
	if player == null:
		return
	var stats: StatSheet = player.stat_sheet

	_add(offense_list, "Strength", "%.1f" % stats.get_stat(Constants.Stat.STRENGTH))
	_add(offense_list, "Arcane", "%.1f" % stats.get_stat(Constants.Stat.ARCANE))
	_add(offense_list, "Enigma", "%.1f" % stats.get_stat(Constants.Stat.ENIGMA))
	_add(offense_list, "Main Hand Damage", _predict_damage(player, Constants.EquipmentSlot.PRIMARY_WEAPON))
	_add(offense_list, "Main Hand Crit", _crit_summary(player, Constants.EquipmentSlot.PRIMARY_WEAPON))
	_add(offense_list, "Offhand Damage", _predict_damage(player, Constants.EquipmentSlot.OFFHAND))
	_add(offense_list, "Offhand Crit", _crit_summary(player, Constants.EquipmentSlot.OFFHAND))

	_add(defense_list, "Vitality", "%.1f" % stats.get_stat(Constants.Stat.VITALITY))
	_add(defense_list, "Instinct", "%.1f" % stats.get_stat(Constants.Stat.INSTINCT))
	_add(defense_list, "Max Health", "%.0f" % player.health.max_health)
	_add(defense_list, "Life Regen", "%.1f/s" % player.health.regen_per_second)
	_add(defense_list, "Max Ward", "%.0f" % player.ward.max_ward)
	_add(defense_list, "Armor", "%.0f" % (player.equipment.get_total_armor() if player.equipment else 0.0))

	_add(misc_list, "Level", "%d" % player.experience.level)
	_add(misc_list, "XP", "%.0f / %.0f" % [player.experience.xp, player.experience.xp_to_next_level()])
	_add(misc_list, "Intellect", "%.1f" % stats.get_stat(Constants.Stat.INTELLECT))
	_add(misc_list, "Max Mana", "%.0f" % player.mana.max_mana)
	_add(misc_list, "Mana Regen", "%.1f/s" % player.mana.regen_per_second)
	_add(misc_list, "Move Speed", "%.1f m/s" % (player.move_speed * player.get_move_speed_multiplier()))
	_add(misc_list, "Sprint Speed", "%.1f m/s" % (player.sprint_speed * player.get_move_speed_multiplier()))
	_add(misc_list, "Action Speed", "%.0f%%" % (player.get_action_speed_multiplier() * 100.0))
	if stats.supercharged_stat != -1:
		_add(misc_list, "Supercharged", Constants.Stat.keys()[stats.supercharged_stat])
	for tag in stats.mastery_by_tag:
		var value: float = stats.mastery_by_tag[tag]
		if value != 0.0:
			_add(misc_list, "%s Mastery" % Constants.DAMAGE_TYPE_NAME.get(tag, "?"), "+%.2f" % value)
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
	return "%.1f" % weapon.predict_damage(motion_value, player.stat_sheet)

static func _crit_summary(player: Player, slot: Constants.EquipmentSlot) -> String:
	var weapon := _weapon_in(player, slot)
	if weapon == null:
		return "None equipped"
	var chance := DamageCalculator.get_crit_chance(weapon.get_base_crit_chance(), player.stat_sheet.get_stat(Constants.Stat.INSTINCT))
	var multiplier := DamageCalculator.get_crit_damage_multiplier(player.stat_sheet.get_stat(Constants.Stat.INTELLECT))
	return "%.0f%% chance / %.0f%% dmg" % [clamp(chance, 0.0, 1.0) * 100.0, multiplier * 100.0]

static func _add(list: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
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
