extends CanvasLayer
class_name AbilitiesScreen
## Ability equip/upgrade menu - opens via the `open_abilities` hotkey (N),
## hotkey-only like Inventory (B)/Fate Board (P). List-based, not a grid
## like InventoryScreen - each ability needs a Level Up button and level
## readout alongside it.
##
## "Owned" abilities are directory-scanned from data/abilities/instances/,
## filtered to GameState.owned_ability_ids (found via SkillTome or the
## Hub's SpellTestShop). List rebuilds every open, not just at _ready(),
## since ownership can change mid-session. Clicking an owned ability
## equips it into the first open slot of the bar, or of the stance page
## (slots a Spell Library conduit casts while RMB is held) when that's the
## chosen target.
##
## Leveling a spell costs Gold + Crystallized Aether (Ability.
## get_upgrade_gold_cost()/get_upgrade_aether_cost()), up to Ability.MAX_LEVEL.

const ABILITY_INSTANCE_DIR := "res://data/abilities/instances/"

@onready var owned_list: VBoxContainer = $HBox/OwnedPanel/OwnedScroll/OwnedList
@onready var equipped_row: HBoxContainer = $HBox/SidePanel/EquippedRow
@onready var close_button: Button = $HBox/SidePanel/CloseButton

var _is_open: bool = false
var _ability_loadout: AbilityLoadoutComponent
var _owned_abilities: Array[Ability] = []
var _level_labels: Array[Label] = []
var _upgrade_buttons: Array[Button] = []
var _equipped_buttons: Array[ItemSlotButton] = []
var _page_buttons: Array[ItemSlotButton] = []
var _equip_to_page: bool = false
var _page_row: HBoxContainer
var _aether_label: Label

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("abilities_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)
	_build_equipped_row()
	_build_page_row()
	_aether_label = Label.new()
	equipped_row.get_parent().add_child(_aether_label)
	equipped_row.get_parent().move_child(_aether_label, _page_row.get_index() + 1)

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
	_build_owned_list()
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
	_owned_abilities = []
	var dir := DirAccess.open(ABILITY_INSTANCE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(ABILITY_INSTANCE_DIR + file_name) as Ability
			if ability and GameState.owned_ability_ids.has(ability.ability_id):
				_owned_abilities.append(ability)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()

func _build_owned_list() -> void:
	for child in owned_list.get_children():
		child.queue_free()
	_level_labels = []
	_upgrade_buttons = []
	_scan_owned_abilities()
	for ability in _owned_abilities:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon := ItemSlotButton.new()
		icon.ability = ability
		icon.text = ability.display_name
		icon.tooltip_text = ability.display_name
		icon.custom_minimum_size = Vector2(200, 40)
		icon.clip_text = true
		var element: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
		AetherStyle.style_slot_button(icon, element)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			icon.add_theme_color_override(state, element.lerp(Color.WHITE, 0.25))
		icon.pressed.connect(_on_owned_ability_pressed.bind(ability))
		row.add_child(icon)

		var level_label := Label.new()
		level_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(level_label)
		_level_labels.append(level_label)

		var upgrade_button := Button.new()
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

## Stance page row under the bar, with a switch for where clicks equip.
func _build_page_row() -> void:
	var parent := equipped_row.get_parent()
	var target_row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Equip to:"
	target_row.add_child(label)
	var group := ButtonGroup.new()
	for page in 2:
		var button := Button.new()
		button.text = "Ability Bar" if page == 0 else "Stance Page"
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = page == 0
		button.pressed.connect(func(): _equip_to_page = page == 1)
		target_row.add_child(button)
	parent.add_child(target_row)
	parent.move_child(target_row, equipped_row.get_index())
	var page_label := Label.new()
	page_label.text = "Stance Page - cast while holding RMB with a Spell Library conduit"
	parent.add_child(page_label)
	var page_row := HBoxContainer.new()
	_page_row = page_row
	page_row.add_theme_constant_override("separation", equipped_row.get_theme_constant("separation"))
	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		var button := ItemSlotButton.new()
		button.custom_minimum_size = Vector2(64, 64)
		button.clip_text = true
		button.pressed.connect(_on_equipped_slot_pressed.bind(AbilityLoadoutComponent.SLOT_COUNT + i))
		page_row.add_child(button)
		_page_buttons.append(button)
	parent.add_child(page_row)
	parent.move_child(page_label, equipped_row.get_index() + 1)
	parent.move_child(page_row, page_label.get_index() + 1)

func _on_owned_ability_pressed(ability: Ability) -> void:
	if _ability_loadout:
		_ability_loadout.equip_first_open(ability, _equip_to_page)
		GameState.sync_ability_loadout(_ability_loadout)

func _can_afford(ability: Ability) -> bool:
	return GameState.gold >= ability.get_upgrade_gold_cost() 		and GameState.inventory.count_of(Ability.AETHER_CURRENCY) >= ability.get_upgrade_aether_cost()

func _on_upgrade_pressed(ability: Ability) -> void:
	if ability.can_upgrade() and _can_afford(ability):
		GameState.gold -= ability.get_upgrade_gold_cost()
		GameState.inventory.remove_currency(Ability.AETHER_CURRENCY, ability.get_upgrade_aether_cost())
		ability.level += 1
		GameState.ability_levels[ability.ability_id] = ability.level
	_refresh_owned_list()
	_refresh_equipped_row()  # equipped copies share the Resource, but the bar's readouts depend on level too

func _on_equipped_slot_pressed(slot_index: int) -> void:
	if _ability_loadout:
		_ability_loadout.unequip(slot_index)
		GameState.sync_ability_loadout(_ability_loadout)

func _refresh_owned_list() -> void:
	for i in range(_owned_abilities.size()):
		var ability := _owned_abilities[i]
		_level_labels[i].text = "Level %d/%d" % [ability.level, Ability.MAX_LEVEL]
		var button := _upgrade_buttons[i]
		if ability.can_upgrade():
			button.text = "Level Up (%d Gold, %d %s)" % [ability.get_upgrade_gold_cost(), ability.get_upgrade_aether_cost(), CurrencyText.name_of(Ability.AETHER_CURRENCY)]
			button.disabled = not _can_afford(ability)
		else:
			button.text = "Max Level"
			button.disabled = true
	if _aether_label:
		_aether_label.text = "Gold: %d    %s: %d" % [GameState.gold, CurrencyText.name_of(Ability.AETHER_CURRENCY), GameState.inventory.count_of(Ability.AETHER_CURRENCY)]

func _refresh_equipped_row() -> void:
	if _ability_loadout == null:
		return
	var buttons: Array[ItemSlotButton] = _equipped_buttons + _page_buttons
	for i in range(buttons.size()):
		var button := buttons[i]
		var ability: Ability = _ability_loadout.slots[i]
		button.ability = ability
		var accent: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE) if ability else AetherStyle.GOLD_FAINT
		button.text = "" if ability else "-"
		button.tooltip_text = ability.display_name if ability else ""
		AetherStyle.style_slot_button(button, accent)
		button.add_theme_font_size_override("font_size", 22)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, accent.lerp(Color.WHITE, 0.2) if ability else AetherStyle.TEXT_DIM)
