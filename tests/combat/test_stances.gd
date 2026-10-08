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
	await _test_guard()
	await _test_fortify()
	await _test_phalanx()
	await _test_brace()
	await _test_parry_stances()
	await _test_water_slices()
	await _test_sweep()
	await _test_armor_pierce()
	await _test_hook()
	await _test_entangle()
	await _test_repulse()
	await _test_slice_and_dice()
	await _test_stealth()
	await _test_stance_cooldown()
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
	_player.weapon_stance._cooldowns.clear()  # each check stands alone
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _seconds(seconds)
	Input.action_release("attack")
	await _seconds(settle)

func _travel() -> float:
	return (_player.global_position - START).dot(_forward())

func _test_stance_cooldown() -> void:
	await _reset("Rapier")
	await _charge(0.1)
	var behavior := _player.weapon_stance.get_ready_behavior()
	var remaining := _player.weapon_stance.get_cooldown_remaining(behavior)
	_check(behavior.cooldown_seconds > 0.0 and remaining > 0.0, "a stance special starts its cooldown (%.1fs)" % remaining)
	var start := _player.global_position
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _seconds(0.1)
	Input.action_release("attack")
	await _seconds(0.6)
	_check(_player.global_position.distance_to(start) < 0.2 and not _player.stance_attack.is_charging, "the special can't be used again while it recharges")
	Input.action_release("stance")
	_player.weapon_stance._cooldowns[behavior] = 0.0
	await _charge(0.1)
	_check(_player.global_position.distance_to(start) > 1.0, "it works again once ready")
	await _leave_stance()

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
	_player.stat_sheet.misc_bonus["ailment_chance_bleed"] = 100.0  # the rider is a roll; force it
	await _charge(0.7, 0.4)
	var hit := _lost(target)
	_check(hit > 0.0, "crack hits at long range")
	_check(target.status_effects.has_effect("bleed"), "crack applies Bleed")
	_check(melee._state == EnemyMeleeAttack.State.RECOVERY, "crack interrupts the target's attack")
	await _seconds(1.2)
	_check(_lost(target) > hit, "bleed ticks for damage")
	_player.stat_sheet.misc_bonus.erase("ailment_chance_bleed")

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
	await _reset("Saber")
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	_check(not _player.melee_attack.is_idle(), "weapons with no stance resource keep the generic special")
	Input.action_release("attack")

## Damage the player takes from one hit, from full health.
func _hit_player(amount: float, source: Node, hit_kind: Player.HitKind = Player.HitKind.ATTACK, is_melee: bool = false) -> float:
	_player.health.current_health = _player.health.max_health
	_player.take_damage(amount, Constants.DamageType.FIRE, source, hit_kind, is_melee)
	return _player.health.max_health - _player.health.current_health

func _enter_page_b(weapon_type: String) -> void:
	await _reset(weapon_type)
	_player.weapon_stance.set_stance_page(WeaponStance.StancePage.B)
	Input.action_press("stance")
	await _frames(3)

func _leave_stance() -> void:
	Input.action_release("stance")
	await _frames(2)
	_player.weapon_stance.set_stance_page(WeaponStance.StancePage.A)

func _test_guard() -> void:
	await _enter_page_b("Greatsword")
	var enemy := _dummy(START + Vector3(0, 0, -2))
	_check(_player.stat_sheet.get_total_evasion(_player.equipment) == 0.0, "test player has no evasion")
	var guarded := _hit_player(50.0, enemy, Player.HitKind.ATTACK, true)
	var ranged := _hit_player(50.0, enemy, Player.HitKind.ATTACK, false)
	await _leave_stance()
	var open := _hit_player(50.0, enemy, Player.HitKind.ATTACK, true)
	_check(absf(guarded - open * 0.2) < 0.5, "guard blocks 80%% of a melee hit (%.1f vs %.1f)" % [guarded, open])
	_check(is_equal_approx(ranged, open), "guard doesn't touch non-melee hits")

func _test_fortify() -> void:
	await _enter_page_b("Mace")
	var enemy := _dummy(START + Vector3(0, 0, -3))
	var fortified := _hit_player(50.0, enemy, Player.HitKind.SPELL)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _seconds(0.4)
	var moved := _travel()
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _leave_stance()
	var open := _hit_player(50.0, enemy, Player.HitKind.SPELL)
	_check(absf(fortified - open * 0.6) < 0.5, "fortify cuts all damage by 40%% (%.1f vs %.1f)" % [fortified, open])
	_check(absf(moved) < 0.02, "fortify roots you, dash included (%.2f m)" % moved)

