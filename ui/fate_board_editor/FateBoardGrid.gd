extends Control
class_name FateBoardGrid
## Renders the Fate Board and handles placement input. Pure rendering +
## input; FateBoard.can_place()/place_slate() stay the source of truth.
## Sits inside a ScrollContainer (its parent) that clips/scrolls this
## oversized Control - LMB-drag pans by driving that ScrollContainer's
## scroll offset directly.

signal cell_clicked(cell: Vector2i, button_index: int)
signal drop_requested

const GRID_SIZE := FateBoard.GRID_SIZE
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
const NEBULA_SHADER := preload("res://ui/fate_board_editor/slate_nebula.gdshader")
const DRAG_THRESHOLD := 6.0

var board: FateBoard
var pending_slate: Slate
var pending_rotation: int = 0
var pending_flipped: bool = false

var _hover_cell: Vector2i = Vector2i(-1, -1)
var _background: ColorRect
var _outline_layer: Control
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
	if _outline_layer:
		_outline_layer.size = extent
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
	mat.set_shader_parameter("line_color", GRID_LINE_COLOR)
	mat.set_shader_parameter("board_radius", float(FateBoard.BOARD_RADIUS))
	_background.material = mat
	add_child(_background)
	move_child(_background, 0)
	# Outlines go on a layer above the Slate fills: the background child draws
	# over this control's own _draw().
	_outline_layer = Control.new()
	_outline_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline_layer.draw.connect(func():
		if board == null:
			return
		if show_outlines:
			_draw_outlines(board.get_occupied_cells())
		_draw_stars())
	_outline_layer.size = _background.size
	add_child(_outline_layer)

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
	var cell := _pixel_to_cell(at_position)
	var star := FateStars.star_at(cell)
	if star >= 0:
		return "star:%d" % star
	for site in board.lit_sites():
		if site.cell == cell:
			return "site:%d:%d" % [site.star, site.index]
	return board.get_occupied_cells().get(cell, "")

func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.begins_with("star:"):
		return TooltipFollow.plain(star_tooltip(int(for_text.get_slice(":", 1))))
	if for_text.begins_with("site:"):
		return TooltipFollow.plain(_site_tooltip(int(for_text.get_slice(":", 1)), int(for_text.get_slice(":", 2))))
	if board == null or not board.placements.has(for_text):
		return null
	var card: ItemCard = ItemSlotButton.new_item_card()
	card.footer_lines = ChainCalculator.chain_lines_for(board, for_text)
	card.footer_lines.append("Right-click to take this Slate off the board.")
	if not (board.placements[for_text].slate as Slate).lenses.is_empty():
		card.footer_lines.append("Its Lenses stay in while it's placed: take it off, then Ctrl+right-click it in the inventory.")
	card.slate_amplifier = ChainCalculator.attribute_multiplier(board, for_text)
	card.display_slate(board.placements[for_text].slate)
	return card

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / _cell_px)), int(floor(pos.y / _cell_px)))

func _in_bounds(cell: Vector2i) -> bool:
	return FateBoard.in_board(cell)

func _draw() -> void:
	if _cells_dirty:
		_refresh_cell_background()
		_cells_dirty = false

	var occupied: Dictionary = board.get_occupied_cells() if board else {}
	_draw_walls(occupied)

	if board == null:
		return

	_draw_lens_radii()
	if _outline_layer:
		_outline_layer.queue_redraw()

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
	if not FateBoard.in_board(a) and not FateBoard.in_board(b):
		return false
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
			# Alpha 0.52-0.99 carries a per-placement seed: each Slate gets its own nebula.
			color.a = 0.52 + 0.47 * float(absi(hash(placement_id)) % 1000) / 999.0
			img.set_pixel(cell.x, cell.y, color)
	var tex := ImageTexture.create_from_image(img)
	(_background.material as ShaderMaterial).set_shader_parameter("cell_data", tex)

func _draw_cell(cell: Vector2i, color: Color) -> void:
	if not _in_bounds(cell):
		return
	var rect := Rect2(cell.x * _cell_px + 1, cell.y * _cell_px + 1, _cell_px - 2, _cell_px - 2)
	draw_rect(rect, color)

## Thick outline round each placed Slate in its own colour, so neighbours
## of one tag can be told apart.
static var show_outlines := false

func _draw_outlines(occupied: Dictionary) -> void:
	var w := maxf(1.5, _cell_px * 0.04)
	var inset := w * 0.5
	var index := 0
	for id in board.placements:
		var data: FateBoard.PlacedSlateData = board.placements[id]
		# Golden-ratio hue steps keep neighbouring Slates' colours far apart.
		var color := Color.from_hsv(fposmod(index * 0.618034, 1.0), 0.35, 1.0, 0.55)
		index += 1
		for c in data.cells:
			if not _in_bounds(c):
				continue
			var r := Rect2(c.x * _cell_px, c.y * _cell_px, _cell_px, _cell_px).grow(-inset)
			if occupied.get(c + Vector2i.UP, "") != id:
				_outline_layer.draw_line(r.position, Vector2(r.end.x, r.position.y), color, w)
			if occupied.get(c + Vector2i.DOWN, "") != id:
				_outline_layer.draw_line(Vector2(r.position.x, r.end.y), r.end, color, w)
			if occupied.get(c + Vector2i.LEFT, "") != id:
				_outline_layer.draw_line(r.position, Vector2(r.position.x, r.end.y), color, w)
			if occupied.get(c + Vector2i.RIGHT, "") != id:
				_outline_layer.draw_line(Vector2(r.end.x, r.position.y), r.end, color, w)

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

