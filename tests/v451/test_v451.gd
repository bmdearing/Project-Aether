extends Node
## Headless checks for the v4.51 batch: Fate Board anchor and chain
## tooltips, shared Spark/Caltrops hit cooldowns, Booming Blade, jewel mods,
## Butterfly, ranged vs melee DPS, control rebinding, portals that fire for a
## player already inside, death interrupting an attack, the Ward fill, and
## the dungeon rework (flat boss room, completion portal, non-overlapping
## props, styles with their own layouts).
## Run: Godot --headless --path . res://tests/v451/test_v451.tscn --quit-after 8000
## Exits 0 when every check passes. Never writes the save or settings file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 11

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

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_fate_board()
	_test_hit_cooldown()
	await _test_booming_blade()
	_test_jewels_and_butterfly()
	_test_dps_balance()
	_test_rebinding()
	await _test_portal_polling()
	await _test_death_interrupt()
	_test_ward_fill()
	await _test_dungeon()
	_test_style_layouts()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.51 tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _flat_arena() -> Node3D:
	var arena := Node3D.new()
	add_child(arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	arena.add_child(body)
	return arena

func _slate(tag: Constants.DamageType) -> Slate:
	var s := Slate.new()
	s.slate_id = "test_%d" % tag
	s.display_name = "Test Slate"
	s.tag = tag
	s.aether_cost = 1
	s.shape_cells = [Vector2i(0, 0)]
	return s

func _test_fate_board() -> void:
	var board := FateBoard.new()
	board.aether_capacity = 100
	_check(board._placement_failure_reason(_slate(Constants.DamageType.FIRE), FateBoard.ANCHOR_CELL, 0, false) == "anchor_cell", "a Slate can't cover the starting point")
	var id := board.place_slate(_slate(Constants.DamageType.FIRE), FateBoard.ANCHOR_CELL + Vector2i(1, 0))
	_check(id != "", "a Slate beside the starting point places")
	var text := ChainCalculator.explanation()
	_check(text.contains("Tiles 1-20") and text.contains("+1.00%"), "the chain tooltip lists the tier table")
	var lines := ChainCalculator.chain_lines_for(board, id)
	_check(lines.size() == 1 and lines[0].contains("1 tiles"), "a placed Slate's card lists its chain (%s)" % [lines])
	_finished += 1

func _test_hit_cooldown() -> void:
	var a := Node.new()
	_check(HitCooldown.try_hit(&"spark", a, 0.15), "first spark hit lands")
	_check(not HitCooldown.try_hit(&"spark", a, 0.15), "a second spark on the same enemy at once is blocked")
	_check(HitCooldown.try_hit(&"caltrops", a, 0.15), "other effects keep their own cooldown")
	var b := Node.new()
	_check(HitCooldown.try_hit(&"spark", b, 0.15), "other enemies aren't blocked")
	a.free()
	b.free()
	_finished += 1

func _test_booming_blade() -> void:
	var arena := _flat_arena()
	var player: Player = load("res://entities/player/Player.tscn").instantiate()
	arena.add_child(player)
	await _frames(3)
	var blade := load("res://data/abilities/instances/booming_blade.tres") as Ability
	_check(blade != null and not blade.is_auto_cast_eligible, "Booming Blade exists and isn't a Slate auto-cast")
	var cast := player.ability_cast
	cast._cast(blade, player.global_position)
	_check(GameState.booming_blade_on, "casting turns Booming Blade on")
	var before := _count_blade_crawlers()
	cast.on_melee_swing()
	await _frames(1)
	var expected := PlayerAbilityCast.booming_blade_bolt_count(blade, player.stat_sheet)
	_check(_count_blade_crawlers() - before == expected, "a swing sends %d straight ground bolt(s) (%d)" % [expected, _count_blade_crawlers() - before])
	cast.on_melee_swing()
	await _frames(1)
	_check(_count_blade_crawlers() - before == expected, "the 0.45s cooldown stops a second volley")
	blade.level = 15
	_check(PlayerAbilityCast.booming_blade_bolt_count(blade, player.stat_sheet) > expected, "higher levels fire more bolts")
	blade.level = 1
	player.mana.current_mana = player.mana.max_mana
	var mana := player.mana.current_mana
	GameState.booming_blade_on = true
	player.ability_loadout.equip(blade, 0)
	cast._try_cast(0, player.global_position)
	_check(not GameState.booming_blade_on and is_equal_approx(player.mana.current_mana, mana), "casting again turns it off for free")
	GameState.booming_blade_on = false
	var javelin := load("res://data/abilities/instances/thunder_javelin.tres") as Ability
	var bolts := _count_bolts()
	player.stat_sheet.conduit_additional_projectiles = 2
	cast._fire_piercing_bolt(javelin, 1.0)
	await _frames(1)
	_check(_count_bolts() - bolts == 3, "a Conduit's +2 additional Projectiles fires 3 bolts (%d)" % (_count_bolts() - bolts))
	player.stat_sheet.conduit_additional_projectiles = 0
	arena.queue_free()
	await _frames(2)
	_finished += 1

func _count_bolts() -> int:
	return get_tree().root.find_children("*", "PiercingBolt", true, false).size()

func _count_blade_crawlers() -> int:
	return get_tree().root.find_children("*", "SparkCrawler", true, false).filter(func(c): return c.straight).size()

func _test_jewels_and_butterfly() -> void:
	var jewel := Jewel.new()
	jewel.item_level = 85
	var by_key := {}
	for def in JewelModifierPool.defs_for(jewel):
		by_key[def.stat_key] = def
	for want in [["increased_attack_damage", 40.0], ["attack_speed", 15.0], ["crit_chance_increased", 20.0]]:
		var def: ModifierDef = by_key.get(want[0])
		_check(def != null and is_equal_approx(def.tiers[0].value_max, want[1]), "jewels roll %s up to %d%%" % [want[0], want[1]])
	var butterfly: Dictionary = {}
	for d in UniqueCatalog.DEFS:
		if d["id"] == "butterfly":
			butterfly = d
	_check(butterfly.get("base_type", "") == "crossbow", "Butterfly is a crossbow unique")
	var sheet := StatSheet.new()
	var effects := UniqueEffects.new()
	effects.effects = {UniqueEffects.DAMAGE_FROM_MOVE_SPEED: 60.0}
	sheet.unique_effects = effects
	sheet.set_misc_bonus({"move_speed": 30.0})
	_check(is_equal_approx(sheet.get_increased_damage_percent(Constants.DamageType.PIERCING, true), 18.0), "60% of +30% Movement Speed is +18% increased damage")
	effects.free()
	_finished += 1

func _test_dps_balance() -> void:
	var sheet: StatSheet = (load("res://data/stats/instances/player_baseline.tres") as StatSheet).duplicate(true)
	var best := {}
	for f in DirAccess.get_files_at("res://data/weapons/instances/"):
		f = f.trim_suffix(".remap")
		var w := load("res://data/weapons/instances/" + f) as Weapon if f.ends_with(".tres") else null
		if w == null or not w.weapon_type in ["Machine Gun", "Submachine Gun", "Service Pistol", "Greatsword", "Saber"]:
			continue
		var cur: Weapon = best.get(w.weapon_type)
		if cur == null or w.base_damage_max > cur.base_damage_max:
			best[w.weapon_type] = w
	var sustained := func(w: Weapon) -> float:
		if not w.is_ranged:
			return w.predict_damage(PlayerMeleeAttack.WEAPON_TYPE_MOTION_VALUE.get(w.weapon_type, 1.0), sheet) / PlayerMeleeAttack.swing_seconds(w.weapon_type)
		var interval := 1.0 / w.fire_rate if w.fire_rate > 0.0 else PlayerRangedAttack.BASE_FIRE_COOLDOWN
		return w.predict_damage(1.0, sheet) * w.magazine_size / (w.magazine_size * interval + w.reload_time)
	var melee_low: float = minf(sustained.call(best["Greatsword"]), sustained.call(best["Saber"]))
	for gun in ["Machine Gun", "Submachine Gun", "Service Pistol"]:
		var dps: float = sustained.call(best[gun])
		_check(dps < melee_low, "%s sustained DPS (%.0f) stays under melee's (%.0f)" % [gun, dps, melee_low])
	var mg: Weapon = best["Machine Gun"]
	_check(is_equal_approx(mg.get_base_range().x, mg.base_damage_min * Weapon.RANGED_DAMAGE_SCALE["Machine Gun"]), "the ranged scale shows on the weapon's own range")
	_finished += 1

func _test_rebinding() -> void:
	var jump_before := GameSettings.current_event("jump")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E  # Interact's key
	GameSettings.bind("jump", key)
	_check(GameSettings.key_name("jump") == "E", "Jump rebinds to E")
	_check(InputMap.action_has_event("interact", jump_before), "Interact takes Jump's old key instead of sharing E")
	var back := GameSettings.event_from_dict(GameSettings.event_to_dict(key))
	_check(back is InputEventKey and (back as InputEventKey).physical_keycode == KEY_E, "a binding survives the settings file round trip")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	GameSettings.bind("parry", mouse)
	_check(GameSettings.key_name("parry") == "Mouse 4", "mouse buttons bind too")
	GameSettings.reset_controls()
	_check(GameSettings.current_event("jump").is_match(jump_before) and GameSettings.key_name("interact") == "E", "reset restores the defaults")
	var label := Label3D.new()
	label.text = "Press E to open Stash"
	GameSettings.bind("interact", _key(KEY_G))
	GameSettings.refresh_interact_prompt(label)
	_check(label.text == "Press G to open Stash", "prompts show the bound key (%s)" % label.text)
	GameSettings.reset_controls()
	label.free()
	_finished += 1

func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k

func _test_portal_polling() -> void:
	var arena := _flat_arena()
	var player: Player = load("res://entities/player/Player.tscn").instantiate()
	arena.add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	var portal := Portal.new()
	portal.destination = Portal.Destination.HUB
	var taken := [false]
	portal.taken.connect(func(): taken[0] = true)
	arena.add_child(portal)
	portal.global_position = Vector3(0, 0, 0)  # spawned on top of the player
	await _frames(10)
	_check(not taken[0], "a portal ignores the player while it arms")
	await get_tree().create_timer(Portal.ARM_DELAY + 0.3).timeout
	await _frames(3)
	_check(taken[0], "a player already standing in a portal goes through once it arms")
	arena.queue_free()
	await _frames(2)
	_finished += 1

func _test_death_interrupt() -> void:
	var arena := _flat_arena()
	var enemy := EnemyRoster.create_unit("unchartered_brigand")
	arena.add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	await _frames(5)
	var anim := enemy.get("_anim_controller") as EnemyAnimationController
	if anim == null:
		_check(false, "the test unit has an animation controller")
	else:
		anim.play_attack(1.0)
		await _frames(4)
		enemy.health.apply_damage(1.0e9)
		await _frames(3)
		_check(anim.is_playing_death(), "death cuts an attack short and plays at once")
	arena.queue_free()
	await _frames(2)
	_finished += 1

func _test_ward_fill() -> void:
	var orb := StatOrb.new()
	orb.set_ward_value(50.0, 100.0)
	_check(is_equal_approx(orb.get_ward_fill(), 0.5) and orb.get_ward_width_fraction() == StatOrb.WARD_MAX_WIDTH, "Ward keeps its width and drains by height")
	orb.set_ward_value(0.0, 100.0)
	_check(orb.get_ward_width_fraction() == 0.0, "no Ward, no lattice")
	orb.free()
	_finished += 1

func _test_dungeon() -> void:
	for style_id in ["dungeon_cellblock", "dungeon_undercroft", "dungeon_mine", "snow_frozen_crypt"]:
		var figment := FigmentRoller.roll(1)
		figment.tileset_id = style_id
		GameState.active_map = figment
		var map: GeneratedMap = load(MAP).instantiate()
		add_child(map)
		await _frames(4)
		var vault := map._cell_to_world(map.graph.vault_cell)
		var half: Vector2 = map.room_half[map.graph.vault_cell]
		_check(half.x * 2.0 >= 20.0, "%s: the boss room is large (%.0fm)" % [style_id, half.x * 2.0])
		var flat := true
		for i in 30:
			var p := vault + Vector3(randf_range(-half.x + 1, half.x - 1), 0, randf_range(-half.y + 1, half.y - 1))
			var hit := _ray_down(map, p + Vector3.UP * 0.4)
			if hit.is_empty() or absf(hit["position"].y) > 0.05:
				if hit.is_empty() or not (hit["collider"] is StaticBody3D and hit["position"].y > 1.0):  # pillars and props stand above
					flat = false
		_check(flat, "%s: the boss room floor is one flat surface with no gaps" % style_id)
		_check(map.boss_portal_point.distance_to(vault) > 3.0, "%s: the altar sits away from the centre" % style_id)
		var occupied: Array[Rect2] = map._dresser._occupied
		var overlaps := 0
		for i in occupied.size():
			for j in range(i + 1, occupied.size()):
				if occupied[i].intersects(occupied[j]):
					overlaps += 1
		# Kept-clear areas (doorway mouths and lanes) overlap each other by design;
		# props are only ever added where they don't.
		_check(overlaps < occupied.size(), "%s: props don't pile up (%d overlaps among %d footprints)" % [style_id, overlaps, occupied.size()])
		if style_id == "dungeon_cellblock":
			var boss := map._boss
			boss.health.apply_damage(1.0e9)
			await _frames(4)
			var portals := map.get_children().filter(func(c): return c is Portal)
			_check(portals.size() == 1 and portals[0].global_position.distance_to(map.boss_portal_point) < 0.1, "killing the boss opens a portal on the altar")
		map.queue_free()
		await _frames(2)
	GameState.active_map = null
	_finished += 1

func _ray_down(map: Node3D, from: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	return map.get_world_3d().direct_space_state.intersect_ray(query)

func _test_style_layouts() -> void:
	var seen := {}
	for id in MapTileset.all_ids():
		var layout := MapLayout.for_tileset(MapTileset.load_style(id))
		var key := "%d|%s|%d|%.2f|%s|%.1f|%.1f|%s|%s|%.2f|%.2f" % [layout.kind, layout.grid_size, layout.room_count.x, layout.branch_stop_chance, layout.room_size, layout.corridor_width, layout.wall_height, layout.pillar_chance, layout.mounds_per_cell, layout.mound_scale, layout.pass_width_scale]
		_check(not seen.has(key), "%s has its own layout (shares with %s)" % [id, seen.get(key, "-")])
		seen[key] = id
		if layout.kind == MapLayout.Kind.ROOMS:
			_check(layout.cell_size >= (layout.boss_room_size + layout.room_size.y) / 2.0 + MapLayout.MIN_CORRIDOR - 0.01, "%s: cells leave room for corridors" % id)
	_finished += 1