func _test_phalanx() -> void:
	await _reset("Spear")
	var front := _dummy(START + Vector3(0, 0, -3))
	var behind := _dummy(START + Vector3(0, 0, 3))
	await _seconds(0.2)
	var defense := _player.stance_defense
	_player.weapon_stance.set_stance_page(WeaponStance.StancePage.B)
	defense.barrier = defense.get_max_barrier()
	Input.action_press("stance")
	await _frames(3)
	var pool := defense.barrier
	_check(pool > 0.0, "phalanx has a barrier (%.0f)" % pool)
	_check(_hit_player(20.0, front) == 0.0, "barrier soaks a frontal hit")
	_check(defense.barrier < pool, "soaking drains the barrier")
	_check(_hit_player(20.0, behind) > 0.0, "hits from behind get past the barrier")
	var past := _hit_player(pool * 3.0, front)
	_check(past > 0.0 and defense.barrier == 0.0, "an empty barrier lets the rest through")
	await _leave_stance()
	await _seconds(BARRIER_WAIT)
	_check(is_equal_approx(defense.barrier, defense.get_max_barrier()), "barrier refills out of stance")

const BARRIER_WAIT := StanceDefense.BARRIER_REGEN_DELAY + StanceDefense.BARRIER_REGEN_TIME + 0.3

func _test_brace() -> void:
	await _enter_page_b("Halberd")
	var charger := _dummy(START + Vector3(0, 0, -8))
	var flank := _dummy(START + Vector3(0, 0, 8))
	await _frames(3)
	var composure_before: float = charger.stance.current_stance if charger.stance else 0.0
	charger.global_position = START + Vector3(0, 0, -2)
	flank.global_position = START + Vector3(0, 0, 2)
	await _frames(3)
	var first := _lost(charger)
	_check(first > 0.0, "brace strikes an enemy that closes in front")
	_check(_lost(flank) == 0.0, "brace ignores enemies behind")
	if charger.stance:
		_check(charger.stance.current_stance < composure_before, "brace staggers")
	await _frames(10)
	_check(is_equal_approx(_lost(charger), first), "one strike per approach, not every frame")
	await _leave_stance()

func _test_parry_stances() -> void:
	var parry := _player.parry_handler
	await _reset("Rapier")
	parry.start_parry_window()
	var base: float = parry._parry_timer
	await _enter_page_b("Rapier")
	parry.start_parry_window()
	_check(parry._parry_timer > base * 2.0, "rapier Ready Parry widens the parry window (%.2fs vs %.2fs)" % [parry._parry_timer, base])
	await _leave_stance()
	await _enter_page_b("Cutlass")
	parry.start_parry_window()
	_check(parry._parry_timer > base * 1.5, "cutlass Parry Ready widens it too")
	await _leave_stance()

var _damage_log: Array = []  # [target, amount, type]

func _log_damage(_source, target, amount: float, damage_type, _is_spell, _crit) -> void:
	_damage_log.append([target, amount, damage_type])

func _hits_on(target: Enemy) -> Array:
	return _damage_log.filter(func(e): return e[0] == target)

## Enter stance on `page` and tap LMB once.
func _tap_stance(page: WeaponStance.StancePage, settle: float = 0.6) -> void:
	_player.weapon_stance._cooldowns.clear()
	_player.weapon_stance.set_stance_page(page)
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(settle)

func _test_water_slices() -> void:
	await _reset("Cutlass")
	var near := _dummy(START + _forward() * 3.0)
	var far := _dummy(START + _forward() * 9.0 + _player.global_transform.basis.x * 0.4)
	var off := _dummy(START + _forward() * 6.0 + _player.global_transform.basis.x * 4.0)
	await _frames(3)
	if not EventBus.damage_dealt.is_connected(_log_damage):
		EventBus.damage_dealt.connect(_log_damage)
	_damage_log.clear()
	await _tap_stance(WeaponStance.StancePage.A, 1.2)
	_check(_lost(near) > 0.0 and _lost(far) > 0.0, "water slice pierces along its path to 9 m")
	_check(_lost(off) == 0.0, "water slice stays on its line")
	var cold := _hits_on(far).filter(func(e): return e[2] == Constants.DamageType.COLD)
	_check(cold.size() == 1, "each slash hit adds a Cold hit (Gain As)")
	await _leave_stance()

func _test_sweep() -> void:
	await _reset("Halberd")
	var right := _player.global_transform.basis.x
	var front := _dummy(START + _forward() * 2.5)
	var left := _dummy(START - right * 2.5)
	var side := _dummy(START + right * 2.5)
	var behind := _dummy(START - _forward() * 2.5)
	await _frames(3)
	var side_start := side.global_position
	await _tap_stance(WeaponStance.StancePage.A, 1.0)
	_check(_lost(front) > 0.0 and _lost(left) > 0.0 and _lost(side) > 0.0, "sweep hits front and both sides")
	_check(_lost(behind) == 0.0, "sweep leaves the 90 degrees behind you")
	_check((side.global_position - side_start).length() > 1.0, "sweep knocks enemies back")
	await _leave_stance()

