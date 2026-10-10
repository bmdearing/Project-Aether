extends Control
class_name SkillWebView
## A spell's skill web on the Spells screen (SkillWeb): the spell at the
## centre, building blocks on the right, its twists on the left, rings of
## nodes linked to what unlocks them. Left-click spends a point, right-click
## takes one back; hover for what a node does.

signal changed

var ability: Ability:
	set(value):
		ability = value
		queue_redraw()

const NODE_RADIUS := 17.0
const TWIST_RADIUS := 21.0
## Ring radii as shares of the web's half-size, and the horizontal stretch.
const RING_FIRST := 0.36
const RING_STEP := 0.29
const STRETCH := 1.45

var _hover_id: String = ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "  # non-empty so the tooltip system asks _get_tooltip()
	resized.connect(queue_redraw)

func _centre() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5 - 10.0)

func _scale() -> float:
	return minf(size.x, size.y - 40.0) * 0.5

func node_position(node: SkillWeb.WebNode) -> Vector2:
	return _centre() + Vector2.from_angle(deg_to_rad(node.angle - 90.0)) * _ring_radius(node.ring) * Vector2(STRETCH, 1.0)

func _ring_radius(ring: int) -> float:
	return _scale() * (RING_FIRST + RING_STEP * (ring - 1))

func _node_at(pos: Vector2) -> SkillWeb.WebNode:
	if ability == null:
		return null
	for node: SkillWeb.WebNode in SkillWeb.nodes_for(ability):
		var radius := TWIST_RADIUS if node.is_twist() else NODE_RADIUS
		if pos.distance_to(node_position(node)) <= radius + 3.0:
			return node
	return null

func _gui_input(event: InputEvent) -> void:
	if ability == null:
		return
	if event is InputEventMouseMotion:
		var node := _node_at(event.position)
		var id := node.id if node else ""
		if id != _hover_id:
			_hover_id = id
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var node := _node_at(event.position)
		if node == null:
			return
		var ok := SkillWeb.allocate(ability, node.id) if event.button_index == MOUSE_BUTTON_LEFT else SkillWeb.refund(ability, node.id) if event.button_index == MOUSE_BUTTON_RIGHT else false
		if ok:
			GameState.store_skill_web(ability)
			changed.emit()
		queue_redraw()
		accept_event()

func _get_tooltip(at_position: Vector2) -> String:
	var node := _node_at(at_position)
	if node == null:
		return ""
	var lines := PackedStringArray([node.name, node.description])
	lines.append("%d / %d point%s" % [SkillWeb.points_in(ability, node.id), node.max_points, "" if node.max_points == 1 else "s"])
	var why := SkillWeb.why_not_allocate(ability, node.id)
	if why != "" and SkillWeb.points_in(ability, node.id) < node.max_points:
		lines.append(why)
	lines.append("Left-click: spend a point.  Right-click: take one back.")
	return "\n".join(lines)

func _draw() -> void:
	AetherStyle.plate(self, Rect2(Vector2.ZERO, size), 4.0, AetherStyle.GLASS)
	var font := AetherStyle.serif()
	if ability == null:
		AetherStyle.text(self, font, Vector2(0, size.y * 0.5), "Click a spell to open its web", 16, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		return
	var c := _centre()
	var nodes := SkillWeb.nodes_for(ability)
	var by_id := {}
	for node: SkillWeb.WebNode in nodes:
		by_id[node.id] = node
	for ring in range(1, 4):
		var r := _ring_radius(ring)
		draw_set_transform(c, 0.0, Vector2(STRETCH, 1.0))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, Color(AetherStyle.GOLD_FAINT, 0.18), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Links: ring 1 from the centre, others from what unlocks them.
	for node: SkillWeb.WebNode in nodes:
		var to := node_position(node)
		var sources: Array[Vector2] = []
		if node.ring == 1:
			sources.append(c)
		for id in node.requires:
			if by_id.has(id):
				sources.append(node_position(by_id[id]))
		var lit := SkillWeb.points_in(ability, node.id) > 0
		for from in sources:
			draw_line(from, to, Color(AetherStyle.GOLD, 0.8) if lit else Color(AetherStyle.GOLD_FAINT, 0.5), 2.0 if lit else 1.2)
	var side := _scale() * RING_FIRST * 0.85
	SpellArt.draw(self, ability, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)))
	for node: SkillWeb.WebNode in nodes:
		_draw_node(node, font)
	var left := SkillWeb.points_left(ability)
	var header := "%s Web   %d / %d points spent" % [ability.display_name, SkillWeb.points_spent(ability), SkillWeb.points_available(ability)]
	AetherStyle.text(self, font, Vector2(0, size.y - 34.0), header, 16, AetherStyle.GOLD if left > 0 else AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	AetherStyle.text(self, font, Vector2(0, size.y - 14.0), "Each level of the spell gives a point for this web.", 13, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)

func _draw_node(node: SkillWeb.WebNode, font: Font) -> void:
	var p := node_position(node)
	var have := SkillWeb.points_in(ability, node.id)
	var open := SkillWeb.why_not_allocate(ability, node.id) == ""
	var radius := TWIST_RADIUS if node.is_twist() else NODE_RADIUS
	var accent := AetherStyle.AETHER if node.is_twist() else AetherStyle.GOLD
	var fill := Color(accent, 0.55) if have > 0 else (Color(AetherStyle.GLASS_LIGHT, 0.95) if open else Color(0.05, 0.05, 0.07, 0.95))
	if node.id == _hover_id:
		draw_circle(p, radius + 5.0, Color(accent, 0.25))
	if node.is_twist():
		var pts := PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, 0), p + Vector2(0, radius), p + Vector2(-radius, 0)])
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, accent if have > 0 or open else Color(accent, 0.35), 2.0)
	else:
		draw_circle(p, radius, fill)
		draw_arc(p, radius, 0.0, TAU, 32, accent if have > 0 or open else Color(accent, 0.35), 2.0)
	var label := "%d/%d" % [have, node.max_points]
	AetherStyle.text(self, AetherStyle.numbers(), p + Vector2(-radius, 5.0), label, 13, AetherStyle.TEXT if have > 0 or open else AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)
	AetherStyle.text(self, font, p + Vector2(-60.0, radius + 14.0), node.name, 12, AetherStyle.TEXT if have > 0 else AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
