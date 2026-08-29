extends CanvasLayer
class_name AbilitiesScreen
## Ability equip/upgrade menu - opens via the `open_abilities` hotkey (N),
## same "hotkey-only, no PauseMenu button" pattern as Inventory (B) and
## Fate Board (P). List-based, not a uniform grid like InventoryScreen -
## each owned ability needs an Upgrade button and rank readout alongside
## it, which doesn't fit a plain icon grid the way equip-only items do.
##
## "Owned" abilities are still directory-scanned from
## data/abilities/instances/, same stand-in convention as Inventory/Fate
## Board - as if the player owns one of each, no real acquisition system.
## Any ability can go in any of the 4 equip slots (unlike
## EquipmentComponent's typed slots), so clicking an owned ability equips
## it into the first open slot (AbilityLoadoutComponent.equip_first_open).
##
## Upgrading is free and uncapped-by-cost right now (just rank-capped at
## Ability.MAX_RANK) - there's no currency/economy for it to spend,
## flagged in Ability.gd's own header comment as an invented placeholder.

const ABILITY_INSTANCE_DIR := "res://data/abilities/instances/"

@onready var owned_list: VBoxContainer = $HBox/OwnedPanel/OwnedScroll/OwnedList
@onready var equipped_row: HBoxContainer = $HBox/SidePanel/EquippedRow
@onready var close_button: Button = $HBox/SidePanel/CloseButton

var _is_open: bool = false
var _ability_loadout: AbilityLoadoutComponent
var _owned_abilities: Array[Ability] = []
var _rank_labels: Array[Label] = []
var _upgrade_buttons: Array[Button] = []
var _equipped_buttons: Array[ItemSlotButton] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("abilities_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)
	_scan_owned_abilities()
	_build_owned_list()
	_build_equipped_row()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := get_tree().get_first_node_in_group("player") as Player
	_ability_loadout = player.ability_loadout if player else null
	if _ability_loadout and not _ability_loadout.loadout_changed.is_connected(_refresh_equipped_row):
		_ability_loadout.loadout_changed.connect(_refresh_equipped_row)
	_refresh_equipped_row()

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

func _scan_owned_abilities() -> void:
	var dir := DirAccess.open(ABILITY_INSTANCE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(ABILITY_INSTANCE_DIR + file_name) as Ability
			if ability:
				_owned_abilities.append(ability)
		file_name = dir.get_next()
	dir.list_dir_end()

func _build_owned_list() -> void:
	for ability in _owned_abilities:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon := ItemSlotButton.new()
		icon.ability = ability
		icon.text = ability.display_name
		icon.tooltip_text = ability.display_name
		icon.custom_minimum_size = Vector2(200, 40)
		icon.clip_text = true
		var box := StyleBoxFlat.new()
		box.bg_color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
		box.set_corner_radius_all(4)
		icon.add_theme_stylebox_override("normal", box)
		icon.add_theme_stylebox_override("hover", box)
		icon.add_theme_stylebox_override("pressed", box)
		icon.pressed.connect(_on_owned_ability_pressed.bind(ability))
		row.add_child(icon)

		var rank_label := Label.new()
		rank_label.custom_minimum_size = Vector2(70, 0)
		row.add_child(rank_label)
		_rank_labels.append(rank_label)

		var upgrade_button := Button.new()
		upgrade_button.text = "Upgrade"
		upgrade_button.pressed.connect(_on_upgrade_pressed.bind(ability))
		row.add_child(upgrade_button)
		_upgrade_buttons.append(upgrade_button)

		owned_list.add_child(row)
	_refresh_owned_list()

func _build_equipped_row() -> void:
	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		var button := ItemSlotButton.new()
		button.custom_minimum_size = Vector2(64, 64)
		button.clip_text = true
		button.pressed.connect(_on_equipped_slot_pressed.bind(i))
		equipped_row.add_child(button)
		_equipped_buttons.append(button)

func _on_owned_ability_pressed(ability: Ability) -> void:
	if _ability_loadout:
		_ability_loadout.equip_first_open(ability)
		GameState.sync_ability_loadout(_ability_loadout)

func _on_upgrade_pressed(ability: Ability) -> void:
	if ability.can_upgrade():
		ability.rank += 1
		GameState.ability_ranks[ability.ability_id] = ability.rank
	_refresh_owned_list()
	_refresh_equipped_row()  # equipped copies share the same Resource, but cooldown/motion_value readouts on the bar depend on rank too

func _on_equipped_slot_pressed(slot_index: int) -> void:
	if _ability_loadout:
		_ability_loadout.unequip(slot_index)
		GameState.sync_ability_loadout(_ability_loadout)

func _refresh_owned_list() -> void:
	for i in range(_owned_abilities.size()):
		var ability := _owned_abilities[i]
		_rank_labels[i].text = "Rank %d/%d" % [ability.rank, Ability.MAX_RANK]
		_upgrade_buttons[i].disabled = not ability.can_upgrade()

func _refresh_equipped_row() -> void:
	if _ability_loadout == null:
		return
	for i in range(_equipped_buttons.size()):
		var button := _equipped_buttons[i]
		var ability: Ability = _ability_loadout.get_equipped(i)
		button.ability = ability
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(4)
		if ability:
			button.text = ability.display_name
			button.tooltip_text = ability.display_name
			box.bg_color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
		else:
			button.text = "Empty"
			button.tooltip_text = ""
			box.bg_color = Color(0.25, 0.25, 0.28)
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_stylebox_override("hover", box)
		button.add_theme_stylebox_override("pressed", box)
