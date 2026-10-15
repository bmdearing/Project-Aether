extends Node
## Aurelia and her arena: phases and spell upgrades, the Earth Wheel's safe
## wedges, the Fire Wall's gap, tracking Ice Spears, Lightning Bolt timings,
## a Fire Golem's knock-up, the Living Bomb's cooldown, Amaterasu's burn.
## Run: Godot --headless --path . res://tests/aurelia/test_aurelia.tscn --quit-after 400000

var _checks := 0
var _failures := 0
var _arena: PinnacleArena
var _boss: Aurelia
var _wheel: AureliaArena
var _player: Player

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _heal() -> void:
	_player.health.current_health = _player.health.max_health
	_player.ward.current_ward = 0.0

func _place(local: Vector3) -> void:
	_player.global_position = _wheel.to_global(local) + Vector3.UP * 0.1

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	GameState.pending_pinnacle = "aurelia"
	_arena = (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	await _wait(0.5)
	_boss = _arena.boss as Aurelia
	_wheel = _arena.aurelia
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_boss != null and _wheel != null, "the Aurelia pinnacle builds her arena with her in it")
	_check(Pinnacle.offered_bosses().has("aurelia") and not Pinnacle.offered_bosses().has("lord_of_the_elements"), "the Reality Engine offers her instead of the Lord of the Elements")
	if _boss == null or _wheel == null:
		_finish()
		return
	_boss.boss_brain.set_physics_process(false)
	_boss.set_physics_process(false)
	_player.set_physics_process(false)
	# At her level, so the level-gap multiplier stays out of these checks.
	_player._on_leveled_up(Aurelia.boss_level)
	_player.health.max_health = 100000.0
	# Ward refilling between checks would soak hits the checks read off Life.
	_player.ward.max_ward = 0.0
	_heal()
	_check(_boss.boss_brain.phase_thresholds == [0.9, 0.75, 0.5, 0.25], "phases start at 90, 75, 50 and 25% Life")
	_check(_boss.boss_brain.phase_openers.size() == 4, "every later phase opens with something")
	await _test_upgrades()
	await _test_earth_wheel()
	await _test_fire_wall()
	await _test_icicles()
	await _test_lightning()
	await _test_roots_and_combos()
	await _test_golem_and_bomb()
	await _test_amaterasu()
	_finish()

