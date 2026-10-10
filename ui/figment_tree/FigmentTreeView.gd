extends Control
class_name FigmentTreeView
## Draws the Figment Tree and handles allocating (click), refunding
## (right-click), panning (drag) and zooming (wheel).

signal changed
signal status(text: String)

const UNIT_PX := 82.0
const SMALL_R := 11.0
const NOTABLE_R := 17.0
const ZOOM_RANGE := Vector2(0.45, 1.8)
const SECTOR_COLORS := {
	"Terrain": Color(0.55, 0.85, 0.55), "Factions": Color(0.9, 0.55, 0.4), "Monsters": Color(0.95, 0.4, 0.4),
	"Rewards": Color(0.95, 0.8, 0.35), "Encounters": Color(0.6, 0.7, 1.0), "Figments": Color(0.45, 0.86, 1.0),
}

var _zoom := 0.85
var _pan := Vector2.ZERO
var _dragging := false
var _drag_moved := 0.0
var _hovered := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + _pan + p * UNIT_PX * _zoom

func _radius(node: FigmentTreeNode) -> float:
	return (NOTABLE_R if node.notable else SMALL_R) * clampf(_zoom, 0.7, 1.4)

func _node_at(pos: Vector2) -> String:
	for node in FigmentTree.all_nodes():
		if _to_screen(node.position).distance_to(pos) <= _radius(node) + 3.0:
			return node.node_id
	return ""

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					var old := _zoom
					_zoom = clampf(_zoom * (1.1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), ZOOM_RANGE.x, ZOOM_RANGE.y)
					# Zoom about the cursor.
					var anchor := button.position - size * 0.5 - _pan
					_pan -= anchor * (_zoom / old - 1.0)
					queue_redraw()
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_dragging = true
					_drag_moved = 0.0
				else:
					_dragging = false
					if _drag_moved < 6.0:
						_click(button.position, false)
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_click(button.position, true)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion:
		if _dragging:
			_pan += motion.relative
			_drag_moved += motion.relative.length()
			queue_redraw()
		var hovered := _node_at(motion.position)
		if hovered != _hovered:
			_hovered = hovered
			queue_redraw()

func _click(pos: Vector2, refund: bool) -> void:
	var id := _node_at(pos)
	if id == "" or id == FigmentTree.ROOT_ID:
		return
	var node := FigmentTree.get_node_by_id(id)
	if refund:
		if FigmentTree.refund(id):
			status.emit("Refunded %s." % node.display_name)
			changed.emit()
		elif FigmentTree.is_allocated(id):
			status.emit("%s holds other nodes to the root; refund those first." % node.display_name)
		return
	if FigmentTree.unlock(id):
		status.emit("Allocated %s." % node.display_name)
		changed.emit()
	elif not FigmentTree.is_allocated(id):
		if FigmentProgress.points_available() < node.point_cost:
			status.emit("%s costs %d point%s." % [node.display_name, node.point_cost, "" if node.point_cost == 1 else "s"])
		else:
			status.emit("%s must connect to an allocated node." % node.display_name)

func _draw() -> void:
	var nodes := FigmentTree.all_nodes()
	# Links: bright between two allocated nodes, dim otherwise.
	for node in nodes:
		for other_id in node.links:
			if other_id < node.node_id:
				continue
			var other := FigmentTree.get_node_by_id(other_id)
			var both := FigmentTree.is_allocated(node.node_id) and FigmentTree.is_allocated(other_id)
			draw_line(_to_screen(node.position), _to_screen(other.position), AetherStyle.GOLD if both else AetherStyle.GOLD_FAINT, 3.0 if both else 1.5, true)
	# Sector names beyond their branch.
	var font := AetherStyle.title()
	for sector in SECTOR_COLORS:
		var far := Vector2.ZERO
		for node in nodes:
			if node.sector == sector and node.position.length() > far.length():
				far = node.position
		if far != Vector2.ZERO:
			var at := _to_screen(far * (1.0 + 0.9 / far.length()))
			AetherStyle.text(self, font, at - Vector2(70, -5), sector, 15, Color(SECTOR_COLORS[sector], 0.85), HORIZONTAL_ALIGNMENT_CENTER, 140.0)
	for node in nodes:
		var c := _to_screen(node.position)
		var r := _radius(node)
		var allocated := FigmentTree.is_allocated(node.node_id)
		var available := FigmentTree.can_unlock(node.node_id)
		var tint: Color = SECTOR_COLORS.get(node.sector, AetherStyle.GOLD)
		var fill := Color(tint, 0.95) if allocated else (Color(tint, 0.35) if available else Color(0.08, 0.09, 0.13, 0.95))
		var ring := AetherStyle.GOLD_BRIGHT if allocated else (tint if available else AetherStyle.GOLD_DIM)
		if node.node_id == FigmentTree.ROOT_ID:
			AetherStyle.diamond(self, c, r * 1.3, AetherStyle.AETHER, AetherStyle.GOLD_BRIGHT)
		elif node.notable:
			AetherStyle.diamond(self, c, r * 1.2, fill, ring)
		else:
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 24, ring, 1.6, true)
		if node.node_id == _hovered:
			draw_arc(c, r + 4.0, 0.0, TAU, 28, AetherStyle.TEXT, 1.2, true)
	if _hovered != "":
		_draw_tooltip(FigmentTree.get_node_by_id(_hovered))

func _draw_tooltip(node: FigmentTreeNode) -> void:
	var serif := AetherStyle.serif()
	var lines := node.description.split("\n")
	var cost_line := "Always allocated" if node.node_id == FigmentTree.ROOT_ID else ("Allocated" if FigmentTree.is_allocated(node.node_id) else "Cost: %d point%s" % [node.point_cost, "" if node.point_cost == 1 else "s"])
	var width := AetherStyle.text_width(AetherStyle.title(), node.display_name, 15) + 20.0
	for line in lines:
		width = maxf(width, AetherStyle.text_width(serif, line, 14) + 20.0)
	var height := 30.0 + lines.size() * 18.0 + 22.0
	var pos := _to_screen(node.position) + Vector2(18, -height * 0.5)
	pos.x = minf(pos.x, size.x - width - 4.0)
	pos.y = clampf(pos.y, 4.0, size.y - height - 4.0)
	AetherStyle.plate(self, Rect2(pos, Vector2(width, height)), 4.0, AetherStyle.GLASS_SOLID)
	AetherStyle.text(self, AetherStyle.title(), pos + Vector2(10, 21), node.display_name, 15, AetherStyle.GOLD)
	for i in lines.size():
		AetherStyle.text(self, serif, pos + Vector2(10, 42 + i * 18), lines[i], 14, AetherStyle.MOD_BLUE)
	AetherStyle.text(self, serif, pos + Vector2(10, height - 8), cost_line, 13, AetherStyle.TEXT_DIM)