func _test_armor_pierce() -> void:
	await _reset("War Pick")
	var target := _dummy(START + _forward() * 2.0)
	target.armor_value = 3000.0
	await _frames(3)
	await _tap_stance(WeaponStance.StancePage.A, 1.0)
	_check(_lost(target) > 50.0, "armor pierce ignores 3000 Armor (%.0f)" % _lost(target))
	_check(target.status_effects.has_effect("armor_shred"), "armor pierce applies Armor Shred")
	_check(target.status_effects.get_armor_multiplier() < 1.0, "shred lowers the target's Armor")
	await _leave_stance()

func _test_hook() -> void:
	await _reset("War Pick")
	var target := _dummy(START + _forward() * 4.2)
	await _frames(3)
	var melee: EnemyMeleeAttack = target.get_node("MeleeAttack")
	melee._state = EnemyMeleeAttack.State.TELEGRAPH
	melee._timer = 5.0
	await _tap_stance(WeaponStance.StancePage.B, 1.2)
	var distance := (target.global_position - _player.global_position).length()
	_check(_lost(target) > 0.0, "hooking strike hits at 4 m")
	_check(distance < 2.4, "hooking strike pulls the target in (%.2f m)" % distance)
	_check(melee._state == EnemyMeleeAttack.State.RECOVERY, "hooking strike interrupts")
	await _leave_stance()

func _test_entangle() -> void:
	await _reset("Whip")
	var target := _dummy(START + _forward() * 6.0)
	target.move_speed = 4.0
	await _frames(3)
	await _tap_stance(WeaponStance.StancePage.B, 0.6)
	var held_at := target.global_position
	_check(target.status_effects.has_effect("entangle"), "entangle roots the target")
	_check(_lost(target) == 0.0, "entangle deals no damage")
	await _seconds(1.0)
	_check((target.global_position - held_at).length() < 0.05, "an entangled enemy can't move")
	await _seconds(1.2)
	_check((target.global_position - held_at).length() > 0.5, "it moves again after 2 s")
	await _leave_stance()

func _test_repulse() -> void:
	await _reset("Shock Lance")
	var a := _dummy(START + _forward() * 2.0)
	var b := _dummy(START + _player.global_transform.basis.x * 2.0)
	var far := _dummy(START - _forward() * 8.0)
	await _frames(3)
	_player.stat_sheet.misc_bonus["ailment_chance_electrocute"] = 100.0  # the rider is a roll; force it
	await _tap_stance(WeaponStance.StancePage.B, 0.8)
	_check((a.global_position - START).length() > 3.5 and (b.global_position - START).length() > 3.5, "repulse pushes everything nearby away")
	_check(a.status_effects.has_effect("electrocute"), "repulse Electrocutes")
	_player.stat_sheet.misc_bonus.erase("ailment_chance_electrocute")
	_check(not far.status_effects.has_effect("electrocute"), "repulse has a limited radius")
	await _leave_stance()

func _test_slice_and_dice() -> void:
	await _reset("Dagger")
	var target := _dummy(START + _forward() * 1.8)
	await _frames(3)
	_damage_log.clear()
	await _tap_stance(WeaponStance.StancePage.A, 1.5)
	var hits := _hits_on(target)
	_check(hits.size() == 5, "slice and dice lands a 5-hit flurry (%d)" % hits.size())
	if hits.size() == 5:
		_check(hits[4][1] > hits[0][1] * 1.5, "a completed flurry ends with a finisher")
	await _leave_stance()
	await _reset("Dagger")
	target = _dummy(START + _forward() * 1.8)
	await _frames(3)
	_damage_log.clear()
	Input.action_press("stance")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(0.15)
	Input.action_release("stance")
	await _seconds(0.8)
	_check(_hits_on(target).size() < 5, "leaving stance cuts the flurry short")

func _test_stealth() -> void:
	await _reset("Dagger")
	_player.weapon_stance.set_stance_page(WeaponStance.StancePage.B)
	Input.action_press("stance")
	await _frames(2)
	var watcher := _dummy(START + _forward() * 9.0)
	watcher.move_speed = 4.0
	await _frames(3)
	var start := watcher.global_position
	await _seconds(1.0)
	_check(_player.stance_attack.is_stealthed(), "standing still in Stealth hides you")
	_check((watcher.global_position - start).length() < 0.05, "a hidden player isn't noticed at 9 m")
	Input.action_release("stance")
	await _seconds(1.0)
	_check((watcher.global_position - start).length() > 1.0, "leaving stealth gets you noticed")
	await _reset("Dagger")
	var target := _dummy(START + _forward() * 2.0)
	if target.stance:
		target.stance.max_stance = 1.0e9  # no Composure break, so the second stab isn't a Riposte
		target.stance.reset()
	await _frames(3)
	await _tap_stance(WeaponStance.StancePage.B, 1.5)
	var from_stealth := _lost(target)
	target.global_position = START + _forward() * 2.0
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(1.5)
	var after := _lost(target) - from_stealth
	_check(after > 0.0 and from_stealth > after * 1.6, "the first attack from stealth hits much harder (%.0f vs %.0f)" % [from_stealth, after])
	await _leave_stance()
