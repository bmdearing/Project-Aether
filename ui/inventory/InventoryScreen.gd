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
##
## The grid is rearrangeable: dragging a slot onto an EMPTY slot moves it
## to that exact cell, full stop - every other item stays exactly where
## it was (no compacting, no shifting). Dragging onto an OCCUPIED slot
## swaps the two. This needs real per-cell position tracking
## (`_slot_assignment`, keyed per entry - see below) since a plain ordered
## list (which is all GameState.owned_loot ever was) can't represent "my
## armor sits in the far corner with empty cells before it." Position is
## session-local, not persisted (README flagged gap) - GameState.owned_loot
## itself is untouched by dragging, only which grid cell each entry
## RENDERS in. Only real owned_loot entries are draggable - the
## directory-scanned "one of each base" catalog always sits first and
## can't be picked up or targeted, since its scan order isn't something
## the player actually owns to rearrange. Brand stacks (identical Brand
## duplicates - fungible crafting currency, not unique rolled gear) show
## as one slot with a count and drag/drop as a whole group.
##
## Brands and the 3 crafting consumables (data/consumables/) aren't
## equippable - clicking one shows a status message instead of trying to
## equip it (equip_slot on those is a meaningless leftover default, same
## as FigmentItem's own doc comment already notes for Maps).

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

var _is_open: bool = false
var _equipment: EquipmentComponent
var _owned_items: Array[Item] = []
var _doll_rows: Array[Dictionary] = []

## Grid indices >= this are real GameState.owned_loot entries (draggable/
## droppable); below it is the fixed hand-authored catalog. Populated by
## the most recent _build_inventory_grid() call.
var _draggable_start_index: int = 0
## One entry per owned_loot-backed stack from the most recent build -
## {"item": Item, "count": int, "loot_indices": Array[int], "key": String}.
## loot_indices holds every GameState.owned_loot array index this stack
## represents (a Brand stack has more than one; everything else has
## exactly one) - informational only now, not used for ordering.
var _stack_entries: Array[Dictionary] = []
## entry["key"] -> RELATIVE slot index within the real-items region (0 =
## _draggable_start_index's own cell) - relative so the whole region can
## slide as a block if the catalog's shown count changes (equipping/
## unequipping a catalog item) without invalidating every stored position.
## Session-local only - never saved, reset on scene reload.
var _slot_assignment: Dictionary = {}
## slot_index (absolute grid index) -> entry dict, from the most recent
## build - lets _on_item_drag_dropped look up what (if anything) already
## occupies the drop target.
var _entry_at_slot: Dictionary = {}

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
	_scan_owned_items()

## Implementation Brief v3.4 Section 4, user-expanded scope ("Properly
## show which set is being worn in the inventory screen"). The paper-doll's
## own weapon slots (Primary/Sidearm/Offhand) already show whichever set
## is ACTIVE with zero changes needed - EquipmentComponent.get_equipped()
## defaults to the active set - this just adds a label + a toggle button
## next to the doll so the player can tell (and switch) directly from the
## inventory instead of only via the in-game X-tap.
func _build_weapon_set_indicator() -> void:
	var row := HBoxContainer.new()
	_weapon_set_label = Label.new()
	_weapon_set_button = Button.new()
	_weapon_set_button.text = "Swap Weapon Set (X)"
	_weapon_set_button.pressed.connect(_on_weapon_set_toggle_pressed)
	row.add_child(_weapon_set_label)
	row.add_child(_weapon_set_button)
	side_panel.add_child(row)
	side_panel.move_child(row, paper_doll.get_index())

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

## User request (2026-08-30): "let's not add all of the new high level
## items to the player's inventory at the start." Section 25's generator
## (tools/generate_base_types.gd) grew these 4 directories from ~14 hand-
## authored bases to ~867 files (real tiered items up to level 91) - this
## scan's own "as if the player owns one of each hand-authored base" intent
## (a testing convenience predating Section 25) never meant to include
## that whole catalog, just the original small set. base_line_id (empty
## only for the pre-Section-25 hand-authored singles, real for every
## generated tier) is exactly the tag needed to keep the old behavior
## without also keeping up with however large the generated catalog grows.
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
				if item and item.base_line_id == "":
					_owned_items.append(item)
			file_name = dir.get_next()
		dir.list_dir_end()

## Anything currently equipped is excluded - it's shown on the paper-doll,
## not duplicated in the grid too. Catalog entries come first (fixed,
## not draggable), then one cell per owned_loot entry/Brand stack, each
## resolved to its own real grid position (see _resolve_slots()).
func _build_inventory_grid() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
	var equipped: Array[Item] = _equipment.get_all_equipped_items() if _equipment else []
	var shown_catalog: Array[Item] = []
	for item in _owned_items:
		if not equipped.has(item):
			shown_catalog.append(item)
	_stack_entries = _build_stack_entries(equipped)
	_draggable_start_index = shown_catalog.size()
	_entry_at_slot = _resolve_slots()

	var max_slot := _draggable_start_index - 1
	for slot in _entry_at_slot:
		max_slot = max(max_slot, slot)
	var capacity: int = max(GRID_MIN_CAPACITY, max_slot + 1)
	capacity += (GRID_COLUMNS - capacity % GRID_COLUMNS) % GRID_COLUMNS  # round up to a full row

	for i in range(capacity):
		var button := ItemSlotButton.new()
		button.custom_minimum_size = Vector2(64, 64)
		button.clip_text = true
		button.draggable = i >= _draggable_start_index
		button.item_drag_dropped.connect(_on_item_drag_dropped)
		if i < shown_catalog.size():
			var item := shown_catalog[i]
			_style_slot_button(button, item)
			button.pressed.connect(_on_item_selected.bind(item))
		elif _entry_at_slot.has(i):
			var entry: Dictionary = _entry_at_slot[i]
			var item: Item = entry["item"]
			_style_slot_button(button, item, entry["count"])
			if _is_equippable(item):
				button.pressed.connect(_on_item_selected.bind(item))
			else:
				button.pressed.connect(_on_non_equippable_selected.bind(item))
		else:
			_style_empty_button(button, "")
			button.disabled = true
		inventory_grid.add_child(button)

