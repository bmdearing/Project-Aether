extends Node3D
class_name SandArena
## Ataras's arena, built by PinnacleArena: a round floor of sand ringed by
## rock pillars and broken walls.
##
##   Shifting Sands (his phase 2 opener, at 50% Life): the floor splits into
##   three wedges. Two turn to quicksand after a warning; only the third is
##   safe. Quicksand hurts (a share of max Life per tick, Kinetic) and slows.
##   Partway through, with a warning, the safe wedge moves once to one of the
##   others. After WEDGE_DURATION the sand settles and the arena is safe again.
##   Ticking Time marks (Ataras.cast_custom) turn into permanent sand traps
##   that hurt the player standing in them, and slow Ataras and drain his
##   Composure when he crosses them.

signal wedges_ended

const RADIUS := 22.0
const BOSS_SPAWN := Vector3(0, 0.05, -10.0)
const PLAYER_SPAWN := Vector3(0, 0.1, 14.0)
const PORTAL_SPOT := Vector3(0, 0.1, 10.0)
const WEDGES := 3
const WEDGE_WARNING := 3.0
const WEDGE_DURATION := 14.0
const TICK := 0.5
## Shares of the player's maximum Life per tick, before armour.
const WEDGE_DAMAGE := 0.04
const TRAP_DAMAGE := 0.025
const QUICKSAND_COLOR := Color(0.32, 0.17, 0.06, 0.72)
const WARNING_COLOR := Color(1.0, 0.4, 0.15, 0.45)
const TRAP_COLOR := Color(0.85, 0.62, 0.3, 0.55)
const EDGE_PILLARS := 18
## The safe wedge moves once: this far into the quicksand, after a warning.
const WEDGE_SHIFT_AT := 6.0
const WEDGE_SHIFT_WARNING := 2.5
const SHIFT_WARNING_COLOR := Color(1.0, 0.85, 0.2, 0.5)
## Composure Ataras loses per tick standing in a trap.
const TRAP_STANCE_DRAIN := 9.0

var boss: Enemy
var safe_wedge := -1
var wedges_active := false
var wedges_dangerous := false
## [{"center": Vector3, "radius": float, "node": Node3D}]
var traps: Array[Dictionary] = []

var _player: Player
var _tick := 0.0
## wedge index -> its overlay.
var _wedge_nodes: Dictionary = {}

func _ready() -> void:
	add_to_group("sand_arena")
	_build_floor()
	_build_edge()

func bind_boss(b: Enemy) -> void:
	boss = b

## ---- Build ----------------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "SandFloor"
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
	var style := MapTileset.load_style("desert_dunes")
	mesh.material_override = style.make_floor_material() if style else null
	body.add_child(mesh)

## Rock pillars around the rim, with an invisible ring wall just outside.
func _build_edge() -> void:
	var pillars: Array[PackedScene] = []
	for path in ["res://entities/environment/doodads/desert/Rockpillar0.tscn", "res://entities/environment/doodads/desert/Ruinedwall.tscn", "res://entities/environment/doodads/desert/BarrensSpires0.tscn"]:
		if ResourceLoader.exists(path):
			pillars.append(load(path))
	for i in EDGE_PILLARS:
		var angle := TAU * i / EDGE_PILLARS
		var pos := Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 2.0)
		if not pillars.is_empty():
			var p := pillars[i % pillars.size()].instantiate() as Node3D
			add_child(p)
			p.position = pos
			p.rotation.y = angle + PI
			p.scale = Vector3.ONE * randf_range(1.2, 1.6)
		var wall := StaticBody3D.new()
		var ws := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * (RADIUS + 3.0) / EDGE_PILLARS + 0.5, 8.0, 1.0)
		ws.shape = box
		wall.add_child(ws)
		add_child(wall)
		wall.position = Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 3.0) + Vector3.UP * 4.0
		wall.rotation.y = angle

## ---- Shifting Sands ---------------------------------------------------------

## The wedge (0..WEDGES-1) a point is in, by angle around the centre.
func wedge_of(point: Vector3) -> int:
	var local := to_local(point)
	var angle := fposmod(atan2(local.x, local.z), TAU)
	return int(angle / (TAU / WEDGES)) % WEDGES

