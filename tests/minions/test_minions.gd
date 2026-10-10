extends Node
## Reap and Wraith, and the Minion modifiers: Reap hits what's in its arc
## and not behind you; Wraith drinks all your Ward, locks Ward recovery while
## it lives, strikes enemies, hits harder for more Ward, and scales with
## increased Minion damage; the Minion modifiers and Brand exist.
## Run: Godot --headless --path . res://tests/minions/test_minions.tscn --quit-after 12000

const ABILITY_DIR := "res://data/abilities/instances/"

var _checks := 0
var _failures := 0
var _arena: Node3D
var _player: Player
var _cast: PlayerAbilityCast

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

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ability(id: String) -> Ability:
	var a := load(ABILITY_DIR + id + ".tres") as Ability
	a.level = 1
	a.web_points = {}
	a.base_crit_chance = 0.0
	return a

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	_arena.add_child(e)
	e.global_position = pos
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
	return 1.0e6 - e.health.current_health if is_instance_valid(e) else 0.0

func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()
	for m in get_tree().get_nodes_in_group("minion"):
		m.queue_free()

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
	_player.global_position = Vector3.ZERO
	await _frames(3)
	_player.set_physics_process(false)
	_cast = _player.ability_cast
	await _test_reap()
	await _test_wraith()
	_test_modifiers()
	print("minion tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_reap() -> void:
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var ahead := _dummy(forward * 3.0)
	var behind := _dummy(-forward * 3.0)
	await _frames(2)
	_cast._cast(_ability("reap"), Vector3.ZERO)
	await _frames(2)
	_check(_lost(ahead) > 0.0, "Reap hits what's in front")
	_check(_lost(behind) == 0.0, "but not what's behind")
	_clear()
	await _frames(2)

func _test_wraith() -> void:
	var e := _dummy(Vector3(4, 0, 0))
	await _frames(2)
	_player.ward.max_ward = 140.0
	_player.ward.current_ward = 140.0
	var wraith := _ability("wraith")
	_cast._cast(wraith, Vector3.ZERO)
	await _frames(2)
	var minions := get_tree().get_nodes_in_group("minion")
	_check(minions.size() == 1, "Wraith summons a wraith")
	_check(_player.ward.current_ward == 0.0, "it drinks all your Ward")
	_player.ward.restore(50.0)
	_check(_player.ward.current_ward == 0.0, "no Ward recovery while it lives")
	var w := minions[0] as WraithMinion if not minions.is_empty() else null
	_check(w != null and w.stacks == 20, "one stack per 7 Ward (%d)" % (w.stacks if w else -1))
	await _wait(2.5)
	_check(_lost(e) > 0.0, "the wraith strikes enemies")
	if w:
		var plain := _average(w)
		_player.stat_sheet.misc_bonus["minion_damage"] = 100.0
		var boosted := _average(w)
		_player.stat_sheet.misc_bonus.erase("minion_damage")
		_check(boosted > plain * 1.5, "increased Minion damage makes it hit harder (%.0f vs %.0f)" % [boosted, plain])
		var none := WraithMinion.new()
		none.ability = wraith
		none.player = _player
		none.stacks = 0
		var unfed := _average(none)
		none.free()
		_check(plain > unfed * 1.8, "more Ward drunk, harder strikes (%.0f vs %.0f)" % [plain, unfed])
		w.queue_free()
	await _frames(2)
	_player.ward.restore(30.0)
	_check(_player.ward.current_ward > 0.0, "Ward recovers once it's gone")
	wraith.web_points = {"spectral_host": 1}
	_player.ward.current_ward = 70.0
	_cast._cast(wraith, Vector3.ZERO)
	await _frames(2)
	_check(get_tree().get_nodes_in_group("minion").size() == 2, "Spectral Host summons two")
	wraith.web_points = {}
	_clear()
	await _frames(2)

## Average strike over many rolls (hits roll a range).
func _average(w: WraithMinion) -> float:
	var total := 0.0
	for i in 200:
		total += w.strike_damage()["final_damage"] as float
	return total / 200.0

func _test_modifiers() -> void:
	var keys := ItemRoller.AFFIX_POOL.map(func(e): return e["stat_key"])
	_check(keys.has("minion_damage") and keys.has("minion_attack_speed") and keys.has("minion_duration"), "gear can roll Minion modifiers")
	_check(JewelModifierPool.STAT_KEYS.has("minion_damage"), "Jewels can roll Minion damage")
	_check(ResourceLoader.exists("res://data/crafting/brands/brand_minion.tres"), "there's a Minion Brand")
	_check(SlateAffixPool.get_pool_for_tag("spell").any(func(a): return a.stat_key == "minion_damage"), "Spell Slates can roll Minion damage")
	_check(_ability("wraith").has_tag(Ability.TAG_MINION) and "Minion" in _ability("wraith").get_tag_names(), "Wraith is a Minion spell")
