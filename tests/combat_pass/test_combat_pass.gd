extends Node
## Checks for the combat pass: spell limits replace the oldest instance,
## status effects roll their chance, enemy hitboxes fit their model,
## headshots, AoE reaching big bodies, and Flame Jets channelling on Mana.
## Run: Godot --headless --path . res://tests/combat_pass/test_combat_pass.tscn --quit-after 20000
## Exits 0 when every check passes. Never writes the save file.

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 6

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

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _setup()
	await _test_limit_replaces_oldest()
	await _test_status_chance()
	await _test_golem_body()
	await _test_aoe_reaches_big_bodies()
	await _test_flame_jets_channel()
	_test_no_spell_cooldowns()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("combat pass tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _setup() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0, 30)
	await _frames(3)
	_player.set_physics_process(false)
	_cast = _player.ability_cast

func _ability(id: String) -> Ability:
	var a := load("res://data/abilities/instances/%s.tres" % id) as Ability
	a.level = 1
	return a

func _unit(id: String, pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit(id)
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	return e

func _damage_numbers() -> int:
	return get_tree().current_scene.get_children().filter(func(n): return n is DamageNumber).size()

func _test_limit_replaces_oldest() -> void:
	var tornado := _ability("tornado")
	var limit := tornado.get_limit(_player.stat_sheet)
	var first: Node = null
	for i in limit + 1:
		_cast._cast(tornado, Vector3(i * 3.0, 0, 0))
		await _frames(1)
		if i == 0:
			first = get_tree().get_nodes_in_group("spell_limit_tornado")[0]
	await _frames(1)
	var live := get_tree().get_nodes_in_group("spell_limit_tornado")
	_check(live.size() == limit, "casting past the limit keeps %d tornadoes (%d)" % [limit, live.size()])
	_check(not is_instance_valid(first), "the oldest tornado made way")
	for n in live:
		n.queue_free()
	var black_hole := _ability("black_hole")
	_cast._cast(black_hole, Vector3.ZERO)
	await _frames(1)
	_cast._cast(black_hole, Vector3(5, 0, 0))
	await _frames(2)
	var holes := get_tree().get_nodes_in_group("spell_limit_black_hole")
	_check(holes.size() == 1 and holes[0].global_position.x > 4.0, "a second Black Hole replaces the first")
	for n in holes:
		n.queue_free()
	await _frames(1)
	_finished += 1

func _test_status_chance() -> void:
	var dummy := _unit("unchartered_brigand", Vector3(40, 0, 0))
	await _frames(2)
	var hits := 400
	var landed := 0
	for i in hits:
		dummy.status_effects.clear_all_effects()
		if dummy.status_effects.try_apply("ignite", _player, 10.0, 0.25):
			landed += 1
	_check(landed > hits * 0.15 and landed < hits * 0.35, "a 25%% base chance lands about a quarter of the time (%d/%d)" % [landed, hits])
	_player.stat_sheet.misc_bonus["ailment_chance_ignite"] = 75.0
	landed = 0
	for i in hits:
		if dummy.status_effects.try_apply("ignite", _player, 10.0, 0.25):
			landed += 1
	_check(landed == hits, "gear chance adds to the base chance (%d/%d)" % [landed, hits])
	_player.stat_sheet.misc_bonus.erase("ailment_chance_ignite")
	_check(dummy.status_effects.try_apply("armor_shred", _player, 0.0, 0.0), "stance riders that are not ailments always land")
	dummy.status_effects.clear_all_effects()
	_player.stat_sheet.misc_bonus["ailment_chance_bleed"] = 100.0
	dummy.status_effects.roll_gear_ailments(_player, 50.0)
	_check(dummy.status_effects.has_effect("bleed"), "a plain hit procs an ailment from gear chance alone")
	_player.stat_sheet.misc_bonus.erase("ailment_chance_bleed")
	_player.stat_sheet.misc_bonus["increased_ailment_duration_ignite"] = 100.0
	dummy.status_effects.apply_effect("ignite", _player, 100.0)
	_check(dummy.status_effects._timers["ignite"] > StatusEffectComponent.IGNITE_DURATION * 1.9, "increased Ignite duration from gear applies")
	_player.stat_sheet.misc_bonus.erase("increased_ailment_duration_ignite")
	var before := dummy.health.current_health
	var numbers_before := _damage_numbers()
	await get_tree().create_timer(0.6).timeout
	_check(dummy.health.current_health < before and _damage_numbers() > numbers_before, "Ignite ticks show damage numbers")
	dummy.queue_free()
	await _frames(1)
	_finished += 1

func _test_golem_body() -> void:
	var golem := _unit("synod_warden_golem", Vector3(-40, 0, 0))
	await _frames(2)
	_check(golem.body_height > 2.8, "golem body is fitted to its model (%.2f m tall)" % golem.body_height)
	var capsule := (golem.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	_check(is_equal_approx(capsule.height, golem.body_height), "golem collision capsule matches its height")
	var plain := EnemyRoster.create_unit("directorate_soldier")
	add_child(plain)
	await _frames(1)
	var plain_capsule := (plain.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	_check(is_equal_approx(plain_capsule.height, 1.9), "resizing one unit leaves the shared capsule alone")
	plain.queue_free()
	var space := get_viewport().world_3d.direct_space_state
	var from := golem.global_position + Vector3(0, golem.body_height * 0.8, 6)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0, -12)))
	_check(not hit.is_empty() and hit["collider"] == golem, "a shot above the golem waist hits it")
	var spot := golem.get_critical_spot()
	var centre: Vector3 = spot["centre"]
	_check(centre.y > golem.global_position.y + golem.body_height * 0.8, "golem head zone sits at the top of the model")
	var eye := centre + Vector3(0, 0, 6)
	_check(golem.is_critical_spot_aimed(eye, Vector3(0, 0, -1)), "aiming at the head is a headshot")
	_check(not golem.is_critical_spot_aimed(eye - Vector3(0, 1.2, 0), Vector3(0, 0, -1)), "aiming at the chest is not")
	_check(golem.is_critical_spot_point(centre) and not golem.is_critical_spot_point(golem.global_position), "projectile contact point decides headshots")
	_check(is_equal_approx(golem.critical_spot_multiplier, 1.10), "headshots deal 10% bonus damage")
	golem.queue_free()
	await _frames(1)
	_finished += 1

func _test_aoe_reaches_big_bodies() -> void:
	var golem := _unit("synod_warden_golem", Vector3(0, 0, 0))
	await _frames(2)
	var radius := 4.0
	golem.global_position = Vector3(radius + golem.body_radius * 0.5, 0, 0)
	_check(golem.distance_to_body(Vector3.ZERO) <= radius, "AoE range is measured to the body edge")
	var ward := golem.get_ward()
	var health := golem.health.current_health
	_cast._damage_area(_ability("entropic_decay"), Vector3.ZERO, radius, 1.0, false, 0.0, Callable())
	_check(golem.get_ward() < ward or golem.health.current_health < health, "Entropic Decay hits a golem at the edge of its range")
	_check(golem.get_ward_max() > 0.0, "golem exposes its Ward for the health bar")
	golem.queue_free()
	await _frames(1)
	_finished += 1

func _test_flame_jets_channel() -> void:
	var jets := _ability("flame_jets")
	_cast._flame_jets_is_manual = true
	_cast._cast(jets, _player.global_position)
	_check(_cast._flame_jets_remaining > PlayerAbilityCast.FLAME_JETS_DURATION * 10.0, "a held Flame Jets has no short duration cap")
	_cast._flame_jets_remaining = 0.0
	_cast._flame_jets_is_manual = false
	_finished += 1

func _test_no_spell_cooldowns() -> void:
	var dir := DirAccess.open("res://data/abilities/instances/")
	var with_cooldown: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".tres"):
			var a := load("res://data/abilities/instances/" + f) as Ability
			if a.cooldown_seconds > 0.0:
				with_cooldown.append(a.ability_id)
	with_cooldown.sort()
	_check(with_cooldown == ["blink", "purge"], "only utility spells keep a cooldown (%s)" % ", ".join(with_cooldown))
	_finished += 1
