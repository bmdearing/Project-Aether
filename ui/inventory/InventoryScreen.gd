extends CanvasLayer
class_name InventoryScreen
## Footprint-grid inventory (GameState.inventory, see GridInventory) +
## paper-doll equipment diagram + a stats column shown with C (StatSummaryBuilder,
## shared with CharacterScreen). Right-clicking an item equips it; clicking a
## paper-doll slot unequips into the grid if there's room. Crafting happens
## here too: right-click a Brand to activate it, right-click an Orb/Edict/
## stone to pick it up, then click the item to use it on. Equipped items
## live on EquipmentComponent, not in the grid. Doesn't pause the game.

const EMPTY_SLOT_COLOR := Color(0.55, 0.45, 0.28, 0.5)
const EMPTY_GRID_COLOR := Color(0.55, 0.45, 0.28, 0.3)
## Pixels between paper doll slots. Each doll row's "cells" places its slot
## in inventory cells (x, y, wide, tall), laid out like Path of Exile: weapons
## flank the body column and every slot is its item's footprint.
const DOLL_GAP := 4

@onready var offense_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/OffenseList
@onready var defense_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/DefenseList
@onready var misc_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/MiscList
@onready var inventory_grid: InventoryGridView = $HBox/SidePanel/InventoryPanel/InventoryScroll/InventoryGrid
@onready var inventory_panel: VBoxContainer = $HBox/SidePanel/InventoryPanel
@onready var status_label: Label = $HBox/SidePanel/StatusLabel
@onready var close_button: Button = $HBox/SidePanel/CloseButton
@onready var stats_panel: VBoxContainer = $HBox/StatsPanel
@onready var hint_label: Label = $HBox/SidePanel/HintLabel

@onready var slot_primary_weapon: ItemSlotButton = $HBox/SidePanel/PaperDoll/PrimaryWeapon
@onready var slot_ring_left: ItemSlotButton = $HBox/SidePanel/PaperDoll/RingLeft
@onready var slot_helmet: ItemSlotButton = $HBox/SidePanel/PaperDoll/Helmet
@onready var slot_amulet: ItemSlotButton = $HBox/SidePanel/PaperDoll/Amulet
@onready var slot_body_armour: ItemSlotButton = $HBox/SidePanel/PaperDoll/BodyArmour
@onready var slot_belt: ItemSlotButton = $HBox/SidePanel/PaperDoll/Belt
@onready var slot_gloves: ItemSlotButton = $HBox/SidePanel/PaperDoll/Gloves
@onready var slot_boots: ItemSlotButton = $HBox/SidePanel/PaperDoll/Boots
@onready var slot_offhand: ItemSlotButton = $HBox/SidePanel/PaperDoll/Offhand
@onready var slot_ring_right: ItemSlotButton = $HBox/SidePanel/PaperDoll/RingRight

@onready var side_panel: VBoxContainer = $HBox/SidePanel
@onready var paper_doll: Control = $HBox/SidePanel/PaperDoll
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

