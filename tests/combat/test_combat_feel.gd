extends Node
## Melee timing, contact window, hit reaction, movement acceleration and
## the raised shield (ShieldBlock).
## Run: Godot --headless --path . res://tests/combat/test_combat_feel.tscn --quit-after 20000
## Exits 0 when every check passes.

var _checks := 0
var _failures := 0
var _arena: Node3D
var _player: Player

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

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _setup()
	await _test_swing_timing()
	await _test_contact_window_and_reaction()
	await _test_acceleration()
	await _test_shield_block()
	print("combat feel tests: %d checks, %d failures" % [_checks, _failures])
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
	_player.global_position = Vector3.ZERO
	await _frames(3)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()
	await _frames(2)

func _equip(weapon_type: String) -> void:
	var w := Weapon.new()
	w.weapon_type = weapon_type
	w.base_damage_min = 20.0
	w.base_damage_max = 20.0
	w.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
	_player.equipment.primary_weapon = w

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	_arena.add_child(e)
	e.global_position = pos
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	var melee := e.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
	return e

func _swing_total(melee: PlayerMeleeAttack) -> float:
	return melee._windup_time() + melee._strike_time() + melee._recovery_time()

func _test_swing_timing() -> void:
	var melee := _player.melee_attack
	_equip("Dagger")
	melee._attack_type = PlayerMeleeAttack.AttackType.JAB
	var dagger_jab := _swing_total(melee)
	_check(dagger_jab >= 0.4, "dagger jab is readable (%.2fs)" % dagger_jab)
	_equip("Gauntlet")
	var gauntlet_jab := _swing_total(melee)
	_check(gauntlet_jab >= 0.36, "gauntlet jab is readable (%.2fs)" % gauntlet_jab)
	_check(melee._strike_time() < melee._windup_time(), "strike is shorter than windup")
	_equip("Greatsword")
	melee._attack_type = PlayerMeleeAttack.AttackType.THRUST
	_check(_swing_total(melee) > dagger_jab * 2.5, "greatsword stays much heavier than a dagger")
	_check(melee._swing_weight() > 1.5, "greatsword swing weight is heavy")
	_equip("Dagger")
	melee._attack_type = PlayerMeleeAttack.AttackType.JAB
	_player.stat_sheet.misc_bonus["attack_speed"] = 400.0
	_check(is_equal_approx(_swing_total(melee), PlayerMeleeAttack.MIN_WINDUP + PlayerMeleeAttack.MIN_STRIKE + PlayerMeleeAttack.MIN_RECOVERY),
		"attack speed can't push a swing below the phase floors")
	_player.stat_sheet.misc_bonus.erase("attack_speed")

func _test_contact_window_and_reaction() -> void:
	_player.set_physics_process(false)
	_player.global_position = Vector3.ZERO
	_equip("Greatsword")
	var forward := -_player.global_transform.basis.z
	var target := _dummy(forward * 2.0)
	await _frames(3)
	var start_pos := target.global_position
	var melee := _player.melee_attack
	melee.try_standard_thrust()
	while melee._state != PlayerMeleeAttack.State.STRIKE:
		await _frames(1)
	await _frames(1)
	_check(is_equal_approx(target.health.current_health, 1.0e6), "no damage at the very start of the strike")
	var waited := 0
	while is_equal_approx(target.health.current_health, 1.0e6) and waited < 120:
		await _frames(1)
		waited += 1
	_check(target.health.current_health < 1.0e6, "hit lands during the strike")
	_check(Engine.time_scale < 1.0, "hitstop slows time on impact")
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored after hitstop")
	var pushed := (target.global_position - start_pos).dot(forward)
	_check(pushed > 0.1, "enemy knocked back away from the player (%.2fm)" % pushed)
	while not melee.is_idle():
		await _frames(1)
	target.queue_free()
	await _frames(2)

func _test_acceleration() -> void:
	_player.set_physics_process(true)
	_player.global_position = Vector3(0, 0.1, 0)
	_player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("move_forward")
	await _frames(1)
	var first := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(first > 0.5 and first < _player.move_speed, "movement ramps up rather than snapping (%.2f)" % first)
	await _frames(20)
	var full := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(is_equal_approx(full, _player.move_speed), "reaches full speed quickly (%.2f)" % full)
	Input.action_release("move_forward")
	await _frames(1)
	var stopping := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(stopping > 0.0 and stopping < full, "short skid on release (%.2f)" % stopping)
	await _frames(20)
	_check(Vector2(_player.velocity.x, _player.velocity.z).length() < 0.01, "comes to a stop")
	_player.velocity = Vector3.ZERO
	var before := _player.global_position
	_equip("Greatsword")
	_player.melee_attack.try_standard_thrust()
	while not _player.melee_attack.is_idle():
		await _frames(1)
	var lunge := (_player.global_position - before).dot(-_player.global_transform.basis.z)
	_check(lunge > 0.1, "heavy strike steps the player forward (%.2fm)" % lunge)

func _health_lost(before: float) -> float:
	return before - _player.health.current_health

func _test_shield_block() -> void:
	var block := _player.shield_block
	_equip("Dagger")
	var shield := Shield.new()
	shield.block_chance = 0.0
	shield.equip_slot = Constants.EquipmentSlot.OFFHAND
	_player.equipment.offhand = shield
	_player.stat_sheet.misc_bonus["evasion"] = 0.0
	GameState.shield_on_rmb = true
	_player.velocity = Vector3.ZERO
	await _frames(5)

	Input.action_press("stance")
	await _frames(3)
	_check(block.is_raised, "RMB raises the shield")
	_check(not _player.weapon_stance.is_active, "shield overrides the weapon stance")
	_check(_player._effective_speed(_player.move_speed) < _player.move_speed, "moving slower while blocking")

	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	var front := _dummy(_player.global_position + forward.normalized() * 2.0)
	var behind := _dummy(_player.global_position - forward.normalized() * 2.0)
	await _frames(2)
	_player.health.current_health = _player.health.max_health
	var hp := _player.health.current_health
	var composure_before := block.composure
	_player.take_damage(20.0, Constants.DamageType.KINETIC, front)
	_check(is_equal_approx(hp, _player.health.current_health), "hit from the front is fully blocked")
	_check(block.composure < composure_before, "a blocked hit costs Composure")
	_player.take_damage(20.0, Constants.DamageType.KINETIC, behind)
	_check(_health_lost(hp) > 0.0 or _player.ward.current_ward < _player.ward.max_ward, "hit from behind gets through")

	Input.action_press("attack")
	await _frames(3)
	Input.action_release("attack")
	await _frames(2)
	_check(_player.melee_attack.is_idle(), "can't attack with the shield raised")

	while block.is_raised:
		block.try_block(_player.health.max_health, front)
	_check(_player.status_effects.is_stunned(), "running out of Composure breaks the guard and stuns")
	await _frames(3)
	_check(not block.is_raised, "shield can't be raised again straight after a break")
	await get_tree().create_timer(ShieldBlock.GUARD_BREAK_STUN + 0.1).timeout
	_check(not _player.status_effects.is_stunned(), "stun ends after a second")
	Input.action_release("stance")
	await _frames(2)

	GameState.shield_on_rmb = false
	Input.action_press("stance")
	await _frames(3)
	_check(not block.is_raised and _player.weapon_stance.is_active, "Weapon Stance setting keeps RMB on the stance")
	Input.action_release("stance")
	await _frames(2)
	GameState.shield_on_rmb = true
	front.queue_free()
	behind.queue_free()
