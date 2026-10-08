extends CanvasLayer
class_name FateBoardEditor
## Fate Board placement UI. Renders GameState.fate_board's live
## placements/Aether budget via FateBoardGrid, and recomputes
## ChainCalculator results after every placement/removal.
##
## Palette = Slates in the carried inventory. Placing one moves it out of the
## inventory onto the board; removing it puts it back (if there's room).

const SLATE_INSTANCES_DIR := "res://data/slates/instances/"
const ABILITY_INSTANCE_DIR := "res://data/abilities/instances/"

@onready var grid: FateBoardGrid = $HBox/GridScroll/FateBoardGrid
@onready var palette_list: VBoxContainer = $HBox/SidePanel/PaletteScroll/PaletteList
@onready var aether_label: Label = $HBox/SidePanel/AetherLabel
@onready var selected_label: Label = $HBox/SidePanel/SelectedLabel
@onready var chain_label: Label = $HBox/SidePanel/ChainLabel
@onready var status_label: Label = $HBox/SidePanel/StatusLabel
@onready var designate_option: OptionButton = $HBox/SidePanel/DesignateOption
@onready var close_button: Button = $HBox/SidePanel/CloseButton

var _is_open: bool = false
var _board: FateBoard
var _selected_slate: Slate
var _rotation_steps: int = 0
var _flipped: bool = false
## Section 10 Unique "The Unbound Chorus": which owned Ability the
## currently-selected Spell Slate will bind to on placement - populated by
## _refresh_designate_options(), read at the moment of a successful click
## placement, then cleared. "" means none chosen yet (blocks placement for
## a Slate with requires_spell_designation).
var _pending_designated_ability_id: String = ""
var _designate_ability_ids: Array[String] = []

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("fate_board_editor")
	add_to_group("blocking_menu")
	grid.cell_clicked.connect(_on_cell_clicked)
	grid.drop_requested.connect(_on_drop_requested)
	close_button.pressed.connect(close)
	designate_option.item_selected.connect(_on_designate_option_selected)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_board = GameState.fate_board
	if _board and not _board.placement_failed.is_connected(_on_placement_failed):
		_board.placement_failed.connect(_on_placement_failed)
	grid.set_board(_board)
	grid.center_on_anchor()
	_populate_palette()
	_refresh_aether()
	_refresh_chains()

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
	elif event.is_action_pressed("fate_board_rotate"):
		_rotation_steps = (_rotation_steps + 1) % 4
		grid.set_pending(_selected_slate, _rotation_steps, _flipped)
	elif event.is_action_pressed("fate_board_flip"):
		_flipped = not _flipped
		grid.set_pending(_selected_slate, _rotation_steps, _flipped)

func _populate_palette() -> void:
	for child in palette_list.get_children():
		child.queue_free()
	for content in GameState.get_inventory_items():
		if content is Slate:
			_add_palette_entry(content)

func _add_palette_entry(slate: Slate) -> void:
	var tag_name: String = slate.category_tag_override if slate.category_tag_override != "" else Constants.DAMAGE_TYPE_NAME.get(slate.tag, "?")
	var button := ItemSlotButton.new()
	button.text = "%s (%d tiles, %d Aether, %s)" % [slate.display_name, slate.get_size(), slate.aether_cost, tag_name]
	button.tooltip_text = slate.display_name  # non-empty just to trigger Godot's tooltip system - ItemCard replaces the actual content
	button.slate = slate
	button.pressed.connect(_on_palette_selected.bind(slate))
	palette_list.add_child(button)

func _on_palette_selected(slate: Slate) -> void:
	_selected_slate = slate
	_rotation_steps = 0
	_flipped = false
	grid.set_pending(slate, 0, false)
	status_label.text = ""
	var lines := PackedStringArray()
	lines.append(slate.display_name)
	for m in slate.modifiers:
		lines.append("- " + m.description)
	selected_label.text = "\n".join(lines)
	_refresh_designate_options(slate)

