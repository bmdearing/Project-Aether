extends Node3D
class_name AureliaArena
## Aurelia's arena, built by PinnacleArena: a round slate floor inlaid like a
## wheel, ringed by ice pillars, with an invisible wall at the rim.
##
##   Earth Wheel (earth_wheel()): thin safe wedges are marked on the floor;
##   EARTH_WHEEL_WARNING seconds later everything else quakes for a share of
##   the player's Life + Ward. The next wedges flash up at once, turned a
##   little left or right, and it repeats. The hub under Aurelia is never
##   safe.
##   Amaterasu (start_amaterasu()): black fire creeps in from the rim until
##   it has the whole floor. Standing in it burns AMATERASU_SHARE of current
##   Life and Ward per second, as Fire.
##   Fire pots (add_fire_pot()): the upgraded Fire Wall's burning pools,
##   cleared at each new phase (clear_fire_pots()).

const RADIUS := 22.0
const BOSS_SPAWN := Vector3(0, 0.05, -8.0)
const PLAYER_SPAWN := Vector3(0, 0.1, 15.0)
const PORTAL_SPOT := Vector3(0, 0.1, 11.0)
const EDGE_PILLARS := 16

## Earth Wheel.
const WEDGES := 2
const WEDGE_HALF_DEG := 11.0
const HUB_RADIUS := 3.0
const EARTH_WHEEL_WARNING := 1.2
## The first wedges stay up a little longer, to be found.
const EARTH_WHEEL_FIRST_WARNING := 2.0
## How far each next set of wedges turns from the last.
const EARTH_WHEEL_TURN_DEG := Vector2(20.0, 34.0)
## The quake: this share of the player's max Life + Ward, before mitigation.
const EARTH_WHEEL_SHARE := 0.6

## Amaterasu.
const AMATERASU_SHARE := 0.0275
const AMATERASU_TICK := 0.5
## Seconds for the black fire to take the whole floor.
const AMATERASU_SPREAD_SEC := 90.0
const AMATERASU_WALL_HEIGHT := 2.6

## Fire pots.
const POT_RADIUS := 2.2
const POT_TICK := 0.5

const FLOOR_SHADER := preload("res://shaders/aurelia_floor.gdshader")
const WHEEL_SHADER := preload("res://shaders/earth_wheel.gdshader")
const BLACK_GROUND_SHADER := preload("res://shaders/black_fire_ground.gdshader")
const BLACK_FLAME_SHADER := preload("res://shaders/black_flame.gdshader")
const FLAME_SHADER := preload("res://shaders/spell_flame.gdshader")
const BossFx := preload("res://entities/effects/boss_fx/BossFx.gd")
const POOL_SHADER := preload("res://shaders/fire_pool.gdshader")

var boss: Enemy
var earth_wheel_active := false
## Wedge centres (radians, atan2(x, z) in local space) while the wheel turns.
var wedge_angles: Array[float] = []
var amaterasu_active := false
var amaterasu_safe_radius := RADIUS + 2.0

var _player: Player
var _wheel: MeshInstance3D
var _wheel_mat: ShaderMaterial
var _black_ground_mat: ShaderMaterial
var _black_wall: MeshInstance3D
var _black_smoke: CPUParticles3D
var _amaterasu_tick := 0.0
var _rumble: AudioStreamPlayer
var _black_roar: AudioStreamPlayer
## [{"node": Node3D, "center": Vector3, "damage": float, "tick": float}]
var _pots: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("aurelia_arena")
	_build_floor()
	_build_edge()

func bind_boss(b: Enemy) -> void:
	boss = b

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	_tick_pots(delta)
	_tick_amaterasu(delta)

func _boss_alive() -> bool:
	return is_instance_valid(boss) and boss.health.is_alive()

## ---- Build ----------------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS + 4.0
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (RADIUS + 4.0) * 2.0
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("radius", RADIUS + 4.0)
	mesh.material_override = mat
	body.add_child(mesh)

## Ice pillars and obelisks round the rim, with an invisible ring wall.
func _build_edge() -> void:
	var props: Array[PackedScene] = []
	for path in ["res://entities/environment/doodads/snow/Icecrownpillar0.tscn", "res://entities/environment/doodads/snow/Northrendbrokencolumn0.tscn", "res://entities/environment/doodads/snow/Icecrownobelisk0.tscn"]:
		if ResourceLoader.exists(path):
			props.append(load(path))
	for i in EDGE_PILLARS:
		var angle := TAU * i / EDGE_PILLARS
		var pos := Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 2.5)
		if not props.is_empty():
			var p := props[i % props.size()].instantiate() as Node3D
			add_child(p)
			p.position = pos
			p.rotation.y = angle + PI
			p.scale = Vector3.ONE * randf_range(1.1, 1.4)
		var wall := StaticBody3D.new()
		var ws := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * (RADIUS + 1.5) / EDGE_PILLARS + 0.5, 8.0, 1.0)
		ws.shape = box
		wall.add_child(ws)
		add_child(wall)
		wall.position = Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 1.5) + Vector3.UP * 4.0
		wall.rotation.y = angle

