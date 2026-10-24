extends Node
## The Sealed King / The Almighty: the arena builds, he can't be pushed below
## 50% before his transformation, the transformation swaps in the Almighty
## model, heals him to full and darkens the arena, Star Seal and Foreseen
## hit, and he dies normally afterwards.
## Run: Godot --headless --path . res://tests/almighty/test_almighty.tscn --quit-after 6000

const TEST_LIFE := 1_000_000.0

var _checks := 0
var _failures := 0
var _arena: PinnacleArena
var _boss: Almighty
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

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.pending_pinnacle = "almighty"
	_arena = (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	await _wait(0.5)
	_boss = _arena.boss as Almighty
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_boss != null and _arena.almighty != null, "the pinnacle builds the Almighty arena with him in it")
	if _boss == null:
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
	_check(_boss.get_display_name() == Almighty.SEALED_NAME, "he starts as the Sealed King")
	_check(_boss._model_root.name == "AlmightyYhwachModel", "in his first model")
	await _test_abilities()
	await _test_awakening()
	_boss.health.apply_damage(_boss.health.max_health * 2.0)
	await _wait(0.3)
	_check(_arena.get_children().any(func(n): return n is Portal), "killing him opens the portal home")
	_finish()

func _finish() -> void:
	print("almighty tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_abilities() -> void:
	# Standing still in front of him: Foreseen lands on you.
	_player.global_position = _boss.global_position + Vector3(0, 0.1, 6.0)
	_player.velocity = Vector3.ZERO
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("foreseen"))
	await _wait(0.2)
	_check(_player.health.current_health < TEST_LIFE, "Foreseen hits a player who doesn't move")
	# Star Seal: a vertex of the star is on a line, the centre is not.
	_heal()
	var cast := func(): await _boss.cast_custom(_boss.boss_brain.find("star_seal"))
	cast.call()
	await _wait(_boss.boss_brain.find("star_seal").telegraph + 0.25)
	_check(is_equal_approx(_player.health.current_health, TEST_LIFE), "the middle of the Star Seal is safe")

func _test_awakening() -> void:
	var max_life := _boss.health.max_health
	_boss.take_damage(max_life * 10.0, Constants.DamageType.AETHERIC)
	_check(_boss.health.is_alive() and is_equal_approx(_boss.health.current_health, max_life * Almighty.AWAKEN_AT), "a huge hit stops at 50%% (%.0f / %.0f)" % [_boss.health.current_health, max_life])
	_check(not _boss.take_damage(1000.0, Constants.DamageType.AETHERIC), "and nothing lands below it before he transforms")
	_boss.boss_brain._check_phase()
	await _wait(0.5)
	_check(_boss.invulnerable, "he can't be hurt while transforming")
	await _wait(Almighty.AWAKEN_GATHER + Almighty.AWAKEN_HOLD + 0.6)
	_check(_boss.awakened and _boss.get_display_name() == Almighty.AWAKENED_NAME, "he wakes as the Almighty")
	_check(_boss._model_root != null and _boss._model_root.name == "AlmightyAwakenedModel", "in the Almighty model")
	_check(_boss._anim_controller != null, "and the new model animates")
	_check(is_equal_approx(_boss.health.current_health, max_life), "back at full Life")
	_check(_boss.boss_brain.phase == 2 and _boss.boss_brain.phase_thresholds.is_empty(), "phase 2, no more phase marks")
	_check(_arena.almighty.awakened, "the arena goes dark")
	_boss.take_damage(max_life * 1.5, Constants.DamageType.PALE)
	_check(_boss.health.current_health < max_life * 0.5, "after awakening, damage goes below 50%% (%.0f)" % _boss.health.current_health)
