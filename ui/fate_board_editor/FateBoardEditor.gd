extends CanvasLayer
class_name FateBoardEditor
## Vertical-slice Fate Board placement UI (Section 10). Renders
## GameState.fate_board's live placements/Aether budget via FateBoardGrid,
## and recomputes ChainCalculator results after every placement/removal.
##
## Slate "ownership" stands in for the not-yet-built Satchel/loot system:
## every .tres under data/slates/instances/ is offered in the palette, as
## if the player owns one of each.

const SLATE_INSTANCES_DIR := "res://data/slates/instances/"

@onready var grid: FateBoardGrid = $HBox/GridScroll/FateBoardGrid
@onready var palette_list: VBoxContainer = $HBox/SidePanel/PaletteScroll/PaletteList
@onready var aether_label: Label = $HBox/SidePanel/AetherLabel
@onready var selected_label: Label = $HBox/SidePanel/SelectedLabel
@onready var chain_label: Label = $HBox/SidePanel/ChainLabel
@onready var status_label: Label = $HBox/SidePanel/StatusLabel
@onready var close_button: Button = $HBox/SidePanel/CloseButton

var _is_open: bool = false
var _board: FateBoard
var _selected_slate: Slate
var _rotation_steps: int = 0
var _flipped: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("fate_board_editor")
	add_to_group("blocking_menu")
	grid.cell_clicked.connect(_on_cell_clicked)
	close_button.pressed.connect(close)
	_populate_palette()

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
	var dir := DirAccess.open(SLATE_INSTANCES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var slate: Slate = load(SLATE_INSTANCES_DIR + file_name) as Slate
			if slate:
				_add_palette_entry(slate)
		file_name = dir.get_next()
	dir.list_dir_end()

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

func _on_cell_clicked(cell: Vector2i, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_RIGHT or _selected_slate == null:
		var occupied := _board.get_occupied_cells()
		if occupied.has(cell):
			_board.remove_slate(occupied[cell])
			grid.queue_redraw()
			_refresh_aether()
			_refresh_chains()
		return

	if button_index == MOUSE_BUTTON_LEFT:
		var id := _board.place_slate(_selected_slate, cell, _rotation_steps, _flipped)
		if id != "":
			status_label.text = ""
			grid.queue_redraw()
			_refresh_aether()
			_refresh_chains()

func _on_placement_failed(reason: String) -> void:
	status_label.text = "Can't place: %s" % reason

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