## ---- Earth Wheel ------------------------------------------------------------

## Runs `count` quakes; returns when the last has landed. `angle_from` is
## where the first wedges point (towards the player, so they can be found).
func earth_wheel(count: int, angle_from: float) -> void:
	if earth_wheel_active:
		return
	earth_wheel_active = true
	_show_wheel()
	_rumble = AureliaSfx.loop(self, "quake_rumble", -6.0)
	wedge_angles.clear()
	for i in WEDGES:
		wedge_angles.append(angle_from + TAU * i / WEDGES)
	for step in count:
		_set_wedges()
		var warning := EARTH_WHEEL_FIRST_WARNING if step == 0 else EARTH_WHEEL_WARNING
		var elapsed := 0.0
		while elapsed < warning:
			await get_tree().physics_frame
			if not is_inside_tree() or not _boss_alive():
				_end_wheel()
				return
			elapsed += get_physics_process_delta_time()
			_wheel_mat.set_shader_parameter("charge", clampf(elapsed / warning, 0.0, 1.0))
		_quake()
		# The next wedges flash up at once, a little left or right.
		var turn := deg_to_rad(randf_range(EARTH_WHEEL_TURN_DEG.x, EARTH_WHEEL_TURN_DEG.y)) * (1.0 if randf() < 0.5 else -1.0)
		for i in wedge_angles.size():
			wedge_angles[i] = wrapf(wedge_angles[i] + turn, -PI, PI)
	_end_wheel()

func _show_wheel() -> void:
	if _wheel == null:
		_wheel = MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * RADIUS * 2.0
		_wheel.mesh = plane
		_wheel_mat = ShaderMaterial.new()
		_wheel_mat.shader = WHEEL_SHADER
		_wheel_mat.set_shader_parameter("radius", RADIUS)
		_wheel_mat.set_shader_parameter("hub_radius", HUB_RADIUS)
		_wheel_mat.set_shader_parameter("wedge_count", WEDGES)
		_wheel_mat.set_shader_parameter("wedge_half", deg_to_rad(WEDGE_HALF_DEG))
		_wheel.material_override = _wheel_mat
		_wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wheel.position.y = 0.05
		add_child(_wheel)
	_wheel.visible = true
	_wheel_mat.set_shader_parameter("charge", 0.0)
	_wheel_mat.set_shader_parameter("strike", 0.0)

func _set_wedges() -> void:
	var v := Vector4.ZERO
	for i in mini(wedge_angles.size(), 4):
		v[i] = wedge_angles[i]
	_wheel_mat.set_shader_parameter("wedges", v)
	_wheel_mat.set_shader_parameter("charge", 0.0)

func _end_wheel() -> void:
	earth_wheel_active = false
	wedge_angles.clear()
	AureliaSfx.fade_out(_rumble)
	if _wheel:
		_wheel.visible = false

## True inside a safe wedge (and outside the hub).
func is_safe_from_quake(point: Vector3) -> bool:
	var local := to_local(point)
	var flat := Vector2(local.x, local.z)
	if flat.length() <= HUB_RADIUS:
		return false
	var angle := atan2(local.x, local.z)
	var half := deg_to_rad(WEDGE_HALF_DEG)
	for w in wedge_angles:
		if absf(wrapf(angle - w, -PI, PI)) <= half:
			return true
	return false