## Section 10 Unique "The Unbound Chorus": "Designate one Spell skill" -
## any owned Ability (not just what's in the 4-slot hotbar; the whole
## point of a Slate-granted cast is it doesn't cost a hotbar slot), scanned
## the same way AbilitiesScreen._scan_owned_abilities() already does.
func _refresh_designate_options(slate: Slate) -> void:
	designate_option.clear()
	_designate_ability_ids = []
	_pending_designated_ability_id = ""
	if slate == null or not slate.requires_spell_designation:
		designate_option.visible = false
		return
	designate_option.visible = true
	designate_option.add_item("- Choose a spell to designate -")
	_designate_ability_ids.append("")
	var dir := DirAccess.open(ABILITY_INSTANCE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next().trim_suffix(".remap")
		while file_name != "":
			if file_name.ends_with(".tres"):
				var ability: Ability = load(ABILITY_INSTANCE_DIR + file_name) as Ability
				if ability and GameState.owned_ability_ids.has(ability.ability_id):
					designate_option.add_item(ability.display_name)
					_designate_ability_ids.append(ability.ability_id)
			file_name = dir.get_next().trim_suffix(".remap")
		dir.list_dir_end()
	designate_option.select(0)

func _on_designate_option_selected(index: int) -> void:
	_pending_designated_ability_id = _designate_ability_ids[index] if index >= 0 and index < _designate_ability_ids.size() else ""

func _on_drop_requested() -> void:
	_selected_slate = null
	grid.set_pending(null, 0, false)
	selected_label.text = ""
	status_label.text = ""
	designate_option.visible = false

func _on_cell_clicked(cell: Vector2i, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_RIGHT or _selected_slate == null:
		var occupied := _board.get_occupied_cells()
		if occupied.has(cell):
			var removed: Slate = _board.placements[occupied[cell]].slate
			if removed.resource_path != "":
				removed = removed.duplicate(true)
			if not GameState.add_to_inventory(removed):
				status_label.text = "No room in your inventory for that Slate."
				return
			_board.remove_slate(occupied[cell])
			grid.mark_cells_dirty()
			grid.queue_redraw()
			_refresh_aether()
			_refresh_chains()
			_populate_palette()
		return

	if button_index == MOUSE_BUTTON_LEFT:
		if not _is_slate_available(_selected_slate):
			status_label.text = "You don't have another one of those to place."
			return
		var designated_ability_id := ""
		if _selected_slate.requires_spell_designation:
			designated_ability_id = _pending_designated_ability_id
			if designated_ability_id == "":
				status_label.text = "Pick a spell to designate first (side panel)."
				return
		var id := _board.place_slate(_selected_slate, cell, _rotation_steps, _flipped, designated_ability_id)
		if id != "":
			GameState.remove_from_inventory(_selected_slate)
			_on_drop_requested()
			status_label.text = ""
			grid.mark_cells_dirty()
			grid.queue_redraw()
			_refresh_aether()
			_refresh_chains()
			_populate_palette()

func _is_slate_available(slate: Slate) -> bool:
	return GameState.inventory.has_content(slate)

const _FAILURE_MESSAGES := {
	"insufficient_aether": "Can't place: not enough Aether.",
	"cell_occupied": "Can't place: that cell is already occupied.",
	"not_connected": "Can't place: Slates must connect to the anchor or an already-placed Slate.",
}

func _on_placement_failed(reason: String) -> void:
	status_label.text = _FAILURE_MESSAGES.get(reason, "Can't place: %s" % reason)

func _refresh_aether() -> void:
	aether_label.text = "Aether: %d / %d" % [_board.aether_used, _board.aether_capacity]

func _refresh_chains() -> void:
	var results := ChainCalculator.compute_chains(_board)
	var lines := PackedStringArray()
	for i in range(results.size()):
		var r: ChainCalculator.ChainResult = results[i]
		var tag_name: String = Constants.DAMAGE_TYPE_NAME.get(r.tag, "?")
		lines.append("%s chain: %d tiles, +%.2f%%" % [tag_name, r.tile_count, r.bonus_percent * 100.0])
		EventBus.chain_recalculated.emit(i, r.tile_count, r.bonus_percent)
	chain_label.text = "\n".join(lines) if lines.size() > 0 else "No chains yet"
