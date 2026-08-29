extends CanvasLayer
class_name InventoryScreen
## Slot-based grid inventory (uniform 1x1 cells, not the Tetris Satchel -
## see README) + paper-doll equipment diagram + a live stats column
## (StatSummaryBuilder, shared with CharacterScreen) so equipping
## something visibly changes stats in place. Placeholder-art: every slot
## is a colored square, not an icon - hovering shows a stat card
## (ItemSlotButton), holding Alt shows an advanced one (AdvancedTooltip).
##
## "Owned" items are directory-scanned from data/{armor,shields,weapons,
## items}/instances/ once at _ready() (as if the player owns one of
## each hand-authored base) plus GameState.owned_loot (real rolled
## drops), rebuilt every time this screen opens since loot can arrive
## mid-session. Anything currently equipped is excluded from the grid -
## it shows on the paper-doll instead, not in both places.

const ITEM_INSTANCE_DIRS := [
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/weapons/instances/",
	"res://data/items/instances/",
]

const GRID_COLUMNS := 5
const GRID_MIN_CAPACITY := 35  # pads with empty cells so it reads as a real inventory, not an exact-fit list

const EMPTY_SLOT_COLOR := Color(0.25, 0.25, 0.28)
const EMPTY_GRID_COLOR := Color(0.2, 0.2, 0.22)

@onready var offense_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/OffenseList
@onready var defense_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/DefenseList
@onready var misc_list: VBoxContainer = $HBox/StatsPanel/StatsScroll/StatsList/MiscList
@onready var inventory_grid: GridContainer = $HBox/InventoryPanel/InventoryScroll/InventoryGrid
@onready var status_label: Label = $HBox/SidePanel/StatusLabel
@onready var close_button: Button = $HBox/SidePanel/CloseButton

@onready var slot_primary_weapon: ItemSlotButton = $HBox/SidePanel/PaperDoll/LeftColumn/PrimaryWeapon
@onready var slot_ring_tl: ItemSlotButton = $HBox/SidePanel/PaperDoll/LeftColumn/RingTopLeft
@onready var slot_ring_bl: ItemSlotButton = $HBox/SidePanel/PaperDoll/LeftColumn/RingBottomLeft
@onready var slot_sidearm: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/ExtraRow/Sidearm
@onready var slot_conduit: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/ExtraRow/Conduit
@onready var slot_secondary: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/ExtraRow/Secondary
@onready var slot_helmet: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/Helmet
@onready var slot_amulet: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/Amulet
@onready var slot_body_armour: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/BodyArmour
@onready var slot_belt: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/Belt
@onready var slot_gloves: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/BottomRow/Gloves
@onready var slot_boots: ItemSlotButton = $HBox/SidePanel/PaperDoll/CenterColumn/BottomRow/Boots
@onready var slot_offhand: ItemSlotButton = $HBox/SidePanel/PaperDoll/RightColumn/Offhand
@onready var slot_ring_tr: ItemSlotButton = $HBox/SidePanel/PaperDoll/RightColumn/RingTopRight
@onready var slot_ring_br: ItemSlotButton = $HBox/SidePanel/PaperDoll/RightColumn/RingBottomRight

var _is_open: bool = false
var _equipment: EquipmentComponent
var _owned_items: Array[Item] = []
var _doll_rows: Array[Dictionary] = []

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
		{"button": slot_sidearm, "slot": Constants.EquipmentSlot.SIDEARM_WEAPON, "label": "Sidearm"},
		{"button": slot_offhand, "slot": Constants.EquipmentSlot.OFFHAND, "label": "Offhand"},
		{"button": slot_conduit, "slot": Constants.EquipmentSlot.CONDUIT, "label": "Conduit"},
		{"button": slot_secondary, "slot": Constants.EquipmentSlot.SECONDARY_THROWABLE, "label": "Secondary"},
		{"button": slot_amulet, "slot": Constants.EquipmentSlot.AMULET, "label": "Amulet"},
		{"button": slot_belt, "slot": Constants.EquipmentSlot.BELT, "label": "Belt"},
		{"button": slot_ring_tl, "slot": Constants.EquipmentSlot.RING, "ring_index": 0, "label": "Ring 1"},
		{"button": slot_ring_bl, "slot": Constants.EquipmentSlot.RING, "ring_index": 1, "label": "Ring 2"},
		{"button": slot_ring_tr, "slot": Constants.EquipmentSlot.RING, "ring_index": 2, "label": "Ring 3"},
		{"button": slot_ring_br, "slot": Constants.EquipmentSlot.RING, "ring_index": 3, "label": "Ring 4"},
	]
	for row in _doll_rows:
		(row["button"] as ItemSlotButton).pressed.connect(_on_doll_slot_pressed.bind(row))
	_scan_owned_items()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
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
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _scan_owned_items() -> void:
	for dir_path in ITEM_INSTANCE_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var item: Item = load(dir_path + file_name) as Item
				if item:
					_owned_items.append(item)
			file_name = dir.get_next()
		dir.list_dir_end()

## Anything currently equipped is excluded - it's shown on the paper-doll,
## not duplicated in the grid too.
func _build_inventory_grid() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
	var equipped: Array[Item] = _equipment.get_all_equipped_items() if _equipment else []
	var all_items: Array[Item] = []
	for item in _owned_items + GameState.owned_loot:
		if not equipped.has(item):
			all_items.append(item)
	var capacity: int = max(GRID_MIN_CAPACITY, all_items.size())
	capacity += (GRID_COLUMNS - capacity % GRID_COLUMNS) % GRID_COLUMNS  # round up to a full row
	for i in range(capacity):
		var button := ItemSlotButton.new()
		button.custom_minimum_size = Vector2(64, 64)
		button.clip_text = true
		if i < all_items.size():
			var item := all_items[i]
			_style_slot_button(button, item)
			button.pressed.connect(_on_item_selected.bind(item))
		else:
			_style_empty_button(button, "")
			button.disabled = true
		inventory_grid.add_child(button)

func _on_item_selected(item: Item) -> void:
	if _equipment == null:
		return
	status_label.text = ""
	_equipment.equip(item)
	GameState.sync_equipment(_equipment)
	_refresh_doll()
	_build_inventory_grid()
	_refresh_stats()

func _on_doll_slot_pressed(row: Dictionary) -> void:
	if _equipment == null:
		return
	var ring_index: int = row.get("ring_index", 0)
	_equipment.unequip(row["slot"], ring_index)
	GameState.sync_equipment(_equipment)
	status_label.text = ""
	_refresh_doll()
	_build_inventory_grid()
	_refresh_stats()

func _refresh_doll() -> void:
	if _equipment == null:
		return
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
	button.text = item.display_name
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

## Weapons key off damage type; everything else off rarity.
func _item_color(item: Item) -> Color:
	if item is Weapon:
		var weapon := item as Weapon
		var dtype: int = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
		return Constants.DAMAGE_TYPE_COLOR.get(dtype, Color.WHITE)
	return Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)

func _on_equip_failed(reason: String) -> void:
	status_label.text = "Can't equip: %s" % reason
