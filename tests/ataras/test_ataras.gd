extends Node
## Ataras and his sand arena: the arena builds, Shifting Sands leaves one
## safe wedge and hurts in the others, Ticking Time waits for the sand to
## settle and leaves permanent traps, Sand Globes spawn and shoot, and
## Sandstorm Cuts hits in front of him.
## Run: Godot --headless --path . res://tests/ataras/test_ataras.tscn --quit-after 12000

const TEST_LIFE := 100000.0

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

## The player's Life is re-derived after setup, and killing the Sand Globes
## grants XP that re-levels them, so every heal sets both back.
func _heal() -> void:
	if GameState.player_level != _boss.level:
		_player.experience.level = _boss.level
		_player._on_leveled_up(_boss.level)
	_player.health.max_health = TEST_LIFE
	_player.health.current_health = TEST_LIFE

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
	# At his level, so the level-gap multiplier stays out of these checks.
	_player._on_leveled_up(_boss.level)
	_heal()
	_check(_boss.boss_brain.phase_thresholds == [0.5, 0.35], "his phases start at 50% and 35% Life")
	print("ataras base hit: %.0f" % _boss.get_ability_base_damage())
	_check(not _boss.can_use_ability(_boss.boss_brain.find("ticking_time")), "no Ticking Time before the sand settles")
	await _test_wedges()
	await _test_ticking_time()
	await _test_globes()
	await _test_cuts()
	await _test_new_mechanics()
	await _test_combos()
	await _test_pillars_and_sun()
	await _test_mirage()
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
	# Count the hits: a bolt's few points of damage regenerate before a Life check.
	var hits := [0]
	var count_hit := func(source: Node, target: Node, _amount: float, _type: int, _more: bool, _crit: bool):
		if target == _player and source is SandGlobe:
			hits[0] += 1
	EventBus.damage_dealt.connect(count_hit)
	await _wait(SandGlobe.FIRE_INTERVAL + 1.5)
	EventBus.damage_dealt.disconnect(count_hit)
	_check(hits[0] > 0, "and shoot at you")
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
	_player.parry_handler.parry_window_seconds = 0.18
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
	await _wait(1.0)

func _place_boss() -> void:
	_boss.status_effects.clear_all_effects()
	_boss.global_position = _sand.to_global(Vector3(0, 0.05, -8))

## Each combo hits a player in front of him; a jump clears the sweep.
func _test_combos() -> void:
	for id in ["jackal_fangs", "dune_reaver", "desert_sweep"]:
		_place_boss()
		_player.global_position = _boss.global_position + Vector3(0, 0.05, 2.5)
		_heal()
		await _boss.cast_custom(_boss.boss_brain.find(id))
		_check(_player.health.current_health < _player.health.max_health, "%s hits a player in front of him" % id)
	_place_boss()
	_player.global_position = _boss.global_position + Vector3(0, 0.05, 7.0)
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("scarab_rush"))
	_check(_player.health.current_health < _player.health.max_health, "Scarab Rush dashes through a player at range")
	_place_boss()
	_player.global_position = _boss.global_position + Vector3(0, 1.0, 2.5)
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("desert_sweep"))
	_check(_player.health.current_health >= _player.health.max_health, "jumping clears the Desert Sweep")

## A pillar comes up under you at 85%; behind one the Sun can't reach you,
## in the open it does; the blast brings the pillars down.
func _test_pillars_and_sun() -> void:
	_place_boss()
	_boss.health.current_health = _boss.health.max_health * 0.84
	var urgent: BossAbility = _boss.urgent_ability(5.0)
	_check(urgent != null and urgent.id == "sand_pillar", "below 85% Life he calls a Sand Pillar")
	_player.global_position = _sand.to_global(Vector3(8, 0.1, 6))
	_heal()
	await _boss.cast_custom(urgent)
	_check(_boss.urgent_ability(5.0) == null, "one pillar per threshold")
	await _wait(SandPillar.DELAY + 0.3)
	_check(_player.health.current_health < _player.health.max_health, "the pillar hits you if you're still on it")
	var pillar: SandPillar = _boss._pillars[0]
	var flat := Vector2(_player.global_position.x - pillar.global_position.x, _player.global_position.z - pillar.global_position.z).length()
	_check(pillar.standing and flat > SandPillar.RADIUS, "it stays standing and throws you clear")
	_boss._raise_pillar(_sand.to_global(Vector3(-8, 0, 6)))
	_boss._raise_pillar(_sand.to_global(Vector3(0, 0, 12)))
	await _wait(SandPillar.DELAY + 0.3)
	var centre := _sand.global_position
	var behind := _sand.to_global(Vector3(11.2, 0.1, 8.4))
	var exposed := _sand.to_global(Vector3(0, 0.1, -14))
	_check(_boss.is_sheltered(centre, behind) and not _boss.is_sheltered(centre, exposed), "a pillar shelters what's behind it from the centre")
	# Sheltered: no damage.
	_boss.health.current_health = _boss.health.max_health * 0.34
	_player.global_position = behind
	_heal()
	var sun := func(): await _boss.cast_custom(_boss.boss_brain.find("fiery_sun"))
	sun.call()
	await _wait(1.0)
	_check(_boss.invulnerable, "he's immune while raising the Sun")
	await _wait(Ataras.SUN_GROW + Ataras.SUN_HOLD + Ataras.SUN_FALL)
	_check(_player.health.current_health >= _player.health.max_health, "behind a pillar the Sun doesn't reach you")
	_check(not _boss.invulnerable, "and he can be hurt again after")
	await _wait(1.0)
	_check(get_tree().get_nodes_in_group("ataras_pillar").is_empty(), "the blast brings the pillars down")
	# Exposed: Fire and Kinetic.
	for spot in [Vector3(8, 0, 6), Vector3(-8, 0, 6), Vector3(0, 0, 12)]:
		_boss._raise_pillar(_sand.to_global(spot))
	await _wait(SandPillar.DELAY + 0.3)
	_player.global_position = exposed
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("fiery_sun"))
	var lost := _player.health.max_health - _player.health.current_health
	print("sun hit taken in the open: %.0f" % lost)
	# No Armour or Resistance on the test player: the full 7000 Fire + 5000 Kinetic.
	_check(lost > 11000.0 and lost < 12100.0, "in the open the Sun deals its 7k Fire + 5k Kinetic (%.0f)" % lost)
	await _wait(1.0)

## Four blinks leave four clones, and their stones hit.
func _test_mirage() -> void:
	_place_boss()
	_player.global_position = _sand.to_global(Vector3(0, 0.1, 10))
	_heal()
	var before := get_tree().get_nodes_in_group("ataras_echo").size()
	var cast := func(): await _boss.cast_custom(_boss.boss_brain.find("mirage_barrage"))
	cast.call()
	await _wait(Ataras.MIRAGE_JUMPS * Ataras.MIRAGE_HOP + 0.1)
	_check(get_tree().get_nodes_in_group("ataras_echo").size() - before >= Ataras.MIRAGE_JUMPS, "Mirage Barrage leaves a clone at each blink")
	await _wait(Ataras.MIRAGE_AIM + Ataras.MIRAGE_STAGGER * Ataras.MIRAGE_JUMPS + 1.5)
	var lost := _player.health.max_health - _player.health.current_health
	print("mirage stones taken: %.0f" % lost)
	_check(lost >= Ataras.MIRAGE_DAMAGE.x - 1.0 and lost <= Ataras.MIRAGE_DAMAGE.y * Ataras.MIRAGE_JUMPS + 1.0, "the clones' stones hit for 2.5-4k each (%.0f)" % lost)
