extends Node3D
class_name SpiderMinion
## Invocation of Arach's summon: an Entropic spider that crawls along the
## ground to the nearest enemy and bites it. At most LIMIT live at once (a
## new one makes the oldest crumble); each fades when its time runs out.
## Like the Wraith it can't be hurt and isn't stopped by walls.

const LIMIT := 10
const GROUP := &"spider_minion"
const SPEED := 7.0
const BITE_RANGE := 1.3
const BASE_ATTACK_INTERVAL := 0.7
const BASE_DURATION := 15.0
## Searches this far from the player for prey.
const HUNT_RANGE := 25.0
const IDLE_RADIUS := 2.5
const COLOR := Color(0.55, 0.22, 0.75)

var ability: Ability
var player: Player

var _life: float = BASE_DURATION
var _attack_timer: float = 0.0
var _target: Enemy
var _body: Node3D
var _legs: Array[Node3D] = []
var _time := 0.0
var _idle_angle := randf() * TAU

static func summon(scene_root: Node, owner_player: Player, spell: Ability, at: Vector3) -> SpiderMinion:
	var live := scene_root.get_tree().get_nodes_in_group(GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	while live.size() >= LIMIT:
		(live.pop_front() as SpiderMinion).crumble()
	var s := SpiderMinion.new()
	s.ability = spell
	s.player = owner_player
	scene_root.add_child(s)
	s.global_position = at
	return s

func _ready() -> void:
	add_to_group("minion")
	add_to_group(GROUP)
	var sheet := player.stat_sheet if player else null
	var duration_mult := ability.get_duration_multiplier(sheet) if ability else 1.0
	var minion_duration := (1.0 + sheet.get_misc_bonus("minion_duration") / 100.0) if sheet else 1.0
	_life = BASE_DURATION * duration_mult * minion_duration
	_build_body()
	SmokePuff.spawn(get_parent(), global_position, 0.8, COLOR)

func crumble() -> void:
	remove_from_group(GROUP)
	SmokePuff.spawn(get_parent(), global_position, 0.7, COLOR)
	queue_free()

## A dark carapace over a glowing abdomen, with eight jointed legs.
func _build_body() -> void:
	_body = Node3D.new()
	_body.position.y = 0.32
	add_child(_body)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.12, 0.08, 0.16)
	shell.roughness = 0.45
	shell.metallic = 0.3
	var abdomen := MeshInstance3D.new()
	var abdomen_mesh := SphereMesh.new()
	abdomen_mesh.radius = 0.24
	abdomen_mesh.height = 0.42
	abdomen.mesh = abdomen_mesh
	abdomen.material_override = SpellFx.energy_material(COLOR, 1.2, 0.35)
	abdomen.position = Vector3(0, 0.05, 0.3)
	abdomen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(abdomen)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15
	head_mesh.height = 0.26
	head.mesh = head_mesh
	head.material_override = shell
	head.position = Vector3(0, 0.0, -0.05)
	_body.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.03
		eye_mesh.height = 0.06
		eye.mesh = eye_mesh
		var eye_mat := SpellFx.glow_material(Color(1.6, 0.5, 1.8, 1.0), true, BaseMaterial3D.BILLBOARD_DISABLED)
		eye_mat.vertex_color_use_as_albedo = false
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(side * 0.06, 0.05, -0.18)
		_body.add_child(eye)
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.018
	leg_mesh.bottom_radius = 0.012
	leg_mesh.height = 0.5
	for side in [-1.0, 1.0]:
		for i in 4:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.1, 0.0, -0.1 + i * 0.09)
			pivot.rotation = Vector3(0.0, side * (-0.6 + i * 0.4), side * -0.9)
			_body.add_child(pivot)
			var leg := MeshInstance3D.new()
			leg.mesh = leg_mesh
			leg.material_override = shell
			leg.position = Vector3(0, -0.22, 0)
			pivot.add_child(leg)
			_legs.append(pivot)

func _physics_process(delta: float) -> void:
	_time += delta
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(player) or not player.health.is_alive():
		crumble()
		return
	if not _valid(_target):
		_target = _nearest_enemy()
	var goal := player.global_position + Vector3(cos(_idle_angle), 0.0, sin(_idle_angle)) * IDLE_RADIUS
	if _target:
		goal = _target.global_position
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var reach := BITE_RANGE + (_target.body_radius if _target else 0.0)
	var moving := to_goal.length() > reach
	if moving:
		global_position += to_goal.normalized() * minf(SPEED * delta, to_goal.length() - reach * 0.5)
		look_at(global_position + to_goal, Vector3.UP)
	_follow_ground()
	# Legs skitter while it moves.
	for i in _legs.size():
		var swing := sin(_time * 22.0 + i * PI * 0.5) * (0.35 if moving else 0.05)
		_legs[i].rotation.x = swing
	_attack_timer -= delta
	if _target and not moving and _attack_timer <= 0.0:
		_attack_timer = BASE_ATTACK_INTERVAL / (1.0 + player.stat_sheet.get_misc_bonus("minion_attack_speed") / 100.0)
		_bite(_target)

## Stays on whatever floor is below it.
func _follow_ground() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and not hit["collider"] is Enemy:
		global_position.y = (hit["position"] as Vector3).y

## Untyped: a freed target can't be passed as an Enemy.
func _valid(e) -> bool:
	return is_instance_valid(e) and e.health.is_alive() and e.global_position.distance_to(player.global_position) <= HUNT_RANGE + 5.0

func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_d := HUNT_RANGE
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null or not e.health.is_alive():
			continue
		var d := e.global_position.distance_to(global_position)
		if d < best_d and e.global_position.distance_to(player.global_position) <= HUNT_RANGE:
			best_d = d
			best = e
	return best

func _bite(enemy: Enemy) -> void:
	var hit := ability.roll_damage(player.stat_sheet)
	var damage: float = float(hit["final_damage"]) * (1.0 + player.stat_sheet.get_misc_bonus("minion_damage") / 100.0)
	if not enemy.take_damage(damage, ability.damage_type, true):
		return
	EventBus.damage_dealt.emit(player, enemy, damage, ability.damage_type, false, hit["is_critical"])
	_body.position.z = -0.18
	create_tween().tween_property(_body, "position:z", 0.0, 0.2)
