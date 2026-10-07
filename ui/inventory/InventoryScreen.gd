extends CanvasLayer
class_name InventoryScreen
## Footprint-grid inventory (GameState.inventory, see GridInventory) +
## paper-doll equipment diagram + a live stats column (StatSummaryBuilder,
## shared with CharacterScreen). Clicking an item equips it; clicking a
## paper-doll slot unequips into the grid if there's room. Equipped items
## live on EquipmentComponent, not in the grid. Doesn't pause the game.

const EMPTY_SLOT_COLOR := Color(0.25, 0.25, 0.28)
const EMPTY_GRID_COLOR := Color(0.2, 0.2, 0.22)

@onready var offense_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/OffenseList
@onready var defense_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/DefenseList
@onready var misc_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/MiscList
@onready var inventory_grid: InventoryGridView = $HBox/SidePanel/InventoryPanel/InventoryScroll/InventoryGrid
@onready var inventory_panel: VBoxContainer = $HBox/SidePanel/InventoryPanel
@onready var status_label: Label = $HBox/SidePanel/StatusLabel
@onready var close_button: Button = $HBox/SidePanel/CloseButton

@onready var slot_primary_weapon: ItemSlotButton = $HBox/SidePanel/PaperDoll/LeftColumn/PrimaryWeapon
@onready var slot_ring_left: ItemSlotButton = $HBox/SidePanel/PaperDoll/LeftColumn/RingLeft
@onready var slot_helmet: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/Helmet
@onready var slot_amulet: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/Amulet
@onready var slot_body_armour: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/BodyArmour
@onready var slot_belt: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/Belt
@onready var slot_gloves: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/BottomRow/Gloves
@onready var slot_boots: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/BottomRow/Boots
@onready var slot_offhand: ItemSlotButton = $HBox/SidePanel/PaperDoll/RightColumn/Offhand
@onready var slot_ring_right: ItemSlotButton = $HBox/SidePanel/PaperDoll/RightColumn/RingRight

@onready var side_panel: VBoxContainer = $HBox/SidePanel
@onready var paper_doll: HBoxContainer = $HBox/SidePanel/PaperDoll
var _weapon_set_label: Label
var _weapon_set_button: Button
## Equipment / Behaviors tabs at the top left of the paper doll. Behaviors
## swaps the doll for per-weapon settings: which stance RMB uses, and
## whether RMB raises an equipped shield instead.
var _equipment_tab: Button
var _behaviors_tab: Button
var _behaviors_panel: VBoxContainer

var _is_open: bool = false
var _equipment: EquipmentComponent
var _doll_rows: Array[Dictionary] = []