## ---- Stars ---------------------------------------------------------------

const STAR_DIM_COLOR := Color(0.55, 0.5, 0.4, 0.8)
const SITE_COLOR := Color(1.0, 0.9, 0.6)
const NOTABLE_SITE_COLOR := Color(1.0, 0.72, 0.25)
const STAR_FONT_SIZE := 15

## Stars (gold once reached, the Lens colour when lit), their names, and the
## bonus sites of lit Stars: open rings until a Slate claims them.
func _draw_stars() -> void:
	var layer := _outline_layer
	var reached := board.reached_stars()
	var star_cells := FateStars.cells()
	var font := AetherStyle.title()
	for i in star_cells.size():
		var centre := (Vector2(star_cells[i]) + Vector2(0.5, 0.5)) * _cell_px
		var lit := reached.has(i) and board.star_lenses.has(i)
		var color: Color = AetherStyle.GOLD if reached.has(i) else STAR_DIM_COLOR
		if lit:
			color = ItemCard.LENS_COLOR
			layer.draw_circle(centre, _cell_px * 0.95, Color(color, 0.12))
		layer.draw_rect(Rect2(Vector2(star_cells[i]) * _cell_px, Vector2.ONE * _cell_px), Color(0.06, 0.05, 0.03, 0.95))
		layer.draw_colored_polygon(_star_points(centre, _cell_px * 0.62, _cell_px * 0.2), color)
		if board.star_lenses.has(i):
			layer.draw_circle(centre, _cell_px * 0.14, Color(1, 1, 1, 0.9))
			# A Star-only Lens's radius counts from the Star.
			var star_lens: Lens = board.star_lenses[i]
			if star_lens.star_only() >= 0:
				layer.draw_arc(centre, (star_lens.radius + 0.5) * _cell_px, 0.0, TAU, 64, Color(color, 0.5), maxf(1.5, _cell_px * 0.06))
		var name_text: String = FateStars.NAMES[i]
		var text_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, STAR_FONT_SIZE)
		AetherStyle.text(layer, font, centre + Vector2(-text_size.x / 2.0, _cell_px * 0.5 + text_size.y), name_text, STAR_FONT_SIZE, Color(color, 0.9))
	var occupied := board.get_occupied_cells()
	for site in board.lit_sites():
		var centre := (Vector2(site.cell) + Vector2(0.5, 0.5)) * _cell_px
		# Notables are drawn bigger, in brighter gold.
		var notable: bool = site.bonus.get("notable", false)
		var size := 1.35 if notable else 1.0
		var colour := NOTABLE_SITE_COLOR if notable else SITE_COLOR
		if occupied.has(site.cell):
			layer.draw_colored_polygon(_star_points(centre, _cell_px * 0.34 * size, _cell_px * 0.13 * size), colour)
		else:
			layer.draw_arc(centre, _cell_px * 0.28 * size, 0.0, TAU, 20, Color(colour, 0.85), maxf(1.5, _cell_px * 0.06 * size))
			layer.draw_circle(centre, _cell_px * 0.08 * size, Color(colour, 0.85))

## A four-pointed star round `centre`.
static func _star_points(centre: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 8:
		var r := outer if k % 2 == 0 else inner
		var angle := k * TAU / 8.0 - PI / 2.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * r)
	return points

func star_tooltip(star: int) -> String:
	var lines := PackedStringArray([FateStars.NAMES[star]])
	var lens: Lens = board.star_lenses.get(star)
	var reached := board.is_star_reached(star)
	if lens:
		lines.append("%s: %s" % [lens.display_name, FateStars.lens_star_text(lens)])
		if not reached:
			lines.append("Unlit: no Slate chain reaches this Star.")
		for site in board.star_sites(star):
			var claimed := board.get_occupied_cells().has(site.cell) and reached
			lines.append("  %s %s" % ["[claimed]" if claimed else "[open]", site.text()])
		lines.append("Right-click to take the Lens out.")
	elif reached:
		lines.append("Hold a Lens and click this Star to set it.")
		lines.append("Its radius modifier picks the bonuses, its size how many.")
	else:
		lines.append("Reach this Star with a chain of Slates to set a Lens in it.")
	return "\n".join(lines)

func _site_tooltip(star: int, index: int) -> String:
	for site in board.lit_sites():
		if site.star == star and site.index == index:
			var claimed := board.get_occupied_cells().has(site.cell)
			return "%s\n%s bonus - %s" % [site.text(), FateStars.NAMES[star], "claimed" if claimed else "cover it with a Slate to claim it"]
	return ""
