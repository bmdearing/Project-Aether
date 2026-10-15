extends Control
class_name MapView
## MapScreen's map: the whole level photographed from straight above (north
## up) once per opening, with fog over unexplored cells and live markers on
## top. Wheel zooms on the cursor, dragging pans.

const ENEMY_COLOR := Color(0.95, 0.25, 0.22)
const VAULT_COLOR := Color(1.0, 0.75, 0.25)
const PORTAL_COLOR := Color(0.45, 0.75, 1.0)
const CHEST_COLOR := Color(1.0, 0.86, 0.4)
const START_COLOR := Color(0.45, 0.86, 1.0)
const FOG_COLOR := Color(0.012, 0.016, 0.03, 0.93)
const FOG_EDGE := Color(0.55, 0.45, 0.28, 0.35)
const RENDER_PX := 1024
const MAX_ZOOM := 6.0
const ZOOM_STEP := 1.2
## World metres around the cells shown past the outermost ones.
const MARGIN := 6.0

const MapAtmosphere := preload("res://levels/generated_map/MapAtmosphere.gd")

var map: GeneratedMap
var explored: Dictionary = {}
var zoom := 1.0
## The world XZ point at the view's centre.
var focus := Vector2.ZERO

var _viewport: SubViewport
var _camera: Camera3D
## The square of world XZ the photograph covers.
var _world := Rect2()
var _dragging := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_PX, RENDER_PX)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees.x = -90.0  # screen up = -Z = north
	_camera.set_cull_mask_value(MapAtmosphere.WEATHER_LAYER, false)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 1.3
	_camera.environment = env
	_viewport.add_child(_camera)

## Frames the whole map and takes a fresh photograph of it.
func setup(new_map: GeneratedMap, new_explored: Dictionary) -> void:
	map = new_map
	explored = new_explored
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cell in map.graph.rooms:
		lo = lo.min(Vector2(cell) * map.cell_size)
		hi = hi.max(Vector2(cell) * map.cell_size)
	var half := map.cell_size / 2.0 + MARGIN
	lo -= Vector2.ONE * half
	hi += Vector2.ONE * half
	var side := maxf(hi.x - lo.x, hi.y - lo.y)
	var centre := (lo + hi) / 2.0
	_world = Rect2(centre - Vector2.ONE * side / 2.0, Vector2.ONE * side)
	zoom = 1.0
	focus = centre
	_photograph()
	queue_redraw()

func _photograph() -> void:
	var top := 30.0
	for t in map.terraces:
		top = maxf(top, float(t["top"]) + 30.0)
	_camera.size = _world.size.x
	_camera.near = 0.05
	_camera.far = top + 20.0
	_camera.global_position = Vector3(_world.get_center().x, top, _world.get_center().y)
	_viewport.world_3d = map.get_world_3d()
	# Roofs would hide indoor maps; they come back once the shot is taken.
	var roofs: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("ceiling"):
		if node is Node3D and (node as Node3D).visible:
			roofs.append(node)
			(node as Node3D).visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	for roof in roofs:
		if is_instance_valid(roof):
			roof.visible = true
	queue_redraw()

func _scale() -> float:
	return minf(size.x, size.y) / maxf(_world.size.x, 1.0) * zoom

func to_screen(world: Vector2) -> Vector2:
	return size / 2.0 + (world - focus) * _scale()

func to_world(screen: Vector2) -> Vector2:
	return focus + (screen - size / 2.0) / _scale()

func centre_on_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		focus = Vector2(player.global_position.x, player.global_position.z)
		_clamp_focus()
		queue_redraw()

func _clamp_focus() -> void:
	focus = focus.clamp(_world.position, _world.end)

func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var anchor := to_world(button.position)
		zoom = clampf(zoom * (ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP), 1.0, MAX_ZOOM)
		focus = anchor - (button.position - size / 2.0) / _scale()  # the point under the cursor stays put
		_clamp_focus()
		queue_redraw()
		accept_event()
	elif button and (button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT):
		_dragging = button.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		focus -= (event as InputEventMouseMotion).relative / _scale()
		_clamp_focus()
		queue_redraw()
		accept_event()

