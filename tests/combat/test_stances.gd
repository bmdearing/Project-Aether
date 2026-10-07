extends Node
## Charge-and-release stance attacks (StanceAttack), driven through real
## input: hold RMB, hold LMB to charge, release.
## Run: Godot --headless --path . res://tests/combat/test_stances.tscn --quit-after 30000

var _checks := 0
var _failures := 0
var _arena: Node3D
var _player: Player
const START := Vector3(0, 0.05, 0)

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(s * Engine.physics_ticks_per_second))

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	GameState.stance_page = 0
	await _setup()
	await _test_rapier()
	await _test_spear()
	await _test_execute()
	await _test_mace()
	await _test_discharge()
	await _test_pressure_blast()
	await _test_whip()
	await _test_cancel_and_fallback()
	print("stance tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _setup() -> void:
	_arena = Node3D.new()
	add_child(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_arena.add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	_arena.add_child(_player)
	await _frames(3)
	_clear()
	await _frames(2)

func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()

func _reset(weapon_type: String) -> void:
	Input.action_release("attack")
	Input.action_release("stance")
	await _frames(2)
	while not _player.melee_attack.is_idle():
		await _frames(1)
	_clear()
	var w := Weapon.new()
	w.weapon_type = weapon_type
	w.base_damage_min = 50.0
	w.base_damage_max = 50.0
	w.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
	_player.equipment.primary_weapon = w
	_player.global_position = START
	_player.velocity = Vector3.ZERO
	await _frames(5)

func _forward() -> Vector3:
	return -_player.global_transform.basis.z

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	e.position = pos  # before entering the tree, or it spends a frame at the origin under the player
	_arena.add_child(e)
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.armor_value = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	var melee := e.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
	return e

func _lost(e: Enemy) -> float:
	return 1.0e6 - e.health.current_health

## Enter stance, charge for `seconds`, release, let the swing finish.
func _charge(seconds: float, settle: float = 0.6) -> void:
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _seconds(seconds)
	Input.action_release("attack")
	await _seconds(settle)

func _travel() -> float:
	return (_player.global_position - START).dot(_forward())

func _test_rapier() -> void:
	await _reset("Rapier")
	await _charge(0.1)
	var short := _travel()
	_check(short > 1.3 and short < 1.8, "rapier tap lunges about 1.5 m (%.2f)" % short)
	await _reset("Rapier")
	var target := _dummy(START + _forward() * 5.5)
	await _frames(2)
	await _charge(0.7)
	var full := _travel()
	_check(full > 3.7 and full < 4.4, "rapier full charge lunges about 4 m (%.2f)" % full)
	_check(_lost(target) > 0.0, "rapier lunge thrust hits a target 5.5 m away")

func _test_spear() -> void:
	await _reset("Spear")
	await _charge(0.9)
	var full := _travel()
	_check(full > 5.0 and full < 6.8, "spear full charge lunges about 6 m (%.2f)" % full)

func _test_execute() -> void:
	await _reset("Greatsword")
	var near := _dummy(START + _forward() * 2.0)
	var side := _dummy(START + _forward() * 1.8 + _player.global_transform.basis.x * 2.0)
	var far := _dummy(START + _forward() * 7.0)
	await _frames(2)
	await _charge(0.5)
	_check(_lost(near) == 0.0, "execute released early does nothing")
	await _charge(1.1, 1.2)
	_check(_lost(near) > 0.0 and _lost(side) > 0.0, "execute slam hits everything in its radius")
	_check(_lost(far) == 0.0, "execute slam misses enemies outside it")
	var jab_scale: float = _lost(near)
	_check(jab_scale > 150.0, "execute hits hard (%.0f from a 50-damage weapon)" % jab_scale)

func _test_mace() -> void:
	await _reset("Mace")
	var target := _dummy(START + _forward() * 1.8)
	await _frames(2)
	Input.action_press("move_forward")
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _seconds(0.3)
	var charging_from := _travel()
	await _seconds(0.6)
	var moved := _travel() - charging_from
	Input.action_release("attack")
	Input.action_release("move_forward")
	await _seconds(0.5)
	_check(moved < 0.02, "mace roots you while charging (%.2f m)" % moved)
	var slam := _lost(target)
	_check(slam > 0.0, "overhead slam hits")
	await _seconds(1.3)
	_check(_lost(target) > slam * 1.5, "aftershock hits again 1.5 s later (%.0f -> %.0f)" % [slam, _lost(target)])

func _test_discharge() -> void:
	await _reset("Shock Lance")
	var ahead := _dummy(START + _forward() * 9.0)
	var aside := _dummy(START + _player.global_transform.basis.x * 4.0)
	await _frames(2)
	await _charge(1.1, 1.0)
	_check(_lost(ahead) > 0.0, "discharge shockwave reaches 9 m along the ground")
	_check(_lost(aside) == 0.0, "shockwave stays in its lane")

func _test_pressure_blast() -> void:
	await _reset("Pressure Fist")
	var front := _dummy(START + _forward() * 2.0)
	var behind := _dummy(START - _forward() * 2.0)
	await _frames(2)
	var start_pos := front.global_position
	var stance_before: float = front.stance.current_stance if front.stance else 0.0
	await _charge(0.9, 0.7)
	_check(_lost(front) > 0.0, "pressure blast hits the cone")
	_check(front.global_position.y > start_pos.y + 0.2 or (front.global_position - start_pos).length() > 1.0, "pressure blast launches the target")
	_check(_lost(behind) == 0.0, "pressure blast misses behind you")
	if front.stance:
		_check(front.stance.current_stance < stance_before, "pressure blast deals heavy stagger")
	await _seconds(1.0)

func _test_whip() -> void:
	await _reset("Whip")
	var target := _dummy(START + _forward() * 6.0)
	await _frames(2)
	var melee: EnemyMeleeAttack = target.get_node("MeleeAttack")
	melee._state = EnemyMeleeAttack.State.TELEGRAPH
	melee._timer = 5.0
	await _charge(0.7, 0.4)
	var hit := _lost(target)
	_check(hit > 0.0, "crack hits at long range")
	_check(target.status_effects.has_effect("bleed"), "crack applies Bleed")
	_check(melee._state == EnemyMeleeAttack.State.RECOVERY, "crack interrupts the target's attack")
	await _seconds(1.2)
	_check(_lost(target) > hit, "bleed ticks for damage")

func _test_cancel_and_fallback() -> void:
	await _reset("Greatsword")
	var target := _dummy(START + _forward() * 2.0)
	await _frames(2)
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _seconds(0.5)
	_check(_player.stance_attack.is_charging, "holding LMB in stance charges")
	Input.action_release("stance")
	await _frames(3)
	_check(not _player.stance_attack.is_charging, "releasing RMB cancels the charge")
	Input.action_release("attack")
	await _seconds(0.8)
	_check(_lost(target) == 0.0 and _player.melee_attack.is_idle(), "a cancelled charge doesn't attack or jab")
	await _reset("Dagger")
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	_check(not _player.melee_attack.is_idle(), "stances without a charged attack keep the instant special")
	Input.action_release("attack")
