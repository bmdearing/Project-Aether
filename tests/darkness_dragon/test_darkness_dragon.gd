extends Node
## Nyxareth and the DarkArena: wells light the floor, Dread builds in the
## dark and Swallows at the cap, wells relight by holding Interact or with a
## Fire hit, Shadow Breath puts out wells in its cone, Shades smother wells,
## Nightfall sears him per well still burning, Eclipse keeps one well lit
## and moves it, and Devouring Dark Swallows a player left in the dark.
## Run: Godot --headless --path . res://tests/darkness_dragon/test_darkness_dragon.tscn --quit-after 20000

const TEST_LIFE := 100000.0

var _checks := 0
var _failures := 0
var _arena: PinnacleArena
var _boss: DarknessDragon
var _dark: DarkArena
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
	_player.health.max_health = TEST_LIFE
	_player.health.current_health = TEST_LIFE

func _place(point: Vector3) -> void:
	_player.global_position = _dark.to_global(point) + Vector3(0, 0.1, 0)

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.pending_pinnacle = "darkness_dragon"
	_arena = (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	await _wait(0.5)
	_boss = _arena.boss as DarknessDragon
	_dark = _arena.dark
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_boss != null and _dark != null, "the Nyxareth pinnacle builds a dark arena with him in it")
	_check(Pinnacle.offered_bosses().has("darkness_dragon"), "he's offered at the Reality Engine")
	if _boss == null or _dark == null:
		_finish()
		return
	_boss.boss_brain.set_physics_process(false)
	_boss.set_physics_process(false)
	var melee := _boss.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
	_player.set_physics_process(false)
	_player._on_leveled_up(_boss.level)
	_heal()
	_boss.boss_brain._player = _player
	_check(_dark.wells.size() == DarkArena.WELLS and _dark.lit_count() == DarkArena.WELLS, "five wells, all burning")
	_check(_boss._clip("sleep", 0.5, true), "his clips play by name")
	await _test_dread()
	await _test_relight()
	await _test_breath()
	await _test_shade()
	await _test_nightfall()
	await _test_eclipse()
	_finish()