## Everything outside the wedges quakes at once.
func _quake() -> void:
	var tween := create_tween()
	tween.tween_method(func(v: float): _wheel_mat.set_shader_parameter("strike", v), 1.0, 0.0, 0.3)
	var ear := _player.global_position if _player else global_position
	AureliaSfx.play("quake", ear + Vector3(2, 0, 0), 6.0, randf_range(0.85, 1.0))
	AureliaSfx.play("quake_wave", ear - Vector3(2, 0, 0), 2.0, randf_range(0.9, 1.1))
	# Rock bursting up across the quaking ground.
	for i in 14:
		var spot := _random_danger_spot()
		SpellFx.shards(self, spot + Vector3.UP * 0.2, Color(0.4, 0.33, 0.28), 8, Vector2(4, 8), Vector2(0.12, 0.3), 0.9, 35.0, false)
		SpellFx.burst(self, spot + Vector3.UP * 0.3, Color(1.0, 0.6, 0.25), 8, Vector2(2, 5), 0.45, Vector2(0.08, 0.16), 40.0, -6.0)
		if i % 3 == 0:
			SmokePuff.spawn(self, spot, 1.2, Color(0.45, 0.38, 0.32))
	SpellFx.light_pop(self, global_position + Vector3.UP * 4.0, Color(1.0, 0.6, 0.3), 3.0, 7.0, 0.3)
	if _player and _player.health.is_alive() and _player.global_position.y - global_position.y < 2.5 and not is_safe_from_quake(_player.global_position):
		var amount := (_player.health.max_health + _player.ward.max_ward) * EARTH_WHEEL_SHARE
		_player.take_damage(amount, Constants.DamageType.KINETIC, boss, Player.HitKind.SPELL)
		SpellFx.shards(get_parent(), _player.global_position + Vector3.UP * 0.2, Color(0.45, 0.38, 0.3), 16, Vector2(4, 9), Vector2(0.12, 0.3), 0.9, 40.0, false)

func _random_danger_spot() -> Vector3:
	for attempt in 10:
		var a := randf() * TAU
		var r := sqrt(randf()) * (RADIUS - 1.0)
		var spot := to_global(Vector3(sin(a) * r, 0, cos(a) * r))
		if not is_safe_from_quake(spot):
			return spot
	return global_position

## ---- Amaterasu --------------------------------------------------------------

func start_amaterasu() -> void:
	if amaterasu_active:
		return
	amaterasu_active = true
	amaterasu_safe_radius = RADIUS - 1.0
	var ground := MeshInstance3D.new()
	ground.name = "Amaterasu"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (RADIUS + 2.0) * 2.0
	ground.mesh = plane
	_black_ground_mat = ShaderMaterial.new()
	_black_ground_mat.shader = BLACK_GROUND_SHADER
	_black_ground_mat.set_shader_parameter("radius", RADIUS + 2.0)
	ground.material_override = _black_ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = 0.06
	add_child(ground)
	# The wall of black flame along the creeping edge (a tube scaled to it).
	_black_wall = MeshInstance3D.new()
	_black_wall.mesh = SpellFx.tube(1.0, 1.0, AMATERASU_WALL_HEIGHT, 10, 96)
	var mat := ShaderMaterial.new()
	mat.shader = BLACK_FLAME_SHADER
	mat.set_shader_parameter("tiles", 48.0)
	mat.set_shader_parameter("period", 48.0)
	_black_wall.material_override = mat
	_black_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_black_wall)
	_black_smoke = SpellFx.emitter(self, 90, 2.6)
	_black_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_black_smoke.emission_ring_axis = Vector3.UP
	_black_smoke.emission_ring_height = 0.2
	_black_smoke.direction = Vector3.UP
	_black_smoke.spread = 15.0
	_black_smoke.initial_velocity_min = 0.8
	_black_smoke.initial_velocity_max = 1.8
	_black_smoke.scale_amount_min = 0.6
	_black_smoke.scale_amount_max = 1.4
	_black_smoke.scale_amount_curve = SpellFx.curve(0.5, 1.6)
	_black_smoke.color_ramp = SpellFx.ramp(Color(0.05, 0.0, 0.07, 0.0), Color(0.04, 0.0, 0.06, 0.55), 0.3)
	_black_smoke.mesh = SpellFx.glow_quad(false)
	_black_smoke.emitting = true
	_black_roar = AureliaSfx.loop(self, "amaterasu_loop", -8.0, 2.0)
	_update_amaterasu_visuals()

func _tick_amaterasu(delta: float) -> void:
	if not amaterasu_active:
		return
	if not _boss_alive():
		_end_amaterasu()
		return
	amaterasu_safe_radius = maxf(amaterasu_safe_radius - RADIUS / AMATERASU_SPREAD_SEC * delta, 0.0)
	_update_amaterasu_visuals()
	_amaterasu_tick -= delta
	if _amaterasu_tick > 0.0:
		return
	_amaterasu_tick = AMATERASU_TICK
	if _player and _player.health.is_alive() and in_black_fire(_player.global_position):
		var amount := (_player.health.current_health + _player.ward.current_ward) * AMATERASU_SHARE * AMATERASU_TICK
		_player.take_damage(amount, Constants.DamageType.FIRE, boss, Player.HitKind.DOT)

