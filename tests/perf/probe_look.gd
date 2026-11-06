extends Node
## Windowed probe for the kill + "look at a drop" hitch. Kills enemies in
## front of the camera and logs the worst frame after each kill, then spawns
## rolled drops one at a time and logs the frame their card appears on, plus
## the card build time on its own.
## Run windowed: Godot --path . res://tests/perf/probe_look.tscn --resolution 1600x900 -- [count] [probe save slot] [warm] [fade|rolls]
## "warm" runs SpellWarmup first; "fade" only fades live enemies per type;
## "rolls" times every unique build and 300 gear rolls.
## The save slot reads a copy of a real save (user://probe_save_slot<N>.json).

const MAP := "res://levels/generated_map/GeneratedMap.tscn"

var player: Player

func _ready() -> void:
	_run.call_deferred()

func _pipelines() -> int:
	var total := 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += int(Performance.get_monitor(m))
	return total

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Worst frame (ms, index, detail) over the next n frames.
func _worst_of(n: int) -> Array:
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var at := -1
	var detail := ""
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pipes := _pipelines()
	for f in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var n2 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var p2 := _pipelines()
		if ms > worst:
			worst = ms
			at = f
			detail = "proc=%.1f phys=%.1f nodes%+d pipes+%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, n2 - nodes, p2 - pipes]
		nodes = n2
		pipes = p2
	return [worst, at, detail]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var count: int = int(args[0]) if args.size() > 0 else 12
	GameState.reset_to_defaults()
	if args.size() > 1:
		SaveManager.slot_prefix = "user://probe_save_slot"
		SaveManager.slot = int(args[1])
		SaveManager.load_game()  # stays game_started, so the map keeps its level; saves go to the copy
	else:
		GameState.game_started = false
	var figment := FigmentRoller.roll(30)
	figment.tileset_id = "snow_tundra"
	GameState.active_map = figment
	seed(11)
	add_child(load(MAP).instantiate())
	await _frames(60)
	player = get_tree().get_first_node_in_group("player") as Player
	player.health.max_health = 1.0e8
	player.health.current_health = 1.0e8
	LootWarmup.start(get_tree())
	await LootWarmup.warm_drops(get_tree())
	if OS.get_cmdline_user_args().has("warm"):
		SpellWarmup.done = false
		await SpellWarmup.run(get_tree())
	await _frames(30)
	print("LOOK save=%s L%d" % [GameState.player_name, GameState.player_level])
	if args.has("fade"):
		await _bench_fade()
		get_tree().quit()
		return
	if args.has("cards"):
		await _bench_card_modes()
		get_tree().quit()
		return
	if args.has("rolls"):
		_bench_unique()
		_bench_rolls()
		get_tree().quit()
		return
	await _bench()
	await _bench_card()
	for k in 8:
		var e := _nearest_enemy()
		if e == null:
			break
		var cam0 := player.camera
		e.global_position = cam0.global_position - cam0.global_transform.basis.z * 3.0 + Vector3.DOWN * 1.2
		await _frames(3)
		var t0 := Time.get_ticks_usec()
		var parts := _timed_kill(e)
		var kill_us := Time.get_ticks_usec() - t0
		var w: Array = await _worst_of(40)
		print("KILL %d call=%dus [%s] worst_after=%.1fms @frame%d %s target=%s" % [k, kill_us, parts, w[0], w[1], w[2], player.loot_picker.target.display_name() if is_instance_valid(player.loot_picker.target) else "-"])
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	for p in get_tree().get_nodes_in_group(LootPickup.LOOK_GROUP):
		p.queue_free()
	await _frames(10)
	var card := ItemSlotButton.new_item_card()
	add_child(card)
	for i in count:
		var item := ItemRoller.roll(30, 3.0)
		var t := Time.get_ticks_usec()
		card.compare_against = ItemCompare.equipped_for(item)
		card.display_item(item)
		var build := Time.get_ticks_usec() - t
		var pickup: LootPickup = (load("res://entities/pickups/loot_pickup/LootPickup.tscn") as PackedScene).instantiate()
		pickup.item = item
		get_tree().current_scene.add_child(pickup)
		var cam := player.camera
		# Lands beside the player first, then gets looked at, as in play.
		pickup.global_position = cam.global_position + cam.global_transform.basis.x * 4.0 + Vector3.DOWN * 0.3
		await _frames(8)
		pickup.global_position = cam.global_position - cam.global_transform.basis.z * 2.5 + Vector3.DOWN * 0.3
		var p0 := _pipelines()
		var w: Array = await _worst_of(30)
		print("LOOK %d %s rarity=%d affixes=%d build=%dus worst=%.1fms @frame%d pipes+%d targeted=%s" % [i, item.display_name, item.rarity, item.affixes.size(), build, w[0], w[1], _pipelines() - p0, player.loot_picker.target == pickup])
		pickup.queue_free()
		await _frames(10)
	print("LOOK_DONE")
	get_tree().quit()

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := 400.0
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := (e as Node3D).global_position.distance_to(player.global_position)
		if d < best_d and not e.is_queued_for_deletion():
			best = e
			best_d = d
	return best

