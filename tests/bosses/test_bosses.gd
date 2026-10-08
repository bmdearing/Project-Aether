extends Node
## Bosses: the Figment boss pool, every BossAbility kind against a live
## player, phases, Maw Fragments and the Pinnacle (Reality Engine entries,
## the arena, its bosses' phases and rewards).
## Run: Godot --headless --path . res://tests/bosses/test_bosses.tscn
## Exits 0 when every check passes. Never writes the save file.

const ARENA := "res://levels/pinnacle_boss/PinnacleArena.tscn"
const FIGMENT_BOSS := "res://entities/enemies/figment_boss/FigmentBoss.tscn"
const TEST_COUNT := 6

var _checks := 0
var _failures := 0
var _finished := 0
var _arena: Node3D
var _player: Player

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
	await get_tree().create_timer(s).timeout

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _setup()
	await _test_figment_bosses()
	await _test_ability_kinds()
	await _test_phases()
	await _test_fragments()
	_test_reality_engine()
	await _test_pinnacle_arena()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("boss tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _setup() -> void:
	_arena = Node3D.new()
	add_child(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_arena.add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	_arena.add_child(_player)
	_player.global_position = Vector3(0, 0.1, 0)
	await _frames(3)
	_player.set_physics_process(false)

func _heal_player() -> void:
	_player._impulse = Vector3.ZERO
	_player.health.current_health = _player.health.max_health
	_player.ward.current_ward = 0.0
	_player.status_effects.clear_all_effects()

func _boss(profile: String = "chieftain") -> FigmentBoss:
	var boss: FigmentBoss = load(FIGMENT_BOSS).instantiate()
	boss.profile_id = profile
	_arena.add_child(boss)
	boss.global_position = Vector3(0, 0.1, -6)
	return boss

func _test_figment_bosses() -> void:
	_check(FigmentBoss.PROFILES.size() >= 4, "the Figment boss pool has the Chieftain and the former Vault elites")
	for id in FigmentBoss.PROFILES:
		var boss := _boss(id)
		await _frames(2)
		var profile: Dictionary = FigmentBoss.PROFILES[id]
		_check(boss.display_name == profile["name"], "%s: named %s" % [id, profile["name"]])
		_check(boss.boss_brain != null and boss.boss_brain.abilities.size() == profile["abilities"].size(), "%s: has its abilities" % id)
		_check(boss.boss_brain != null and boss.boss_brain.phase_thresholds.size() == 1, "%s: has a second phase" % id)
		_check(boss.health.max_health >= FigmentBoss.BOSS_HEALTH, "%s: has boss health" % id)
		if profile.get("ranged", false):
			_check(boss.get_node_or_null("RangedAttack") != null, "%s: casts at range" % id)
		boss.free()
	_check(not Constants.get("ENEMY_PACKS_VAULT_ELITE"), "the Vault no longer spawns an elite pack")
	_finished += 1

## A plain boss carrying one ability, for driving BossBrain directly.
func _caster(fields: Dictionary) -> Enemy:
	var boss := _boss("chieftain")
	await _frames(2)
	boss.set_physics_process(false)
	for n in ["MeleeAttack", "RangedAttack"]:
		var attack := boss.get_node_or_null(n)
		if attack:
			attack.set_physics_process(false)
	boss.boss_brain.set_physics_process(false)
	boss.boss_brain.abilities = [BossAbility.make(fields)]
	boss.boss_brain._player = _player
	return boss

func _hurt() -> float:
	return _player.health.max_health - _player.health.current_health

func _test_ability_kinds() -> void:
	_player.parry_handler.set_physics_process(false)
	var Kind := BossAbility.Kind

	# SLAM: around the boss, so it misses at range and hits up close.
	var boss := await _caster({"id": "slam", "kind": Kind.SLAM, "telegraph": 0.3, "radius": 4.0, "damage_mult": 1.0})
	_heal_player()
	_player.global_position = Vector3(0, 0.1, 6)
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	_check(_hurt() == 0.0, "a slam misses a player outside its circle")
	_check(not boss.boss_brain.casting and not boss.boss_brain.is_ready(boss.boss_brain.abilities[0]), "casting ends and starts the cooldown")
	_player.global_position = boss.global_position + Vector3(2, 0, 0)
	boss.boss_brain._cooldowns.clear()
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	_check(_hurt() > 0.0, "a slam hits a player inside its circle")
	boss.free()

	# BLAST: lands where the player stood when it was cast.
	boss = await _caster({"id": "blast", "kind": Kind.BLAST, "telegraph": 0.3, "radius": 2.0, "damage_mult": 1.0})
	_heal_player()
	_player.global_position = Vector3(5, 0.1, 5)
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	_check(_hurt() > 0.0, "a blast hits where the player stands")
	_heal_player()
	var blast := boss.boss_brain.abilities[0]
	boss.boss_brain._cooldowns.clear()
	var dodge := func():
		await _seconds(0.1)
		_player.global_position = Vector3(12, 0.1, 5)
	dodge.call()
	await boss.boss_brain.cast(blast)
	_check(_hurt() == 0.0, "stepping out of a blast avoids it")
	boss.free()

	# HAZARD: stays and ticks.
	boss = await _caster({"id": "pool", "kind": Kind.HAZARD, "telegraph": 0.2, "radius": 3.0, "duration": 1.6, "damage_mult": 1.0})
	boss.boss_brain.set_physics_process(true)
	_heal_player()
	_player.global_position = Vector3(-5, 0.1, 5)
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	await _seconds(1.2)
	var after_ticks := _hurt()
	_check(after_ticks > 0.0, "a hazard pool burns a player standing in it")
	await _seconds(1.0)
	_check(boss.boss_brain._hazards.is_empty(), "the pool goes away after its duration")
	boss.free()

	# CHARGE: rushes at the player and hits once.
	boss = await _caster({"id": "charge", "kind": Kind.CHARGE, "telegraph": 0.2, "damage_mult": 1.0, "max_range": 14.0})
	boss.set_physics_process(true)
	_heal_player()
	_player.global_position = boss.global_position + Vector3(0, 0, 8)
	var start := boss.global_position
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	_check(boss.global_position.distance_to(start) > 5.0, "a charge carries the boss forward (%.1f m)" % boss.global_position.distance_to(start))
	_check(_hurt() > 0.0, "a charge hits the player in its path")
	boss.free()

	# VOLLEY: a fan of projectiles.
	boss = await _caster({"id": "volley", "kind": Kind.VOLLEY, "telegraph": 0.2, "count": 5, "damage_mult": 1.0})
	_player.global_position = boss.global_position + Vector3(0, 0, 10)
	var before := _arena.get_children().filter(func(n): return n is Projectile).size()
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	var fired := _arena.get_children().filter(func(n): return n is Projectile).size() - before
	_check(fired == 5, "a volley fires its count of projectiles (%d)" % fired)
	boss.free()

	# SUMMON: adds, capped.
	boss = await _caster({"id": "adds", "kind": Kind.SUMMON, "telegraph": 0.2, "count": 2, "unit_id": "hollowed_shambler"})
	var enemies_before := get_tree().get_nodes_in_group("enemy").size()
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	await _frames(2)
	_check(get_tree().get_nodes_in_group("enemy").size() - enemies_before == 2, "a summon brings in its adds")
	for n in boss.boss_brain._summoned:
		n.queue_free()
	boss.free()

	# PULL: drags the player in, then slams.
	boss = await _caster({"id": "pull", "kind": Kind.PULL, "telegraph": 0.2, "radius": 4.0, "damage_mult": 1.0, "max_range": 16.0})
	_player.set_physics_process(true)
	_heal_player()
	_player.global_position = boss.global_position + Vector3(0, 0, 11)
	var far := _player.global_position.distance_to(boss.global_position)
	await boss.boss_brain.cast(boss.boss_brain.abilities[0])
	var near := _player.global_position.distance_to(boss.global_position)
	_check(near < far - 5.0, "a pull drags the player toward the boss (%.1f -> %.1f m)" % [far, near])
	_check(_hurt() > 0.0, "and the slam after it lands")
	_player.set_physics_process(false)
	boss.free()
	await _frames(2)
	_finished += 1

func _test_phases() -> void:
	var boss := _boss("threshold_knight")
	await _frames(2)
	var brain := boss.boss_brain
	_player.global_position = boss.global_position + Vector3(0, 0, 40)  # out of range: no casts
	boss.health.current_health = boss.health.max_health * 0.4
	await _frames(2)
	_check(brain.phase == 2, "dropping past half health starts phase 2")
	_check(boss.invulnerable and brain.casting, "the transition makes the boss briefly invulnerable")
	var hp := boss.health.current_health
	boss.take_damage(500.0, Constants.DamageType.KINETIC)
	_check(is_equal_approx(boss.health.current_health, hp), "hits during the transition deal nothing")
	await _seconds(BossBrain.PHASE_TRANSITION_SEC + 0.3)
	_check(not boss.invulnerable, "the boss is hittable again after the roar")
	_check(not brain.is_ready(brain.find("pale_ruin")) or brain.casting, "the phase opens with its signature ability")
	boss.free()
	await _frames(2)
	_finished += 1

func _test_fragments() -> void:
	var boss := _boss("exarch")
	await _frames(2)
	var pickups_before := _arena.get_children().filter(func(n): return n is LootPickup and Pinnacle.is_fragment(n.currency_id)).size()
	boss._on_died()
	await _frames(1)
	var fragments := _arena.get_children().filter(func(n): return n is LootPickup and Pinnacle.is_fragment(n.currency_id))
	_check(fragments.size() - pickups_before == 1, "a Figment boss drops one Maw Fragment")
	for n in _arena.get_children():
		if n is LootPickup:
			n.queue_free()
	var inv := GridInventory.new()
	for id in Pinnacle.FRAGMENT_IDS.slice(0, 3):
		inv.add(id)
	_check(Pinnacle.missing_fragments(inv) == [Pinnacle.FRAGMENT_IDS[3]] and not Pinnacle.consume_set(inv), "three pieces aren't a set")
	inv.add(Pinnacle.FRAGMENT_IDS[3])
	inv.add(Pinnacle.FRAGMENT_IDS[0])
	_check(Pinnacle.has_full_set(inv) and Pinnacle.consume_set(inv), "four different pieces are a set")
	_check(inv.count_of(Pinnacle.FRAGMENT_IDS[0]) == 1 and inv.count_of(Pinnacle.FRAGMENT_IDS[3]) == 0, "opening spends one of each")
	_check(Pinnacle.FRAGMENT_IDS.all(func(id): return CurrencyText.name_of(id).begins_with("Maw Fragment")), "fragments have names")
	_finished += 1

func _test_reality_engine() -> void:
	var engine := RealityEngine.new()
	var saved := GameState.inventory
	GameState.inventory = GridInventory.new()
	var entries := engine._pinnacle_entries()
	_check(entries.size() == Pinnacle.BOSSES.size(), "the Reality Engine lists every Pinnacle boss")
	_check(entries.all(func(e): return e["cost_text"] == "0/4 Fragments"), "and how many fragments you hold")
	_check(not entries[0]["on_buy"].call(), "it won't open without a full set")
	GameState.inventory = saved
	engine.free()
	_finished += 1

func _test_pinnacle_arena() -> void:
	_arena.queue_free()
	_player = null
	await _frames(2)
	for boss_id in Pinnacle.BOSSES:
		GameState.pending_pinnacle = boss_id
		var arena: PinnacleArena = load(ARENA).instantiate()
		add_child(arena)
		await _frames(3)
		var boss := arena.boss
		var expected: String = Pinnacle.BOSSES[boss_id]["name"]
		_check(boss is PinnacleBoss and boss.get_display_name().contains(expected), "%s: the arena spawns the chosen boss (%s)" % [boss_id, boss.get_display_name()])
		_check(GameState.pending_pinnacle == "", "%s: the choice is used up" % boss_id)
		_check(boss.boss_brain.phase_thresholds.size() == 2 and boss.boss_brain.phase_openers.size() == 2, "%s: three phases, each opening with an ability" % boss_id)
		_check(boss.boss_brain.abilities.any(func(a): return a.min_phase == 3), "%s: phase 3 unlocks new abilities" % boss_id)
		boss.health.apply_damage(boss.health.max_health * 2.0)
		await _frames(3)
		var portal := arena.get_children().filter(func(n): return n is Portal)
		_check(portal.size() == 1, "%s: killing it opens a portal home" % boss_id)
		var reward := arena.get_children().filter(func(n): return n is LootPickup and n.item and n.item.rarity >= Constants.ItemRarity.UNIQUE)
		_check(reward.size() >= 1, "%s: it drops a Unique or Mythic" % boss_id)
		arena.queue_free()
		await _frames(3)
	_check(Pinnacle.BOSSES["herald_of_the_maw"]["name"] == "Herald of the Maw", "Xalatath goes by a placeholder name")
	_finished += 1
