extends Node
## The Sealed King / The Almighty: the arena builds, his phases run 60% and
## 25%, he can't be pushed below 25% before his transformation, which swaps in
## the Almighty model, heals him to full, gives his bar new marks and darkens
## the arena; Foreseen, Star Seal and the Eyes hit; the Verdict kills unless
## broken; he dies normally afterwards.
## Run: Godot --headless --path . res://tests/almighty/test_almighty.tscn --quit-after 12000

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
	_check(is_equal_approx(_boss.health.max_health, Almighty.LIFE), "145m Life (%.0f)" % _boss.health.max_health)
	_check(_boss.get_display_name() == Almighty.SEALED_NAME, "he starts as the Sealed King")
	_check(_boss._model_root.name == "AlmightyYhwachModel", "in his first model")
	_check(_boss.boss_bar_marks() == Almighty.SEALED_MARKS, "his bar marks 60% and 25%")
	_check(_boss.boss_brain.find("sealed_blade") == null, "no charge")
	await _test_abilities()
	await _test_awakening()
	await _test_eyes()
	await _test_verdict()
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
	# Star Seal: the centre of the star is off its lines.
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("star_seal"))
	await _wait(0.2)
	_check(is_equal_approx(_player.health.current_health, TEST_LIFE), "the middle of the Star Seal is safe")
	_heal()
	await _boss.cast_custom(_boss.boss_brain.find("spirit_lances"))
	await _wait(0.2)
	_check(_player.health.current_health < TEST_LIFE, "Spirit Lances run through where you stand")

func _test_awakening() -> void:
	var max_life := _boss.health.max_health
	_boss.take_damage(max_life * 0.9, Constants.DamageType.PALE)
	_boss.boss_brain._check_phase()
	_check(_boss.boss_brain.phase == 2, "phase 2 at 60%")
	await _wait(BossBrain.PHASE_TRANSITION_SEC + 2.0)
	_boss.take_damage(max_life * 10.0, Constants.DamageType.AETHERIC)
	_check(_boss.health.is_alive() and is_equal_approx(_boss.health.current_health, max_life * Almighty.AWAKEN_AT), "a huge hit stops at 25%% (%.0f / %.0f)" % [_boss.health.current_health, max_life])
	_check(not _boss.take_damage(1000.0, Constants.DamageType.AETHERIC), "and nothing lands below it before he transforms")
	_boss.boss_brain._check_phase()
	await _wait(0.5)
	_check(_boss.invulnerable, "he can't be hurt while transforming")
	await _wait(Almighty.AWAKEN_GATHER + Almighty.AWAKEN_HOLD + 0.6)
	_check(_boss.awakened and _boss.get_display_name() == Almighty.AWAKENED_NAME, "he wakes as the Almighty")
	_check(_boss._model_root != null and _boss._model_root.name == "AlmightyAwakenedModel", "in the Almighty model")
	_check(_boss._anim_controller != null, "and the new model animates")
	_check(_boss.health.current_health >= max_life * 0.99, "back at full Life")
	_check(_boss.boss_brain.phase == 3 and _boss.boss_bar_marks() == Almighty.AWAKENED_MARKS, "phase 3, his bar shows the new marks")
	_check(_arena.almighty.awakened, "the arena goes dark")
	# The Selection opener may still be landing.
	await _wait(2.0)
	_boss.take_damage(max_life * 1.5, Constants.DamageType.PALE)
	_check(_boss.health.current_health < max_life * 0.5, "after awakening, damage goes below 25%% (%.0f)" % _boss.health.current_health)
	_boss._set_life(max_life)

## Standing still on the open floor through the channel gets hit.
func _test_eyes() -> void:
	await _wait(1.0)
	_heal()
	_player.global_position = _arena.almighty.global_position + Vector3(0, 0.1, 8.0)
	await _boss.cast_custom(_boss.boss_brain.find("eyes_of_the_almighty"))
	_check(_player.health.current_health < TEST_LIFE, "the Eyes and sweeping beams hit a player who stands still")
	await _wait(1.0)
	_check(get_tree().get_nodes_in_group("almighty_arena").size() == 1 and _arena.almighty.get_parent().get_children().filter(func(n): return n is AlmightyBeam).is_empty(), "the beams are gone when the channel ends")

func _test_verdict() -> void:
	await _wait(1.0)
	_heal()
	var cast := func(): await _boss.cast_custom(_boss.boss_brain.find("verdict"))
	cast.call()
	await _wait(1.0)
	_boss.take_damage(_boss.health.max_health * Almighty.VERDICT_BREAK_SHARE * 3.0, Constants.DamageType.PALE)
	await _wait(0.3)
	_check(_player.health.is_alive() and _boss.status_effects.is_stunned(), "enough damage breaks the Verdict and stuns him")
	await _wait(Almighty.VERDICT_STUN + 0.5)
	_heal()
	# His death pauses the tree (and the boss's own timers), so this cast never returns.
	var sentence := func(): await _boss.cast_custom(_boss.boss_brain.find("verdict"))
	sentence.call()
	await _wait(Almighty.VERDICT_SEC + 0.5)
	_check(not _player.health.is_alive(), "an unbroken Verdict kills, whatever your Life (%.0f left)" % _player.health.current_health)
