extends Node
## Ataras and his sand arena: the arena builds, Shifting Sands leaves one
## safe wedge and hurts in the others, Ticking Time waits for the sand to
## settle and leaves permanent traps, Sand Globes spawn and shoot, and
## Sandstorm Cuts hits in front of him.
## Run: Godot --headless --path . res://tests/ataras/test_ataras.tscn --quit-after 12000

var _checks := 0
var _failures := 0
var _arena: Node
var _boss: Ataras
var _sand: SandArena
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

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.pending_pinnacle = "ataras"
	_arena = (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	await _wait(0.5)
	_boss = _arena.boss as Ataras
	_sand = _arena.sand
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_boss != null and _sand != null, "the Ataras pinnacle builds a sand arena with him in it")
	_check(Pinnacle.BOSSES.has("ataras"), "he's offered at the Reality Engine")
	if _boss == null or _sand == null:
		_finish()
		return
	_boss.boss_brain.set_physics_process(false)
	_boss.set_physics_process(false)
	# His ordinary melee would hit the test player whenever a check puts them beside him.
	var melee := _boss.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
	_player.set_physics_process(false)
	_player.health.max_health = 5000.0
	_heal()
	_check(_boss.boss_brain.phase_thresholds == [0.5], "his second phase starts at half Life")
	_check(not _boss.can_use_ability(_boss.boss_brain.find("ticking_time")), "no Ticking Time before the sand settles")
	await _test_wedges()
	await _test_ticking_time()
	await _test_globes()
	await _test_cuts()
	await _test_new_mechanics()
	_finish()

func _finish() -> void:
	print("ataras tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_wedges() -> void:
	var seen := {}
	for i in 12:
		var angle := TAU * i / 12.0 + 0.1
		seen[_sand.wedge_of(_sand.to_global(Vector3(sin(angle), 0, cos(angle)) * 10.0))] = true
	_check(seen.size() == 3, "the floor splits into three wedges")
	_sand.start_wedges()
	await _wait(SandArena.WEDGE_WARNING + 0.3)
	_check(_sand.wedges_dangerous and _sand.safe_wedge >= 0, "after the warning, the quicksand is live")
	var safe_angle := (_sand.safe_wedge + 0.5) * TAU / 3.0
	var bad_angle := safe_angle + TAU / 3.0
	_player.global_position = _sand.to_global(Vector3(sin(safe_angle), 0.1, cos(safe_angle)) * 10.0)
	_heal()
	var safe_start := _player.health.current_health
	await _wait(1.2)
	_check(_player.health.current_health >= safe_start - 1.0, "the safe wedge is safe (lost %.1f)" % (safe_start - _player.health.current_health))
	_player.global_position = _sand.to_global(Vector3(sin(bad_angle), 0.1, cos(bad_angle)) * 10.0)
	_heal()
	await _wait(1.2)
	_check(_player.health.current_health < _player.health.max_health - 50.0, "the quicksand hurts")
	# Partway through, the safe wedge moves once, after a warning.
	var old_safe := _sand.safe_wedge
	await _sand.shift_safe_wedge()
	_check(_sand.safe_wedge != old_safe and _sand.wedges_active, "the safe wedge moves")
	_sand.end_wedges()
	_check(not _sand.wedges_dangerous and not _sand.wedges_active, "the sand settles")

func _test_ticking_time() -> void:
	_boss._sands_settled = true
	_check(_boss.can_use_ability(_boss.boss_brain.find("ticking_time")), "Ticking Time is open once the sand settles")
	var before := _sand.traps.size()
	_player.global_position = _sand.to_global(Vector3(-6, 0.1, 6))
	var ticking := func(): await _boss.cast_custom(_boss.boss_brain.find("ticking_time"))
	ticking.call()  # runs alongside while the player moves
	await _wait(1.0)
	_player.global_position = _sand.to_global(Vector3(0, 0.1, 6))
	await _wait(Ataras.TICKING_DURATION)
	_check(_sand.traps.size() - before >= 2, "the ground you crossed becomes traps (%d)" % (_sand.traps.size() - before))
	_heal()
	await _wait(1.2)
	_check(_player.health.current_health < _player.health.max_health - 30.0, "and the traps hurt")
	_player.global_position = _sand.to_global(Vector3(12, 0.1, -4))
	_heal()

func _test_globes() -> void:
	var before := get_tree().get_nodes_in_group("enemy").filter(func(e): return e is SandGlobe).size()
	await _boss.cast_custom(_boss.boss_brain.find("sand_globes"))
	await _wait(0.2)
	var globes := get_tree().get_nodes_in_group("enemy").filter(func(e): return e is SandGlobe)
	_check(globes.size() - before == Ataras.GLOBE_COUNT, "Sand Globes appear")
	_heal()
	await _wait(SandGlobe.FIRE_INTERVAL + 1.5)
	_check(_player.health.current_health < _player.health.max_health, "and shoot at you")
	for g in globes:
		g.health.apply_damage(g.health.current_health + 1.0)
	await _wait(0.2)
	_check(get_tree().get_nodes_in_group("enemy").filter(func(e): return e is SandGlobe and e.health.is_alive()).is_empty(), "they can be killed")

func _test_cuts() -> void:
	_player.global_position = _boss.global_position + Vector3(0, 0.1, 2.5)
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("sandstorm_cuts"))
	_check(_player.health.current_health < _player.health.max_health, "Sandstorm Cuts hits in front of him")

## His own traps slow him and drain his Composure; the thrust can be parried;
## an echo replays the cuts from where he stood.
func _test_new_mechanics() -> void:
	_boss.composure.end_broken_state()
	_boss.stance.reset()
	_sand.add_trap(_boss.global_position, 2.0)
	var stance_before: float = _boss.stance.current_stance
	await _wait(1.2)
	_check(_boss.status_effects.has_effect("slow") and _boss.stance.current_stance < stance_before, "crossing his own trap slows him and drains his Composure")
	_boss.composure.end_broken_state()
	_boss.stance.reset()
	_boss.status_effects.clear_all_effects()
	for t in _sand.traps:
		if is_instance_valid(t["node"]):
			t["node"].queue_free()
	_sand.traps.clear()
	# Parry the thrust.
	_player.global_position = _boss.global_position + Vector3(0, 0.1, 4.0)
	_heal()
	var cuts := _boss.boss_brain.find("sandstorm_cuts")
	var echoes_before := get_tree().get_nodes_in_group("ataras_echo").size()
	_player.parry_handler.parry_window_seconds = 10.0
	var cast := func(): await _boss.cast_custom(cuts)
	cast.call()
	await _wait(2 * (Ataras.SLASH_TELEGRAPH + Ataras.SLASH_GAP) + 0.05)
	_player.parry_handler.start_parry_window()
	await _wait(Ataras.THRUST_TELEGRAPH + 0.2)
	_player.parry_handler.parry_window_seconds = 0.25
	_check(_boss.status_effects.is_stunned() and _boss.stance.current_stance < _boss.stance.max_stance, "a parried thrust staggers him")
	_check(get_tree().get_nodes_in_group("ataras_echo").size() > echoes_before, "he leaves a sand echo where he stood")
	_boss.status_effects.clear_all_effects()
	# The echo replays the cuts from that spot.
	_boss.global_position += Vector3(12, 0, 0)
	_heal()
	await _wait(Ataras.ECHO_DELAY + 0.1)
	_heal()
	await _wait(Ataras.SLASH_TELEGRAPH + 0.1)
	_check(_player.health.current_health < _player.health.max_health, "the echo hits where he used to stand")
