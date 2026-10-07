extends Node
class_name StanceDefense
## Held defensive stances (Patch v3.4 melee table, mostly Stance B): their
## effects last exactly as long as RMB holds the stance. Driven by the
## active MeleeStanceBehavior's "Held stance" fields:
## - Guard (Greatsword): negates melee_damage_blocked of each melee hit.
## - Fortify (Mace): roots you; damage_reduction off everything.
## - Phalanx (Spear): a frontal barrier that soaks hits until its pool
##   (barrier_fraction of max life) runs out; refills out of stance.
## - Brace (Halberd): roots you; enemies that close in front are struck
##   for Piercing damage and staggered.
## Parry stances need nothing here - ParryRiposteHandler reads the window.

signal barrier_broken

const BARRIER_REGEN_DELAY := 3.0
const BARRIER_REGEN_TIME := 4.0      # empty to full
const BRACE_HALF_ANGLE := 70.0
const BRACE_COOLDOWN := 1.5          # per enemy
const BRACE_STAGGER := 25.0          # Composure damage on a brace strike
const FORTIFY_COLOR := Color(1.0, 0.8, 0.45, 0.35)
const BARRIER_COLOR := Color(0.55, 0.8, 1.0, 0.12)
const BARRIER_SIZE := Vector2(2.2, 0.9)
const BARRIER_DISTANCE := 1.3

var barrier: float = 0.0
var _barrier_regen_delay: float = 0.0
var _brace_ready_at: Dictionary = {}   # enemy instance id -> msec
var _in_brace_range: Dictionary = {}
var _player: Player
var _barrier_mesh: MeshInstance3D
var _fortify_ring: MeshInstance3D

func _ready() -> void:
	_player = get_parent()
	barrier = get_max_barrier()

func _behavior() -> MeleeStanceBehavior:
	if not _player.weapon_stance.is_active:
		return null
	return _player.weapon_stance.current_behavior as MeleeStanceBehavior

func is_rooted() -> bool:
	var b := _behavior()
	return b != null and b.roots

func get_move_speed_multiplier() -> float:
	return 0.0 if is_rooted() else 1.0

## Sized from the equipped weapon's stance even outside stance, so the
## barrier refills toward the right maximum.
func get_max_barrier() -> float:
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return 0.0
	var b := _player.weapon_stance._resolve_behavior(weapon) as MeleeStanceBehavior
	return _player.health.max_health * b.barrier_fraction if b else 0.0

func is_barrier_up() -> bool:
	var b := _behavior()
	return b != null and b.barrier_fraction > 0.0 and barrier > 0.0

## Called by Player.take_damage() for every hit; returns what gets through.
func absorb(amount: float, source: Node, hit_kind: Player.HitKind, is_melee: bool) -> float:
	var b := _behavior()
	if b == null:
		return amount
	if is_melee and b.melee_damage_blocked > 0.0:
		amount *= 1.0 - b.melee_damage_blocked
		EventBus.hit_blocked.emit(_player)
	if b.damage_reduction > 0.0:
		amount *= 1.0 - b.damage_reduction
	if b.barrier_fraction > 0.0 and barrier > 0.0 and hit_kind != Player.HitKind.DOT and _is_in_front(source, b.barrier_half_angle):
		var soaked := minf(barrier, amount)
		barrier -= soaked
		amount -= soaked
		_barrier_regen_delay = BARRIER_REGEN_DELAY
		_pulse_barrier()
		if barrier <= 0.0:
			barrier_broken.emit()
	return amount

func _is_in_front(source: Node, half_angle: float) -> bool:
	if not (source is Node3D):
		return false
	var to_source := (source as Node3D).global_position - _player.global_position
	to_source.y = 0.0
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	if to_source.length() < 0.01 or forward.length() < 0.01:
		return true
	return rad_to_deg(forward.normalized().angle_to(to_source.normalized())) <= half_angle

func _physics_process(delta: float) -> void:
	var b := _behavior()
	var max_barrier := get_max_barrier()
	if b != null and b.barrier_fraction > 0.0:
		_barrier_regen_delay = BARRIER_REGEN_DELAY
	elif _barrier_regen_delay > 0.0:
		_barrier_regen_delay -= delta
	elif max_barrier > 0.0:
		barrier = minf(barrier + max_barrier / BARRIER_REGEN_TIME * delta, max_barrier)
	barrier = minf(barrier, max_barrier)
	if b != null and b.brace_range > 0.0:
		_update_brace(b)
	else:
		_in_brace_range.clear()
	_update_visuals(b)

## Strikes each enemy as it enters range in front, or as it starts an
## attack while already there, at most once per BRACE_COOLDOWN.
func _update_brace(b: MeleeStanceBehavior) -> void:
	var now := Time.get_ticks_msec()
	var still_in_range := {}
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var offset := enemy.global_position - _player.global_position
		offset.y = 0.0
		if offset.length() - 0.5 > b.brace_range or not _is_in_front(enemy, BRACE_HALF_ANGLE):
			continue
		var id := enemy.get_instance_id()
		still_in_range[id] = true
		var entering := not _in_brace_range.has(id)
		if (entering or enemy.is_attack_locked()) and now >= int(_brace_ready_at.get(id, 0)):
			_brace_ready_at[id] = now + int(BRACE_COOLDOWN * 1000.0)
			_player.melee_attack.deal_stance_damage(enemy, b.brace_motion_value, Constants.DamageType.PIERCING)
			enemy.interrupt_attack()
			if enemy.stance:
				enemy.stance.apply_parry_damage(BRACE_STAGGER)
	_in_brace_range = still_in_range

func _update_visuals(b: MeleeStanceBehavior) -> void:
	var show_barrier := b != null and b.barrier_fraction > 0.0 and barrier > 0.0
	if show_barrier and _barrier_mesh == null:
		_barrier_mesh = _make_barrier()
	if _barrier_mesh:
		_barrier_mesh.visible = show_barrier
	var fortified := b != null and b.damage_reduction > 0.0
	if fortified and _fortify_ring == null:
		_fortify_ring = _make_ring()
	if _fortify_ring:
		_fortify_ring.visible = fortified

func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat

## A low pale wall in front of the camera, turning with the view.
func _make_barrier() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = BARRIER_SIZE
	mesh_instance.mesh = quad
	mesh_instance.material_override = _unshaded(BARRIER_COLOR)
	_player.camera.add_child(mesh_instance)
	mesh_instance.position = Vector3(0.0, -0.75, -BARRIER_DISTANCE)
	return mesh_instance

func _pulse_barrier() -> void:
	if _barrier_mesh == null:
		return
	var mat := _barrier_mesh.material_override as StandardMaterial3D
	var tween := _barrier_mesh.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.45, 0.04)
	tween.tween_property(mat, "albedo_color:a", BARRIER_COLOR.a, 0.25)

## A ring on the ground around your feet while Fortify holds.
func _make_ring() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.12
	torus.outer_radius = 1.2
	torus.rings = 48
	mesh_instance.mesh = torus
	mesh_instance.material_override = _unshaded(FORTIFY_COLOR)
	_player.add_child(mesh_instance)
	mesh_instance.position = Vector3(0.0, 0.05, 0.0)
	mesh_instance.scale = Vector3(1.0, 0.15, 1.0)
	return mesh_instance
