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
## Zoom resizes the cells (_cell_px = BASE_CELL_PX * _zoom) rather than
## scaling the Control, since ScrollContainer ignores scale when sizing.
const BASE_CELL_PX := 20.0
const ZOOM_STEP := 0.15
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const DEFAULT_ZOOM := 2.2  # 44px cells
const GRID_LINE_COLOR := Color(0.86, 0.71, 0.42, 0.13)
const VALID_PREVIEW_COLOR := Color(0.2, 0.9, 0.3, 0.55)
const INVALID_PREVIEW_COLOR := Color(0.9, 0.2, 0.2, 0.55)
const ANCHOR_COLOR := Color(1.0, 0.86, 0.55, 0.45)
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
var _zoom: float = DEFAULT_ZOOM
var _cell_px: float = BASE_CELL_PX * DEFAULT_ZOOM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll_container = get_parent() as ScrollContainer
	_setup_background()
	_apply_zoom()

## Resizes the grid for the current _zoom.
func _apply_zoom() -> void:
	_cell_px = BASE_CELL_PX * _zoom
	var extent := Vector2(GRID_SIZE * _cell_px, GRID_SIZE * _cell_px)
	custom_minimum_size = extent
	if _background:
		_background.size = extent
	queue_redraw()

## Wheel zoom that keeps the point under the cursor fixed. The scroll offset
## is set a frame later, once the ScrollContainer has re-measured the resized
## grid - setting it immediately would clamp to the old, smaller scroll range.
func _zoom_at(mouse_pos: Vector2, zoom_in: bool) -> void:
	var new_zoom: float = clamp(_zoom + (ZOOM_STEP if zoom_in else -ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom):
		return
	var cell_under_mouse := mouse_pos / _cell_px
	_zoom = new_zoom
	_apply_zoom()
	if _scroll_container == null:
		return
	var new_pos := cell_under_mouse * _cell_px
	var shift := new_pos - mouse_pos
	await get_tree().process_frame
	_scroll_container.scroll_horizontal += int(shift.x)
	_scroll_container.scroll_vertical += int(shift.y)

## Scrolls so the anchor cell (where the first Slate must attach) sits at the
## middle of the visible area. Called by FateBoardEditor.open().
func center_on_anchor() -> void:
	if _scroll_container == null:
		return
	await get_tree().process_frame  # the editor was just made visible - wait for real sizes
	var anchor_center := (Vector2(FateBoard.ANCHOR_CELL) + Vector2(0.5, 0.5)) * _cell_px
	_scroll_container.scroll_horizontal = int(anchor_center.x - _scroll_container.size.x / 2.0)
	_scroll_container.scroll_vertical = int(anchor_center.y - _scroll_container.size.y / 2.0)

func _setup_background() -> void:
	_background = ColorRect.new()
	_background.size = Vector2(GRID_SIZE * _cell_px, GRID_SIZE * _cell_px)
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

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed:
			_zoom_at(event.position, event.button_index == MOUSE_BUTTON_WHEEL_UP)
		accept_event()  # otherwise the ScrollContainer also scrolls vertically
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

## v4.7: hovering a placed Slate shows its ItemCard, same custom-tooltip hook
## ItemSlotButton uses for the palette. The grid is one Control, so the
## tooltip text is the hovered placement_id - Godot re-shows the tooltip
## whenever it changes, i.e. when the cursor moves onto a different Slate.
## Suppressed while a Slate is held for placement.
func _get_tooltip(at_position: Vector2) -> String:
	if board == null or pending_slate:
		return ""
	return board.get_occupied_cells().get(_pixel_to_cell(at_position), "")

func _make_custom_tooltip(for_text: String) -> Object:
	if board == null or not board.placements.has(for_text):
		return null
	var card: ItemCard = ItemSlotButton.ITEM_CARD_SCENE.instantiate()
	card.display_slate(board.placements[for_text].slate)
	return card

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / _cell_px)), int(floor(pos.y / _cell_px)))

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

	_draw_lens_radii()

	if pending_slate and _in_bounds(_hover_cell):
		var preview_cells := pending_slate.get_transformed_shape(pending_rotation, pending_flipped)
		var valid := board.can_place(pending_slate, _hover_cell, pending_rotation, pending_flipped)
		var tint := VALID_PREVIEW_COLOR if valid else INVALID_PREVIEW_COLOR
		for local_cell in preview_cells:
			_draw_cell(_hover_cell + local_cell, tint)
		if valid:
			var world: Array[Vector2i] = []
			for local_cell in preview_cells:
				world.append(_hover_cell + local_cell)
			for lens in pending_slate.lenses:
				_draw_radius(world, lens.radius)

## Draws a line on a cell edge unless both sides belong to the same
## placed Slate - same Slate reads as one solid shape, different Slates
## (or empty space) still show a wall between them.
func _draw_walls(occupied: Dictionary) -> void:
	for x in range(GRID_SIZE + 1):
		for y in range(GRID_SIZE):
			if _is_wall(occupied, Vector2i(x - 1, y), Vector2i(x, y)):
				draw_line(Vector2(x * _cell_px, y * _cell_px), Vector2(x * _cell_px, (y + 1) * _cell_px), GRID_LINE_COLOR)
	for y in range(GRID_SIZE + 1):
		for x in range(GRID_SIZE):
			if _is_wall(occupied, Vector2i(x, y - 1), Vector2i(x, y)):
				draw_line(Vector2(x * _cell_px, y * _cell_px), Vector2((x + 1) * _cell_px, y * _cell_px), GRID_LINE_COLOR)

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
	var rect := Rect2(cell.x * _cell_px + 1, cell.y * _cell_px + 1, _cell_px - 2, _cell_px - 2)
	draw_rect(rect, color)

const LENS_RADIUS_COLOR := Color(0.55, 0.9, 0.85, 0.14)
const LENS_EDGE_COLOR := Color(0.55, 0.9, 0.85, 0.55)

## Every placed Lens's radius, as a faint tint with an outline.
func _draw_lens_radii() -> void:
	for id in board.placements:
		var data: FateBoard.PlacedSlateData = board.placements[id]
		for lens in data.slate.lenses:
			_draw_radius(data.cells, lens.radius)

func _draw_radius(host_cells: Array[Vector2i], radius: int) -> void:
	var cells := FateBoard.radius_cells(host_cells, radius)
	var inside := {}
	for c in cells:
		inside[c] = true
	for c in cells:
		if not _in_bounds(c):
			continue
		var rect := Rect2(c.x * _cell_px, c.y * _cell_px, _cell_px, _cell_px)
		draw_rect(rect, LENS_RADIUS_COLOR)
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if inside.has(c + dir):
				continue
			var a := rect.position
			var b := rect.position
			match dir:
				Vector2i.UP: b += Vector2(_cell_px, 0)
				Vector2i.DOWN: a += Vector2(0, _cell_px); b = a + Vector2(_cell_px, 0)
				Vector2i.LEFT: b += Vector2(0, _cell_px)
				Vector2i.RIGHT: a += Vector2(_cell_px, 0); b = a + Vector2(0, _cell_px)
			draw_line(a, b, LENS_EDGE_COLOR, 1.5)