var _ammo_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("inventory_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)
	_doll_rows = [
		{"button": slot_helmet, "slot": Constants.EquipmentSlot.HELMET, "label": "Helmet"},
		{"button": slot_body_armour, "slot": Constants.EquipmentSlot.BODY_ARMOUR, "label": "Body Armour"},
		{"button": slot_gloves, "slot": Constants.EquipmentSlot.GLOVES, "label": "Gloves"},
		{"button": slot_boots, "slot": Constants.EquipmentSlot.BOOTS, "label": "Boots"},
		{"button": slot_primary_weapon, "slot": Constants.EquipmentSlot.PRIMARY_WEAPON, "label": "Primary Weapon"},
		{"button": slot_offhand, "slot": Constants.EquipmentSlot.OFFHAND, "label": "Offhand"},
		{"button": slot_amulet, "slot": Constants.EquipmentSlot.AMULET, "label": "Amulet"},
		{"button": slot_belt, "slot": Constants.EquipmentSlot.BELT, "label": "Belt"},
		{"button": slot_ring_left, "slot": Constants.EquipmentSlot.RING, "ring_index": 0, "label": "Ring 1"},
		{"button": slot_ring_right, "slot": Constants.EquipmentSlot.RING, "ring_index": 1, "label": "Ring 2"},
	]
	for row in _doll_rows:
		(row["button"] as ItemSlotButton).pressed.connect(_on_doll_slot_pressed.bind(row))
	_build_weapon_set_indicator()
	_build_behaviors_panel()
	inventory_grid.cell_size = 52
	inventory_grid.entry_clicked.connect(_on_entry_clicked)
	inventory_grid.drop_failed.connect(func(): status_label.text = "That doesn't fit there.")
	_ammo_label = Label.new()
	inventory_panel.add_child(_ammo_label)

## Implementation Brief v3.4 Section 4, user-expanded scope ("Properly
## show which set is being worn in the inventory screen"). The paper-doll's
## own weapon slots (Primary/Sidearm/Offhand) already show whichever set
## is ACTIVE with zero changes needed - EquipmentComponent.get_equipped()
## defaults to the active set - this just adds a label + a toggle button
## next to the doll so the player can tell (and switch) directly from the
## inventory instead of only via the in-game X-tap.
func _build_weapon_set_indicator() -> void:
	var row := HBoxContainer.new()
	var tabs := ButtonGroup.new()
	_equipment_tab = _make_toggle("Equipment", tabs, true)
	_equipment_tab.pressed.connect(_show_tab.bind(false))
	_behaviors_tab = _make_toggle("Behaviors", tabs, false)
	_behaviors_tab.pressed.connect(_show_tab.bind(true))
	row.add_child(_equipment_tab)
	row.add_child(_behaviors_tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_weapon_set_label = Label.new()
	_weapon_set_button = Button.new()
	_weapon_set_button.text = "Swap Weapon Set (X)"
	_weapon_set_button.pressed.connect(_on_weapon_set_toggle_pressed)
	row.add_child(_weapon_set_label)
	row.add_child(_weapon_set_button)
	side_panel.add_child(row)
	side_panel.move_child(row, paper_doll.get_index())

func _make_toggle(text: String, group: ButtonGroup, pressed: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = pressed
	return button

func _build_behaviors_panel() -> void:
	_behaviors_panel = VBoxContainer.new()
	_behaviors_panel.custom_minimum_size = paper_doll.custom_minimum_size
	_behaviors_panel.add_theme_constant_override("separation", 8)
	_behaviors_panel.visible = false
	side_panel.add_child(_behaviors_panel)
	side_panel.move_child(_behaviors_panel, paper_doll.get_index() + 1)

func _show_tab(behaviors: bool) -> void:
	paper_doll.visible = not behaviors
	_behaviors_panel.visible = behaviors
	if behaviors:
		_refresh_behaviors()

func _refresh_behaviors() -> void:
	if _behaviors_panel == null or not _behaviors_panel.visible:
		return
	for child in _behaviors_panel.get_children():
		child.queue_free()
	var weapon: Weapon = _equipment.primary_weapon if _equipment else null
	_add_heading("Main Hand - %s" % (weapon.display_name if weapon else "empty"))
	if weapon == null:
		_add_text("No weapon equipped.")
	elif weapon.is_ranged:
		var aim := StanceInfo.for_weapon(weapon, 0)
		if aim.is_empty():
			_add_text("Hold RMB to aim. No aim stance is designed for %s yet." % weapon.weapon_type)
		else:
			_add_text("Hold RMB to aim - %s: %s" % [aim["name"], aim["desc"]])
	elif not StanceInfo.MELEE.has(weapon.weapon_type):
		_add_text("No stances are designed for %s yet." % weapon.weapon_type)
	else:
		_add_text("Hold RMB to enter the selected stance. Holding X in combat also switches.")
		var group := ButtonGroup.new()
		for page in 2:
			var info := StanceInfo.for_weapon(weapon, page)
			var button := _make_toggle("Stance %s - %s" % ["A" if page == 0 else "B", info["name"]], group, GameState.stance_page == page)
			button.pressed.connect(_on_stance_page_chosen.bind(page))
			_behaviors_panel.add_child(button)
			_add_text(info["desc"])

	var shield: Shield = _equipment.offhand as Shield if _equipment else null
	_add_heading("Off Hand - %s" % (shield.display_name if shield else "no shield"))
	if shield == null:
		_add_text("Equip a shield to block with right mouse.")
		return
	_add_text("Right mouse with a shield:")
	var row := HBoxContainer.new()
	var rmb := ButtonGroup.new()
	var raise := _make_toggle("Raise Shield", rmb, GameState.shield_on_rmb)
	raise.pressed.connect(func(): GameState.shield_on_rmb = true)
	var stance := _make_toggle("Weapon Stance", rmb, not GameState.shield_on_rmb)
	stance.pressed.connect(func(): GameState.shield_on_rmb = false)
	row.add_child(raise)
	row.add_child(stance)
	_behaviors_panel.add_child(row)
	_add_text("A raised shield stops every hit from the front, but holding it and taking hits drains Composure (the bar under the crosshair). When it runs out your guard breaks and you're stunned for a second.")

func _on_stance_page_chosen(page: int) -> void:
	GameState.stance_page = page
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.weapon_stance.set_stance_page(page as WeaponStance.StancePage)

func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	_behaviors_panel.add_child(label)

func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_behaviors_panel.add_child(label)

func _refresh_weapon_set_label() -> void:
	if _equipment == null or _weapon_set_label == null:
		return
	var set_name := "A" if _equipment.active_weapon_set == 0 else "B"
	_weapon_set_label.text = "Weapon Set: %s (worn)" % set_name

func _on_weapon_set_toggle_pressed() -> void:
	if _equipment == null:
		return
	_equipment.toggle_weapon_set()
	GameState.sync_weapon_sets(_equipment)
	_refresh_doll()
	_refresh_stats()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_equipment = GameState.player_equipment
	if _equipment and not _equipment.equip_failed.is_connected(_on_equip_failed):
		_equipment.equip_failed.connect(_on_equip_failed)
	status_label.text = ""
	_build_inventory_grid()
	_refresh_doll()
	_refresh_stats()

func close() -> void:
	_is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build_inventory_grid() -> void:
	inventory_grid.set_inventory(GameState.inventory)
	(inventory_grid.get_parent() as Control).custom_minimum_size = inventory_grid.custom_minimum_size
	var ammo: Array[String] = []
	for type in Constants.AmmoType.values():
		if type != Constants.AmmoType.ARROW:
			ammo.append("%s %d" % [Constants.AmmoType.keys()[type].capitalize(), AmmoInventory.get_reserve(type)])
	_ammo_label.text = "Ammo: " + "   ".join(ammo)

func _is_equippable(item: Item) -> bool:
	return item.is_equipment()

func _on_entry_clicked(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	status_label.text = ""
	if entry.is_currency():
		status_label.text = "%s is crafting currency." % CurrencyText.name_of(entry.content)
	elif entry.content is Slate:
		status_label.text = "Slates are placed from the Fate Board."
	elif _is_equippable(entry.content):
		_equip_from_inventory(entry)
	elif entry.content is FigmentItem:
		status_label.text = "%s is used at the Reality Engine, not equipped." % entry.content.display_name
	else:
		status_label.text = "%s is used from the Crafting screen (K), not equipped." % entry.content.display_name

## Moves an item from the grid onto the paper doll. Whatever it displaces
## goes back into the grid; if that doesn't fit, the swap is undone.
func _equip_from_inventory(entry: GridInventory.Entry) -> void:
	if _equipment == null:
		return
	var item: Item = entry.content
	var old_position := entry.position
	var before := _equipment.get_all_equipped_items()
	_equipment.equip(item)
	var after := _equipment.get_all_equipped_items()
	if not after.has(item):
		return  # equip_failed already reported why
	GameState.remove_from_inventory(item)

	var stored: Array[Item] = []
	var displaced := before.filter(func(i): return not after.has(i))
	for old in displaced:
		var copy := _inventory_copy(old)
		if GameState.add_to_inventory(copy):
			stored.append(copy)
			continue
		for s in stored:
			GameState.remove_from_inventory(s)
		for d in displaced:
			_equipment.equip(d, true)
		GameState.inventory.place(item, old_position)
		status_label.text = "No room in your inventory for what that would replace."
		break
	_after_equipment_change()

func _on_doll_slot_pressed(row: Dictionary) -> void:
	if _equipment == null:
		return
	var ring_index: int = row.get("ring_index", 0)
	var item := _equipment.get_equipped(row["slot"], ring_index)
	if item == null:
		return
	var copy := _inventory_copy(item)
	if not GameState.add_to_inventory(copy):
		status_label.text = "No room in your inventory."
		return
	_equipment.unequip(row["slot"], ring_index)
	status_label.text = ""
	_after_equipment_change()

## Hand-authored bases are shared load()-cached Resources; the grid gets its
## own copy so crafting it can't change every other reference.
func _inventory_copy(item: Item) -> Item:
	if item.resource_path == "":
		return item
	var copy := item.duplicate(true) as Item
	if copy.tolerance_max == 0:
		CraftingResolver.roll_tolerance(copy)
	return copy

func _after_equipment_change() -> void:
	GameState.sync_equipment(_equipment)
	GameState.sync_weapon_sets(_equipment)
	_refresh_doll()
	_build_inventory_grid()
	_refresh_stats()

func _refresh_doll() -> void:
	if _equipment == null:
		return
	_refresh_weapon_set_label()
	_refresh_behaviors()
	for row in _doll_rows:
		var ring_index: int = row.get("ring_index", 0)
		var equipped: Item = _equipment.get_equipped(row["slot"], ring_index)
		var button: ItemSlotButton = row["button"]
		if equipped:
			_style_slot_button(button, equipped)
		else:
			_style_empty_button(button, row["label"])

func _refresh_stats() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	StatSummaryBuilder.refresh(offense_list, defense_list, misc_list, player)

func _style_slot_button(button: ItemSlotButton, item: Item, count: int = 1) -> void:
	button.text = "%s x%d" % [item.display_name, count] if count > 1 else item.display_name
	if item.icon_path != "":
		button.text = ""  # the icon stands in for the name, as in the grid
	button.tooltip_text = item.display_name  # non-empty just to trigger Godot's tooltip system - ItemCard replaces the actual content
	button.item = item
	button.disabled = false
	_apply_button_color(button, _item_color(item))

func _style_empty_button(button: ItemSlotButton, label: String) -> void:
	button.text = label
	button.tooltip_text = ""
	button.item = null
	_apply_button_color(button, EMPTY_SLOT_COLOR if label != "" else EMPTY_GRID_COLOR)

func _apply_button_color(button: Button, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("disabled", box)
	var text_color := Constants.get_contrasting_text_color(color)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_disabled_color", text_color)

## Patch v3.8b: was weapons-key-off-damage-type, everything else off
## rarity - a Magic-rarity weapon showed its (Lightning-yellow etc.) damage
## color instead of blue. Every item slot now colors off rarity alone,
## matching ItemCard's hover-tooltip border (Ability cards are the sole,
## intentional exception - see ItemCard.gd's own header comment).
func _item_color(item: Item) -> Color:
	return Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)

func _on_equip_failed(reason: String) -> void:
	status_label.text = "Can't equip: %s" % reason