## Kills `e` with each death-signal handler timed on its own: "handler=us ...".
func _timed_kill(e: Node) -> String:
	var sigs: Array[Signal] = [EventBus.enemy_died]
	if "health" in e and e.health:
		sigs.append(e.health.died)
	var saved := {}
	for s in sigs:
		var conns: Array = s.get_connections()
		saved[s] = conns
		for c in conns:
			s.disconnect(c["callable"])
	var parts := {}
	EventBus.enemy_died.connect(func(en): _time_calls(saved[EventBus.enemy_died], [en], parts, "bus"))
	if sigs.size() > 1:
		e.health.died.connect(func(): _time_calls(saved[sigs[1]], [], parts, "hp"))
	e.take_damage(1.0e9, Constants.DamageType.KINETIC)
	for s in sigs:
		for c in s.get_connections():
			s.disconnect(c["callable"])
		for c in saved[s]:
			if (c["callable"] as Callable).is_valid() and not s.is_connected(c["callable"]):
				s.connect(c["callable"], c["flags"])
	var top := parts.keys()
	top.sort_custom(func(a, b): return parts[a] > parts[b])
	var desc := PackedStringArray()
	for k in top.slice(0, 5):
		desc.append("%s=%dus" % [k, parts[k]])
	return " ".join(desc)

func _time_calls(conns: Array, args: Array, parts: Dictionary, tag: String) -> void:
	for c in conns:
		var cb: Callable = c["callable"]
		if not cb.is_valid():
			continue
		var t := Time.get_ticks_usec()
		cb.callv(args)
		var obj := cb.get_object()
		var key := "%s:%s.%s" % [tag, obj.get_script().resource_path.get_file() if obj and obj.get_script() else str(obj), cb.get_method()]
		parts[key] = parts.get(key, 0) + Time.get_ticks_usec() - t

## Per-call costs of the pieces a kill runs, after warm-up.
func _bench() -> void:
	var scene := get_tree().current_scene
	var at := player.global_position + Vector3(0, 1, -3)
	var rows := {}
	for i in 6:
		var t := Time.get_ticks_usec()
		SpellFx.burst(scene, at, Color(3, 2, 0.5, 1), 40, Vector2(3.0, 6.0), 0.7, Vector2(0.1, 0.22), 180.0, -6.0)
		var t1 := Time.get_ticks_usec()
		SpellFx.flash(scene, at, Color(2, 1.5, 0.5, 0.6), 1.4, 0.2)
		var t2 := Time.get_ticks_usec()
		SpellFx.light_pop(scene, at, Color.GOLD, 2.5, 5.0, 0.3)
		var t3 := Time.get_ticks_usec()
		var item := ItemRoller.roll(80, 1.0)
		var t4 := Time.get_ticks_usec()
		var pickup: LootPickup = (load("res://entities/pickups/loot_pickup/LootPickup.tscn") as PackedScene).instantiate()
		pickup.item = item
		scene.add_child(pickup)
		pickup.global_position = at + Vector3(0, -0.5, 0)
		var t5 := Time.get_ticks_usec()
		EventBus.loot_dropped.emit(item, at)
		var t6 := Time.get_ticks_usec()
		print("BENCH burst=%d flash=%d light=%d roll=%d pickup=%d loot_dropped=%d (%s)" % [t1 - t, t2 - t1, t3 - t2, t4 - t3, t5 - t4, t6 - t5, item.display_name])
		await _frames(20)
		pickup.queue_free()

