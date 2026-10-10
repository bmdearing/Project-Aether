extends Node
## Skill webs (SkillWeb): every spell has a web, points come from levels,
## the allocation rules hold, building blocks change the spell's numbers,
## twists change what it does, every twist casts cleanly, and webs survive a
## save. Run: Godot --headless --path . res://tests/skill_web/test_skill_web.tscn --quit-after 20000

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

func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()

func _count(script_class: String) -> int:
	return get_tree().current_scene.find_children("*", script_class, true, false).size()

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_arena = Node3D.new()
	add_child(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_arena.add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	_arena.add_child(_player)
	_player.global_position = Vector3(0, 0, 30)
	await _frames(3)
	_player.set_physics_process(false)
	_cast = _player.ability_cast
	_test_every_spell_has_a_web()
	_test_rules()
	_test_blocks()
	await _test_spark_and_volley()
	await _test_comet_molten()
	await _test_every_twist_casts()
	_test_save_and_migration()
	print("skill web tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_every_spell_has_a_web() -> void:
	_check(not FileAccess.file_exists(ABILITY_DIR + "meteor.tres"), "Meteor is gone (Comet's Molten Core replaces it)")
	for f in DirAccess.get_files_at(ABILITY_DIR):
		if not f.ends_with(".tres"):
			continue
		var a := _ability(f.get_basename())
		var nodes := SkillWeb.nodes_for(a)
		var ids := nodes.map(func(n): return n.id)
		_check(nodes.size() >= 4, "%s has a web (%d nodes)" % [a.ability_id, nodes.size()])
		_check(nodes.any(func(n): return n.is_twist()), "%s has at least one twist" % a.ability_id)
		for n: SkillWeb.WebNode in nodes:
			_check(n.ring == 1 or (not n.requires.is_empty() and n.requires.all(func(r): return ids.has(r))), "%s/%s links to nodes that exist" % [a.ability_id, n.id])

func _test_rules() -> void:
	var a := _ability("spark")
	_check(SkillWeb.points_available(a) == 0 and not SkillWeb.allocate(a, "potency"), "a level 1 spell has no points")
	a.level = 6
	_check(SkillWeb.points_available(a) == 5, "one point per level above 1")
	_check(not SkillWeb.allocate(a, "static_swarm"), "an outer node needs a connected point first")
	_check(SkillWeb.allocate(a, "velocity"), "ring 1 is open")
	_check(SkillWeb.allocate(a, "static_swarm"), "and then its neighbour opens")
	_check(SkillWeb.allocate(a, "overcharge") and not SkillWeb.allocate(a, "stalking_spark"), "exclusive twists lock each other")
	_check(not SkillWeb.refund(a, "static_swarm"), "can't take back a point something else depends on")
	_check(SkillWeb.refund(a, "overcharge") and SkillWeb.refund(a, "static_swarm"), "outer points come back first")
	SkillWeb.allocate(a, "velocity")
	SkillWeb.allocate(a, "velocity")
	_check(not SkillWeb.allocate(a, "velocity"), "a node stops at its maximum")
	a.level = 2
	SkillWeb.trim_to_available(a)
	_check(SkillWeb.points_spent(a) == 1, "a lower level trims the web back to its points")
	SkillWeb.refund_all(a)
	_check(SkillWeb.points_spent(a) == 0, "refund all clears it")

func _test_blocks() -> void:
	var a := _ability("comet")
	a.level = 10
	var damage := a.predict_damage(_player.stat_sheet)
	var cost := a.get_mana_cost(_player.stat_sheet)
	var radius := a.get_radius(_player.stat_sheet)
	for i in 3:
		SkillWeb.allocate(a, "potency")
		SkillWeb.allocate(a, "efficiency")
		SkillWeb.allocate(a, "reach")
	_check(a.predict_damage(_player.stat_sheet) > damage * 1.15, "Potency raises damage")
	_check(a.get_mana_cost(_player.stat_sheet) < cost * 0.85, "Efficiency lowers the Mana cost")
	_check(a.get_radius(_player.stat_sheet) > radius * 1.2, "Reach widens the area")
	a.level = 1
	a.web_points = {}

func _test_spark_and_volley() -> void:
	var spark := _ability("spark")
	spark.web_points = {"velocity": 1, "static_swarm": 3}
	var before := _count("SparkCrawler")
	_cast._cast(spark, Vector3.ZERO)
	await _frames(1)
	_check(_count("SparkCrawler") - before == 6, "Static Swarm adds a spark per point (%d)" % (_count("SparkCrawler") - before))
	var pulse := _ability("ice_pulse")
	pulse.web_points = {"efficiency": 1, "shard_volley": 1, "splinters": 2}
	var bolts := _count("PiercingBolt")
	_cast._cast(pulse, _player.global_position)
	await _frames(1)
	_check(_count("PiercingBolt") - bolts == 7, "Shard Volley fires icicles, Splinters adds more (%d)" % (_count("PiercingBolt") - bolts))
	spark.web_points = {}
	pulse.web_points = {}

func _test_comet_molten() -> void:
	_clear()
	var comet := _ability("comet")
	comet.web_points = {"efficiency": 1, "molten_core": 1}
	var e := _dummy(Vector3.ZERO)
	await _frames(2)
	var types: Array = []
	var record := func(_s, target, _amount, damage_type, _more, _crit): if target == e: types.append(damage_type)
	EventBus.damage_dealt.connect(record)
	_cast._cast(comet, Vector3.ZERO)
	await _wait(0.6)
	EventBus.damage_dealt.disconnect(record)
	_check(types.has(Constants.DamageType.FIRE), "Molten Core makes Comet Fire")
	comet.web_points = {"efficiency": 1, "molten_core": 1, "reach": 1, "reach_2": 1, "meteor_shower": 1}
	var impacts := _count("CometImpact")
	_cast._cast(comet, Vector3.ZERO)
	await _frames(1)
	_check(_count("CometImpact") - impacts == 3, "Meteor Shower drops three comets")
	comet.web_points = {}
	_clear()

## Every twist, taken alone, casts without errors (the runner fails on any
## SCRIPT ERROR) - exclusive pairs are tried one at a time.
func _test_every_twist_casts() -> void:
	_dummy(Vector3(0, 0, 26))
	await _frames(2)
	for ability_id in SkillWeb.TWISTS:
		var a := _ability(ability_id)
		for t in SkillWeb.TWISTS[ability_id]:
			a.web_points = {t["id"]: 1}
			for r in t.get("requires", []):
				if not (SkillWeb.find(a, r) and SkillWeb.find(a, r).exclusive_with == t["id"]):
					a.web_points[r] = 1
			_player.global_position = Vector3(0, 0, 30)
			_cast._cast(a, Vector3(0, 0, 24))
			await _frames(2)
		a.web_points = {}
	await _wait(2.5)
	_check(true, "every twist casts")
	_clear()

func _test_save_and_migration() -> void:
	var a := _ability("spark")
	a.level = 4
	a.web_points = {"velocity": 2, "static_swarm": 1}
	GameState.ability_levels["spark"] = 4
	GameState.store_skill_web(a)
	_check(GameState.skill_webs.get("spark", {}) == {"velocity": 2, "static_swarm": 1}, "the web is stored for saving")
	a.web_points = {}
	_player._apply_saved_ability_levels()
	_check(a.web_points.get("static_swarm", 0) == 1 and a.web_points.get("velocity", 0) == 2, "and restored onto the spell")
	GameState.ability_loadout_paths = ["res://data/abilities/instances/meteor.tres", "", "", ""]
	GameState.owned_ability_ids = ["meteor"]
	GameState.ability_levels["meteor"] = 7
	SaveManager._migrate_meteor()
	_check(GameState.ability_loadout_paths[0] == "res://data/abilities/instances/comet.tres" and GameState.owned_ability_ids == ["comet"] and int(GameState.ability_levels["comet"]) == 7, "a save with Meteor gets Comet at its level")
	a.web_points = {}
	a.level = 1
