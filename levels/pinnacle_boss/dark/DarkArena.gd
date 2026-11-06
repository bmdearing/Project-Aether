extends Node3D
class_name DarkArena
## The Darkness Dragon's arena, built by PinnacleArena: a round undercroft
## floor in near-darkness, five Lightwells on a ring.
##   Dread: once the fight starts, the player gains Dread outside every lit
##   well's light and sheds it inside one. Each stack makes the dragon hit
##   harder (dread_damage_multiplier()). At DREAD_MAX the player is
##   Swallowed: a heavy Entropic hit and a short blackout, then Dread falls
##   back to DREAD_AFTER_SWALLOW. A dark vignette and a bar show the stacks.
##   Shades (Nightfall's adds, ShadeChannel) walk to lit wells and snuff them.
##   Eclipse (phase 3): only one well burns at a time, the sun well; the next
##   one is marked ECLIPSE_WARNING before the light moves to it.

const RADIUS := 24.0
const WELL_RING := 15.0
const WELLS := 5
const BOSS_SPAWN := Vector3(0, 0.05, -6.0)
const PLAYER_SPAWN := Vector3(0, 0.1, 19.0)
const PORTAL_SPOT := Vector3(0, 0.1, 12.0)
const EDGE_ROCKS := 22

const DREAD_MAX := 10.0
## About 17 seconds from none to Swallowed in the dark.
const DREAD_GAIN_PER_SEC := 0.6
const DREAD_DRAIN_PER_SEC := 2.0
const DREAD_DAMAGE_PER_STACK := 0.06
const SWALLOW_LIFE_SHARE := 0.35
const SWALLOW_BLACKOUT := 1.6
const DREAD_AFTER_SWALLOW := 4.0

const ECLIPSE_SHIFT_SEC := 12.0
const ECLIPSE_WARNING := 2.5

var boss: Enemy
var wells: Array[Lightwell] = []
var dread := 0.0
var eclipse := false
var sun_well := 0