func _bench_card() -> void:
	var card := ItemSlotButton.new_item_card()
	add_child(card)
	for i in 5:
		var item := ItemRoller.roll(80, 3.0)
		var worn := ItemCompare.equipped_for(item)
		var r := {}
		var t := Time.get_ticks_usec()
		card._merged_explicit_lines(item); r["merged"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card._check_requirements_met(item); r["req"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card._item_type_line(item); r["type"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card._item_stat_lines(item); r["stats"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		if item is Weapon:
			card._build_attack_power_lines(item); r["attack"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
			card._ranged_info_lines(item); r["ranged"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card._craft_preview(item); r["craft"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for w in worn:
			ItemCompare.diff_lines(item, w)
		r["diff"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card._clear(); r["clear"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card._add_mod_line("+12 to Strength", Color.WHITE); r["1line"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card.compare_against = worn
		card.display_item(item); r["full"] = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		card.reset_size(); r["reset_size"] = Time.get_ticks_usec() - t
		r["children"] = card._content().get_child_count()
		print("CARD %s %s" % [item.display_name, r])
		await _frames(3)
	card.queue_free()
## Fades one or two live enemies per type the way a corpse does, and logs the
## pipeline compiles and worst frame that follow.
func _bench_fade() -> void:
	var seen := {}
	var done := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if done >= 14 or not is_instance_valid(e):
			continue
		done += 1
		var key: String = e.definition.resource_path.get_file() if "definition" in e and e.definition else e.name
		if seen.has(key):
			key += "#2"
			if seen.has(key):
				continue
		seen[key] = true
		var cam := player.camera
		e.global_position = cam.global_position - cam.global_transform.basis.z * 4.0 + Vector3.DOWN * 1.2
		e.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(5)
		var meshes: Array[Node] = e.find_children("*", "GeometryInstance3D", true, false)
		var p0 := _pipelines()
		for g: GeometryInstance3D in meshes:
			g.transparency = 0.3
		var w: Array = await _worst_of(4)
		print("FADE %s meshes=%d worst=%.1fms @%d pipes+%d" % [key, meshes.size(), w[0], w[1], _pipelines() - p0])
		e.queue_free()
		await _frames(3)

func _bench_unique() -> void:
	for d in UniqueCatalog.DEFS:
		var t := Time.get_ticks_usec()
		var base: Item = UniqueRoller._base(d["base_item"]) if d.has("base_item") else UniqueRoller.base_for(d["base_type"], 80)
		var t1 := Time.get_ticks_usec()
		var it := UniqueRoller.build(d, 80)
		var t2 := Time.get_ticks_usec()
		if t2 - t > 3000:
			print("UNIQUE %s base=%dus build=%dus" % [d["name"], t1 - t, t2 - t1])
	var t3 := Time.get_ticks_usec()
	UniqueRoller.droppable(Constants.ItemRarity.UNIQUE)
	print("UNIQUE droppable=%dus defs=%d" % [Time.get_ticks_usec() - t3, UniqueCatalog.DEFS.size()])

func _bench_rolls() -> void:
	var slow := 0
	for i in 300:
		var t := Time.get_ticks_usec()
		var it := ItemRoller.roll(80, 1.0)
		var dt := Time.get_ticks_usec() - t
		if dt > 8000:
			slow += 1
			print("ROLL slow %dus %s rarity=%d base=%s unique=%s" % [dt, it.display_name, it.rarity, it.resource_path if it.resource_path else it.item_id, it.unique_id])
	print("ROLL slow=%d/300" % slow)

## Card build variants: on a shown card, on a hidden card in the tree, then showing it.
func _bench_card_modes() -> void:
	var shown := ItemSlotButton.new_item_card()
	add_child(shown)
	var hidden := ItemSlotButton.new_item_card()
	hidden.visible = false
	add_child(hidden)
	for i in 6:
		var item := ItemRoller.roll(80, 3.0)
		var worn := ItemCompare.equipped_for(item)
		var t := Time.get_ticks_usec()
		shown.compare_against = worn
		shown.display_item(item)
		shown.reset_size()
		var a := Time.get_ticks_usec() - t
		await _frames(3)
		t = Time.get_ticks_usec()
		hidden.compare_against = worn
		hidden.display_item(item)
		var b := Time.get_ticks_usec() - t
		await _frames(3)
		t = Time.get_ticks_usec()
		hidden.visible = true
		hidden.reset_size()
		var c := Time.get_ticks_usec() - t
		var w: Array = await _worst_of(2)
		print("MODES %s shown_build=%d hidden_build=%d show=%d next_frame=%.1fms" % [item.display_name, a, b, c, w[0]])
		hidden.visible = false
		await _frames(3)
