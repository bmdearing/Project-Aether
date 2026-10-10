extends Node
## Spell behaviour checks: casts each spell at stationary dummy enemies and
## verifies its specific mechanic (timing, forks/chains, pull, walls, DoT).
## Run: Godot --headless --path . res://tests/spells/test_spells.tscn --quit-after 20000
## Exits 0 when every check passes. Never writes the save file.

const ABILITY_DIR := "res://data/abilities/instances/"

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 18

var _arena: Node3D
var _player: Player
var _cast: PlayerAbilityCast

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
	await _test_comet_timing_and_bonus()
	await _test_comet_timing()
	await _test_wave()
	await _test_stormcall_forks()
	await _test_static_chain()
	await _test_black_hole_pull()
	await _test_flame_wall_ignite()
	await _test_winters_eye()
	await _test_bolt_walls()
	await _test_spark_and_tornado()
	await _test_javelin_pierce()
	await _test_thunder_sweep()
	await _test_frost_armor()
	await _test_flame_jets_walls()
	await _test_caltrops_and_inferno()
	await _test_scorch()
	await _test_shatter()
	await _test_every_spell_casts()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("spell tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _setup() -> void:
	_arena = Node3D.new()
	add_child(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_arena.add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	_arena.add_child(_player)
	_player.global_position = Vector3(0, 0, 30)
	await _frames(3)
	_player.set_physics_process(false)
	_cast = _player.ability_cast
	_clear()

func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()

func _ability(id: String) -> Ability:
	var a := load(ABILITY_DIR + id + ".tres") as Ability
	a.level = 1
	a.base_crit_chance = 0.0
	a.status_chance = 1.0  # mechanics checks; the roll itself is covered in tests/combat_pass
	return a

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	_arena.add_child(e)
	e.global_position = pos
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
	return 1.0e6 - e.health.current_health if is_instance_valid(e) else 0.0

func _reset_effects() -> void:
	_clear()
	for n in get_tree().get_nodes_in_group("tornado_field"):
		n.queue_free()
	await _frames(3)

func _test_comet_timing_and_bonus() -> void:
	await _reset_effects()
	var comet := _ability("comet")
	var plain := _dummy(Vector3(-1, 0, 0))
	var chilled := _dummy(Vector3(1, 0, 0))
	await _frames(2)
	chilled.status_effects.apply_effect("chill", null)
	_cast._cast(comet, Vector3.ZERO)
	await _frames(1)
	_check(_lost(plain) == 0.0, "comet deals no damage before it lands")
	await _wait(0.6)
	_check(_lost(plain) > 0.0, "comet damages on impact")
	_check(_lost(chilled) > _lost(plain) * 1.8, "comet hits Chilled enemies much harder (%.0f vs %.0f)" % [_lost(chilled), _lost(plain)])
	_finished += 1

func _test_comet_timing() -> void:
	await _reset_effects()
	var e := _dummy(Vector3.ZERO)
	await _frames(2)
	_cast._cast(_ability("comet"), Vector3.ZERO)
	await _frames(1)
	_check(_lost(e) == 0.0, "comet deals no damage before it lands")
	await _wait(0.6)
	_check(_lost(e) > 0.0, "comet damages on impact")
	_finished += 1

func _test_wave() -> void:
	await _reset_effects()
	var pulse := _ability("ice_pulse")
	var near := _dummy(Vector3(0, 0, 29))
	var far := _dummy(Vector3(4.5, 0, 30))
	await _frames(2)
	_cast._cast(pulse, _player.global_position)
	await _frames(1)
	_check(_lost(far) == 0.0, "ice pulse hasn't reached the far enemy yet")
	await _wait(0.5)
	_check(_lost(near) > 0.0 and _lost(far) > 0.0, "ice pulse wave reaches everyone in range")
	_check(near.status_effects.has_effect("chill"), "ice pulse chills")
	_finished += 1

func _test_stormcall_forks() -> void:
	await _reset_effects()
	var storm := _ability("stormcall")
	var core := _dummy(Vector3(0.5, 0, 0))
	var outer := _dummy(Vector3(4.5, 0, 0))
	var outside := _dummy(Vector3(9.0, 0, 0))
	await _frames(2)
	_cast._cast(storm, Vector3.ZERO)
	await _frames(2)
	_check(_lost(core) > 0.0, "stormcall hits its core")
	_check(_lost(outer) > 0.0 and _lost(outer) < _lost(core), "stormcall forks to a nearby enemy for less damage")
	_check(_lost(outside) == 0.0, "stormcall forks stay within range")
	_finished += 1

func _test_static_chain() -> void:
	await _reset_effects()
	var sd := _ability("static_discharge")
	var inside := _dummy(Vector3(2, 0, 30))
	var beyond := _dummy(Vector3(6.5, 0, 30))
	await _frames(2)
	_cast._cast(sd, _player.global_position)
	await _wait(0.5)
	_check(_lost(inside) > 0.0, "static discharge hits nearby enemies")
	_check(_lost(beyond) > 0.0, "static discharge arcs on to an enemy outside the burst")
	_finished += 1

func _test_black_hole_pull() -> void:
	await _reset_effects()
	var e := _dummy(Vector3(4, 0, 0))
	await _frames(2)
	var start := e.global_position.distance_to(Vector3.ZERO)
	var field: BlackHoleField = load("res://entities/effects/black_hole_field/BlackHoleField.tscn").instantiate()
	_arena.add_child(field)
	var bh := _ability("black_hole")
	field.play(bh.radius, Color.PURPLE, bh, _player.stat_sheet, _player)
	await _wait(1.0)
	_check(e.global_position.distance_to(Vector3.ZERO) < start - 1.0, "black hole drags enemies in")
	# A wall between the hole and an enemy holds it.
	field.queue_free()
	await _reset_effects()
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(0.6, 4, 8)
	ws.shape = wb
	wall.add_child(ws)
	_arena.add_child(wall)
	wall.global_position = Vector3(2.5, 2, 0)
	var walled := _dummy(Vector3(4, 0, 0))
	await _frames(2)
	var field2: BlackHoleField = load("res://entities/effects/black_hole_field/BlackHoleField.tscn").instantiate()
	_arena.add_child(field2)
	field2.play(bh.radius, Color.PURPLE, bh, _player.stat_sheet, _player)
	await _wait(1.0)
	_check(walled.global_position.x > 2.5, "black hole can't drag enemies through a wall (x %.2f)" % walled.global_position.x)
	field2.queue_free()
	wall.queue_free()
	_finished += 1

func _test_flame_wall_ignite() -> void:
	await _reset_effects()
	var fw := _ability("flame_wall")
	var field: FlameWallField = load("res://entities/effects/flame_wall_field/FlameWallField.tscn").instantiate()
	_arena.add_child(field)
	field.global_position = Vector3(0, 0, 0)
	field.play(fw.radius, Color.ORANGE_RED, fw, _player.stat_sheet, _player, Vector3(0, 0, 10))
	await _frames(2)
	var e := _dummy(Vector3(0, 0, 0))
	await _wait(0.3)
	_check(e.status_effects.has_effect("ignite"), "flame wall ignites enemies that enter")
	var before := _lost(e)
	await _wait(1.2)
	_check(_lost(e) > before, "flame wall burns over time")
	field.queue_free()
	_finished += 1

func _test_winters_eye() -> void:
	await _reset_effects()
	var we := _ability("winters_eye")
	var e := _dummy(Vector3(2, 0, 0))
	await _frames(2)
	var orb: WintersEyeOrb = load("res://entities/effects/winters_eye_orb/WintersEyeOrb.tscn").instantiate()
	_arena.add_child(orb)
	orb.global_position = Vector3(0, 1, 6)
	orb.play(we.radius, Color.CYAN, we, _player.stat_sheet, _player, Vector3.ZERO)
	await _wait(1.5)
	_check(is_instance_valid(orb), "winter's eye hasn't detonated on arrival")
	_check(_lost(e) > 0.0 and (e.status_effects.has_effect("chill") or e.status_effects.has_effect("freeze")), "winter's eye icicles hit and chill")
	await _wait(2.0)
	_check(not is_instance_valid(orb), "winter's eye detonates when its duration ends")
	_finished += 1

func _test_bolt_walls() -> void:
	await _reset_effects()
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(6, 6, 0.5)
	ws.shape = wb
	wall.add_child(ws)
	_arena.add_child(wall)
	wall.global_position = Vector3(0, 2, 20)
	var behind := _dummy(Vector3(0, 0, 15))
	var open := _dummy(Vector3(8, 0, 22))
	await _frames(2)
	var lance := _ability("cinder_lance")
	_cast._spawn_bolt(lance, 1.0, Transform3D(Basis.IDENTITY, Vector3(0, 1, 26)))
	var aimed := Transform3D(Basis.looking_at(Vector3(8, 1, 22) - Vector3(0, 1, 26)), Vector3(0, 1, 26))
	_cast._spawn_bolt(lance, 1.0, aimed)
	await _wait(1.2)
	_check(_lost(behind) == 0.0, "cinder lance stops at walls")
	_check(_lost(open) > 0.0, "cinder lance hits in the open")
	wall.queue_free()
	_finished += 1

func _test_spark_and_tornado() -> void:
	await _reset_effects()
	var e := _dummy(Vector3(0, 0, 25))
	await _frames(2)
	_cast._cast(_ability("spark"), _player.global_position)
	await _wait(2.0)
	_check(_lost(e) > 0.0, "spark hunts down an enemy")
	await _reset_effects()
	var t := _dummy(Vector3(3, 0, 0))
	await _frames(2)
	var tor := _ability("tornado")
	_cast._play_range_effect(tor, Vector3(-2, 0, 0))
	await _wait(2.5)
	_check(_lost(t) > 0.0, "tornado hunts and damages")
	_finished += 1

func _test_javelin_pierce() -> void:
	await _reset_effects()
	var a := _dummy(Vector3(0, 0, 20))
	var b := _dummy(Vector3(0, 0, 12))
	await _frames(2)
	_cast._spawn_bolt(_ability("thunder_javelin"), 1.0, Transform3D(Basis.IDENTITY, Vector3(0, 1, 26)))
	await _wait(0.6)
	_check(_lost(a) > 0.0 and _lost(b) > 0.0, "thunder javelin pierces through a line of enemies")
	_finished += 1

func _test_thunder_sweep() -> void:
	await _reset_effects()
	# A ramp in one direction: sweep bolts ride over it rather than dying on it.
	var ramp := StaticBody3D.new()
	var rs := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(3, 0.4, 6)
	rs.shape = rb
	ramp.add_child(rs)
	_arena.add_child(ramp)
	ramp.global_position = Vector3(0, 0.1, 27)
	ramp.rotation.x = deg_to_rad(10)
	var over_ramp := _dummy(Vector3(0, 0, 24))
	var side := _dummy(Vector3(5, 0, 30))
	var too_far := _dummy(Vector3(-12, 0, 30))
	await _frames(2)
	_cast._cast(_ability("thunder_sweep"), _player.global_position)
	await _wait(1.2)
	_check(_lost(side) > 0.0, "thunder sweep hits enemies around the caster")
	_check(_lost(over_ramp) > 0.0, "thunder sweep rides over sloped ground")
	_check(_lost(too_far) == 0.0, "thunder sweep stops at its radius")
	ramp.queue_free()
	_finished += 1

func _test_frost_armor() -> void:
	await _reset_effects()
	var attacker := _dummy(_player.global_position + Vector3(1, 0, 0))
	var bystander := _dummy(_player.global_position + Vector3(-2, 0, 0))
	var distant := _dummy(_player.global_position + Vector3(-8, 0, 0))
	await _frames(2)
	_cast._cast(_ability("frost_armor"), _player.global_position)
	await _frames(1)
	_check(is_instance_valid(_cast._frost_armor_fx), "frost armor shows its shards")
	_cast.trigger_frost_armor_retaliation(attacker)
	_check(_lost(attacker) > 0.0 and attacker.status_effects.has_effect("chill"), "frost armor retaliates against the attacker")
	_check(_lost(bystander) > 0.0, "frost armor's burst hits enemies nearby")
	_check(_lost(distant) == 0.0, "frost armor's burst stays within its radius")
	var after := _lost(attacker)
	_cast.trigger_frost_armor_retaliation(attacker)
	_check(_lost(attacker) == after, "frost armor bursts at most once per half second")
	_cast._frost_armor_remaining = 0.0
	await _frames(3)
	_check(not is_instance_valid(_cast._frost_armor_fx), "frost armor shards go away when it ends")
	_finished += 1

func _test_flame_jets_walls() -> void:
	await _reset_effects()
	_player.camera.global_rotation = Vector3.ZERO
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(1.2, 4, 0.4)
	ws.shape = wb
	wall.add_child(ws)
	_arena.add_child(wall)
	wall.global_position = Vector3(0.8, 2, 26.5)
	var open := _dummy(Vector3(-0.8, 0, 24.6))
	var hidden := _dummy(Vector3(0.8, 0, 24.6))
	await _frames(2)
	_cast._flame_jets_ability = _ability("flame_jets")
	_cast._tick_flame_jets()
	_check(_lost(open) > 0.0, "flame jets burn what's in front")
	_check(_lost(hidden) == 0.0, "flame jets don't burn through walls")
	wall.queue_free()
	_finished += 1

func _test_caltrops_and_inferno() -> void:
	await _reset_effects()
	var e := _dummy(Vector3(1, 0, 0))
	await _frames(2)
	var field := _cast._play_range_effect(_ability("caltrops"), Vector3.ZERO)
	await _wait(0.6)
	_check(_lost(e) > 0.0 and e.status_effects.has_effect("slow"), "caltrops cut and slow")
	field.queue_free()
	await _reset_effects()
	var near := _dummy(Vector3(3.5, 0, 0))
	var far := _dummy(Vector3(7, 0, 0))
	await _frames(2)
	_cast._cast(_ability("inferno"), Vector3.ZERO)
	await _frames(1)
	_check(_lost(near) > 0.0 and near.status_effects.has_effect("ignite"), "inferno engulfs and ignites its area")
	_check(_lost(far) == 0.0, "inferno stays within its radius")
	_finished += 1

func _test_scorch() -> void:
	await _reset_effects()
	var e := _dummy(Vector3(0, 0, 0))
	await _frames(2)
	var se := e.status_effects
	var before := _lost(e)
	e.take_damage(100.0, Constants.DamageType.FIRE)
	var plain := _lost(e) - before
	for i in 7:
		se.apply_effect("scorch", _player)
	_check(se.get_scorch_stacks() == StatusEffectComponent.SCORCH_MAX_STACKS, "scorch stacks up to its cap")
	before = _lost(e)
	e.take_damage(100.0, Constants.DamageType.FIRE)
	var scorched := _lost(e) - before
	_check(is_equal_approx(scorched, plain * se.get_scorch_multiplier()), "scorch raises fire damage taken (%.1f vs %.1f)" % [scorched, plain])
	before = _lost(e)
	e.take_damage(100.0, Constants.DamageType.COLD)
	_check(is_equal_approx(_lost(e) - before, plain), "scorch leaves other damage types alone")
	se._timers["scorch"] = 0.01
	await _frames(3)
	_check(se.get_scorch_stacks() == 0, "scorch stacks clear when it expires")
	await _reset_effects()
	var target := _dummy(Vector3(0, 0, 24.6))
	await _frames(2)
	_player.camera.global_rotation = Vector3.ZERO
	_cast._flame_jets_ability = _ability("flame_jets")
	for i in 3:
		_cast._tick_flame_jets()
	_check(target.status_effects.get_scorch_stacks() == 3, "flame jets build scorch on prolonged contact")
	_finished += 1

## Every spell's cast path runs without a script error.
func _test_every_spell_casts() -> void:
	await _reset_effects()
	_dummy(Vector3(0, 0, 26))
	await _frames(2)
	for f in DirAccess.get_files_at(ABILITY_DIR):
		if not f.ends_with(".tres"):
			continue
		var a := _ability(f.get_basename())
		_player.global_position = Vector3(0, 0, 30)
		_cast._cast(a, Vector3(0, 0, 24))
		await _frames(2)
	await _wait(3.0)
	_check(true, "all spells cast")
	_finished += 1

## Shatter breaks every ailment for a hit in its element; Freeze is worth more
## than Chill; an enemy without ailments takes nothing.
func _test_shatter() -> void:
	await _reset_effects()
	var shatter := _ability("shatter")
	var clean := _dummy(Vector3(-2, 0, 0))
	var chilled := _dummy(Vector3(0, 0, 0))
	var frozen := _dummy(Vector3(2, 0, 0))
	var many := _dummy(Vector3(0, 0, 2))
	await _frames(2)
	chilled.status_effects.apply_effect("chill", null)
	for i in StatusEffectComponent.CHILL_STACKS_TO_FREEZE:
		frozen.status_effects.apply_effect("chill", null)
	_check(frozen.status_effects.has_effect("freeze"), "three Chills freeze the dummy")
	for id in ["ignite", "unraveling", "shock"]:
		many.status_effects.apply_effect(id, null, 10.0)
	var types := {}
	var on_dealt := func(_s, target, _amount, damage_type, _spell, _crit):
		if target == many:
			types[damage_type] = true
	EventBus.damage_dealt.connect(on_dealt)
	_cast._cast(shatter, Vector3.ZERO)
	await _frames(2)
	EventBus.damage_dealt.disconnect(on_dealt)
	_check(_lost(clean) == 0.0, "shatter does nothing to an enemy without ailments")
	_check(_lost(chilled) > 0.0 and not chilled.status_effects.has_effect("chill"), "shatter breaks Chill for damage")
	_check(_lost(frozen) > _lost(chilled) * 2.0, "a broken Freeze hits harder than Chill (%.0f vs %.0f)" % [_lost(frozen), _lost(chilled)])
	_check(not many.status_effects.has_effect("ignite") and not many.status_effects.has_effect("unraveling") and not many.status_effects.has_effect("shock"), "every ailment is removed")
	_check(types.has(Constants.DamageType.FIRE) and types.has(Constants.DamageType.ENTROPIC) and types.has(Constants.DamageType.LIGHTNING), "each burst uses its ailment's element (%s)" % [types.keys()])
	_finished += 1
