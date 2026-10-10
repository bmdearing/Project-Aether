extends Node
## Ranged aim stances (Patch v3.4 table, RangedStanceBehavior), fired
## through real input: hold RMB to aim, press or hold LMB.
## Run: Godot --headless --path . res://tests/combat/test_ranged_stances.tscn --quit-after 60000

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
	await _setup()
	await _test_resolution()
	await _test_steady_aim()
	await _test_fan_the_hammer()
	await _test_suppression()
	await _test_full_auto_burst()
	await _test_point_blank()
	await _test_pump_brace()
	await _test_rapid_fire()
	await _test_kiting_shot()
	await _test_snipe()
	await _test_rain_of_arrows()
	await _test_marksman()
	await _test_breath_control()
	await _test_dig_in()
	await _test_tracer_round()
	await _test_extra_arrows()
	await _test_hitscan()
	print("ranged stance tests: %d checks, %d failures" % [_checks, _failures])
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
	for node in get_tree().current_scene.get_children():
		if node is Projectile:
			node.queue_free()

func _reset(weapon_type: String, page: WeaponStance.StancePage = WeaponStance.StancePage.A) -> Weapon:
	Input.action_release("attack")
	Input.action_release("stance")
	await _frames(2)
	_clear()
	var w := Weapon.new()
	w.weapon_type = weapon_type
	w.is_ranged = true
	w.base_damage_min = 40.0
	w.base_damage_max = 40.0
	w.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
	w.apply_ranged_profile()
	_player.equipment.primary_weapon = w
	_player.ranged_attack._on_weapon_swapped(_player)
	_player.ranged_attack._cooldown_remaining = 0.0
	_player.ranged_attack._dump_remaining = 0
	_player.stat_sheet.finesse_crit_bonus = -1.0  # no crits: damage comparisons stay exact
	_player.weapon_stance.set_stance_page(page)
	_player.global_position = START
	_player.velocity = Vector3.ZERO
	_player.head.rotation.x = 0.0
	await _frames(5)
	return w

func _forward() -> Vector3:
	return -_player.global_transform.basis.z

func _right() -> Vector3:
	return _player.global_transform.basis.x

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	e.position = pos  # before entering the tree, or it spends a frame at the origin
	_arena.add_child(e)
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.armor_value = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	var melee := e.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
	var ranged := e.get_node_or_null("RangedAttack")
	if ranged:
		ranged.set_physics_process(false)
	return e

func _lost(e: Enemy) -> float:
	return 1.0e6 - e.health.current_health

func _aim() -> void:
	Input.action_press("stance")
	await _frames(3)

func _tap(settle: float = 0.6) -> void:
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(settle)

func _hold(seconds: float) -> void:
	Input.action_press("attack")
	await _seconds(seconds)
	Input.action_release("attack")

func _travel() -> float:
	return (_player.global_position - START).dot(_forward())

func _test_resolution() -> void:
	var expected := {
		"Service Pistol": RangedStanceBehavior.RangedStanceType.STEADY_AIM,
		"Revolver": RangedStanceBehavior.RangedStanceType.FAN_THE_HAMMER,
		"Machine Gun": RangedStanceBehavior.RangedStanceType.DIG_IN,
		"Battle Rifle": RangedStanceBehavior.RangedStanceType.TRACER_ROUND,
	}
	for weapon_type in expected:
		await _reset(weapon_type)
		await _aim()
		var b := _player.weapon_stance.current_behavior as RangedStanceBehavior
		_check(b != null and b.stance_type == expected[weapon_type], "%s aims with its own stance" % weapon_type)
	await _reset("Longbow", WeaponStance.StancePage.B)
	await _aim()
	var rain := _player.weapon_stance.current_behavior as RangedStanceBehavior
	_check(rain != null and rain.stance_type == RangedStanceBehavior.RangedStanceType.RAIN_OF_ARROWS, "longbow page B is Rain of Arrows")

func _test_steady_aim() -> void:
	await _reset("Service Pistol")
	_player.stat_sheet.finesse_crit_bonus = 0.25
	var target := _dummy(START + _forward() * 6.0)
	await _aim()
	await _tap(0.5)
	_check(_lost(target) > 0.0, "steady aim fires")
	_check(is_equal_approx(_player.stat_sheet.finesse_crit_bonus, 0.25), "steady aim's crit bonus lasts only for the shot")

func _test_fan_the_hammer() -> void:
	var w := await _reset("Revolver")
	_dummy(START + _forward() * 6.0)
	await _aim()
	await _tap(0.7)
	_check(w.get_current_magazine() == 0, "fan the hammer empties the cylinder from one press (%d left)" % w.get_current_magazine())
	_check(_player.ranged_attack.is_reloading(), "then forces a reload")