## Brands stack by item_id (identical Brand duplicates are fungible
## crafting currency, not unique rolled gear) - grouped into one entry
## with a count instead of one slot per drop, keyed "brand:<item_id>" so
## every duplicate of the same Brand always merges into that one entry.
## Everything else keys off its own Resource instance id, since item_id
## alone isn't unique per-instance for non-rolled items (e.g. two
## separately-dropped Infusion Stones both have item_id "infusion_stone"
## but must NOT merge into one slot the way Brands do).
func _build_stack_entries(equipped: Array[Item]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var stack_slot_by_key: Dictionary = {}  # key -> index into `entries`
	for i in range(GameState.owned_loot.size()):
		var item: Item = GameState.owned_loot[i]
		if equipped.has(item):
			continue
		var key: String = "brand:%s" % item.item_id if item is Brand else "obj:%d" % item.get_instance_id()
		if stack_slot_by_key.has(key):
			var entry: Dictionary = entries[stack_slot_by_key[key]]
			entry["count"] += 1
			(entry["loot_indices"] as Array).append(i)
		else:
			stack_slot_by_key[key] = entries.size()
			entries.append({"item": item, "count": 1, "loot_indices": [i], "key": key})
	return entries

## Resolves each _stack_entries entry to an absolute grid slot: its
## previously dragged-to position (_slot_assignment, stored relative to
## _draggable_start_index) if that cell is still free, otherwise the
## lowest free cell in entry order - so a never-touched item just fills
## in left-to-right/top-to-bottom like before, and a dragged one stays
## exactly where the player put it. Resolved positions are written back
## to _slot_assignment so an auto-placed item keeps its spot too.
func _resolve_slots() -> Dictionary:
	var slot_for_key: Dictionary = {}
	var claimed: Dictionary = {}
	var unresolved: Array[Dictionary] = []
	for entry in _stack_entries:
		var key: String = entry["key"]
		if _slot_assignment.has(key):
			var slot: int = _draggable_start_index + int(_slot_assignment[key])
			if not claimed.has(slot):
				claimed[slot] = true
				slot_for_key[key] = slot
				continue
		unresolved.append(entry)

	var next_free := _draggable_start_index
	for entry in unresolved:
		while claimed.has(next_free):
			next_free += 1
		claimed[next_free] = true
		slot_for_key[entry["key"]] = next_free
		next_free += 1

	var entry_at_slot: Dictionary = {}
	for entry in _stack_entries:
		var slot: int = slot_for_key[entry["key"]]
		_slot_assignment[entry["key"]] = slot - _draggable_start_index
		entry_at_slot[slot] = entry
	return entry_at_slot

func _is_equippable(item: Item) -> bool:
	return not (item is Brand) and not (item is FigmentItem) and not Constants.CRAFTING_CONSUMABLE_IDS.has(item.item_id)

func _on_item_selected(item: Item) -> void:
	if _equipment == null:
		return
	status_label.text = ""
	_equipment.equip(item)
	GameState.sync_equipment(_equipment)
	GameState.sync_weapon_sets(_equipment)
	_refresh_doll()
	_build_inventory_grid()
	_refresh_stats()

func _on_non_equippable_selected(item: Item) -> void:
	if item is FigmentItem:
		status_label.text = "%s is used at the Reality Engine, not equipped." % item.display_name
	else:
		status_label.text = "%s is used from the Crafting screen (K), not equipped." % item.display_name

## Dropping on an EMPTY cell moves the dragged stack there and nothing
## else - no compacting, no shifting (the bug report this fixes: dropping
## on empty space was instead appending to the end of a dense list,
## dragging every later item along with it). Dropping on an OCCUPIED cell
## swaps the two. Only ever touches _slot_assignment (a session-local
## rendering position) - GameState.owned_loot itself is never reordered,
## so nothing here can perturb equipped-item bookkeeping or the save data.
func _on_item_drag_dropped(source_grid_index: int, target_grid_index: int) -> void:
	if source_grid_index == target_grid_index or source_grid_index < _draggable_start_index:
		return
	if not _entry_at_slot.has(source_grid_index):
		return
	var source_key: String = _entry_at_slot[source_grid_index]["key"]
	var target_entry: Dictionary = _entry_at_slot.get(target_grid_index, {})

	_slot_assignment[source_key] = target_grid_index - _draggable_start_index
	if not target_entry.is_empty():
		_slot_assignment[target_entry["key"]] = source_grid_index - _draggable_start_index

	_build_inventory_grid()

func _on_doll_slot_pressed(row: Dictionary) -> void:
	if _equipment == null:
		return
	var ring_index: int = row.get("ring_index", 0)
	_equipment.unequip(row["slot"], ring_index)
	GameState.sync_equipment(_equipment)
	GameState.sync_weapon_sets(_equipment)
	status_label.text = ""
	_refresh_doll()
	_build_inventory_grid()
	_refresh_stats()

func _refresh_doll() -> void:
	if _equipment == null:
		return
	_refresh_weapon_set_label()
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
