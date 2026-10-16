extends Node
## Dual wielding: which weapons pair, the attack speed bonus, alternating
## hands, the both-blade finisher, the Dual Wield stances, dual guns and a
## mixed pair's Offhand Attack.
## Run: Godot --headless --path . res://tests/combat/test_dual_wield.tscn --quit-after 30000

const TEST_COUNT := 5
var _checks := 0
var _failures := 0
var _finished := 0
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

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _setup()
	_test_equip_rules()
	await _test_melee_hands()
	await _test_stances()
	await _test_guns()
	await _test_mixed()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("dual wield tests: %d checks, %d failures" % [_checks, _failures])
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
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()

func _weapon(type: String, ranged := false, two_handed := false, conduit := false, damage := 40.0) -> Weapon:
	var w := Weapon.new()
	w.weapon_type = type
	w.is_ranged = ranged
	w.is_two_handed = two_handed
	w.is_conduit = conduit
	w.base_damage_min = damage
	w.base_damage_max = damage
	w.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
	if ranged:
		w.apply_ranged_profile()
	return w

func _arm(main: Weapon, off: Weapon) -> void:
	var eq := _player.equipment
	eq.primary_weapons[eq.active_weapon_set] = null
	eq.offhands[eq.active_weapon_set] = null
	eq.equip(main, true)
	if off:
		eq.equip(off, true)
	_player.ranged_attack._on_weapon_swapped(_player)
	_player.stat_sheet.finesse_crit_bonus = -1.0  # no crits

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	e.position = pos
	_arena.add_child(e)
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.armor_value = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	for n in ["MeleeAttack", "RangedAttack"]:
		var node := e.get_node_or_null(n)
		if node:
			node.set_physics_process(false)
	return e

func _test_equip_rules() -> void:
	var eq := _player.equipment
	var a := _weapon("Shortsword")
	var b := _weapon("Saber")
	_arm(a, b)
	_check(eq.primary_weapon == a and eq.offhand == b, "a second one-hander goes in the empty offhand")
	_check(_player.dual_wield_kind() == "melee", "two blades dual wield as melee")
	_check(is_equal_approx(_player.get_attack_speed_multiplier(a), _player.get_action_speed_multiplier() * 1.1), "dual wielding gives 10% more attack speed")
	var c := _weapon("Cutlass")
	eq.equip(c, true)
	_check(eq.primary_weapon == c and eq.offhand == b, "with both hands full, a one-hander replaces the main hand")
	eq.equip(a, true, -1, true)
	_check(eq.offhand == a, "to_offhand (Shift) replaces the offhand")
	eq.equip(_weapon("Wand", false, false, true), true)
	_check(eq.offhand == null, "a conduit in the main hand doesn't dual wield; the offhand weapon comes off")
	eq.equip(_weapon("Staff", false, true, true), true)
	eq.equip(_weapon("Shortsword"), true, -1, true)
	_check(eq.offhand == null, "no offhand weapon beside a two-hander")
	_arm(_weapon("Shortsword"), null)
	eq.equip(_weapon("Wand", false, false, true), true, -1, true)
	_check(not _player.is_dual_wielding(), "a conduit can't be dual wielded")
	_finished += 1

func _test_melee_hands() -> void:
	var main := _weapon("Shortsword", false, false, false, 10.0)
	var off := _weapon("Shortsword", false, false, false, 1000.0)
	_arm(main, off)
	_player.global_position = START
	_player.rotation.y = 0.0
	_player.head.rotation.x = 0.0
	await _frames(3)
	var target := _dummy(START + Vector3(0, 0, -1.6))
	target.stance = null  # a 1000-damage hit would break it and turn the next swing into a riposte
	await _frames(3)
	var melee := _player.melee_attack
	var hands: Array[int] = []
	# Each swing's own hits (Life lost would also count damage over time).
	var swings: Array = []
	var record := func(_p: Node, damage: float, _t: int, _mv: float) -> void: swings[-1].append(damage)
	EventBus.melee_attack_executed.connect(record)
	for i in 4:
		swings.append([])
		target.global_position = START + Vector3(0, 0, -1.6)
		target.velocity = Vector3.ZERO
		_player.global_position = START
		_player.velocity = Vector3.ZERO
		_player.rotation.y = 0.0
		await _frames(1)
		melee.try_light_jab()
		hands.append(melee.get_strike_hands())
		for f in 120:
			await get_tree().physics_frame
			if melee.is_idle():
				break
	EventBus.melee_attack_executed.disconnect(record)
	_check(hands == [PlayerMeleeAttack.Strike.MAIN, PlayerMeleeAttack.Strike.OFF, PlayerMeleeAttack.Strike.MAIN, PlayerMeleeAttack.Strike.BOTH], "the dual combo goes main, off, main, both (%s)" % [hands])
	var ok: bool = swings[0].size() == 1 and swings[1].size() == 1 and swings[2].size() == 1
	_check(ok and swings[1][0] > swings[0][0] * 20.0 and swings[2][0] < swings[1][0] / 20.0, "each swing rolls its own hand's weapon (%s)" % [swings])
	_check(swings[3].size() == 2 and swings[3][1] > swings[3][0] * 20.0, "the both-blade finisher hits once with each weapon (%s)" % [swings[3]])
	_check(_player.attack_hand == Player.Hand.MAIN, "the main hand is back in front once idle")
	target.queue_free()
	_finished += 1