func start_wedges() -> void:
	if wedges_active:
		return
	wedges_active = true
	safe_wedge = randi() % WEDGES
	for i in WEDGES:
		if i == safe_wedge:
			continue
		_wedge_nodes[i] = _sector(i, WARNING_COLOR)
	await get_tree().create_timer(WEDGE_WARNING, false).timeout
	if not is_inside_tree():
		return
	wedges_dangerous = true
	for node in _wedge_nodes.values():
		_tint(node, QUICKSAND_COLOR)
	await get_tree().create_timer(WEDGE_SHIFT_AT, false).timeout
	if not is_inside_tree() or not wedges_active:
		return
	await shift_safe_wedge()
	if not is_inside_tree() or not wedges_active:
		return
	await get_tree().create_timer(maxf(WEDGE_DURATION - WEDGE_SHIFT_AT - WEDGE_SHIFT_WARNING, 0.5), false).timeout
	if not is_inside_tree():
		return
	end_wedges()

## The safe wedge moves: the current one flashes a warning, then sinks while
## one of the others clears.
func shift_safe_wedge() -> void:
	var old := safe_wedge
	var next := (old + 1 + randi() % (WEDGES - 1)) % WEDGES
	var warning := _sector(old, SHIFT_WARNING_COLOR)
	_wedge_nodes[old] = warning
	if _wedge_nodes.has(next):
		_tint(_wedge_nodes[next], Color(0.95, 0.9, 0.6, 0.35))
	await get_tree().create_timer(WEDGE_SHIFT_WARNING, false).timeout
	if not is_inside_tree() or not wedges_active:
		return
	_tint(warning, QUICKSAND_COLOR)
	if _wedge_nodes.has(next):
		_wedge_nodes[next].queue_free()
		_wedge_nodes.erase(next)
	safe_wedge = next

func _tint(node: Node, color: Color) -> void:
	if is_instance_valid(node):
		((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = color

func end_wedges() -> void:
	wedges_dangerous = false
	wedges_active = false
	for node in _wedge_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_wedge_nodes.clear()
	wedges_ended.emit()

## A filled pie slice over one wedge, slightly above the sand.
func _sector(index: int, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start := index * TAU / WEDGES
	var steps := 24
	for i in steps:
		var a0 := start + TAU / WEDGES * i / steps
		var a1 := start + TAU / WEDGES * (i + 1) / steps
		for v in [Vector3.ZERO, Vector3(sin(a1), 0, cos(a1)) * RADIUS, Vector3(sin(a0), 0, cos(a0)) * RADIUS]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3.UP * 0.03)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi

## ---- Ticking Time traps ------------------------------------------------------

## A permanent patch of grasping sand.
func add_trap(at: Vector3, radius: float) -> void:
	var marker := BossTelegraph.circle(self, at, radius, 0.01, TRAP_COLOR)
	marker.persist = true
	traps.append({"center": at, "radius": radius, "node": marker})

func in_trap(point: Vector3) -> bool:
	for t in traps:
		var c: Vector3 = t["center"]
		if Vector2(point.x - c.x, point.z - c.z).length() <= float(t["radius"]):
			return true
	return false

## ---- Damage -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_trap_boss()
	if _player == null or not _player.health.is_alive():
		return
	var share := 0.0
	if wedges_dangerous and wedge_of(_player.global_position) != safe_wedge:
		share += WEDGE_DAMAGE
		_player.status_effects.apply_effect("slow", boss)
	if in_trap(_player.global_position):
		share += TRAP_DAMAGE
	if share > 0.0:
		var amount := _player.health.max_health * share * (1.0 - _player.get_dot_mitigation())
		_player.take_damage(amount, Constants.DamageType.KINETIC, boss if is_instance_valid(boss) else null, Player.HitKind.DOT)

## Ataras crossing his own traps: slowed and losing Composure.
func _trap_boss() -> void:
	if not is_instance_valid(boss) or not boss.health.is_alive() or not in_trap(boss.global_position):
		return
	boss.status_effects.apply_effect("slow", null)
	if boss.stance:
		boss.stance.apply_parry_damage(TRAP_STANCE_DRAIN)
