extends Node
## Pack positioning (EnemyTactics): melee packs surround the player, shooters
## fan out, stand behind a heavy ally off its line, and never fire through one.
## Run: Godot --headless --path . res://tests/combat/test_pack_tactics.tscn --quit-after 6000

const TEST_COUNT := 3

var _checks := 0
var _failures := 0
var _finished := 0
var _arena: Node3D
var _player: Player

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_arena = Node3D.new()
	add_child(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_arena.add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	_arena.add_child(_player)
	_player.global_position = Vector3(0, 0.1, 0)
	await _frames(3)
	_player.set_physics_process(false)
	await _test_surround()
	await _test_cover_and_clear_shot()
	await _test_ranged_fan()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("pack tactics tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _spawn(unit_id: String, at: Vector3, attacks: bool) -> Enemy:
	var e := EnemyRoster.create_unit(unit_id)
	_arena.add_child(e)
	e.global_position = at
	if not attacks:
		for n in ["MeleeAttack", "RangedAttack"]:
			var attack := e.get_node_or_null(n)
			if attack:
				attack.set_physics_process(false)
	e.mark_in_combat()
	return e

func _clear(units: Array[Enemy]) -> void:
	for e in units:
		if is_instance_valid(e):
			e.free()
	await _frames(2)

func _keep_in_combat(units: Array[Enemy], seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		for e in units:
			e.mark_in_combat()
		await _frames(6)
		left -= 6.0 / Engine.physics_ticks_per_second

## Four soldiers coming from one side spread round the player.
func _test_surround() -> void:
	var pack: Array[Enemy] = []
	for i in 4:
		pack.append(_spawn("directorate_soldier", Vector3(-3.0 + i * 2.0, 0.1, -12.0), false))
	await _keep_in_combat(pack, 7.0)
	var angles: Array[float] = []
	var behind := 0
	for e in pack:
		var a := EnemyTactics.angle_of(e.global_position, _player.global_position)
		angles.append(a)
		# They came from -Z (angle PI); behind the player is +Z.
		if absf(wrapf(a - PI, -PI, PI)) > PI * 0.5:
			behind += 1
	angles.sort()
	var widest := TAU - (angles[-1] - angles[0])
	for i in range(1, angles.size()):
		widest = maxf(widest, angles[i] - angles[i - 1])
	_check(widest < deg_to_rad(150.0), "4 melee spread round the player (widest gap %.0f deg)" % rad_to_deg(widest))
	_check(behind >= 1, "at least one melee came round behind the player (%d)" % behind)
	var close := 0
	for e in pack:
		if Enemy._flat(e.global_position - _player.global_position).length() <= e.stop_distance + 1.0:
			close += 1
	_check(close == 4, "all 4 reached melee range (%d)" % close)
	await _clear(pack)
	_finished += 1

## An exarch straight behind a heavy soldier steps off the soldier's line,
## stays behind it, and never starts a shot with an ally in the way.
func _test_cover_and_clear_shot() -> void:
	var tank := _spawn("directorate_soldier", Vector3(0, 0.1, -2.6), false)
	var shooter := _spawn("synod_exarch", Vector3(0, 0.1, -9.0), true)
	await _frames(4)
	tank.set_physics_process(false)  # holds its spot so the line stays blocked
	shooter._blocker_msec = -100000
	_check(shooter.shot_blocker() == tank, "the soldier blocks the exarch's line at the start")
	var bad_shots := [0]
	var shots := [0]
	var on_tell := func(e: Enemy) -> void:
		if e == shooter:
			shots[0] += 1
			shooter._blocker_msec = -100000
			if shooter.shot_blocker() != null:
				bad_shots[0] += 1
	EventBus.enemy_attack_telegraphed.connect(on_tell)
	_player.health.max_health = 1.0e9
	_player.health.current_health = 1.0e9
	await _keep_in_combat([tank, shooter] as Array[Enemy], 6.0)
	EventBus.enemy_attack_telegraphed.disconnect(on_tell)
	shooter._blocker_msec = -100000
	var tank_d := Enemy._flat(tank.global_position - _player.global_position).length()
	var shooter_d := Enemy._flat(shooter.global_position - _player.global_position).length()
	_check(shooter.shot_blocker() == null, "the exarch found a clear line")
	_check(shooter.tactic_cover == tank, "the exarch uses the soldier as cover")
	_check(shooter_d > tank_d + 2.0, "the exarch stays behind the soldier (%.1fm vs %.1fm)" % [shooter_d, tank_d])
	var off := absf(wrapf(EnemyTactics.angle_of(shooter.global_position, _player.global_position) - EnemyTactics.angle_of(tank.global_position, _player.global_position), -PI, PI))
	_check(off < deg_to_rad(60.0), "and close to its line (%.0f deg off)" % rad_to_deg(off))
	_check(shots[0] >= 1, "the exarch fired once clear (%d shots)" % shots[0])
	_check(bad_shots[0] == 0, "no shot started with an ally in the way (%d)" % bad_shots[0])
	await _clear([tank, shooter] as Array[Enemy])
	_finished += 1

## Three shooters bunched together fan out.
func _test_ranged_fan() -> void:
	var group: Array[Enemy] = []
	for i in 3:
		group.append(_spawn("synod_exarch", Vector3(-1.0 + i * 1.0, 0.1, -14.0), false))
	await _keep_in_combat(group, 6.0)
	var nearest := 1000.0
	for i in group.size():
		for j in range(i + 1, group.size()):
			nearest = minf(nearest, Enemy._flat(group[i].global_position - group[j].global_position).length())
	_check(nearest > 3.0, "3 shooters spread apart (closest pair %.1fm)" % nearest)
	await _clear(group)
	_finished += 1
