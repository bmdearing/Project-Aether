extends CanvasLayer
class_name CharacterScreen
## Read-only character sheet - opens via the `open_character` hotkey (C),
## same hotkey-only pattern as Inventory (B)/Fate Board (P)/Abilities (N),
## no PauseMenu button. Three columns per user request: Offense, Defense,
## Misc.
##
## Only Strength/Arcane/Enigma actually drive anything right now
## (Constants.DAMAGE_TYPE_MAIN_STAT - they scale Physical/Elemental/
## Esoteric damage respectively). Vitality/Instinct/Intellect exist on
## StatSheet but aren't wired to any formula anywhere in this project
## yet - shown anyway (the user asked for "all of the player's stats,"
## and hiding them would just be a different kind of dishonesty), but
## the hint label says so explicitly rather than implying they matter.
##
## Predicted Melee/Ranged Damage reuse Weapon.predict_damage() -
## the exact calculation PlayerMeleeAttack/PlayerRangedAttack actually
## use - so these numbers can't drift from what attacking really deals.
## Values are computed once on open() rather than refreshed per-frame:
## the screen pauses the game, so nothing here changes while it's open.

@onready var offense_list: VBoxContainer = $CenterContainer/VBox/Columns/OffenseColumn/OffenseList
@onready var defense_list: VBoxContainer = $CenterContainer/VBox/Columns/DefenseColumn/DefenseList
@onready var misc_list: VBoxContainer = $CenterContainer/VBox/Columns/MiscColumn/MiscList
@onready var close_button: Button = $CenterContainer/VBox/CloseButton

var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("character_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	_clear(offense_list)
	_clear(defense_list)
	_clear(misc_list)

	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var stats: StatSheet = player.stat_sheet

	_add_line(offense_list, "Strength", "%.1f" % stats.get_stat(Constants.Stat.STRENGTH))
	_add_line(offense_list, "Arcane", "%.1f" % stats.get_stat(Constants.Stat.ARCANE))
	_add_line(offense_list, "Enigma", "%.1f" % stats.get_stat(Constants.Stat.ENIGMA))
	_add_line(offense_list, "Predicted Melee Damage", _predict_melee(player))
	_add_line(offense_list, "Predicted Ranged Damage", _predict_ranged(player))

	_add_line(defense_list, "Vitality", "%.1f" % stats.get_stat(Constants.Stat.VITALITY))
	_add_line(defense_list, "Instinct", "%.1f" % stats.get_stat(Constants.Stat.INSTINCT))
	_add_line(defense_list, "Max Health", "%.0f" % player.health.max_health)
	_add_line(defense_list, "Max Ward", "%.0f" % player.ward.max_ward)
	_add_line(defense_list, "Armor", "%.0f" % (player.equipment.get_total_armor() if player.equipment else 0.0))

	_add_line(misc_list, "Intellect", "%.1f" % stats.get_stat(Constants.Stat.INTELLECT))
	_add_line(misc_list, "Max Mana", "%.0f" % player.mana.max_mana)
	_add_line(misc_list, "Move Speed", "%.1f m/s" % player.move_speed)
	_add_line(misc_list, "Sprint Speed", "%.1f m/s" % player.sprint_speed)
	if stats.supercharged_stat != -1:
		_add_line(misc_list, "Supercharged", Constants.Stat.keys()[stats.supercharged_stat])
	for tag in stats.mastery_by_tag:
		var value: float = stats.mastery_by_tag[tag]
		if value != 0.0:
			_add_line(misc_list, "%s Mastery" % Constants.DAMAGE_TYPE_NAME.get(tag, "?"), "+%.2f" % value)

func _predict_melee(player: Player) -> String:
	var weapon: Weapon = player.equipment.primary_weapon if player.equipment else null
	if weapon == null:
		return "None equipped"
	return "%.1f" % weapon.predict_damage(player.melee_attack.base_motion_value, player.stat_sheet)

func _predict_ranged(player: Player) -> String:
	var weapon: Weapon = player.equipment.sidearm_weapon if player.equipment else null
	if weapon == null:
		return "None equipped"
	return "%.1f" % weapon.predict_damage(player.ranged_attack.base_motion_value, player.stat_sheet)

func _add_line(list: VBoxContainer, label_text: String, value_text: String) -> void:
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

func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
