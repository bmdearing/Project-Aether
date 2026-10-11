extends Node
## Headless checks for v4.79: indoor ceilings, the outdoor day/night clock
## and weather (MapAtmosphere), and the boss spell effects and sounds (BossFx).
## Run: Godot --headless --path . res://tests/v479/test_v479.tscn
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const TEST_COUNT := 4

var _checks := 0
var _failures := 0
var _finished := 0

const BossFx := preload("res://entities/effects/boss_fx/BossFx.gd")
const MapAtmosphere := preload("res://levels/generated_map/MapAtmosphere.gd")

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
	await _test_ceilings()
	await _test_day_night()
	await _test_weather()
	await _test_boss_fx()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.79 tests: %d checks, %d failures" % [_checks, _failures])
	GameState.active_map = null
	get_tree().quit(1 if _failures > 0 else 0)

func _build(style_id: String, map_seed: int) -> GeneratedMap:
	var figment := FigmentItem.new()
	figment.tileset_id = style_id
	GameState.active_map = figment
	GameState.portal_map_state = {"seed": map_seed, "tileset_id": style_id}
	GameState.returning_through_portal = true
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	return map

static func _luma(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.59 + c.b * 0.11

func _test_ceilings() -> void:
	for style_id in ["dungeon_cellblock", "dungeon_foundry_pit", "snow_frozen_crypt"]:
		var map := _build(style_id, 7)
		await _frames(4)
		var ceilings := map.get_children().filter(func(c): return c.is_in_group("ceiling"))
		var corridors := 0
		for cell in map.graph.rooms:
			corridors += map.graph.rooms[cell].connections.size()
		corridors /= 2
		_check(map.is_indoor(), "%s is indoors" % style_id)
		_check(ceilings.size() == map.graph.rooms.size() + corridors, "%s roofs every room and corridor (%d for %d + %d)" % [style_id, ceilings.size(), map.graph.rooms.size(), corridors])
		_check(ceilings.all(func(c): return is_equal_approx(c.position.y, map.layout.wall_height + GeneratedMap.CEILING_THICKNESS / 2.0)), "%s ceilings sit on the walls" % style_id)
		_check(ceilings.all(func(c): return c is MeshInstance3D and c.get_children().is_empty()), "%s ceilings have no collision" % style_id)
		_check(map.atmosphere == null, "%s has no sky or weather" % style_id)
		map.queue_free()
		await _frames(2)
	var outdoor := _build("forest_plains", 7)
	await _frames(4)
	_check(not outdoor.is_indoor() and outdoor.get_children().all(func(c): return not c.is_in_group("ceiling")), "outdoor maps stay open to the sky")
	_check(outdoor.atmosphere != null, "outdoor maps get the day/night clock")
	outdoor.queue_free()
	await _frames(2)
	_finished += 1

func _test_day_night() -> void:
	var map := _build("forest_plains", 21)
	await _frames(4)
	var atmo := map.atmosphere
	var env: Environment = map.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = map.get_node("DirectionalLight3D")
	atmo.weather = MapAtmosphere.Weather.CLEAR
	atmo.time_of_day = 0.5
	var before := atmo.time_of_day
	await get_tree().process_frame
	await get_tree().process_frame
	_check(atmo.time_of_day > before, "the clock runs")
	var noon_ambient := env.ambient_light_energy
	var noon_sky := _luma(env.background_color)
	_check(sun.visible and sun.light_energy > map.tileset.sun_energy * 0.9, "noon sun at full strength (%.2f)" % sun.light_energy)
	_check((-sun.global_transform.basis.z).y < -0.5, "the noon sun shines down from high up")
	atmo.time_of_day = 0.0
	await get_tree().process_frame
	_check(atmo.is_night() and sun.light_color.b > sun.light_color.r, "at midnight the moon's blue light takes over")
	_check(sun.light_energy < 0.3, "moonlight is faint (%.2f)" % sun.light_energy)
	_check(env.ambient_light_energy < noon_ambient * 0.6 and env.ambient_light_energy > 0.0, "nights are darker but not black")
	_check(_luma(env.background_color) < noon_sky * 0.5, "the night sky is dark")
	atmo.time_of_day = 0.73
	await get_tree().process_frame
	_check(sun.visible and sun.light_color.r > sun.light_color.b + 0.2, "the setting sun is warm")
	var state := map.capture_state()
	_check(is_equal_approx(float(state.get("time_of_day", -1.0)), atmo.time_of_day), "the time of day goes through the portal")
	var a := RandomNumberGenerator.new()
	a.seed = 3
	var day := 0
	for i in 400:
		var t := MapAtmosphere.roll_time(a)
		_check(t >= 0.0 and t < 1.0, "rolled times are within the day") if i == 0 else null
		if t > 0.3 and t < 0.7:
			day += 1
	_check(day > 180 and day < 320, "most maps start in daylight (%d/400)" % day)
	map.queue_free()
	await _frames(2)
	_finished += 1

func _test_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seen := {}
	for family in ["forest", "city", "snow", "desert", "dungeon"]:
		seen[family] = {}
		for i in 300:
			seen[family][MapAtmosphere.roll_weather(family, rng)] = true
	var W := MapAtmosphere.Weather
	_check(seen["forest"].has(W.RAIN) and seen["forest"].has(W.STORM) and not seen["forest"].has(W.SNOW), "forests get rain and storms, never snow")
	_check(seen["snow"].has(W.SNOW) and seen["snow"].has(W.BLIZZARD) and not seen["snow"].has(W.RAIN), "snow maps get snow and blizzards")
	_check(seen["desert"].has(W.SANDSTORM) and seen["desert"].size() == 2, "deserts get sandstorms only")
	_check(seen["dungeon"].keys() == [W.CLEAR], "unknown families stay clear")
	var m1 := _build("forest_hills", 5)
	await _frames(2)
	var w1 := m1.atmosphere.weather
	m1.queue_free()
	await _frames(2)
	var m2 := _build("forest_hills", 5)
	await _frames(2)
	_check(m2.atmosphere.weather == w1, "the same map seed rolls the same weather")
	m2.queue_free()
	await _frames(2)

	# A storm, set up by hand: falling rain, lightning that lights the sky, its sound.
	var style := MapTileset.load_style("forest_plains")
	var env := style.make_environment()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	var atmo := MapAtmosphere.new()
	atmo.setup(style, env, sun, 1)
	atmo.weather = W.STORM
	atmo.time_of_day = 0.5
	add_child(atmo)
	await get_tree().process_frame
	var rain := atmo.get_node_or_null("Precipitation") as GPUParticles3D
	_check(rain != null and rain.amount >= 1500 and rain.emitting, "a storm pours rain")
	_check(rain != null and rain.layers == 1 << (MapAtmosphere.WEATHER_LAYER - 1), "rain stays off the minimap's layer")
	_check(rain != null and rain.global_position.distance_to(camera.global_position) < MapAtmosphere.FALL_HEIGHT, "the rain follows the camera")
	_check(env.fog_density > style.fog_density * 2.0, "storms thicken the fog")
	var calm := _luma(env.background_color)
	atmo.strike()
	await get_tree().process_frame
	_check(_luma(env.background_color) > calm, "lightning lights the sky")
	_check(atmo.ambience_spec("wind_calm").contains("rain"), "storms add rain to the map's ambience")
	atmo.weather = W.SANDSTORM
	_check(atmo.ambience_spec("wind_gusts") == "wind_gusts:4", "a sandstorm turns the wind up instead of doubling it (%s)" % atmo.ambience_spec("wind_gusts"))
	atmo.weather = W.BLIZZARD
	await get_tree().process_frame
	_check(env.fog_density <= MapAtmosphere.MAX_FOG_DENSITY, "even a blizzard leaves you something to see")
	for n in [atmo, sun, camera]:
		n.queue_free()
	await _frames(2)
	_finished += 1

func _test_boss_fx() -> void:
	var lib := SoundLib.library
	for slot in ["boss_spell_cast", "boss_void_cast", "boss_void_burst", "boss_ghost_moan", "boss_fire", "boss_frost", "boss_ice_shatter", "boss_shock", "boss_sand", "boss_whoosh", "boss_summon", "boss_roar", "boss_heavy_impact"]:
		_check(not (lib.get(slot) as Array).is_empty(), "%s has sounds" % slot)
	for slot in ["boss_beam_start", "boss_beam_loop", "boss_deep_roar"]:
		_check(lib.get(slot) != null, "%s has a sound" % slot)
	var stage := Node3D.new()
	add_child(stage)
	var caster := Node3D.new()
	stage.add_child(caster)
	var marker := Node3D.new()
	stage.add_child(marker)
	for type in Constants.DamageType.values():
		BossFx.impact(stage, Vector3(type * 3.0, 0, 0), 3.5, type)
		BossFx.charge(caster, Vector3.UP, type, 0.3)
	BossFx.hazard_aura(marker, 3.0, Constants.DamageType.FIRE)
	BossFx.hazard_aura(marker, 3.0, Constants.DamageType.ENTROPIC)
	BossFx.trail(caster, Constants.DamageType.ENTROPIC, 0.3)
	BossFx.summon_gate(stage, Vector3.ZERO, Constants.DamageType.ENTROPIC)
	BossFx.vortex(stage, Vector3.ZERO, 8.0, Constants.DamageType.ENTROPIC, 0.3)
	BossFx.phase_roar(caster, Constants.DamageType.FIRE, lib.boss_deep_roar)
	var bolt: Projectile = EnemyRangedAttack.PROJECTILE_SCENE.instantiate()
	bolt.speed = 0.0
	stage.add_child(bolt)
	BossFx.dress_bolt(bolt, Constants.DamageType.COLD)
	_check(bolt.get_children().size() >= 4, "a boss bolt gets a glow and a trail")
	await get_tree().process_frame
	_check(stage.get_children().size() > 20, "impacts spawn their pieces (%d)" % stage.get_children().size())
	await get_tree().create_timer(6.0).timeout
	if is_instance_valid(bolt):
		bolt.queue_free()
	marker.queue_free()
	await _frames(2)
	var left := stage.get_children().filter(func(c): return c != caster)
	_check(left.is_empty(), "every effect frees itself (%s left)" % [left.map(func(c): return c.get_class())])
	_check(caster.get_children().is_empty(), "the charge glow and trail leave the caster")
	stage.queue_free()
	_finished += 1