func _test_suppression() -> void:
	await _reset("Machine Pistol")
	var target := _dummy(START + _forward() * 6.0)
	await _aim()
	await _hold(0.6)
	await _seconds(0.3)
	_check(target.status_effects.has_effect("suppressed") and target.status_effects._suppressed_stacks >= 2, "suppression stacks a slow on hits")
	_check(target.status_effects.get_move_speed_multiplier() < 0.9, "suppressed enemies move slower")

func _test_full_auto_burst() -> void:
	await _reset("Submachine Gun")
	var target := _dummy(START + _forward() * 6.0)
	await _frames(2)
	var melee: EnemyMeleeAttack = target.get_node("MeleeAttack")
	melee._state = EnemyMeleeAttack.State.TELEGRAPH
	melee._timer = 5.0
	await _aim()
	await _hold(0.8)
	await _seconds(0.3)
	_check(melee._state != EnemyMeleeAttack.State.TELEGRAPH, "repeated hits stagger and interrupt")

func _test_point_blank() -> void:
	await _reset("Loaded Shotgun")
	var near := _dummy(START + _forward() * 2.0)
	await _aim()
	await _tap(0.5)
	var close_damage := _lost(near)
	await _reset("Loaded Shotgun")
	var far := _dummy(START + _forward() * 10.0)
	await _aim()
	await _tap(0.8)
	_check(close_damage > _lost(far) * 1.4, "point blank hits harder up close (%.0f vs %.0f)" % [close_damage, _lost(far)])

func _test_pump_brace() -> void:
	await _reset("Pump Action Shotgun")
	var center := _dummy(START + _forward() * 6.0)
	var wide := _dummy(START + _forward() * 6.0 + _right() * 2.6)
	await _aim()
	Input.action_press("move_forward")
	await _seconds(0.3)
	var moved := absf(_travel())
	Input.action_release("move_forward")
	await _tap(0.3)
	_check(moved < 0.02, "brace plants your feet (%.2f m)" % moved)
	_check(_lost(center) > 0.0 and _lost(wide) > 0.0, "the braced shot hits everything in its wide cone")
	var wide_first := _lost(wide)
	_check(wide_first > _lost(center) * 0.9, "every enemy in the cone takes the full shot")

func _test_rapid_fire() -> void:
	await _reset("Shortbow")
	var target := _dummy(START + _forward() * 6.0)
	await _aim()
	for i in 3:
		await _tap(0.2)
	await _seconds(0.4)
	var aimed_hits := _lost(target)
	await _reset("Shortbow")
	target = _dummy(START + _forward() * 6.0)
	await _frames(2)
	for i in 3:
		await _tap(0.2)
	await _seconds(0.4)
	var plain_hits := _lost(target)
	_check(aimed_hits > 0.0 and plain_hits > 0.0, "both land")
	# Aimed arrows deal 0.5x x 1.4 each, unaimed 1x: three rapid arrows vs the one or two the draw time allows.
	_check(aimed_hits / (40.0 * 1.4 * 0.5) > plain_hits / 40.0 + 0.5, "rapid fire looses arrows faster than the draw allows")

func _test_kiting_shot() -> void:
	await _reset("Shortbow", WeaponStance.StancePage.B)
	await _aim()
	Input.action_press("move_backward")
	await _seconds(0.5)
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release("move_backward")
	_check(speed > _player.move_speed * 0.95, "kiting shot: full speed moving away (%.2f)" % speed)
	Input.action_press("move_forward")
	await _seconds(0.5)
	var forward_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release("move_forward")
	_check(forward_speed < _player.move_speed * 0.7, "still slowed moving toward the target (%.2f)" % forward_speed)

func _test_snipe() -> void:
	await _reset("Longbow")
	var a := _dummy(START + _forward() * 5.0)
	var b := _dummy(START + _forward() * 8.0)
	var c := _dummy(START + _forward() * 11.0)
	await _aim()
	await _tap(1.0)
	_check(_lost(a) > 0.0 and _lost(b) > 0.0 and _lost(c) > 0.0, "snipe pierces every enemy in the line")

func _test_rain_of_arrows() -> void:
	await _reset("Longbow", WeaponStance.StancePage.B)
	_player.head.rotation.x = deg_to_rad(-20.0)
	await _frames(2)
	var spot := START + _forward() * (1.6 / tan(deg_to_rad(20.0)))
	var under := _dummy(spot)
	var outside := _dummy(spot + _right() * 6.0)
	await _aim()
	await _tap(0.2)
	_check(_lost(under) == 0.0, "volleys land after the arc's flight time")
	await _seconds(1.6)
	_check(_lost(under) > 0.0, "rain of arrows hits the spot under the crosshair")
	_check(_lost(outside) == 0.0, "and only that spot")

