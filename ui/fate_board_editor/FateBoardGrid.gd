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
## FateBoard.ANCHOR_CELL's on-grid marker color - the one cell every first
## placement must touch now that Slates require connection (see FateBoard.gd).
const ANCHOR_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const NEBULA_SHADER := preload("res://ui/fate_board_editor/slate_nebula.gdshader")

var board: FateBoard
var pending_slate: Slate
var pending_rotation: int = 0
var pending_flipped: bool = false

var _hover_cell: Vector2i = Vector2i(-1, -1)
var _background: ColorRect
var _cells_dirty: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(GRID_SIZE * CELL_PX, GRID_SIZE * CELL_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_background()

## A dedicated ColorRect behind everything _draw() renders, carrying the
## animated nebula shader - keeps the shader's per-pixel work off the
## plain grid-line/preview drawing _draw() still does directly (see
## slate_nebula.gdshader's header for why this needed a shader at all).
func _setup_background() -> void:
	_background = ColorRect.new()
	_background.size = Vector2(GRID_SIZE * CELL_PX, GRID_SIZE * CELL_PX)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = NEBULA_SHADER
	mat.set_shader_parameter("grid_size", float(GRID_SIZE))
	_background.material = mat
	add_child(_background)
	move_child(_background, 0)

func set_board(b: FateBoard) -> void:
	board = b
	mark_cells_dirty()
	queue_redraw()

## Called by FateBoardEditor after every successful placement/removal -
## rebuilding the cell texture on every hover-driven redraw would be
## wasted work, since hovering never changes which cells are occupied.
func mark_cells_dirty() -> void:
	_cells_dirty = true

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
	if _cells_dirty:
		_refresh_cell_background()
		_cells_dirty = false

	_draw_cell(FateBoard.ANCHOR_CELL, ANCHOR_COLOR)

	for x in range(GRID_SIZE + 1):
		draw_line(Vector2(x * CELL_PX, 0), Vector2(x * CELL_PX, GRID_SIZE * CELL_PX), GRID_LINE_COLOR)
	for y in range(GRID_SIZE + 1):
		draw_line(Vector2(0, y * CELL_PX), Vector2(GRID_SIZE * CELL_PX, y * CELL_PX), GRID_LINE_COLOR)

	if board == null:
		return

	if pending_slate and _in_bounds(_hover_cell):
		var preview_cells := pending_slate.get_transformed_shape(pending_rotation, pending_flipped)
		var valid := board.can_place(pending_slate, _hover_cell, pending_rotation, pending_flipped)
		var tint := VALID_PREVIEW_COLOR if valid else INVALID_PREVIEW_COLOR
		for local_cell in preview_cells:
			_draw_cell(_hover_cell + local_cell, tint)

## Rebuilds the shader background's cell_data texture from the board's
## current occupied cells - alpha 0 (transparent black) for empty cells,
## which slate_nebula.gdshader discards so grid lines show through.
func _refresh_cell_background() -> void:
	var img := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8)
	if board:
		var occupied := board.get_occupied_cells()
		for cell in occupied.keys():
			if not _in_bounds(cell):
				continue
			var placement_id: String = occupied[cell]
			var data: FateBoard.PlacedSlateData = board.placements[placement_id]
			var color: Color = Constants.DAMAGE_TYPE_COLOR.get(data.slate.tag, Color.GRAY)
			color.a = 1.0
			img.set_pixel(cell.x, cell.y, color)
	var tex := ImageTexture.create_from_image(img)
	(_background.material as ShaderMaterial).set_shader_parameter("cell_data", tex)

func _draw_cell(cell: Vector2i, color: Color) -> void:
	if not _in_bounds(cell):
		return
	var rect := Rect2(cell.x * CELL_PX + 1, cell.y * CELL_PX + 1, CELL_PX - 2, CELL_PX - 2)
	draw_rect(rect, color)