func _finish() -> void:
	print("aurelia tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_upgrades() -> void:
	_check(_boss.upgraded.is_empty(), "no spell starts upgraded")
	var speed1 := _boss.get_cast_speed_multiplier()
	_boss.boss_brain.phase = 2
	_check(_boss.get_cast_speed_multiplier() > speed1, "she casts faster once the fight begins")
	_boss._on_phase_changed(2)
	_check(_boss.upgraded.size() == 1, "the 90% phase upgrades one spell")
	_boss._on_phase_changed(3)
	_boss._on_phase_changed(4)
	_check(_boss.upgraded.size() == 3 and _boss.upgraded[0] != _boss.upgraded[1] and _boss.upgraded[1] != _boss.upgraded[2], "75% and 50% each upgrade another")
	_boss._on_phase_changed(5)
	_check(_boss.upgraded.size() == 4, "by the last phase all four spells are upgraded")
	_boss.upgraded.clear()
	_boss.boss_brain.phase = 1

func _test_earth_wheel() -> void:
	_wheel.wedge_angles.assign([0.0, PI])
	_check(_wheel.is_safe_from_quake(_wheel.to_global(Vector3(0, 0, 10))), "inside a wedge is safe")
	_check(not _wheel.is_safe_from_quake(_wheel.to_global(Vector3(10, 0, 0))), "outside the wedges quakes")
	_check(not _wheel.is_safe_from_quake(_wheel.to_global(Vector3(0, 0, 1.5))), "the hub under her is never safe")
	_wheel.wedge_angles.clear()
	# Standing in the first wedge (aimed at the player) for one quake.
	_place(Vector3(0, 0, 10))
	_heal()
	await _wheel.earth_wheel(1, 0.0)
	_check(_player.health.current_health == _player.health.max_health, "a player in the wedge takes nothing")
	_heal()
	await _wheel.earth_wheel(1, PI / 2.0)
	var lost := _player.health.max_health - _player.health.current_health
	_check(lost > _player.health.max_health * 0.2, "outside it the quake hits hard (%.0f of %.0f)" % [lost, _player.health.max_health])
	_check(not _wheel.earth_wheel_active, "the wheel stops after its count")
	# Each next set of wedges turns a little left or right.
	_heal()
	_place(Vector3(0, 0, -10))
	var turns: Array[float] = []
	_wheel.earth_wheel.call(3, 0.0)
	var last := 0.0
	for i in 3:
		await _wait((AureliaArena.EARTH_WHEEL_FIRST_WARNING + 0.1) if i == 0 else AureliaArena.EARTH_WHEEL_WARNING)
		_heal()
		if not _wheel.wedge_angles.is_empty():
			turns.append(absf(wrapf(_wheel.wedge_angles[0] - last, -PI, PI)))
			last = _wheel.wedge_angles[0]
	await _wait(0.5)
	_check(turns.size() >= 2 and turns.slice(0, 2).all(func(t): return t >= deg_to_rad(AureliaArena.EARTH_WHEEL_TURN_DEG.x) - 0.01 and t <= deg_to_rad(AureliaArena.EARTH_WHEEL_TURN_DEG.y) + 0.01), "each quake turns the wedges %d-%d degrees" % [AureliaArena.EARTH_WHEEL_TURN_DEG.x, AureliaArena.EARTH_WHEEL_TURN_DEG.y])
	_heal()
	# She's immune while she turns it.
	_boss.boss_brain.casting = true
	_boss._earth_wheel.call(1)
	await _wait(0.2)
	_check(_boss.invulnerable, "Aurelia is immune during the Earth Wheel")
	_check(_boss.global_position.distance_to(_wheel.global_position) < 0.5, "she turns it from the hub")
	await _wait(AureliaArena.EARTH_WHEEL_FIRST_WARNING + 0.3)
	_check(not _boss.invulnerable, "and vulnerable again after")
	_boss.boss_brain.casting = false
	_boss.global_position = _wheel.to_global(AureliaArena.BOSS_SPAWN)
	_heal()

func _test_fire_wall() -> void:
	var origin := _wheel.to_global(Vector3(0, 0, -8))
	var aim := Vector3(0, 0, 1)
	# Straight down the middle: through the split.
	_place(Vector3(0, 0, 2))
	_heal()
	var wall := AureliaFireWall.cast(_arena, origin, aim, 500.0, _boss)
	await _wait(2.0)
	_check(_player.health.current_health == _player.health.max_health, "the gap in the middle of the Fire Wall is safe")
	wall.queue_free()
	# Off to one side: burned.
	_place(Vector3(4, 0, 0))
	wall = AureliaFireWall.cast(_arena, origin, aim, 500.0, _boss)
	await _wait(2.0)
	_check(_player.health.current_health < _player.health.max_health, "the rest of the arc burns")
	wall.queue_free()
	_heal()
	# Upgraded, it leaves fire pots; a new phase clears them.
	_boss.upgraded.assign([Aurelia.Spell.FIRE_WALL])
	_place(Vector3(0, 0, 14))
	await _boss._fire_wall(_boss.boss_brain.find("fire_wall"))
	await _wait(2.2)
	_check(_wheel.fire_pot_count() >= 1 and _wheel.fire_pot_count() <= 2, "the upgraded Fire Wall leaves 1-2 fire pots (%d)" % _wheel.fire_pot_count())
	_boss._on_phase_changed(2)
	_check(_wheel.fire_pot_count() == 0, "they go away at the next phase")
	_boss.upgraded.clear()
	_heal()

func _test_icicles() -> void:
	_place(Vector3(10, 0, 0))
	var origin := _wheel.to_global(Vector3.ZERO)
	var off := Vector3(0, 0, 1)
	var plain := AureliaIcicle.fire(_arena, origin, off, 1.0, _boss, false)
	var tracking := AureliaIcicle.fire(_arena, origin, off, 1.0, _boss, true)
	await _wait(1.0)
	_check(plain.direction.is_equal_approx(off), "plain Ice Spears fly straight")
	var to_player := (_player.global_position - tracking.global_position)
	to_player.y = 0.0
	_check(tracking.direction.angle_to(off) > 0.3, "upgraded Ice Spears turn toward the player")
	plain.queue_free()
	tracking.queue_free()
	_heal()

func _test_lightning() -> void:
	_check(Aurelia.BOLT_GAPS == [1.5, 1.0] and is_equal_approx(Aurelia.BIG_BOLT_DELAY, 0.75), "warning strikes 1.5s then 1s apart, the big bolt 0.75s after")
	_check(Aurelia.BOLT_GAPS_UPGRADED.size() == Aurelia.BOLT_GAPS.size() - 1, "upgraded: one fewer warning strike")
	_place(Vector3(6, 0, 6))
	_heal()
	var ability := _boss.boss_brain.find("lightning_bolt")
	var t0 := Time.get_ticks_msec()
	await _boss._lightning_bolt(ability)
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	_check(_player.health.current_health < _player.health.max_health, "standing still, the bolts land on you")
	_check(took > 1.5 + 1.0 + 0.75, "the whole cast takes the warning gaps plus the big bolt (%.2fs)" % took)
	_heal()

func _clear_status() -> void:
	_player.status_effects.clear_all_effects()
	for n in get_tree().get_nodes_in_group("forbidden_fire"):
		n.free()

func _test_roots_and_combos() -> void:
	_clear_status()
	_place(Vector3(0, 0, 4))
	_heal()
	_boss.global_position = _wheel.to_global(Vector3(0, 0.05, -6))
	await _boss._entangling_roots(_boss.boss_brain.find("entangling_roots"))
	await _wait(1.2)
	_check(_player.status_effects.has_effect("entangle") and _player.health.current_health < _player.health.max_health, "Entangling Roots catch and root the player")
	_check(_player.status_effects.get_move_speed_multiplier() == 0.0, "an Entangled player can't move")
	# Entangled + fire -> Forbidden Fire.
	_heal()
	AureliaAilments.hit(_player, 10.0, Constants.DamageType.FIRE, _boss)
	await _wait(1.1)
	_check(_player.status_effects.has_effect("forbidden_fire") and get_tree().get_nodes_in_group("forbidden_fire").size() == 1, "fire on an Entangled player starts Forbidden Fire")
	var before := _player.health.current_health
	await _wait(1.0)
	_check(_player.health.current_health < before, "Forbidden Fire burns over time")
	_clear_status()
	# Chilled + lightning -> Electrocuted and Shocked.
	_player.status_effects.apply_effect("chill", _boss)
	AureliaAilments.hit(_player, 10.0, Constants.DamageType.LIGHTNING, _boss)
	_check(_player.status_effects.has_effect("electrocute") and _player.status_effects.has_effect("shock"), "lightning on a Chilled player Electrocutes and Shocks")
	_clear_status()
	AureliaAilments.hit(_player, 10.0, Constants.DamageType.LIGHTNING, _boss)
	_check(not _player.status_effects.has_effect("electrocute"), "lightning alone doesn't Electrocute")
	# Ignited + cold -> Pallid, which lowers the player's own damage.
	_player.status_effects.apply_effect("ignite", _boss, 10.0)
	AureliaAilments.hit(_player, 10.0, Constants.DamageType.COLD, _boss)
	_check(_player.status_effects.has_effect("pallid"), "cold on an Ignited player makes them Pallid")
	_check(_player.stat_sheet.outgoing_more_multiplier(Constants.DamageType.FIRE) < 1.0, "a Pallid player deals less damage")
	_clear_status()
	# Her brain: she reaches for whatever completes a combo.
	var brain := _boss.boss_brain
	_player.status_effects.apply_effect("chill", _boss)
	_check(_boss.ability_weight(brain.find("lightning_bolt")) > _boss.ability_weight(brain.find("fire_wall")), "a Chilled player draws her Lightning Bolt")
	_clear_status()
	_player.status_effects.apply_effect("ignite", _boss, 10.0)
	_check(_boss.ability_weight(brain.find("ice_spears")) > 1.0 and _boss.ability_weight(brain.find("lightning_bolt")) == 1.0, "an Ignited player draws her cold")
	_clear_status()
	_check(_boss.ability_weight(brain.find("entangling_roots")) > 1.0, "with nothing on you she sets a combo up")
	_player.status_effects.apply_timed_effect("entangle", 2.0)
	var near := _boss.urgent_ability(3.0)
	_check(near != null and near.id == "searing_thrust", "an Entangled player in reach gets Searing Thrust at once")
	_boss._answered_entangle_msec = -100000
	var far := _boss.urgent_ability(15.0)
	_check(far != null and far.id == "fire_wall", "out of reach, Fire Wall")
	_check(_boss.urgent_ability(15.0) == null, "once per Entangle")
	_clear_status()
	_boss.global_position = _wheel.to_global(AureliaArena.BOSS_SPAWN)
	_heal()

func _test_golem_and_bomb() -> void:
	_place(Vector3(0, 0, 10))
	_heal()
	var golem: FireGolem = (load(Aurelia.GOLEM_SCENE) as PackedScene).instantiate()
	_arena.add_child(golem)
	golem.global_position = _wheel.to_global(Vector3(0, 0, 14))
	_check(is_equal_approx(golem.health.max_health, FireGolem.LIFE), "a Fire Golem has %.0f Life" % golem.health.max_health)
	var knocked := [false]
	golem.player_knocked_up.connect(func(_g, _p): knocked[0] = true)
	await _wait(FireGolem.SLAM_TELEGRAPH + 2.0)
	_check(knocked[0] and _player.health.current_health < _player.health.max_health, "a Fire Golem's slam hits and knocks the player up")
	_check(_player.is_knocked_up(), "the player is airborne and can't act")
	golem.queue_free()
	_heal()
	# The Living Bomb answers a knock-up only in her last phase, once per 5s.
	_boss.boss_brain.phase = 4
	_boss._on_player_knocked_up(null, _player)
	await _wait(0.5)
	_check(get_tree().get_nodes_in_group("living_bomb").is_empty(), "no Living Bomb before the last phase")
	_boss.boss_brain.phase = 5
	_boss._on_player_knocked_up(null, _player)
	await _wait(0.5)
	_check(get_tree().get_nodes_in_group("living_bomb").size() == 1, "in the last phase she plants a Living Bomb")
	_boss._on_player_knocked_up(null, _player)
	await _wait(0.5)
	_check(get_tree().get_nodes_in_group("living_bomb").size() == 1, "not again within 5 seconds")
	_heal()
	await _wait(LivingBomb.FUSE)
	_check(get_tree().get_nodes_in_group("living_bomb").is_empty() and _player.health.current_health < _player.health.max_health, "the bomb explodes on the player")
	_boss.boss_brain.phase = 1
	_heal()

func _test_amaterasu() -> void:
	_wheel.start_amaterasu()
	_place(Vector3(0, 0, AureliaArena.RADIUS - 0.5))
	_player.health.current_health = 4000.0
	await _wait(1.1)
	var lost := 4000.0 - _player.health.current_health
	_check(lost > 0.0 and lost < 4000.0 * 0.06, "the black fire burns ~2.75%% of current Life a second at the rim (%.0f in ~1s)" % lost)
	_place(Vector3(0, 0, 2))
	_heal()
	await _wait(1.1)
	_check(_player.health.current_health == _player.health.max_health, "the middle isn't burning yet")
	var r := _wheel.amaterasu_safe_radius
	await _wait(1.0)
	_check(_wheel.amaterasu_safe_radius < r, "the fire keeps creeping inward")