func in_black_fire(point: Vector3) -> bool:
	if not amaterasu_active:
		return false
	var local := to_local(point)
	return Vector2(local.x, local.z).length() > amaterasu_safe_radius

func _update_amaterasu_visuals() -> void:
	if _black_ground_mat:
		_black_ground_mat.set_shader_parameter("safe_radius", amaterasu_safe_radius)
	var r := maxf(amaterasu_safe_radius, 0.05)
	if is_instance_valid(_black_wall):
		_black_wall.scale = Vector3(r, 1.0, r)
		_black_wall.visible = amaterasu_safe_radius > 0.3
	if is_instance_valid(_black_smoke):
		_black_smoke.emission_ring_radius = r
		_black_smoke.emission_ring_inner_radius = maxf(r - 0.6, 0.0)

func _end_amaterasu() -> void:
	amaterasu_active = false
	AureliaSfx.fade_out(_black_roar, 1.5)
	for n in [_black_wall, _black_smoke, get_node_or_null("Amaterasu")]:
		if is_instance_valid(n):
			var fade := (n as Node3D).create_tween()
			fade.tween_property(n, "scale", Vector3(n.scale.x, 0.01, n.scale.z), 1.2)
			fade.tween_callback(n.queue_free)

## ---- Fire pots --------------------------------------------------------------

## A pool of fire on the floor that burns until clear_fire_pots().
func add_fire_pot(at: Vector3, tick_damage: float) -> void:
	var root := Node3D.new()
	root.name = "FirePot"
	add_child(root)
	root.global_position = Vector3(at.x, global_position.y, at.z)
	# The burning pool itself, flat on the floor.
	var pool := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * POT_RADIUS * 2.0
	pool.mesh = plane
	var pmat := ShaderMaterial.new()
	pmat.shader = POOL_SHADER
	pool.material_override = pmat
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position.y = 0.04
	root.add_child(pool)
	# Low flames licking up round its edge.
	var flame := MeshInstance3D.new()
	flame.mesh = SpellFx.tube(POT_RADIUS * 0.85, POT_RADIUS * 0.6, 0.9, 6, 40, 0.8)
	var fmat := ShaderMaterial.new()
	fmat.shader = FLAME_SHADER
	fmat.set_shader_parameter("tiles", 10.0)
	fmat.set_shader_parameter("period", 10.0)
	fmat.set_shader_parameter("fill", 0.22)
	fmat.set_shader_parameter("edge_soft", 0.15)
	flame.material_override = fmat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	BossFx.hazard_aura(root, POT_RADIUS, Constants.DamageType.FIRE)
	SpellFx.flash(self, root.global_position + Vector3.UP, Color(1.0, 0.5, 0.15), 3.0, 0.3)
	AureliaSfx.play("fire_pot", root.global_position, 0.0)
	root.scale = Vector3.ONE * 0.2
	root.create_tween().tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pots.append({"node": root, "center": root.global_position, "damage": tick_damage, "tick": 0.0})

func fire_pot_count() -> int:
	return _pots.size()

func clear_fire_pots() -> void:
	for pot in _pots:
		var node: Node3D = pot["node"]
		if is_instance_valid(node):
			SmokePuff.spawn(self, node.global_position, 0.8, Color(0.3, 0.27, 0.25))
			var fade := node.create_tween()
			fade.tween_property(node, "scale", Vector3(1.0, 0.01, 1.0), 0.4)
			fade.tween_callback(node.queue_free)
	_pots.clear()

func _tick_pots(delta: float) -> void:
	if _pots.is_empty():
		return
	if not _boss_alive():
		clear_fire_pots()
		return
	for pot in _pots:
		pot["tick"] -= delta
		if pot["tick"] > 0.0:
			continue
		pot["tick"] = POT_TICK
		if _player and _player.health.is_alive() and absf(_player.global_position.y - pot["center"].y) < 3.0 \
				and Vector2(_player.global_position.x - pot["center"].x, _player.global_position.z - pot["center"].z).length() <= POT_RADIUS + 0.3:
			_player.take_damage(pot["damage"], Constants.DamageType.FIRE, boss, Player.HitKind.DOT)

## ---- Call-outs --------------------------------------------------------------

## A line of text across the top of the screen that fades (her call-outs).
func announce(text: String, color: Color = Color(1.0, 0.85, 0.6), seconds: float = 2.6, font_size: int = 54) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = 150.0
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 10)
	var title_font: Font = load("res://assets/fonts/Cinzel-Variable.ttf")
	if title_font:
		label.add_theme_font_override("font", title_font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.modulate.a = 0.0
	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.25)
	tween.tween_interval(seconds)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(layer.queue_free)
