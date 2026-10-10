extends Node
## Bosses: the Figment boss pool, every BossAbility kind against a live
## player, phases, Maw Fragments and the Pinnacle (Reality Engine entries,
## the arena, its bosses' phases and rewards).
## Run: Godot --headless --path . res://tests/bosses/test_bosses.tscn
## Exits 0 when every check passes. Never writes the save file.

const ARENA := "res://levels/pinnacle_boss/PinnacleArena.tscn"
const FIGMENT_BOSS := "res://entities/enemies/figment_boss/FigmentBoss.tscn"
const TEST_COUNT := 8

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
	await _test_lord_sigils()
	await _test_maw_arena()
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
	var free := Pinnacle.free_entry
	Pinnacle.free_entry = true
	_check(engine._pinnacle_entries().all(func(e): return e["cost_text"] == "Free (testing)"), "free entry shows on the Reality Engine")
	Pinnacle.free_entry = false
	var entries := engine._pinnacle_entries()
	_check(entries.size() == Pinnacle.BOSSES.size(), "the Reality Engine lists every Pinnacle boss")
	_check(entries.all(func(e): return e["cost_text"] == "0/4 Fragments"), "and how many fragments you hold")
	_check(not entries[0]["on_buy"].call(), "it won't open without a full set")
	Pinnacle.free_entry = free
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
		# Each later phase opens with an ability and unlocks new ones (Ataras
		# has two phases; the others three).
		var phases: int = boss.boss_brain.phase_thresholds.size() + 1
		_check(phases >= 2 and boss.boss_brain.phase_openers.size() == phases - 1, "%s: %d phases, each later one opening with an ability" % [boss_id, phases])
		_check(boss.boss_brain.abilities.any(func(a): return a.min_phase == phases), "%s: the last phase unlocks new abilities" % boss_id)
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

## Lord of the Elements: hovers in the bay, wide body, orbs become sigils
## that cut the damage of other elements and raise his current one.
## A boss landing a lucky hit on the test's player used to kill it, and the
## death screen paused the tree, stalling every timed check after it.
func _sturdy_player() -> void:
	get_tree().paused = false
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.health.max_health = 1.0e7
		player.health.current_health = 1.0e7

func _test_lord_sigils() -> void:
	GameState.pending_pinnacle = "lord_of_the_elements"
	var arena: PinnacleArena = load(ARENA).instantiate()
	add_child(arena)
	await _frames(3)
	_sturdy_player()
	var lord := arena.boss as LordOfTheElements
	_check(lord != null and lord.immovable, "the Lord hovers in place")
	var bay := arena.to_global(PinnacleArena.BAY_SPAWN_LOCAL)
	_check(lord.global_position.distance_to(bay) < 0.5, "he floats in the crescent's empty bay")
	_check(lord.body_radius >= LordOfTheElements.BODY_RADIUS, "his body is wide enough to reach from the edge")
	var edge := arena.to_global(Vector3(0, 0, PinnacleArena.CUT_OFFSET - PinnacleArena.CUT_RADIUS - 0.5))
	_check(lord.distance_to_body(edge) < 2.0, "melee standing on the edge is within reach (%.2f m)" % lord.distance_to_body(edge))
	var start := lord.global_position
	lord.apply_knockback(Vector3(30, 0, 0))
	await _frames(10)
	_check(lord.global_position.distance_to(start) < 0.05, "he can't be knocked around")
	_check(lord._orbs.size() == 3, "his three planets are the elements")
	await _seconds(LordOfTheElements.ORB_FLIGHT + 0.6)
	var sigils := get_tree().get_nodes_in_group("element_sigil")
	_check(sigils.size() == 3, "the orbs land as three sigils (%d)" % sigils.size())
	var elements := sigils.map(func(s): return s.element)
	_check(elements.has(Constants.DamageType.FIRE) and elements.has(Constants.DamageType.COLD) and elements.has(Constants.DamageType.LIGHTNING), "one sigil per element")
	var floor_ok := true
	for s in sigils:
		var local := arena.to_local(s.global_position)
		var outer := Vector2(local.x, local.z).length()
		var from_cut := Vector2(local.x, local.z - PinnacleArena.CUT_OFFSET).length()
		floor_ok = floor_ok and outer + ElementSigil.RADIUS <= PinnacleArena.OUTER_RADIUS + 0.5 and from_cut - ElementSigil.RADIUS >= PinnacleArena.CUT_RADIUS - 0.5
	_check(floor_ok, "every sigil sits on the crescent")
	_check(lord.get_cast_origin().distance_to(lord.global_position) > 1.0, "spells leave from the active orb")
	var player := get_tree().get_first_node_in_group("player") as Player
	var sigil: ElementSigil = sigils.filter(func(s): return s.element == Constants.DamageType.FIRE)[0]
	player.set_physics_process(false)
	player.global_position = sigil.global_position + Vector3(0, 0.1, 0)
	lord.current_element = Constants.DamageType.COLD
	_check(is_equal_approx(sigil.damage_multiplier_for(player, Constants.DamageType.COLD), ElementSigil.PROTECTED_MULTIPLIER), "a sigil of another element protects you")
	_check(is_equal_approx(sigil.damage_multiplier_for(player, Constants.DamageType.FIRE), ElementSigil.MATCHED_MULTIPLIER), "its own element hurts more")
	lord.current_element = Constants.DamageType.FIRE
	_check(sigil.is_dangerous(), "a sigil warns while he uses its element")
	player.health.current_health = player.health.max_health
	player.ward.current_ward = 0.0
	var outside := player.global_position + Vector3(0, 0, 30)
	var hit := func(pos: Vector3) -> float:
		player.global_position = pos
		player.health.current_health = player.health.max_health
		player._take_damage_single(0.0, Constants.DamageType.COLD)
		var before := player.health.current_health
		player.take_damage(50.0, Constants.DamageType.COLD, null, Player.HitKind.DOT)
		return before - player.health.current_health
	var unprotected: float = hit.call(outside)
	var protected: float = hit.call(sigil.global_position + Vector3(0, 0.1, 0))
	_check(protected < unprotected * 0.8, "standing in the sigil really takes less (%.1f vs %.1f)" % [protected, unprotected])
	var old := sigils.duplicate()
	lord.boss_brain.phase_changed.emit(2)
	await _seconds(LordOfTheElements.ORB_FLIGHT + 1.0)
	var moved := get_tree().get_nodes_in_group("element_sigil")
	_check(moved.size() == 3 and not moved.any(func(s): return old.has(s)), "a new phase moves the sigils")
	lord.health.apply_damage(lord.health.max_health * 2.0)
	await _seconds(0.8)
	_check(get_tree().get_nodes_in_group("element_sigil").is_empty(), "the sigils fade when he dies")
	arena.queue_free()
	await _frames(2)
	_finished += 1