func _finish() -> void:
	print("darkness dragon tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_dread() -> void:
	_dark._active = true
	_place(Vector3(0, 0, 4))
	_check(not _dark.is_lit(_player.global_position), "the middle of the arena is dark")
	var base_mult := _boss.get_outgoing_damage_multiplier()
	await _wait(3.0)
	_check(_dark.dread >= 1.5, "Dread builds in the dark (%.2f)" % _dark.dread)
	_check(_boss.get_outgoing_damage_multiplier() > base_mult, "Dread makes his hits land harder")
	_place(_dark.wells[0].position + Vector3(1.5, 0, 0))
	var before := _dark.dread
	await _wait(1.0)
	_check(_dark.dread < before, "Dread drains in a well's light")
	_heal()
	_place(Vector3(0, 0, 4))
	_dark.dread = DarkArena.DREAD_MAX - 0.05
	await _wait(0.4)
	_check(absf(_dark.dread - DarkArena.DREAD_AFTER_SWALLOW) < 0.5, "at the cap the player is Swallowed and Dread falls back")
	_check(_player.health.current_health < TEST_LIFE * 0.9, "being Swallowed hurts (%.0f left)" % _player.health.current_health)
	_heal()
	_dark.dread = 0.0

func _test_relight() -> void:
	var w := _dark.wells[1]
	w.set_lit(false)
	_place(w.position + Vector3(1.5, 0, 0))
	Input.action_press("interact")
	await _wait(Lightwell.RELIGHT_SEC + 0.4)
	Input.action_release("interact")
	_check(w.lit, "holding Interact beside a dark well relights it")
	w.set_lit(false)
	EventBus.damage_dealt.emit(_player, _boss, 10.0, Constants.DamageType.FIRE, false, false)
	_check(w.lit, "a Fire hit landed beside a dark well lights it at once")
	w.set_lit(false)
	EventBus.damage_dealt.emit(_player, _boss, 10.0, Constants.DamageType.COLD, false, false)
	_check(not w.lit, "other hits don't")
	w.set_lit(true)

func _test_breath() -> void:
	_heal()
	_boss.global_position = _dark.to_global(Vector3.ZERO)
	var target := _dark.wells[0]
	_place(target.position * 0.6)
	await _boss.cast_custom(_boss.boss_brain.find("shadow_breath"))
	_check(not target.lit, "Shadow Breath puts out the well in its cone")
	_check(_dark.wells[2].lit, "wells outside the cone keep burning")
	_check(_player.health.current_health < TEST_LIFE, "the breath hits a player in the cone")
	for w in _dark.wells:
		w.set_lit(true)

func _test_shade() -> void:
	var w := _dark.wells[3]
	var unit := EnemyRoster.create_unit(DarknessDragon.SHADE_UNIT)
	_arena.add_child(unit)
	unit.global_position = w.global_position + Vector3(1.6, 0.1, 0)
	var channel := ShadeChannel.new()
	channel.arena = _dark
	unit.add_child(channel)
	_place(Vector3(0, 0, -15))
	await _wait(ShadeChannel.SNUFF_SEC + ShadeChannel.RETARGET_SEC + 1.0)
	_check(not w.lit, "a Shade beside a lit well smothers it")
	unit.queue_free()
	for x in _dark.wells:
		x.set_lit(true)

func _test_nightfall() -> void:
	_heal()
	_place(_dark.wells[0].position + Vector3(1.5, 0, 0))
	_boss.boss_brain._enter_phase(2)
	await _wait(0.5)
	_check(_dark.lit_count() == 0, "Nightfall puts every well out")
	_check(_boss.invulnerable and _boss.nightfall, "he sleeps through Nightfall, untouchable")
	await _wait(DarknessDragon.NIGHTFALL_SHADE_GAP * DarknessDragon.NIGHTFALL_SHADES + 0.5)
	var shades := get_tree().get_nodes_in_group("shade_channel")
	_check(shades.size() == DarknessDragon.NIGHTFALL_SHADES, "Shades rise (%d)" % shades.size())
	for s in shades:
		s.get_parent().queue_free()
	_dark.wells[0].set_lit(true)
	_dark.wells[2].set_lit(true)
	var life := _boss.health.current_health
	await _wait(DarknessDragon.NIGHTFALL_SEC - DarknessDragon.NIGHTFALL_SHADE_GAP * DarknessDragon.NIGHTFALL_SHADES + 1.0)
	_check(not _boss.nightfall and not _boss.invulnerable, "he wakes")
	var seared := (life - _boss.health.current_health) / _boss.health.max_health
	_check(absf(seared - DarknessDragon.NIGHTFALL_BURST_SHARE * 2.0) < 0.002, "two wells burning sear him for 4%% (%.3f)" % seared)

func _test_eclipse() -> void:
	_heal()
	_place(Vector3(0, 0, 4))
	_boss.boss_brain._enter_phase(3)
	await _wait(0.3)
	_check(_dark.eclipse and _dark.lit_count() == 1, "Eclipse leaves one well burning")
	var locked := _dark.wells[(_dark.sun_well + 1) % DarkArena.WELLS]
	locked.set_lit(true)
	_check(not locked.lit, "the other wells can't be relit")
	# His phase 3 opener, Devouring Dark, finds the player in the dark.
	await _wait(1.6 + DarknessDragon.DEVOUR_CHANNEL_SEC + 0.6)
	_check(_player.health.current_health < TEST_LIFE * 0.6, "Devouring Dark Swallows a player outside the light (%.0f left)" % _player.health.current_health)
	var sun := _dark.sun_well
	await _wait(DarkArena.ECLIPSE_SHIFT_SEC)
	_check(_dark.sun_well != sun and _dark.lit_count() == 1, "the light moves to another well")
