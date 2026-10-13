extends Node
## Dash-cancel, enemy tells, heavy staggers, aim assist, kill shove,
## backstabs and the visceral lock (ripostes).
## Run: Godot --headless --path . res://tests/combat/test_visceral.tscn
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

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _setup()
	await _test_dash_cancels_recovery()
	await _test_tell()
	await _test_heavy_stagger()
	await _test_aim_assist()
	await _test_kill_shove()
	await _test_riposte_lock()
	await _test_backstab()
	print("visceral tests: %d checks, %d failures" % [_checks, _failures])
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
	_player.set_physics_process(false)
	_equip("Saber")

func _equip(weapon_type: String) -> void:
	var w := Weapon.new()
	w.weapon_type = weapon_type
	w.base_damage_min = 20.0
	w.base_damage_max = 20.0
	w.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
	_player.equipment.primary_weapon = w

func _reset() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()
	_player.global_position = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	while not _player.melee_attack.is_idle():
		await _frames(1)
	await _frames(2)

func _dummy(pos: Vector3, life: float = 1.0e6, unit := "unchartered_brigand") -> Enemy:
	var e := EnemyRoster.create_unit(unit)
	_arena.add_child(e)
	e.global_position = pos
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.health.max_health = life
	e.health.current_health = life
	return e

func _ahead(dist: float) -> Vector3:
	return -_player.global_transform.basis.z * dist

func _test_dash_cancels_recovery() -> void:
	await _reset()
	var melee := _player.melee_attack
	melee.try_light_jab()
	while melee._state != PlayerMeleeAttack.State.RECOVERY:
		await _frames(1)
	_player._start_dash(_player.transform.basis.x)
	await _frames(2)
	_check(melee.is_idle(), "a dash cuts the swing's follow-through short")

func _test_tell() -> void:
	await _reset()
	var e := _dummy(_ahead(1.5))
	await _frames(3)
	var attack := e.get_node("MeleeAttack") as EnemyMeleeAttack
	attack._enter_telegraph()
	_check(not attack._told, "no tell at the start of the wind-up")
	while attack._state == EnemyMeleeAttack.State.TELEGRAPH:
		await _frames(1)
	_check(attack._told, "the tell shows before the strike")
	_player.parry_handler.grant_invulnerability(2.0)
	await _wait(1.0)

func _test_heavy_stagger() -> void:
	await _reset()
	var melee := _player.melee_attack
	var grunt := _dummy(_ahead(1.6))
	await _frames(3)
	var attack := grunt.get_node("MeleeAttack") as EnemyMeleeAttack
	attack.set_physics_process(false)
	attack._enter_telegraph()
	melee._combo_idle = 0.0
	melee._combo_step = 1
	melee.try_light_jab()  # step 2: the finisher
	_check(melee.is_combo_finisher(), "set up the finisher")
	while melee._state != PlayerMeleeAttack.State.RECOVERY:
		await _frames(1)
	_check(not attack.is_attacking() and grunt.status_effects.is_stunned(), "a finisher staggers a rank-and-file enemy out of its attack")
	await _reset()
	var chief := _dummy(_ahead(1.6), 1.0e6, "unchartered_chieftain")
	await _frames(3)
	_check(not chief.is_rank_and_file(), "elites aren't rank-and-file")

func _test_aim_assist() -> void:
	await _reset()
	var off := Vector3(sin(deg_to_rad(18.0)), 0, -cos(deg_to_rad(18.0))) * 1.6
	_dummy(off)
	await _frames(3)
	var before := _player.rotation.y
	_player.melee_attack.try_light_jab()
	while _player.melee_attack._state != PlayerMeleeAttack.State.RECOVERY:
		await _frames(1)
	var turned := rad_to_deg(absf(angle_difference(before, _player.rotation.y)))
	_check(turned > 6.0 and turned <= PlayerMeleeAttack.ASSIST_MAX_DEG + 0.1, "the swing turns toward an enemy just off the crosshair (%.1f deg)" % turned)

func _test_kill_shove() -> void:
	await _reset()
	var e := _dummy(_ahead(1.6), 1.0)
	await _frames(3)
	var start := e.global_position
	_player.melee_attack.try_light_jab()
	await _wait(1.0)
	var moved := Vector2(e.global_position.x - start.x, e.global_position.z - start.z).length()
	_check(not e.health.is_alive() and moved > 1.0, "the killing blow throws the body (%.2f m)" % moved)

func _test_riposte_lock() -> void:
	await _reset()
	var e := _dummy(_ahead(1.6))
	await _frames(3)
	e.composure.enter_broken_state()
	_player.melee_attack.try_light_jab()
	while not _player.is_in_visceral():
		await _frames(1)
	var life := e.health.current_health
	_check(is_equal_approx(life, 1.0e6), "the riposte's damage waits for the rip-out")
	_check(_player.parry_handler.is_invulnerable, "invulnerable during the visceral")
	_check(e.status_effects.is_stunned(), "the enemy is held through the visceral")
	_check(is_zero_approx(_player._effective_speed(5.0)), "the player can't move during the visceral")
	_player.take_damage(50.0, Constants.DamageType.KINETIC)
	_check(_player.health.current_health == _player.health.max_health, "hits do nothing during the visceral")
	await _wait(Player.VISCERAL_RIP_AT + 0.15)
	_check(e.health.current_health < life, "the visceral lands as the weapon tears out")
	await _wait(Player.VISCERAL_LOCK)
	_check(not _player.is_in_visceral(), "the lock ends")

func _test_backstab() -> void:
	await _reset()
	var melee := _player.melee_attack
	var e := _dummy(_ahead(1.6))
	await _frames(3)
	e._model_root.global_rotation.y = atan2(-_player.global_transform.basis.z.x, -_player.global_transform.basis.z.z) + e.model_forward_yaw_offset
	e.set_physics_process(false)
	_check(e.is_behind(_player.global_position), "the player is behind the enemy")
	_player.weapon_stance._enter_stance()
	melee.try_charged_thrust()
	var locked := false
	for i in 240:
		await _frames(1)
		if _player.is_in_visceral():
			locked = true
			break
	_player.weapon_stance._exit_stance()
	_check(locked, "a charged attack into the back is a visceral")
	await _wait(Player.VISCERAL_LOCK + 0.2)
	await _reset()
	await _frames(3)