func _test_marksman() -> void:
	await _reset("Lever Action Rifle")
	var target := _dummy(START + _forward() * 6.0)
	await _aim()
	await _seconds(1.6)
	await _tap(0.6)
	var held := _lost(target)
	await _tap(0.6)
	var quick := _lost(target) - held
	# The lever's 0.5 s cycle means the quick shot still has ~0.6 s of aim behind it.
	_check(quick > 0.0 and held > quick * 1.3, "a long aim hits much harder (%.0f vs %.0f)" % [held, quick])

func _test_breath_control() -> void:
	await _reset("Bolt Action Rifle")
	var a := _dummy(START + _forward() * 5.0)
	var b := _dummy(START + _forward() * 8.0)
	var c := _dummy(START + _forward() * 11.0)
	await _aim()
	Input.action_press("move_forward")
	await _seconds(0.3)
	var moved := absf(_travel())
	Input.action_release("move_forward")
	await _tap(1.0)
	_check(moved < 0.02, "breath control: no movement")
	_check(_lost(a) > 0.0 and _lost(b) > 0.0 and _lost(c) == 0.0, "breath control pierces exactly one target")

func _test_dig_in() -> void:
	var w := await _reset("Machine Gun")
	await _hold(1.0)
	var plain := w.magazine_size - w.get_current_magazine()
	w = await _reset("Machine Gun")
	await _aim()
	Input.action_press("move_forward")
	await _hold(1.0)
	var moved := absf(_travel())
	Input.action_release("move_forward")
	var dug_in := w.magazine_size - w.get_current_magazine()
	_check(moved < 0.02, "dig in roots you")
	_check(dug_in >= plain * 2, "dig in fires much faster (%d vs %d rounds in 1 s)" % [dug_in, plain])

func _test_tracer_round() -> void:
	await _reset("Battle Rifle")
	var target := _dummy(START + _forward() * 6.0)
	await _aim()
	await _tap(0.5)
	var first := _lost(target)
	_check(target.status_effects.has_effect("marked"), "tracer round marks what it hits")
	await _tap(0.5)
	var second := _lost(target) - first
	_check(second > first * 1.3, "shots on the marked target hit harder (%.0f vs %.0f)" % [second, first])

func _projectile_count() -> int:
	return get_tree().current_scene.get_children().filter(func(n): return n is Projectile and not n.is_queued_for_deletion()).size()

func _test_extra_arrows() -> void:
	var bow := await _reset("Longbow")
	var extra := ItemAffix.new()
	extra.stat_key = "local_additional_arrows"
	extra.value = 2.0
	bow.affixes.append(extra)
	await _tap(0.05)
	_check(_projectile_count() == 3, "a bow with +2 additional Arrows fires 3 (%d)" % _projectile_count())
	var speeds := get_tree().current_scene.get_children().filter(func(n): return n is Projectile).map(func(p): return p.speed)
	_player.stat_sheet.misc_bonus["projectile_speed"] = 50.0
	await _reset("Longbow")
	await _tap(0.05)
	var faster := get_tree().current_scene.get_children().filter(func(n): return n is Projectile and not n.is_queued_for_deletion()).map(func(p): return p.speed)
	_check(not speeds.is_empty() and not faster.is_empty() and is_equal_approx(faster[0], speeds[0] * 1.5), "Projectile Speed speeds up arrows")
	_player.stat_sheet.misc_bonus.erase("projectile_speed")

## Revolver and Bolt Action Rifle land on the same frame they fire, far away;
## a Service Pistol shot still flies.
func _test_hitscan() -> void:
	for t in ["Revolver", "Bolt Action Rifle"]:
		var w := await _reset(t)
		_check(w.is_hitscan(), "%s is hitscan" % t)
		var far := _dummy(START + _forward() * 60.0)
		await _frames(3)
		Input.action_press("attack")
		await _frames(4)
		Input.action_release("attack")
		var lost := 1.0e6 - far.health.current_health
		_check(lost > 0.0, "%s hits a target 60 m away within four frames (%.1f)" % [t, lost])
	var pistol := await _reset("Service Pistol")
	_check(not pistol.is_hitscan(), "Service Pistol is not hitscan")
	var target := _dummy(START + _forward() * 60.0)
	await _frames(3)
	Input.action_press("attack")
	await _frames(4)
	Input.action_release("attack")
	_check(target.health.current_health == 1.0e6, "a pistol bullet is still in flight after four frames")