## Herald of the Maw: her round arena over the void, its plates, the Anchor
## pylons, the Maw opening in phase 3, and death off the edge.
func _test_maw_arena() -> void:
	GameState.pending_pinnacle = "herald_of_the_maw"
	var arena: PinnacleArena = load(ARENA).instantiate()
	add_child(arena)
	await _frames(3)
	_sturdy_player()
	var maw := arena.maw
	var herald := arena.boss as Xalatath
	_check(maw != null and herald != null, "the Herald gets the Maw arena")
	if maw == null or herald == null:
		arena.queue_free()
		return
	_check(arena.get_node_or_null("Boundary") == null, "there's no wall at the edge")
	_check(maw.dais_plates.size() == 4 and maw.inner_plates.size() == 8 and maw.outer_plates.size() == 8, "dais, inner and outer rings of plates")
	_check(maw.pylons.size() == 4 and maw.pylons_standing() == 4, "four Anchor pylons")
	_check(is_equal_approx(herald._model_root.scale.x, 1.4), "she's sized up")
	var player := get_tree().get_first_node_in_group("player") as Player
	_player = player
	_check(maw.plate_at(player.global_position) != null and maw.plate_at(herald.global_position) != null, "both start on the floor")
	_check(herald.arena() == maw, "she finds her arena")
	player.set_physics_process(false)
	herald.set_physics_process(false)
	herald.boss_brain.set_physics_process(false)
	for n in ["MeleeAttack", "RangedAttack"]:
		herald.get_node(n).set_physics_process(false)
	herald.boss_brain._player = player

	# Void Rift running out cracks the floor; a hit drops cracked outer plates only.
	var rift := herald.boss_brain.find("void_rift")
	var outer: MawPlate = maw.outer_plates[2]
	var inner: MawPlate = maw.inner_plates[2]
	for plate in [outer, inner]:
		herald.boss_brain.hazard_ended.emit(rift, maw.to_global(plate.center_local()), rift.radius)
	_check(outer.state == MawPlate.State.CRACKED and inner.state == MawPlate.State.CRACKED, "an expired Void Rift cracks the plates under it")
	_check(maw.dais_plates.all(func(p): return p.state == MawPlate.State.INTACT), "the dais doesn't crack")
	for plate in [outer, inner]:
		herald.boss_brain.ground_struck.emit(rift, maw.to_global(plate.center_local()), 2.0)
	_check(outer.state == MawPlate.State.FALLING, "a hit on a cracked outer plate drops it")
	_check(inner.state == MawPlate.State.CRACKED, "inner plates never fall")
	await _seconds(MawArena.STRIKE_FALL_WARNING + 0.2)
	var shapes_off := outer.get_children().filter(func(c): return c is CollisionShape3D).all(func(c): return c.disabled)
	_check(outer.state == MawPlate.State.GONE and shapes_off, "the fallen plate is gone, collision and all")

	# Standing on a cracked plate builds Entropic stacks; stepping off clears them.
	player.global_position = maw.to_global(inner.center_local()) + Vector3(0, 0.1, 0)
	_heal_player()
	await _seconds(2.1)
	_check(maw.entropy_stacks >= 1.5, "stacks build on a cracked plate (%.1f)" % maw.entropy_stacks)
	_check(_hurt() > 0.0, "and they hurt")
	player.global_position = maw.to_global(maw.inner_plates[5].center_local()) + Vector3(0, 0.1, 0)
	await _frames(2)
	_check(maw.entropy_stacks == 0.0, "stepping off an intact plate clears them")

	# Pylons: shelter against the pull, stun a Lunge, raise the Lens odds.
	var storm: MawPylon = maw.pylons[1]
	player.global_position = storm.global_position + Vector3(-2.0, 0.1, 0)
	_check(herald.is_player_anchored(player), "a pylon anchors a player beside it")
	player.global_position = storm.global_position + Vector3(-6.0, 0.1, 0)
	_check(not herald.is_player_anchored(player), "but not one out of its reach")
	var reach := herald.body_radius + MawPylon.RADIUS + 0.2
	herald.global_position = storm.global_position + Vector3(0, 0.05, reach)
	_check(not herald.blocks_charge(Vector3(0, 0, 1)), "lunging away from a pylon goes on")
	_check(herald.blocks_charge(Vector3(0, 0, -1)) and herald.status_effects.is_stunned(), "lunging into a pylon stuns her")
	herald.status_effects.clear_all_effects()
	_check(Pinnacle.maw_lens_chance(4) > Pinnacle.maw_lens_chance(3) and Pinnacle.maw_lens_chance(0) > 0.0, "each standing pylon raises the Lens chance")

	# A summoned Mindbender walks to a pylon and shatters it with a channel.
	var unit := EnemyRoster.create_unit("veilborne_mindbender")
	arena.add_child(unit)
	unit.global_position = maw.to_global(Vector3(0, 0.1, -15.0))
	await _frames(2)
	unit.set_physics_process(false)
	herald.on_unit_summoned(unit)
	var channels := unit.get_children().filter(func(c): return c is MawChannel)
	var ash: MawPylon = maw.pylons[0]
	_check(channels.size() == 1 and channels[0].pylon == ash and unit.move_target == ash, "a Mindbender heads for the nearest pylon")
	_check(not unit.get_node("RangedAttack").is_physics_processing(), "and doesn't fight on the way")
	if channels.size() == 1:
		channels[0].progress = 0.95
		await _seconds(0.6)
	_check(not ash.alive and maw.pylons_standing() == 3, "a finished channel shatters the pylon")
	_check(maw.outer_plates[0].state == MawPlate.State.FALLING and maw.outer_plates[7].state == MawPlate.State.FALLING, "the plates beside it give way")
	await _frames(2)
	_check(unit.move_target == maw.pylons[3] or unit.move_target == maw.pylons[1], "the Mindbender moves on to another pylon")
	unit.health.apply_damage(unit.health.max_health * 10.0)
	await _frames(2)

	# Phase 3: the dais falls into the Maw, and Unmaking pulls toward it.
	herald.global_position = maw.to_global(Vector3(-9.5, 0.05, 0))
	herald.boss_brain.phase_changed.emit(3)
	_check(maw.maw_open and maw.dais_plates.all(func(p): return p.state == MawPlate.State.FALLING), "phase 3 opens the Maw")
	_check(herald.get_pull_center().distance_to(maw.maw_center()) < 0.01, "Unmaking pulls to the Maw")
	await _seconds(MawArena.MAW_OPEN_WARNING + 0.2)
	_check(maw.dais_plates.all(func(p): return p.state == MawPlate.State.GONE), "the dais is gone")
	var unmaking := herald.boss_brain.find("unmaking")
	_heal_player()
	player.global_position = maw.to_global(Vector3(11.5, 0.1, 0))
	herald.boss_brain.cast(unmaking)
	await _seconds(unmaking.telegraph + 0.1)
	_check(player._impulse.x < -1.0, "an unanchored player is dragged toward the Maw")
	await _seconds(1.0)
	_heal_player()
	player.global_position = storm.global_position + Vector3(-2.0, 0.1, 0)
	herald.boss_brain.cast(unmaking)
	await _seconds(unmaking.telegraph + 0.1)
	_check(player._impulse.length() < 0.01, "an anchored player holds")
	await _seconds(1.0)
	var bitten := maw.bite()
	_check(bitten != null and bitten.state == MawPlate.State.FALLING, "the open Maw eats an outer plate")

	# The void: the Herald is put back on the inner ring, anything else dies.
	herald.global_position = maw.to_global(Vector3(0, -20, 0))
	await _frames(2)
	_check(herald.global_position.y > -1.0 and maw.plate_at(herald.global_position) in maw.inner_plates, "the Herald is pulled back from the void")
	player.global_position = maw.to_global(Vector3(30, -20, 0))
	await _frames(2)
	_check(not player.health.is_alive(), "falling off the edge kills")
	get_tree().paused = false  # the death screen pauses
	arena.queue_free()
	await _frames(3)
	_finished += 1