var _player: Player
var _active := false
var _eclipse_timer := 0.0
var _next_sun := -1
var _hud: CanvasLayer
var _dread_bar: ProgressBar
var _dread_label: Label
var _vignette: ColorRect
var _blackout: ColorRect

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float edge = smoothstep(0.25, 0.75, d);
	COLOR = vec4(0.02, 0.0, 0.04, edge * strength);
}
"""

func _ready() -> void:
	add_to_group("dark_arena")
	_build_floor()
	_build_edge()
	_build_wells()
	_build_hud()
	EventBus.damage_dealt.connect(_on_damage_dealt)

func bind_boss(b: Enemy) -> void:
	boss = b

## ---- Build ----------------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "DarkFloor"
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS + 4.0
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS + 4.0
	disc.bottom_radius = RADIUS + 4.0
	disc.height = 1.0
	disc.radial_segments = 64
	mesh.mesh = disc
	mesh.position.y = -0.5
	var style := MapTileset.load_style("dungeon_undercroft")
	mesh.material_override = style.make_floor_material() if style else null
	body.add_child(mesh)

## Rocks and stalagmites round the rim, with an invisible ring wall.
func _build_edge() -> void:
	var rocks: Array[PackedScene] = []
	for path in ["res://entities/environment/doodads/dungeon/Dungeonrock0.tscn", "res://entities/environment/doodads/dungeon/Dungeonstalagmite0.tscn", "res://entities/environment/doodads/dungeon/Dungeonrock3.tscn", "res://entities/environment/doodads/dungeon/Dungeonstalagmite2.tscn"]:
		if ResourceLoader.exists(path):
			rocks.append(load(path))
	for i in EDGE_ROCKS:
		var angle := TAU * i / EDGE_ROCKS
		if not rocks.is_empty():
			var r := rocks[i % rocks.size()].instantiate() as Node3D
			add_child(r)
			r.position = Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 2.0)
			r.rotation.y = angle + PI + randf_range(-0.4, 0.4)
			r.scale = Vector3.ONE * randf_range(1.6, 2.4)
		var wall := StaticBody3D.new()
		var ws := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * (RADIUS + 1.0) / EDGE_ROCKS + 0.6, 10.0, 1.0)
		ws.shape = box
		wall.add_child(ws)
		add_child(wall)
		wall.position = Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 1.0) + Vector3.UP * 5.0
		wall.rotation.y = angle

## The first well stands by the player's entry, the rest spread round the ring.
func _build_wells() -> void:
	for i in WELLS:
		var angle := TAU * i / WELLS
		var w := Lightwell.new()
		w.name = "Lightwell%d" % i
		add_child(w)
		w.position = Vector3(sin(angle), 0, cos(angle)) * WELL_RING
		wells.append(w)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	mat.shader = shader
	_vignette.material = mat
	_hud.add_child(_vignette)
	_blackout = ColorRect.new()
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.color = Color(0, 0, 0, 0)
	_hud.add_child(_blackout)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-120, -250)
	box.custom_minimum_size = Vector2(240, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	_hud.add_child(box)
	_dread_label = Label.new()
	_dread_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dread_label.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0))
	_dread_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_dread_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_dread_label)
	_dread_bar = ProgressBar.new()
	_dread_bar.max_value = DREAD_MAX
	_dread_bar.show_percentage = false
	_dread_bar.custom_minimum_size = Vector2(240, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.5, 0.2, 0.85)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.03, 0.08, 0.8)
	_dread_bar.add_theme_stylebox_override("fill", fill)
	_dread_bar.add_theme_stylebox_override("background", back)
	box.add_child(_dread_bar)

## ---- Light ----------------------------------------------------------------

## In any lit well's light.
func is_lit(point: Vector3) -> bool:
	for w in wells:
		if w.lights(point):
			return true
	return false

func lit_count() -> int:
	return wells.filter(func(w: Lightwell): return w.lit).size()

## Puts out every well whose flame is inside the cone.
func snuff_cone(origin: Vector3, direction: Vector3, length: float, half_deg: float) -> void:
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	for w in wells:
		var to := w.global_position - origin
		to.y = 0.0
		if to.length() <= length and (to.length() < 0.5 or rad_to_deg(flat.angle_to(to.normalized())) <= half_deg):
			w.set_lit(false)

func snuff_all() -> void:
	for w in wells:
		w.set_lit(false)

## The lit well a Shade should go for: unclaimed first, then nearest.
func well_for_shade(point: Vector3) -> Lightwell:
	var best: Lightwell
	var best_score := INF
	for w in wells:
		if not w.lit:
			continue
		var claimed := get_tree().get_nodes_in_group("shade_channel").filter(func(c): return c.well == w).size()
		var score := claimed * 1000.0 + w.global_position.distance_to(point)
		if score < best_score:
			best_score = score
			best = w
	return best

## ---- Eclipse --------------------------------------------------------------

## Only the sun well (the one nearest the player) burns; the rest are locked dark.
func start_eclipse() -> void:
	eclipse = true
	var player := _get_player()
	var nearest := 0
	if player:
		for i in wells.size():
			if wells[i].global_position.distance_to(player.global_position) < wells[nearest].global_position.distance_to(player.global_position):
				nearest = i
	_set_sun(nearest)

func _set_sun(index: int) -> void:
	sun_well = index
	_eclipse_timer = ECLIPSE_SHIFT_SEC
	for i in wells.size():
		var w := wells[i]
		w.marked = false
		w.locked = i != index
		if i == index:
			w.set_lit(true)
		else:
			w.set_lit(false)

func _tick_eclipse(delta: float) -> void:
	_eclipse_timer -= delta
	if _eclipse_timer <= ECLIPSE_WARNING and _next_sun < 0:
		# One or two wells round the ring, so the route can't be learned by rote.
		_next_sun = (sun_well + (1 if randf() < 0.5 else 2)) % wells.size()
		wells[_next_sun].marked = true
	if _eclipse_timer <= 0.0:
		var target := _next_sun if _next_sun >= 0 else (sun_well + 1) % wells.size()
		_next_sun = -1
		_set_sun(target)

## ---- Dread ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var player := _get_player()
	if not _active:
		_active = boss != null and is_instance_valid(boss) and boss.boss_brain != null and boss.boss_brain.engaged
	var fighting := _active and is_instance_valid(boss) and boss.health.is_alive() and player != null and player.health.is_alive()
	if fighting:
		if eclipse:
			_tick_eclipse(delta)
		if is_lit(player.global_position):
			dread = maxf(dread - DREAD_DRAIN_PER_SEC * delta, 0.0)
		else:
			dread = minf(dread + DREAD_GAIN_PER_SEC * delta, DREAD_MAX)
			if dread >= DREAD_MAX:
				swallow()
	elif not (is_instance_valid(boss) and boss.health.is_alive()):
		dread = maxf(dread - DREAD_DRAIN_PER_SEC * delta, 0.0)
	_update_hud(fighting)

## Each stack of Dread: the dragon's hits deal DREAD_DAMAGE_PER_STACK more.
func dread_damage_multiplier() -> float:
	return 1.0 + DREAD_DAMAGE_PER_STACK * floorf(dread)

## A heavy Entropic hit and a blackout; Dread drops back down after.
func swallow(life_share: float = SWALLOW_LIFE_SHARE) -> void:
	var player := _get_player()
	if player == null:
		return
	dread = DREAD_AFTER_SWALLOW
	player.take_damage(player.health.max_health * life_share, Constants.DamageType.ENTROPIC, boss if is_instance_valid(boss) else null, Player.HitKind.SPELL)
	var tween := create_tween()
	tween.tween_property(_blackout, "color:a", 0.96, 0.15)
	tween.tween_interval(SWALLOW_BLACKOUT * 0.5)
	tween.tween_property(_blackout, "color:a", 0.0, SWALLOW_BLACKOUT * 0.5)
	if is_instance_valid(boss):
		BossFx.sound(boss.roar_sound(), player.global_position, -4.0, 0.7)

func _update_hud(fighting: bool) -> void:
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", clampf(dread / DREAD_MAX, 0.0, 1.0) * 0.85)
	var box := _dread_bar.get_parent() as Control
	box.visible = fighting or dread > 0.0
	_dread_bar.value = dread
	_dread_label.text = "Dread %d / %d" % [int(floorf(dread)), int(DREAD_MAX)]

## A Fire hit landed while standing beside a dark well lights it at once.
func _on_damage_dealt(source: Node, _target: Node, _amount: float, damage_type: int, _more: bool, _crit: bool) -> void:
	if not source is Player or damage_type != Constants.DamageType.FIRE:
		return
	for w in wells:
		if not w.lit and not w.locked and w.is_beside((source as Player).global_position):
			w.set_lit(true)

func _get_player() -> Player:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player

const BossFx := preload("res://entities/effects/boss_fx/BossFx.gd")
