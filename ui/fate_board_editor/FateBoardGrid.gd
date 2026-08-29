extends Control
class_name FateBoardGrid
## Bounded 32x32-cell window into the Fate Board (Section 10 says the real
## board is "effectively unlimited" - Aether is the constraint, not space -
## so a fixed viewport is enough to place/remove Slates and see chain math
## without building a pannable/infinite canvas). Pure rendering + input;
## FateBoard.can_place()/place_slate() stay the source of truth.

signal cell_clicked(cell: Vector2i, button_index: int)

const GRID_SIZE := 32
const CELL_PX := 20
const GRID_LINE_COLOR := Color(1, 1, 1, 0.08)
const VALID_PREVIEW_COLOR := Color(0.2, 0.9, 0.3, 0.55)
const INVALID_PREVIEW_COLOR := Color(0.9, 0.2, 0.2, 0.55)

var board: FateBoard
var pending_slate: Slate
var pending_rotation: int = 0
var pending_flipped: bool = false

var _hover_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	custom_minimum_size = Vector2(GRID_SIZE * CELL_PX, GRID_SIZE * CELL_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_board(b: FateBoard) -> void:
	board = b
	queue_redraw()

func set_pending(slate: Slate, rotation_steps: int, flipped: bool) -> void:
	pending_slate = slate
	pending_rotation = rotation_steps
	pending_flipped = flipped
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _pixel_to_cell(event.position)
		if cell != _hover_cell:
			_hover_cell = cell
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var cell := _pixel_to_cell(event.position)
		if _in_bounds(cell):
			cell_clicked.emit(cell, event.button_index)

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_PX)), int(floor(pos.y / CELL_PX)))

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE

func _draw() -> void:
	for x in range(GRID_SIZE + 1):
		draw_line(Vector2(x * CELL_PX, 0), Vector2(x * CELL_PX, GRID_SIZE * CELL_PX), GRID_LINE_COLOR)
	for y in range(GRID_SIZE + 1):
		draw_line(Vector2(0, y * CELL_PX), Vector2(GRID_SIZE * CELL_PX, y * CELL_PX), GRID_LINE_COLOR)

	if board == null:
		return

	var occupied := board.get_occupied_cells()
	for cell in occupied.keys():
		var placement_id: String = occupied[cell]
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]
		var color: Color = Constants.DAMAGE_TYPE_COLOR.get(data.slate.tag, Color.GRAY)
		_draw_cell(cell, color)

	if pending_slate and _in_bounds(_hover_cell):
		var preview_cells := pending_slate.get_transformed_shape(pending_rotation, pending_flipped)
		var valid := board.can_place(pending_slate, _hover_cell, pending_rotation, pending_flipped)
		var tint := VALID_PREVIEW_COLOR if valid else INVALID_PREVIEW_COLOR
		for local_cell in preview_cells:
			_draw_cell(_hover_cell + local_cell, tint)

func _draw_cell(cell: Vector2i, color: Color) -> void:
	if not _in_bounds(cell):
		return
	var rect := Rect2(cell.x * CELL_PX + 1, cell.y * CELL_PX + 1, CELL_PX - 2, CELL_PX - 2)
	draw_rect(rect, color)
