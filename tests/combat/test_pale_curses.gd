extends Node
## Curses (Meager, Fracturing, Decompose, Elemental Fragility) and the Pale
## spells (Linger, Pale Thread, Death Shroud), cast with the real keys.
## Run: Godot --headless --path . res://tests/combat/test_pale_curses.tscn --quit-after 60000

var _checks := 0
var _failures := 0
var _arena: Node3D
var _player: Player
var _cast_failures: Array[String] = []
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
	EventBus.ability_cast_failed.connect(func(_c, _a, reason): _cast_failures.append(reason))
	await _test_curses()
	await _test_linger()
	await _test_pale_thread()
	await _test_death_shroud()
	await _test_hex_aura()
	await _test_no_target_and_mana()
	_test_effect_text()
	print("pale curse tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _reset() -> void:
	for i in 4:
		Input.action_release("ability_%d" % (i + 1))
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()
	for i in 8:
		_player.ability_loadout.slots[i] = null
	_player.ability_cast._cooldowns.clear()
	_player.global_position = START
	_player.velocity = Vector3.ZERO
	_player.mana.current_mana = _player.mana.max_mana
	GameState.death_shroud_on = false
	_cast_failures.clear()
	await _frames(5)

func _spell(id: String) -> Ability:
	var a := load("res://data/abilities/instances/%s.tres" % id) as Ability
	a.level = 1
	a.base_damage_min = a.base_damage_max
	return a

func _forward() -> Vector3:
	return -_player.global_transform.basis.z

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	e.position = pos
	_arena.add_child(e)
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.armor_value = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := e.get_node_or_null(path)
		if attack:
			attack.set_physics_process(false)
	return e

func _lost(e: Enemy) -> float:
	return 1.0e6 - e.health.current_health

func _cast_key(key: int, settle: float = 0.3) -> void:
	var action := "ability_%d" % key
	_player.ability_cast._cast_lockout = 0.0
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _seconds(settle)

func _test_curses() -> void:
	await _reset()
	var e := _dummy(START + _forward() * 4.0)
	await _frames(3)
	var cast := _player.ability_cast
	_player.stat_sheet.misc_bonus["additional_curses"] = 3.0  # room for all four
	for id in ["meager", "fracturing", "decompose", "elemental_fragility"]:
		cast._cast_resolved(_spell(id), e.global_position)
	var s := e.status_effects
	_check(s.has_effect("meager") and e.get_outgoing_damage_multiplier() < 0.9, "Meager: less damage dealt (%.2f)" % e.get_outgoing_damage_multiplier())
	_check(s.get_evasion_multiplier() < 0.8, "Meager: less evasion (%.2f)" % s.get_evasion_multiplier())
	_check(s.get_armor_multiplier() < 0.8, "Fracturing: less armour (%.2f)" % s.get_armor_multiplier())
	_check(s.get_damage_taken_multiplier(Constants.DamageType.KINETIC) > 1.1 and is_equal_approx(s.get_damage_taken_multiplier(Constants.DamageType.FIRE), 1.0), "Fracturing: more Physical damage taken only")
	_check(s.get_curse_resistance_shred(Constants.DamageType.ENTROPIC) >= 25.0 and s.get_curse_resistance_shred(Constants.DamageType.PALE) == 0.0, "Decompose: Entropic resistance only")
	_check(s.get_curse_resistance_shred(Constants.DamageType.COLD) >= 20.0 and s.get_curse_resistance_shred(Constants.DamageType.KINETIC) == 0.0, "Elemental Fragility: Elemental resistance only")
	var before := _lost(e)
	e.take_damage(100.0, Constants.DamageType.ENTROPIC, true)
	_check(_lost(e) - before > 110.0, "Decompose: Entropic hits deal more (%.1f)" % (_lost(e) - before))
	# The curse limit: one by default, a new curse pushes out the oldest.
	_player.stat_sheet.misc_bonus.erase("additional_curses")
	var f := _dummy(START + _forward() * 4.0 + Vector3(3, 0, 0))
	await _frames(2)
	cast._cast_resolved(_spell("meager"), f.global_position)
	cast._cast_resolved(_spell("fracturing"), f.global_position)
	_check(f.status_effects.get_curses() == ["fracturing"], "one curse at a time: Fracturing replaced Meager (%s)" % [f.status_effects.get_curses()])
	_player.stat_sheet.misc_bonus["additional_curses"] = 1.0
	cast._cast_resolved(_spell("decompose"), f.global_position)
	_check(f.status_effects.get_curses() == ["fracturing", "decompose"], "+1 additional Curse holds two")
	_player.stat_sheet.misc_bonus["curse_effect"] = 50.0
	cast._cast_resolved(_spell("meager"), f.global_position)
	_check(absf(f.status_effects.get_magnitude("meager") - 1.5) < 0.01 and f.status_effects.get_curses() == ["decompose", "meager"], "Curse Effect strengthens a curse, which pushes out the oldest")
	_player.stat_sheet.misc_bonus.erase("curse_effect")
	_player.stat_sheet.misc_bonus.erase("additional_curses")

func _test_linger() -> void:
	await _reset()
	var first := _dummy(START + _forward() * 4.0)
	_player.ability_loadout.equip(_spell("linger"), 0)
	await _frames(3)
	await _cast_key(1, 1.2)
	_check(first.status_effects.has_effect("linger"), "Linger lands on the crosshair target")
	_check(_lost(first) > 0.0, "Linger deals Pale damage over time (%.1f)" % _lost(first))
	_check(first.status_effects.get_move_speed_multiplier() < 1.0, "Linger boggles: slower")
	var near_a := _dummy(first.global_position + Vector3(2.5, 0, 0))
	var near_b := _dummy(first.global_position + Vector3(-2.5, 0, 0))
	var far := _dummy(first.global_position + Vector3(0, 0, -6.0))
	await _frames(3)
	first.health.apply_damage(2.0e6)
	await _frames(3)
	_check(near_a.status_effects.has_effect("linger") and near_b.status_effects.has_effect("linger"), "Linger spreads to the two nearest on death")
	_check(not far.status_effects.has_effect("linger"), "Linger spreads to only two")

func _test_pale_thread() -> void:
	await _reset()
	var e := _dummy(START + _forward() * 5.0)
	_player.ward.max_ward = 100.0
	_player.ward.current_ward = 0.0
	_player.ability_loadout.equip(_spell("pale_thread"), 0)
	await _frames(3)
	await _cast_key(1, 1.0)
	_check(_lost(e) > 0.0, "Pale Thread deals damage (%.1f)" % _lost(e))
	_check(_player.ward.current_ward > 3.0, "Pale Thread restores Ward (%.1f)" % _player.ward.current_ward)
	_check(is_instance_valid(_player.ability_cast._thread_beam), "Pale Thread draws its thread")
	e.global_position = START + _forward() * 30.0
	await _frames(3)
	_check(_player.ability_cast._thread_remaining <= 0.0 and not is_instance_valid(_player.ability_cast._thread_beam), "Pale Thread breaks out of range")

func _test_death_shroud() -> void:
	await _reset()
	var inside := _dummy(START + _forward() * 3.0)
	var outside := _dummy(START + _forward() * 15.0)
	_player.ability_loadout.equip(_spell("death_shroud"), 0)
	await _frames(3)
	await _cast_key(1, 0.6)
	_check(GameState.death_shroud_on, "Death Shroud toggles on")
	_check(inside.status_effects.has_effect("pallid") and not outside.status_effects.has_effect("pallid"), "Death Shroud makes enemies within it Pallid")
	var mana_before := _player.mana.current_mana
	await _cast_key(1, 0.1)
	_check(not GameState.death_shroud_on and _player.mana.current_mana >= mana_before, "casting again turns it off for free")
	_check(absf(inside.status_effects.get_magnitude("pallid") - PlayerAbilityCast.DEATH_SHROUD_STRENGTH) < 0.01, "Death Shroud's Pallid is the strong one (35% less damage)")
	# Drain: Mana falls while it's on, faster than regen, and it ends at 0.
	_player.mana.current_mana = _player.mana.max_mana
	await _cast_key(1, 0.2)
	var at_start := _player.mana.current_mana
	await _seconds(1.0)
	_check(_player.mana.current_mana < at_start, "Death Shroud drains Mana while on (%.1f -> %.1f)" % [at_start, _player.mana.current_mana])
	_player.mana.current_mana = 0.0
	await _frames(3)
	_check(not GameState.death_shroud_on and _cast_failures.has("Not enough Mana"), "it switches off when Mana runs dry")

func _test_hex_aura() -> void:
	await _reset()
	var near := _dummy(START + _forward() * 3.0)
	var hex := _spell("fracturing")
	hex.web_points = {"hex_potency": 1, "hex_aura": 1}
	_player.ability_loadout.equip(hex, 0)
	await _frames(3)
	await _cast_key(1, 0.6)
	_check(GameState.hex_auras.has("fracturing"), "Hex Aura: casting switches the curse on as an aura (no targeting)")
	_check(near.status_effects.has_effect("fracturing") and near.status_effects.get_magnitude("fracturing") > PlayerAbilityCast.HEX_AURA_STRENGTH, "the aura curses enemies near you, stronger than a cast (%.2f)" % near.status_effects.get_magnitude("fracturing"))
	var at_start := _player.mana.current_mana
	await _seconds(1.0)
	_check(_player.mana.current_mana < at_start, "the curse aura drains Mana")
	await _cast_key(1, 0.1)
	_check(not GameState.hex_auras.has("fracturing"), "casting again switches it off")
	hex.web_points = {}

func _test_no_target_and_mana() -> void:
	await _reset()
	_player.ability_loadout.equip(_spell("linger"), 0)
	var mana_before := _player.mana.current_mana
	await _cast_key(1, 0.1)
	_check(_cast_failures.has("No target") and _player.mana.current_mana == mana_before, "Linger with no target is refused at no cost")
	_dummy(START + _forward() * 4.0)
	_player.mana.current_mana = 0.0
	_player.mana.regen_per_second = 0.0
	var voice_before: int = AudioManager._no_mana_voice_at
	await _frames(3)
	await _cast_key(1, 0.1)
	_check(_cast_failures.has("Not enough Mana") and AudioManager._no_mana_voice_at != voice_before, "out of Mana plays the voice line")

func _test_effect_text() -> void:
	var text := preload("res://data/abilities/spell_effect_text.gd")
	for id in ["meager", "fracturing", "decompose", "elemental_fragility", "linger", "pale_thread", "death_shroud", "battle_cry", "intimidating_shout", "frost_armor", "ice_pulse", "entropic_decay"]:
		var lines: Array[String] = text.lines(_spell(id), _player.stat_sheet, _player)
		print("[%s]\n  %s" % [id, "\n  ".join(lines)])
		_check(lines.any(func(l: String): return l.contains("%")), "%s card shows its numbers" % id)
