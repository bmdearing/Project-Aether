extends Node3D
class_name WraithMinion
## The Wraith spell's summon: a hooded shade that drifts at the player's
## shoulder, flies at the nearest enemy within reach and strikes it with
## Aetheric damage. It passes through walls (it's a wraith), can't be hurt,
## and fades when its time runs out. While it lives the player can't recover
## Ward (WardComponent.recovery_locks).

const SPEED := 8.0
const STRIKE_RANGE := 1.6
const BASE_ATTACK_INTERVAL := 0.8
const BASE_DURATION := 20.0
const HOVER := 1.3
const IDLE_OFFSET := Vector3(0.9, 0.0, 0.9)
const COLOR := Color(0.45, 0.86, 1.0, 0.38)
## Each Ward-per-stack consumed adds this much more damage.
const MORE_PER_STACK := 0.05

var ability: Ability
var player: Player
## More-damage stacks from the Ward it consumed.
var stacks: int = 0
var damage_share: float = 1.0

var _life: float = BASE_DURATION
var _attack_timer: float = 0.0
var _target: Enemy
var _body: Node3D
var _time := 0.0

static func summon(scene_root: Node, owner_player: Player, spell: Ability, ward_stacks: int, share: float, offset: Vector3) -> WraithMinion:
	var w := WraithMinion.new()
	w.ability = spell
	w.player = owner_player
	w.stacks = ward_stacks
	w.damage_share = share
	scene_root.add_child(w)
	w.global_position = owner_player.global_position + offset + Vector3.UP * HOVER
	return w

func _ready() -> void:
	add_to_group("minion")
	var stat_sheet := player.stat_sheet if player else null
	var duration_mult := ability.get_duration_multiplier(stat_sheet) if ability else 1.0
	var minion_duration := (1.0 + stat_sheet.get_misc_bonus("minion_duration") / 100.0) if stat_sheet else 1.0
	var bound := 1.5 if ability and ability.has_twist("bound_soul") else 1.0
	_life = BASE_DURATION * duration_mult * minion_duration * bound
	if player:
		player.ward.recovery_locks[get_instance_id()] = true
	_build_body()
	SmokePuff.spawn(get_parent(), global_position - Vector3.UP * HOVER, 1.2, Color(0.5, 0.8, 1.0))

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.ward.recovery_locks.erase(get_instance_id())

func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = Color(COLOR.r, COLOR.g, COLOR.b) * 0.6
	var robe := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 0.45
	cone.height = 1.3
	robe.mesh = cone
	robe.material_override = mat
	robe.position = Vector3(0, -0.2, 0)
	_body.add_child(robe)
	var hood := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	hood.mesh = sphere
	hood.material_override = mat
	hood.position = Vector3(0, 0.55, 0)
	_body.add_child(hood)
	# Wisps trailing off the robe.
	var wisps := CPUParticles3D.new()
	wisps.amount = 18
	wisps.lifetime = 0.9
	wisps.local_coords = false
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = 0.3
	wisps.position = Vector3(0, -0.6, 0)
	wisps.gravity = Vector3(0, 0.4, 0)
	wisps.initial_velocity_min = 0.1
	wisps.initial_velocity_max = 0.4
	wisps.scale_amount_min = 0.15
	wisps.scale_amount_max = 0.35
	var fade := Gradient.new()
	fade.set_color(0, Color(COLOR.r, COLOR.g, COLOR.b, 0.6))
	fade.set_color(1, Color(COLOR.r, COLOR.g, COLOR.b, 0.0))
	wisps.color_ramp = fade
	var quad := QuadMesh.new()
	var wisp_mat := StandardMaterial3D.new()
	wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	wisp_mat.vertex_color_use_as_albedo = true
	wisp_mat.albedo_texture = GlowTexture.radial()
	quad.material = wisp_mat
	wisps.mesh = quad
	_body.add_child(wisps)
	var light := OmniLight3D.new()
	light.light_color = Color(COLOR.r, COLOR.g, COLOR.b)
	light.light_energy = 0.8
	light.omni_range = 3.0
	_body.add_child(light)

func _physics_process(delta: float) -> void:
	_time += delta
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(player) or not player.health.is_alive():
		SmokePuff.spawn(get_parent(), global_position - Vector3.UP * HOVER, 1.0, Color(0.5, 0.8, 1.0))
		queue_free()
		return
	_body.position.y = sin(_time * 2.4) * 0.12
	if not _valid(_target):
		_target = _nearest_enemy()
	var goal := player.global_position + IDLE_OFFSET.rotated(Vector3.UP, player.rotation.y) + Vector3.UP * HOVER
	if _target:
		goal = _target.global_position + Vector3.UP * HOVER
	var to_goal := goal - global_position
	var reach := STRIKE_RANGE if _target else 0.2
	if to_goal.length() > reach:
		global_position += to_goal.normalized() * minf(SPEED * delta, to_goal.length() - reach * 0.5)
	if to_goal.length() > 0.05:
		var flat := Vector3(to_goal.x, 0, to_goal.z)
		if flat.length() > 0.05:
			look_at(global_position + flat, Vector3.UP)
	_attack_timer -= delta
	if _target and to_goal.length() <= STRIKE_RANGE + 0.3 and _attack_timer <= 0.0:
		_attack_timer = BASE_ATTACK_INTERVAL / (1.0 + player.stat_sheet.get_misc_bonus("minion_attack_speed") / 100.0)
		_strike(_target)

func _valid(e: Enemy) -> bool:
	return is_instance_valid(e) and e.health.is_alive() and e.global_position.distance_to(player.global_position) <= ability.get_radius(player.stat_sheet) + 5.0

func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_d := ability.get_radius(player.stat_sheet)
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null or not e.health.is_alive():
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

## Damage per strike: the spell's hit, more for every stack of Ward it
## drank, and increased by minion damage.
func strike_damage() -> Dictionary:
	var hit := ability.roll_damage(player.stat_sheet)
	var mult := (1.0 + stacks * MORE_PER_STACK) * (1.0 + player.stat_sheet.get_misc_bonus("minion_damage") / 100.0) * damage_share
	return {"final_damage": float(hit["final_damage"]) * mult, "is_critical": hit["is_critical"]}

func _strike(enemy: Enemy) -> void:
	var hit := strike_damage()
	var damage: float = hit["final_damage"]
	if not enemy.take_damage(damage, ability.damage_type, true):
		return
	EventBus.damage_dealt.emit(player, enemy, damage, ability.damage_type, false, hit["is_critical"])
	ability.apply_statuses(enemy, player, damage)
	_body.position.z = -0.25  # a lunge the next frames ease back from
	create_tween().tween_property(_body, "position:z", 0.0, 0.25)
