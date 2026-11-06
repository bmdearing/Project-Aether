extends Node
## Windowed spike probe: a real map with fights going on (packs drawn in,
## spells cast, enemies killed so loot, XP and death FX play), logging every
## frame over SPIKE_MS with what happened in it: pipeline compiles, nodes
## added, process/physics time.
## Run windowed: Godot --path . res://tests/perf/probe_spikes.tscn --resolution 1600x900 -- <style> [seconds] [cel]

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const SPIKE_MS := 25.0
const SPELLS := ["inferno", "comet", "tornado", "thunder_javelin", "flame_wall", "spark"]

var map: GeneratedMap
var player: Player
var _events: PackedStringArray = []

func _ready() -> void:
	_run.call_deferred()

func _pipelines() -> int:
	var total := 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += int(Performance.get_monitor(m))
	return total

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var style: String = args[0] if args.size() > 0 else "snow_tundra"
	var seconds: float = float(args[1]) if args.size() > 1 else 40.0
	GameState.reset_to_defaults()
	GameState.game_started = false
	GameState.cel_shading = args.has("cel")
	EventBus.settings_changed.emit()
	var figment := FigmentRoller.roll(30)
	figment.tileset_id = style
	GameState.active_map = figment
	seed(7)
	map = load(MAP).instantiate()
	add_child(map)
	for i in 60:
		await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player") as Player
	player.health.max_health = 1.0e8
	player.health.current_health = 1.0e8
	LootWarmup.start(get_tree())
	SpellWarmup.done = false
	await SpellWarmup.run(get_tree())
	await LootWarmup.warm_drops(get_tree())
	for i in 30:
		await get_tree().process_frame
	print("SPIKE start style=%s cel=%s nodes=%d" % [style, GameState.cel_shading, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var spells: Array[Ability] = []
	for id in SPELLS:
		var a := load("res://data/abilities/instances/%s.tres" % id) as Ability
		if a:
			spells.append(a)
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	var pipes := _pipelines()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var frames := 0
	var spikes := 0
	var worst := 0.0
	var times: Array[float] = []
	var next_cast := 0.0
	var next_kill := 0.0
	var next_pack := 0.0
	var clock := 0.0
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		clock += ms / 1000.0
		frames += 1
		times.append(ms)
		var p := _pipelines()
		var n := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		if ms > SPIKE_MS and frames > 3:
			spikes += 1
			print("SPIKE %.1fms t=%.1fs pipelines+%d nodes%+d proc=%.1f phys=%.1f events=%s" % [ms, clock, p - pipes, n - nodes,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, ",".join(_events)])
		worst = maxf(worst, ms)
		_win_ms += ms
		_win_n += 1
		if clock >= _next_stat:
			_next_stat = clock + 5.0
			print("STAT t=%.0fs avg=%.1fms enemies=%d nodes=%d proc=%.1f phys=%.1f draws=%d objs=%d prims=%dk" % [clock, _win_ms / maxf(_win_n, 1), get_tree().get_nodes_in_group("enemy").size(), n, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
			_win_ms = 0.0
			_win_n = 0
		pipes = p
		nodes = n
		_events.clear()
		_drive(clock, spells)
		if clock >= next_cast:
			next_cast = clock + 0.7
			_cast(spells.pick_random())
		if clock >= next_kill:
			next_kill = clock + 0.5
			_kill_one()
		if clock >= next_pack:
			next_pack = clock + 6.0
			_pull_pack()
	times.sort()
	var avg: float = times.reduce(func(s, v): return s + v, 0.0) / maxf(times.size(), 1.0)
	print("SPIKE summary frames=%d avg=%.1fms p99=%.1fms worst=%.1fms spikes>%d=%d" % [frames, avg, times[int(times.size() * 0.99)], worst, int(SPIKE_MS), spikes])
	var ks := _part_sums.keys()
	ks.sort_custom(func(a, b): return _part_sums[a] > _part_sums[b])
	for k in ks.slice(0, 12):
		print("KILLPART %s total=%dms" % [k, _part_sums[k] / 1000])
	print("SPIKE kept materials=%d" % MaterialKeeper.kept_count())
	print("SPIKE_DONE")
	get_tree().quit()

## Walks the player in a slow circle so new ground, doodads and enemies come into view.
func _drive(clock: float, _spells: Array[Ability]) -> void:
	var dir := Vector3(cos(clock * 0.15), 0, sin(clock * 0.15))
	player.velocity.x = dir.x * 5.0
	player.velocity.z = dir.z * 5.0
	player.look_at(player.global_position + dir, Vector3.UP)

func _cast(a: Ability) -> void:
	var target := _nearest_enemy()
	var spot := target.global_position if target else player.global_position - player.global_transform.basis.z * 8.0
	var t := Time.get_ticks_usec()
	player.ability_cast._cast(a, spot)
	_events.append("cast:%s:%dus" % [a.ability_id, Time.get_ticks_usec() - t])

func _kill_one() -> void:
	var e := _nearest_enemy()
	if e and e.has_method("take_damage"):
		var sigs: Array[Signal] = [EventBus.enemy_died]
		if "health" in e and e.health:
			sigs.append(e.health.died)
		var saved := {}
		for s in sigs:
			var conns: Array = s.get_connections()
			saved[s] = conns
			for c in conns:
				s.disconnect(c["callable"])
		var t := Time.get_ticks_usec()
		var parts := {}
		EventBus.enemy_died.connect(func(en): _time_calls(saved[EventBus.enemy_died], [en], parts, "bus"))
		if sigs.size() > 1:
			e.health.died.connect(func(): _time_calls(saved[sigs[1]], [], parts, "hp"))
		e.take_damage(1.0e9, Constants.DamageType.KINETIC)
		var total := Time.get_ticks_usec() - t
		for s in sigs:
			for c in s.get_connections():
				s.disconnect(c["callable"])
			for c in saved[s]:
				if (c["callable"] as Callable).is_valid() and not s.is_connected(c["callable"]):
					s.connect(c["callable"], c["flags"])
		var top := parts.keys()
		top.sort_custom(func(a, b): return parts[a] > parts[b])
		var desc := PackedStringArray()
		for k in top.slice(0, 4):
			desc.append("%s=%dus" % [k, parts[k]])
		_events.append("kill:%dus[%s]" % [total, " ".join(desc)])
		_kill_totals.append([total, desc])

var _kill_totals: Array = []
var _win_ms := 0.0
var _win_n := 0
var _next_stat := 0.0
var _part_sums := {}

func _time_calls(conns: Array, args: Array, parts: Dictionary, tag: String) -> void:
	for c in conns:
		var cb: Callable = c["callable"]
		if not cb.is_valid():
			continue
		var t := Time.get_ticks_usec()
		cb.callv(args)
		var key := "%s:%s.%s" % [tag, cb.get_object().get_script().resource_path.get_file() if cb.get_object() and cb.get_object().get_script() else str(cb.get_object()), cb.get_method()]
		var dt := Time.get_ticks_usec() - t
		parts[key] = parts.get(key, 0) + dt
		_part_sums[key] = _part_sums.get(key, 0) + dt

func _pull_pack() -> void:
	var cells: Array = map.graph.rooms.keys()
	var spot := player.global_position + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
	var t := Time.get_ticks_usec()
	map._spawn_pack(EnemyRoster.roll_pack(Constants.ENEMY_PACKS_NORMAL), spot)
	_events.append("pack:%dus" % (Time.get_ticks_usec() - t))

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := 40.0
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := (e as Node3D).global_position.distance_to(player.global_position)
		if d < best_d and not e.is_queued_for_deletion():
			best = e
			best_d = d
	return best