func _draw() -> void:
	if map == null or not is_instance_valid(map):
		return
	draw_texture_rect(_viewport.get_texture(), Rect2(to_screen(_world.position), _world.size * _scale()), false)
	_draw_fog()
	_draw_markers()

func _cell_rect(cell: Vector2i) -> Rect2:
	var c := Vector2(cell) * map.cell_size
	var h := map.cell_size / 2.0
	return Rect2(to_screen(c - Vector2.ONE * h), Vector2.ONE * map.cell_size * _scale())

## Unexplored cells are covered; a faint edge marks where fog meets the
## explored ground, so you can see which ways lead on.
func _draw_fog() -> void:
	for cell in map.graph.rooms:
		if explored.has(cell):
			continue
		var rect := _cell_rect(cell)
		draw_rect(rect, FOG_COLOR)
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if explored.has(cell + d) and (map.graph.rooms[cell] as MapGraph.RoomData).connections.has(cell + d):
				var a := rect.get_center() + Vector2(d) * rect.size / 2.0
				var along := Vector2(absf(d.y), absf(d.x)) * rect.size / 2.0
				draw_line(a - along, a + along, FOG_EDGE, 2.0)

func _is_seen(world: Vector3) -> bool:
	return explored.has(Vector2i(roundi(world.x / map.cell_size), roundi(world.z / map.cell_size)))

func _draw_markers() -> void:
	var start := map._cell_to_world(map.graph.start_cell)
	_diamond(to_screen(Vector2(start.x, start.z)), 7.0, START_COLOR)
	var vault := map.boss_portal_point
	_diamond(to_screen(Vector2(vault.x, vault.z)), 9.0, VAULT_COLOR)
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_inside_tree() or enemy.is_queued_for_deletion() or not _is_seen(enemy.global_position):
			continue
		var boss := enemy.rank == Constants.EnemyRank.BOSS
		draw_circle(to_screen(Vector2(enemy.global_position.x, enemy.global_position.z)), 5.0 if boss else 3.0, VAULT_COLOR if boss else ENEMY_COLOR)
	for node in get_tree().get_nodes_in_group("treasure_chest"):
		var chest := node as Node3D
		if chest == null or (chest.has_method("is_opened") and chest.is_opened()) or not _is_seen(chest.global_position):
			continue
		var p := to_screen(Vector2(chest.global_position.x, chest.global_position.z))
		draw_rect(Rect2(p - Vector2(5, 4), Vector2(10, 8)), CHEST_COLOR)
		draw_rect(Rect2(p - Vector2(5, 4), Vector2(10, 8)), Color(0, 0, 0, 0.7), false, 1.0)
	for node in get_tree().get_nodes_in_group("portal"):
		var portal := node as Node3D
		if portal == null:
			continue
		var p := to_screen(Vector2(portal.global_position.x, portal.global_position.z))
		draw_circle(p, 5.0, PORTAL_COLOR)
		draw_arc(p, 8.0, 0.0, TAU, 20, Color(PORTAL_COLOR, 0.6), 1.5)
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		_player_arrow(to_screen(Vector2(player.global_position.x, player.global_position.z)), player.global_rotation.y)
	_draw_north()

func _diamond(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.8), 1.2)

func _player_arrow(c: Vector2, yaw: float) -> void:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	var tip := c + forward * 11.0
	var points := PackedVector2Array([tip, c - forward * 7.0 + side * 7.5, c - forward * 2.5, c - forward * 7.0 - side * 7.5])
	draw_colored_polygon(points, Color.WHITE)
	draw_polyline(points + PackedVector2Array([tip]), Color(0, 0, 0, 0.85), 1.5)

## A small rose in the top-right corner; north is always up.
func _draw_north() -> void:
	var c := Vector2(size.x - 30.0, 34.0)
	draw_circle(c, 20.0, Color(0, 0, 0, 0.45))
	draw_arc(c, 18.0, 0.0, TAU, 32, AetherStyle.GOLD_DIM, 1.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -15), c + Vector2(4, 0), c + Vector2(-4, 0)]), AetherStyle.GOLD_BRIGHT)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 15), c + Vector2(4, 0), c + Vector2(-4, 0)]), AetherStyle.GOLD_FAINT)
	var font := AetherStyle.title()
	var w := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, c + Vector2(-w / 2.0, -22.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, AetherStyle.GOLD_BRIGHT)
