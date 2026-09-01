extends Control
class_name FateBoardGrid
## Renders the Fate Board and handles placement input. Pure rendering +
## input; FateBoard.can_place()/place_slate() stay the source of truth.
## Sits inside a ScrollContainer (its parent) that clips/scrolls this
## oversized Control - LMB-drag pans by driving that ScrollContainer's
## scroll offset directly.

signal cell_clicked(cell: Vector2i, button_index: int)
signal drop_requested

const GRID_SIZE := 150
const CELL_PX := 20
const GRID_LINE_COLOR := Color(1, 1, 1, 0.08)
const VALID_PREVIEW_COLOR := Color(0.2, 0.9, 0.3, 0.55)
const INVALID_PREVIEW_COLOR := Color(0.9, 0.2, 0.2, 0.55)
const ANCHOR_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const NEBULA_SHADER := preload("res://ui/fate_board_editor/slate_nebula.gdshader")
const DRAG_THRESHOLD := 6.0

var board: FateBoard
var pending_slate: Slate
var pending_rotation: int = 0
var pending_flipped: bool = false

var _hover_cell: Vector2i = Vector2i(-1, -1)
var _background: ColorRect
var _cells_dirty: bool = true
var _scroll_container: ScrollContainer
var _lmb_press_pos: Vector2 = Vector2.ZERO
var _lmb_dragging: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(GRID_SIZE * CELL_PX, GRID_SIZE * CELL_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll_container = get_parent() as ScrollContainer
	_setup_background()

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

func mark_cells_dirty() -> void:
	_cells_dirty = true

func set_pending(slate: Slate, rotation_steps: int, flipped: bool) -> void:
	pending_slate = slate
	pending_rotation = rotation_steps
	pending_flipped = flipped
	queue_redraw()

## LMB drag pans the view (via the parent ScrollContainer); a plain click
## (press+release under DRAG_THRESHOLD movement) places/removes instead.
## RMB drops the held Slate if one is selected, otherwise removes whatever
## is at the clicked cell.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _pixel_to_cell(event.position)
		if cell != _hover_cell:
			_hover_cell = cell
			queue_redraw()
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if not _lmb_dragging and _lmb_press_pos.distance_to(event.position) > DRAG_THRESHOLD:
				_lmb_dragging = true
			if _lmb_dragging and _scroll_container:
				_scroll_container.scroll_horizontal -= int(event.relative.x)
				_scroll_container.scroll_vertical -= int(event.relative.y)
		return

	if not event is InputEventMouseButton:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_lmb_press_pos = event.position
			_lmb_dragging = false
		else:
			if not _lmb_dragging:
				var cell := _pixel_to_cell(event.position)
				if _in_bounds(cell):
					cell_clicked.emit(cell, MOUSE_BUTTON_LEFT)
			_lmb_dragging = false
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if pending_slate:
			drop_requested.emit()
		else:
			var cell := _pixel_to_cell(event.position)
			if _in_bounds(cell):
				cell_clicked.emit(cell, MOUSE_BUTTON_RIGHT)

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_PX)), int(floor(pos.y / CELL_PX)))

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE

func _draw() -> void:
	if _cells_dirty:
		_refresh_cell_background()
		_cells_dirty = false

	var occupied: Dictionary = board.get_occupied_cells() if board else {}
	_draw_walls(occupied)
	_draw_cell(FateBoard.ANCHOR_CELL, ANCHOR_COLOR)

	if board == null:
		return

	if pending_slate and _in_bounds(_hover_cell):
		var preview_cells := pending_slate.get_transformed_shape(pending_rotation, pending_flipped)
		var valid := board.can_place(pending_slate, _hover_cell, pending_rotation, pending_flipped)
		var tint := VALID_PREVIEW_COLOR if valid else INVALID_PREVIEW_COLOR
		for local_cell in preview_cells:
			_draw_cell(_hover_cell + local_cell, tint)

## Draws a line on a cell edge unless both sides belong to the same
## placed Slate - same Slate reads as one solid shape, different Slates
## (or empty space) still show a wall between them.
func _draw_walls(occupied: Dictionary) -> void:
	for x in range(GRID_SIZE + 1):
		for y in range(GRID_SIZE):
			if _is_wall(occupied, Vector2i(x - 1, y), Vector2i(x, y)):
				draw_line(Vector2(x * CELL_PX, y * CELL_PX), Vector2(x * CELL_PX, (y + 1) * CELL_PX), GRID_LINE_COLOR)
	for y in range(GRID_SIZE + 1):
		for x in range(GRID_SIZE):
			if _is_wall(occupied, Vector2i(x, y - 1), Vector2i(x, y)):
				draw_line(Vector2(x * CELL_PX, y * CELL_PX), Vector2((x + 1) * CELL_PX, y * CELL_PX), GRID_LINE_COLOR)

func _is_wall(occupied: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	var id_a: String = occupied.get(a, "")
	var id_b: String = occupied.get(b, "")
	return id_a == "" or id_a != id_b

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