func _test_stances() -> void:
	_arm(_weapon("Dagger"), _weapon("Dagger"))
	var ws := _player.weapon_stance
	ws.set_stance_page(WeaponStance.StancePage.A)
	var a := ws._resolve_behavior(_player.get_active_weapon()) as MeleeStanceBehavior
	_check(a != null and a.stance_type == MeleeStanceBehavior.MeleeStanceType.PARRY_READY and a.riposte_both_blades, "page A is Crossguard")
	ws.set_stance_page(WeaponStance.StancePage.B)
	var b := ws._resolve_behavior(_player.get_active_weapon()) as MeleeStanceBehavior
	_check(b != null and b.stance_type == MeleeStanceBehavior.MeleeStanceType.FLURRY, "page B is Flurry")
	_check(StanceInfo.for_weapon(_player.get_active_weapon(), 1, true).get("name", "") == "Flurry", "the HUD names it")
	# Flurry: a full charge throws 7 cuts and the cross-cut.
	var sa := _player.stance_attack
	sa._behavior = b
	sa._held = b.charge_time
	sa.is_charging = true
	sa.release()
	_check(sa._flurry_dual and sa._flurry_left == 7, "a full Flurry queues its cuts (%d left after the first)" % sa._flurry_left)
	for f in 400:
		await get_tree().physics_frame
		if sa._flurry_left == 0 and _player.melee_attack.is_idle():
			break
	_check(sa._flurry_left == 0, "the Flurry runs to the end out of stance")
	ws.set_stance_page(WeaponStance.StancePage.A)
	_arm(_weapon("Dagger"), null)
	var single := ws._resolve_behavior(_player.get_active_weapon()) as MeleeStanceBehavior
	_check(single != null and single.weapon_type == "Dagger", "a single dagger keeps its own stance")
	_finished += 1

func _test_guns() -> void:
	var main := _weapon("Service Pistol", true)
	var off := _weapon("Service Pistol", true)
	_arm(main, off)
	AmmoInventory.add(main.ammo_type, 200)
	main.current_magazine = main.magazine_size
	off.current_magazine = off.magazine_size
	_check(_player.dual_wield_kind() == "guns", "two pistols dual wield as guns")
	var ra := _player.ranged_attack
	for i in 4:
		ra._cooldown_remaining = 0.0
		ra._is_cycling = false
		ra.try_attack(false)
		await _frames(1)
	_check(main.get_current_magazine() == main.magazine_size - 2 and off.get_current_magazine() == off.magazine_size - 2, "shots alternate between the guns (%d, %d)" % [main.get_current_magazine(), off.get_current_magazine()])
	main.current_magazine = 0
	ra._cooldown_remaining = 0.0
	ra._is_cycling = false
	ra.try_attack(false)
	_check(off.get_current_magazine() == off.magazine_size - 3 and not ra.is_reloading(), "an empty gun is skipped while the other has rounds")
	off.current_magazine = 0
	ra._start_reload(main)
	ra._reload_timer = 0.0
	await _frames(2)
	_check(main.get_current_magazine() == main.magazine_size and off.get_current_magazine() == off.magazine_size, "one reload refills both guns")
	_finished += 1

func _test_mixed() -> void:
	var blade := _weapon("Cutlass")
	var gun := _weapon("Revolver", true)
	_arm(blade, gun)
	AmmoInventory.add(gun.ammo_type, 100)
	gun.current_magazine = gun.magazine_size
	_check(_player.dual_wield_kind() == "mixed", "a blade and a gun are a mixed pair")
	_check(_player.ranged_attack.get_guns() == [gun], "the offhand gun is the gun in hand")
	_player.ranged_attack._cooldown_remaining = 0.0
	_player.ranged_attack.try_offhand_fire()
	_check(gun.get_current_magazine() == gun.magazine_size - 1, "Offhand Attack fires the offhand gun")
	_check(_player.attack_hand == Player.Hand.MAIN, "and hands control back to the main hand")
	_finished += 1