## Currency picked up with right-click; the next item clicked receives it.
var _armed: StringName = &""
var _resolver: CraftingResolver
var _active_brands: ActiveBrands
## A jewel picked up from the grid, waiting to be clicked into a socket.
var _held_jewel: Jewel
const ARMED_BORDER := Color(1.0, 0.82, 0.3)
const ACTIVE_BRAND_BORDER := Color(0.95, 0.15, 0.15)
const PREVIEW_LINES := 5
const HINT := "Right-click an item to equip it; click an equipped slot to unequip. Right-click a Brand to activate it, or an Orb, Edict or stone to pick it up, then click an item to use it. Right-click a Jewel to pick it up, then click an item to socket it - socketing is permanent. C shows stats. Hold Alt over an item for details."

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("inventory_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)
	_doll_rows = [
		{"button": slot_helmet, "slot": Constants.EquipmentSlot.HELMET, "label": "Helmet", "cells": Rect2i(3, 0, 2, 2), "ghost": &"helmet"},
		{"button": slot_body_armour, "slot": Constants.EquipmentSlot.BODY_ARMOUR, "label": "Body Armour", "cells": Rect2i(3, 2, 2, 3), "ghost": &"body_armour"},
		{"button": slot_gloves, "slot": Constants.EquipmentSlot.GLOVES, "label": "Gloves", "cells": Rect2i(1, 4, 2, 2), "ghost": &"gloves"},
		{"button": slot_boots, "slot": Constants.EquipmentSlot.BOOTS, "label": "Boots", "cells": Rect2i(5, 4, 2, 2), "ghost": &"boots"},
		{"button": slot_primary_weapon, "slot": Constants.EquipmentSlot.PRIMARY_WEAPON, "label": "Primary Weapon", "cells": Rect2i(0, 0, 2, 4), "ghost": &"shortsword"},
		{"button": slot_offhand, "slot": Constants.EquipmentSlot.OFFHAND, "label": "Offhand", "cells": Rect2i(6, 0, 2, 4), "ghost": &"kite_shield"},
		{"button": slot_amulet, "slot": Constants.EquipmentSlot.AMULET, "label": "Amulet", "cells": Rect2i(5, 2, 1, 1), "ghost": &"amulet"},
		{"button": slot_belt, "slot": Constants.EquipmentSlot.BELT, "label": "Belt", "cells": Rect2i(3, 5, 2, 1), "ghost": &"belt"},
		{"button": slot_ring_left, "slot": Constants.EquipmentSlot.RING, "ring_index": 0, "label": "Ring 1", "cells": Rect2i(2, 3, 1, 1), "ghost": &"ring"},
		{"button": slot_ring_right, "slot": Constants.EquipmentSlot.RING, "ring_index": 1, "label": "Ring 2", "cells": Rect2i(5, 3, 1, 1), "ghost": &"ring"},
	]
	for row in _doll_rows:
		(row["button"] as ItemSlotButton).pressed.connect(_on_doll_slot_pressed.bind(row))
		(row["button"] as ItemSlotButton).gui_input.connect(_on_doll_slot_input.bind(row))
	inventory_grid.cell_size = 52
	_layout_doll()
	_build_weapon_set_indicator()
	_build_behaviors_panel()
	inventory_grid.entry_clicked.connect(_on_entry_clicked)
	inventory_grid.entry_right_clicked.connect(_on_entry_right_clicked)
	inventory_grid.entry_hovered.connect(_on_entry_hovered)
	inventory_grid.highlight = _highlight_for
	inventory_grid.currency_hint = _hint_for
	hint_label.text = HINT
	stats_panel.visible = false
	inventory_grid.drop_failed.connect(func(): status_label.text = "That doesn't fit there.")
	_ammo_label = Label.new()
	inventory_panel.add_child(_ammo_label)

## Sizes the doll slots from inventory cells so equipped icons match the grid.
func _layout_doll() -> void:
	var pitch := inventory_grid.cell_size + DOLL_GAP
	var extent := Vector2i.ZERO
	for row in _doll_rows:
		var cells: Rect2i = row["cells"]
		var button: ItemSlotButton = row["button"]
		button.position = Vector2(cells.position * pitch)
		button.size = Vector2(cells.size * pitch - Vector2i(DOLL_GAP, DOLL_GAP))
		button.ghost_key = row["ghost"]
		extent = extent.max(cells.end)
	paper_doll.custom_minimum_size = Vector2(extent * pitch - Vector2i(DOLL_GAP, DOLL_GAP))

## Label and toggle showing which weapon set is active.
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
	elif weapon.is_conduit:
		_add_conduit_text(weapon, "Hold RMB (Stance A)")
	elif weapon.is_ranged and StanceInfo.RANGED_B.has(weapon.weapon_type):
		_add_text("Hold RMB to aim with the selected stance. Holding X in combat also switches.")
		_add_page_choices(weapon)
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
		_add_page_choices(weapon)

	var off_conduit: Weapon = _equipment.offhand as Weapon if _equipment else null
	if off_conduit and off_conduit.is_conduit:
		_add_heading("Off Hand - %s" % off_conduit.display_name)
		_add_conduit_text(off_conduit, "Hold X to switch to Stance B, then hold RMB")
		return
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

func _add_page_choices(weapon: Weapon) -> void:
	var group := ButtonGroup.new()
	for page in 2:
		var info := StanceInfo.for_weapon(weapon, page)
		var button := _make_toggle("Stance %s - %s" % ["A" if page == 0 else "B", info["name"]], group, GameState.stance_page == page)
		button.pressed.connect(_on_stance_page_chosen.bind(page))
		_behaviors_panel.add_child(button)
		_add_text(info["desc"])

func _add_conduit_text(conduit: Weapon, how: String) -> void:
	var info := StanceInfo.for_conduit(conduit)
	if info.is_empty():
		_add_text("No stance is designed for this conduit yet.")
	elif conduit.conduit_stance_type == "passive":
		_add_text("%s: %s" % [info["name"], info["desc"]])
	else:
		_add_text("%s - %s: %s" % [how, info["name"], info["desc"]])

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

func open(show_stats: bool = false) -> void:
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_equipment = GameState.player_equipment
	if _equipment and not _equipment.equip_failed.is_connected(_on_equip_failed):
		_equipment.equip_failed.connect(_on_equip_failed)
	_resolver = CraftingResolver.create_default()
	_resolver.currency = GameState.inventory
	if _active_brands == null or _active_brands.carried != GameState.inventory:
		_active_brands = ActiveBrands.new(GameState.inventory)
	_held_jewel = null
	_armed = &""
	stats_panel.visible = show_stats
	status_label.text = ""
	_build_inventory_grid()
	_refresh_doll()
	_refresh_stats()

func close() -> void:
	_is_open = false
	visible = false
	_armed = &""
	_held_jewel = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## C while the inventory is open: stats column on the left, grid on the right.
func toggle_stats() -> void:
	stats_panel.visible = not stats_panel.visible
	_refresh_stats()

func is_showing_stats() -> bool:
	return stats_panel.visible

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _armed != &"":
			_disarm()
		elif _held_jewel:
			_release_jewel()
		else:
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

## Left click: uses the picked-up currency on the item; otherwise nothing
## (drag to move).
func _on_entry_clicked(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	if _armed != &"" and not entry.is_currency():
		_use_armed_on(entry.content)
	elif _held_jewel and not entry.is_currency() and entry.content != _held_jewel:
		_socket_into(entry.content)

func _on_entry_right_clicked(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	status_label.text = ""
	if entry.is_currency():
		_on_currency_right_clicked(entry.content)
	elif _armed != &"":
		_use_armed_on(entry.content)
	elif entry.content is Jewel:
		_toggle_held_jewel(entry.content)
	elif _held_jewel:
		_socket_into(entry.content)
	elif entry.content is Slate and Input.is_key_pressed(KEY_CTRL) and not (entry.content as Slate).lenses.is_empty():
		_take_lenses_out(entry.content)
	elif entry.content is Slate:
		status_label.text = "Slates are placed from the Fate Board. Ctrl+right-click one to take its Lenses out."
	elif entry.content is FigmentItem:
		_empower_figment(entry.content)
	elif _is_equippable(entry.content):
		_equip_from_inventory(entry)
	else:
		status_label.text = "%s can't be equipped." % entry.content.display_name

## ---- Jewels ---------------------------------------------------------

func _toggle_held_jewel(jewel: Jewel) -> void:
	if _held_jewel == jewel:
		_release_jewel()
		return
	_armed = &""
	_held_jewel = jewel
	status_label.text = "Click an item with a free socket to set the Jewel. Esc or right-click it again to put it back."
	inventory_grid.refresh()

func _release_jewel() -> void:
	_held_jewel = null
	status_label.text = ""
	inventory_grid.refresh()

func _socket_into(target: Resource) -> void:
	var jewel := _held_jewel
	if jewel is Lens:
		_lens_into(jewel as Lens, target)
		return
	if not (target is Item) or not target.is_equipment():
		status_label.text = "Jewels go into the sockets of gear."
		return
	var item := target as Item
	if item.resource_path != "":
		status_label.text = "Unequip this item first to socket it."
		return
	if item.free_sockets() <= 0:
		status_label.text = "%s has no free socket." % item.display_name if item.sockets > 0 else "%s has no sockets." % item.display_name
		return
	GameState.remove_from_inventory(jewel)
	item.socketed.append(jewel)
	_held_jewel = null
	status_label.text = "Jewel set into %s." % item.display_name
	_after_socket_change(item)

## A Lens goes into a Slate's free socket (in the grid; placed Slates come
## off the board first).
func _lens_into(lens: Lens, target: Resource) -> void:
	if not target is Slate:
		status_label.text = "Lenses go into the sockets of Slates."
		return
	var slate := target as Slate
	if slate.free_sockets() <= 0:
		status_label.text = "%s has no free socket." % slate.display_name if slate.sockets > 0 else "%s has no sockets." % slate.display_name
		return
	GameState.remove_from_inventory(lens)
	slate.lenses.append(lens)
	_held_jewel = null
	status_label.text = "Lens set into %s." % slate.display_name
	_build_inventory_grid()

## Lenses come out freely, back into the grid as far as room allows.
func _take_lenses_out(slate: Slate) -> void:
	var moved := 0
	for lens in slate.lenses.duplicate():
		if not GameState.add_to_inventory(lens):
			break
		slate.lenses.erase(lens)
		moved += 1
	status_label.text = "Took %d Lens%s out of %s." % [moved, "" if moved == 1 else "es", slate.display_name]
	if not slate.lenses.is_empty():
		status_label.text += " No room for the rest."
	_build_inventory_grid()

func _after_socket_change(item: Item) -> void:
	EventBus.item_sockets_changed.emit(item)
	if _equipment and _equipment.get_all_equipped_items().has(item):
		_equipment.equipment_changed.emit()
		_after_equipment_change()
	else:
		_build_inventory_grid()

## ---- Crafting -------------------------------------------------------

func _is_brand(id: StringName) -> bool:
	return _resolver != null and _resolver.brand_defs.has(id)

func _is_usable_currency(id: StringName) -> bool:
	return Constants.ORB_IDS.has(id) or (_resolver != null and _resolver.edict_defs.has(id)) or Constants.CRAFTING_CONSUMABLE_IDS.has(String(id))

func _on_currency_right_clicked(id: StringName) -> void:
	if _is_brand(id):
		if _active_brands.is_active(id):
			_active_brands.deactivate(id)
			status_label.text = "%s deactivated." % CurrencyText.name_of(id)
		elif _active_brands.activate(id):
			status_label.text = "%s active - it applies to your next Orb." % CurrencyText.name_of(id)
	elif _is_usable_currency(id):
		if _armed == id:
			_disarm()
			return
		_held_jewel = null
		_armed = id
		status_label.text = "Click an item to use %s on it. Esc or right-click it again to put it back." % CurrencyText.name_of(id)
	else:
		status_label.text = CurrencyText.description_of(id)
	inventory_grid.refresh()

func _disarm() -> void:
	_armed = &""
	status_label.text = ""
	inventory_grid.refresh()

func _highlight_for(entry: GridInventory.Entry) -> Color:
	if _held_jewel and entry.content == _held_jewel:
		return ARMED_BORDER
	if not entry.is_currency():
		return Color.TRANSPARENT
	if entry.content == _armed:
		return ARMED_BORDER
	if _active_brands and _active_brands.is_active(entry.content):
		return ACTIVE_BRAND_BORDER
	return Color.TRANSPARENT

func _hint_for(entry: GridInventory.Entry) -> String:
	var id: StringName = entry.content
	if _is_brand(id):
		return "Active - right-click to deactivate." if _active_brands.is_active(id) else "Right-click to activate for your next Orb."
	if _is_usable_currency(id):
		return "Right-click to pick up, then click an item to use it."
	return ""

## Uses the picked-up Orb/Edict/stone on target (a grid or equipped item).
func _use_armed_on(target: Resource) -> void:
	var id := _armed
	if not (target is Item or target is Slate) or target is FigmentItem:
		status_label.text = "%s can't be used on that." % CurrencyText.name_of(id)
		return
	if target.resource_path != "":
		status_label.text = "Unequip this item first to craft on it."
		return
	if Constants.ORB_IDS.has(id):
		var result := _resolver.apply(target, id, _active_brands)
		status_label.text = _describe_craft(id, result) if result.success else result.get_message()
	elif _resolver.edict_defs.has(id):
		var result := _resolver.apply_edict(target, id)
		status_label.text = "%s applied." % CurrencyText.name_of(id) if result.success else result.get_message()
	else:
		var outcome := _use_stone(id, target)
		status_label.text = outcome["message"]
		if outcome["success"]:
			GameState.inventory.remove_currency(id)
	if GameState.inventory.count_of(id) <= 0:
		_armed = &""
	_after_craft(target)

func _describe_craft(id: StringName, result: CraftResult) -> String:
	var parts: Array[String] = ["%s used." % CurrencyText.name_of(id)]
	for a in result.removed:
		parts.append("Removed: " + a.description)
	for a in result.added:
		parts.append("Added: " + a.description)
	if result.anchored:
		parts.append("Anchored: " + result.anchored.description)
	if result.quality_gained > 0:
		parts.append("+%d quality" % result.quality_gained)
	if result.sockets_rolled_to >= 0:
		parts.append("Sockets: %d" % result.sockets_rolled_to)
	return "  ".join(parts)

func _use_stone(id: StringName, target: Resource) -> Dictionary:
	match String(id):
		"infusion_stone":
			return CraftingSystem.infuse(target) if target is Weapon else {"success": false, "message": "Infusion Stone only works on weapons."}
		"shrivening_stone":
			return CraftingSystem.shrive(target) if target is Weapon else {"success": false, "message": "Shrivening Stone only works on weapons."}
		"shard_of_tharsis":
			if not target is Item:
				return {"success": false, "message": "The Shard only corrupts gear."}
			var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
			return CraftingSystem.corrupt(target, power_level)
	return {"success": false, "message": "That can't be used here."}

## Hovering an item with an Orb picked up previews the outcomes.
func _on_entry_hovered(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	if _armed == &"" or entry.is_currency() or not Constants.ORB_IDS.has(_armed):
		return
	if not (entry.content is Item or entry.content is Slate) or entry.content is FigmentItem:
		return
	status_label.text = _preview_text(entry.content)

func _preview_text(target: Resource) -> String:
	var p := _resolver.preview(target, _armed, _active_brands)
	var orb_name := CurrencyText.name_of(_armed)
	if not p.is_valid():
		return "%s: %s" % [orb_name, CurrencyText.error_message(CraftResult.error_name(p.error))]
	var lines: Array[String] = [orb_name + ": " + CurrencyText.description_of(_armed)]
	if not p.applied_brands.is_empty():
		lines.append("Brands used: " + ", ".join(p.applied_brands.map(func(b): return CurrencyText.name_of(b))))
	var outcomes := p.outcomes.duplicate()
	outcomes.sort_custom(func(a, b): return a["probability"] > b["probability"])
	var shown: Array[String] = []
	for o in outcomes.slice(0, PREVIEW_LINES):
		var text: String = o["def"].text if o["def"].text != "" else String(o["def"].id)
		shown.append("%s (%.0f%%)" % [text.replace("%d", "X").replace("%%", "%"), o["probability"] * 100.0])
	if not shown.is_empty():
		lines.append("Likely: " + ", ".join(shown) + (" ..." if outcomes.size() > PREVIEW_LINES else ""))
	return "\n".join(lines)

func _empower_figment(figment: FigmentItem) -> void:
	if GameState.gold < CraftingSystem.EMPOWER_FIGMENT_GOLD_COST:
		status_label.text = "Empowering a Figment costs %d Gold." % CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
		return
	var result := CraftingSystem.empower_figment(figment)
	if result["success"]:
		GameState.gold -= CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
	status_label.text = result["message"]
	_build_inventory_grid()

func _after_craft(target: Resource) -> void:
	if _equipment and _equipment.get_all_equipped_items().has(target):
		_equipment.equipment_changed.emit()
	_build_inventory_grid()
	_refresh_doll()
	_refresh_stats()

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

func _on_doll_slot_input(event: InputEvent, row: Dictionary) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var item := _equipment.get_equipped(row["slot"], row.get("ring_index", 0)) if _equipment else null
	if item == null:
		return
	if _armed != &"":
		_use_armed_on(item)
	elif _held_jewel:
		_socket_into(item)

func _on_doll_slot_pressed(row: Dictionary) -> void:
	if _equipment == null:
		return
	var ring_index: int = row.get("ring_index", 0)
	var item := _equipment.get_equipped(row["slot"], ring_index)
	if item == null:
		return
	if _armed != &"":
		_use_armed_on(item)
		return
	if _held_jewel:
		_socket_into(item)
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

func _style_slot_button(button: ItemSlotButton, item: Item) -> void:
	button.text = ""
	button.tooltip_text = item.display_name  # non-empty just to trigger Godot's tooltip system - ItemCard replaces the actual content
	button.item = item
	button.disabled = false
	_apply_button_color(button, _item_color(item))

func _style_empty_button(button: ItemSlotButton, label: String) -> void:
	button.text = ""
	button.tooltip_text = label
	button.item = null
	_apply_button_color(button, EMPTY_SLOT_COLOR if label != "" else EMPTY_GRID_COLOR)

func _apply_button_color(button: Button, color: Color) -> void:
	AetherStyle.style_slot_button(button, color)
	if color == EMPTY_SLOT_COLOR or color == EMPTY_GRID_COLOR:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			button.add_theme_color_override(state, AetherStyle.TEXT_DIM)

## Rarity color, matching ItemCard's border.
func _item_color(item: Item) -> Color:
	return Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)

func _on_equip_failed(reason: String) -> void:
	status_label.text = "Can't equip: %s" % reason
