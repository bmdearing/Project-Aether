extends Control
class_name Minimap
## Top-right minimap: an orthographic camera looks straight down on the
## player (north up) and renders into a small SubViewport a few times a
## second; markers for the player, enemies, portals and chests are drawn on
## top. The camera sits a little above the player's head and only sees
## below it, so roofs and overhangs don't cover the view.

const SIZE := 210.0
const MARGIN := 16.0
## World metres across the map.
const VIEW_METRES := 64.0
const CAMERA_ABOVE := 7.0
const UPDATE_HZ := 15.0
const RENDER_PX := 256
const ENEMY_COLOR := Color(0.95, 0.25, 0.22)
const BOSS_COLOR := Color(1.0, 0.55, 0.15)
const PORTAL_COLOR := Color(0.45, 0.75, 1.0)
const CHEST_COLOR := Color(1.0, 0.82, 0.35)

var _viewport: SubViewport
var _camera: Camera3D
var _picture: TextureRect
var _markers: Control
var _since_render := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -SIZE - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + SIZE

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_PX, RENDER_PX)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.positional_shadow_atlas_size = 0
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = VIEW_METRES
	_camera.near = 0.05
	_camera.far = 80.0
	_camera.rotation_degrees.x = -90.0  # screen up = -Z = north
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.9
	_camera.environment = env
	_viewport.add_child(_camera)

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", AetherStyle.glass_box(AetherStyle.GOLD_DIM, Color(0, 0, 0, 0.6), 2, 0.0))
	add_child(frame)
	_picture = TextureRect.new()
	_picture.texture = _viewport.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.offset_left = 3
	_picture.offset_top = 3
	_picture.offset_right = -3
	_picture.offset_bottom = -3
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.modulate = Color(1, 1, 1, 0.92)
	add_child(_picture)
	_markers = Control.new()
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.clip_contents = true
	_markers.draw.connect(_draw_markers)
	add_child(_markers)
	var north := Label.new()
	north.text = "N"
	north.add_theme_font_size_override("font_size", 14)
	north.add_theme_color_override("font_color", AetherStyle.GOLD_BRIGHT)
	north.add_theme_color_override("font_outline_color", Color.BLACK)
	north.add_theme_constant_override("outline_size", 4)
	north.position = Vector2(SIZE / 2.0 - 5.0, 2.0)
	add_child(north)

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _process(delta: float) -> void:
	var player := _player()
	visible = player != null and is_instance_valid(player)
	if not visible:
		return
	var at := player.global_position
	_camera.global_position = Vector3(at.x, at.y + CAMERA_ABOVE, at.z)
	_since_render += delta
	if _since_render >= 1.0 / UPDATE_HZ:
		_since_render = 0.0
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_markers.queue_redraw()

## Minimap pixel for a world position, relative to the player.
func to_map(world: Vector3, centre: Vector3) -> Vector2:
	var px_per_metre := (SIZE - 6.0) / VIEW_METRES
	return SIZE / 2.0 * Vector2.ONE + Vector2(world.x - centre.x, world.z - centre.z) * px_per_metre

func _draw_markers() -> void:
	var player := _player()
	if player == null:
		return
	var centre := player.global_position
	var bounds := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).grow(-4.0)
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_inside_tree() or enemy.is_queued_for_deletion():
			continue
		var p := to_map(enemy.global_position, centre)
		if bounds.has_point(p):
			var boss := enemy.rank == Constants.EnemyRank.BOSS
			_markers.draw_circle(p, 4.5 if boss else 3.0, BOSS_COLOR if boss else ENEMY_COLOR)
	for node in get_tree().get_nodes_in_group("portal"):
		var p := to_map((node as Node3D).global_position, centre)
		if bounds.has_point(p):
			_markers.draw_circle(p, 5.0, PORTAL_COLOR)
			_markers.draw_arc(p, 7.0, 0.0, TAU, 16, Color(PORTAL_COLOR, 0.6), 1.5)
	for node in get_tree().get_nodes_in_group("treasure_chest"):
		if node.has_method("is_opened") and node.is_opened():
			continue
		var p := to_map((node as Node3D).global_position, centre)
		if bounds.has_point(p):
			_markers.draw_rect(Rect2(p - Vector2(4, 3), Vector2(8, 6)), CHEST_COLOR)
	_draw_player_arrow(Vector2(SIZE, SIZE) / 2.0, player.global_rotation.y)

func _draw_player_arrow(c: Vector2, yaw: float) -> void:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	var tip := c + forward * 8.0
	var points := PackedVector2Array([tip, c - forward * 5.0 + side * 5.5, c - forward * 2.0, c - forward * 5.0 - side * 5.5])
	_markers.draw_colored_polygon(points, Color.WHITE)
	_markers.draw_polyline(points + PackedVector2Array([tip]), Color(0, 0, 0, 0.8), 1.2)
