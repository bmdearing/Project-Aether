extends Node
## Day/night and weather for an outdoor Figment (GeneratedMap adds it when the
## style has a sun). The clock runs a full day in DAY_LENGTH seconds: the sun
## crosses the sky warming at dawn and dusk, sets, and a dim blue moon takes
## its light, while the sky, ambient light and fog follow it from the style's
## own daytime values. Weather is rolled per map from the style's family and
## stays for the run: rain, thunderstorms (lightning and thunder), snow,
## blizzards and sandstorms each darken the sky, thicken the fog, fall around
## the camera and layer their sound over the map's ambience.

enum Weather { CLEAR, RAIN, STORM, SNOW, BLIZZARD, SANDSTORM }

const WEATHER_NAMES := ["clear", "rain", "storm", "snow", "blizzard", "sandstorm"]
## family -> [[Weather, weight], ...]
const WEATHER_ODDS := {
	"forest": [[Weather.CLEAR, 0.55], [Weather.RAIN, 0.3], [Weather.STORM, 0.15]],
	"city": [[Weather.CLEAR, 0.55], [Weather.RAIN, 0.3], [Weather.STORM, 0.15]],
	"snow": [[Weather.CLEAR, 0.4], [Weather.SNOW, 0.45], [Weather.BLIZZARD, 0.15]],
	"desert": [[Weather.CLEAR, 0.7], [Weather.SANDSTORM, 0.3]],
}
## Weather -> sun dimming, fog multiplier, fog tint, ambience layer.
const WEATHER_LOOK := {
	Weather.CLEAR: {"sun": 1.0, "fog": 1.0, "tint": Color(0, 0, 0, 0), "sound": ""},
	Weather.RAIN: {"sun": 0.45, "fog": 1.8, "tint": Color(0.45, 0.48, 0.52, 0.5), "sound": "rain:-3"},
	Weather.STORM: {"sun": 0.3, "fog": 2.4, "tint": Color(0.3, 0.32, 0.38, 0.65), "sound": "rain:1,wind_gusts:-4"},
	Weather.SNOW: {"sun": 0.6, "fog": 2.0, "tint": Color(0.82, 0.86, 0.92, 0.5), "sound": "wind_calm:-2"},
	Weather.BLIZZARD: {"sun": 0.35, "fog": 4.5, "tint": Color(0.86, 0.9, 0.95, 0.8), "sound": "wind_gusts:3"},
	Weather.SANDSTORM: {"sun": 0.5, "fog": 5.0, "tint": Color(0.78, 0.6, 0.4, 0.8), "sound": "wind_gusts:4"},
}

## Seconds for a full day and night.
const DAY_LENGTH := 900.0
## Time of day: 0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset.
const SUNRISE := 0.25
const MOON_ENERGY := 0.22
const MOON_COLOR := Color(0.55, 0.65, 0.95)
const DUSK_COLOR := Color(1.0, 0.5, 0.25)
const NIGHT_TINT := Color(0.16, 0.2, 0.34)
## Ambient light at midnight, as a share of the style's daytime ambient.
const NIGHT_AMBIENT := 0.45
const SUN_TILT := 0.35
const THUNDER_INTERVAL := Vector2(10.0, 24.0)
## Precipitation falls in a box this wide around the camera, from this high.
const FALL_AREA := 26.0
const FALL_HEIGHT := 14.0
## Render layer of the falling weather; the minimap's camera leaves it out.
const WEATHER_LAYER := 20
## Thick weather never closes in tighter than this.
const MAX_FOG_DENSITY := 0.045
## Sky, light and fog follow the clock this often (lightning flashes every frame).
const APPLY_INTERVAL := 0.2

## Setting the time or weather updates the look on the next frame.
var time_of_day: float:
	get: return _clock
	set(value):
		_clock = value
		_apply_in = 0.0
## Changing the weather on a live map swaps its particles and its sound together.
var weather: Weather = Weather.CLEAR:
	set(value):
		weather = value
		_apply_in = 0.0
		if is_inside_tree():
			_rebuild_weather()
## The map's own ambience; the weather's sound layers on top (play_weather_sound()).
var base_ambience: String = ""
var _clock: float = 0.4

var _style: MapTileset
var _env: Environment
var _sun: DirectionalLight3D
var _base_fog: float
var _flash: float = 0.0
var _thunder_in: float = 0.0
var _fall: GPUParticles3D
var _apply_in: float = 0.0
var _fall_offset := Vector3(0, FALL_HEIGHT * 0.6, 0)
var _rng := RandomNumberGenerator.new()

## Rolls the clock and weather from `map_seed` (its own RNG, so the layout
## that seed builds is untouched).
func setup(style: MapTileset, env: Environment, sun: DirectionalLight3D, map_seed: int) -> void:
	_style = style
	_env = env
	_sun = sun
	_rng.seed = map_seed ^ 0x5eed_a7
	time_of_day = roll_time(_rng)
	weather = roll_weather(style.family, _rng)
	_base_fog = maxf(style.fog_density, 0.004)
	_thunder_in = _rng.randf_range(4.0, 9.0)

static func roll_time(rng: RandomNumberGenerator) -> float:
	var r := rng.randf()
	if r < 0.6:
		return rng.randf_range(0.3, 0.68)   # day
	if r < 0.85:
		return rng.randf_range(0.22, 0.3) if rng.randf() < 0.5 else rng.randf_range(0.68, 0.78)   # dawn, dusk
	return fposmod(rng.randf_range(0.82, 1.15), 1.0)   # night

static func roll_weather(family: String, rng: RandomNumberGenerator) -> Weather:
	var odds: Array = WEATHER_ODDS.get(family, [[Weather.CLEAR, 1.0]])
	var total: float = odds.reduce(func(sum, o): return sum + o[1], 0.0)
	var roll := rng.randf() * total
	for o in odds:
		roll -= o[1]
		if roll < 0.0:
			return o[0]
	return Weather.CLEAR

func _ready() -> void:
	if _style == null:
		return
	_build_fall()
	_apply()
	play_weather_sound()

func play_weather_sound() -> void:
	AudioManager.play_ambience(ambience_spec(base_ambience))

func _rebuild_weather() -> void:
	if is_instance_valid(_fall):
		_fall.queue_free()
	_fall = null
	_fall_offset = Vector3(0, FALL_HEIGHT * 0.6, 0)
	_build_fall()
	play_weather_sound()

## The map's ambience with the weather's own layer on top.
func ambience_spec(base: String) -> String:
	var extra: String = WEATHER_LOOK[weather]["sound"]
	if extra.is_empty():
		return base
	var kept := Array(base.split(",", false))
	for layer in extra.split(","):
		var id := layer.split(":")[0]
		kept = kept.filter(func(l: String): return l.split(":")[0].strip_edges() != id)
	kept.append_array(Array(extra.split(",")))
	return ",".join(PackedStringArray(kept))

func _process(delta: float) -> void:
	if _style == null:
		return
	_clock = fposmod(_clock + delta / DAY_LENGTH, 1.0)
	if weather == Weather.STORM:
		_tick_storm(delta)
	_apply_in -= delta
	if _flash > 0.0 or _apply_in <= 0.0:
		_apply_in = APPLY_INTERVAL
		_apply()
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_follow_camera()

## Sun height: 1 at noon, -1 at midnight.
func sun_elevation() -> float:
	return sin((time_of_day - SUNRISE) * TAU)

## 0 at night, 1 in full day.
func daylight() -> float:
	return smoothstep(-0.12, 0.25, sun_elevation())

func is_night() -> bool:
	return sun_elevation() < -0.05

func _apply() -> void:
	var look: Dictionary = WEATHER_LOOK[weather]
	var el := sun_elevation()
	var day := daylight()
	var dusk := clampf(1.0 - absf(el) / 0.3, 0.0, 1.0)
	var tint: Color = look["tint"]
	# Light: the sun by day, the moon by night, both faint near the horizon.
	var up := absf(el)
	var angle := (time_of_day - SUNRISE) * TAU
	var toward := Vector3(cos(angle), absf(sin(angle)) * (1.0 - SUN_TILT) + 0.05, SUN_TILT).normalized()
	if el < 0.0:
		toward = Vector3(-toward.x, toward.y, -toward.z)
	_sun.look_at_from_position(Vector3.ZERO, -toward, Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD)
	var rise := smoothstep(0.0, 0.25, up)
	if el >= 0.0:
		_sun.light_color = DUSK_COLOR.lerp(_style.sun_color, smoothstep(0.05, 0.4, el))
		_sun.light_energy = _style.sun_energy * float(look["sun"]) * rise
	else:
		_sun.light_color = MOON_COLOR
		_sun.light_energy = MOON_ENERGY * lerpf(1.0, float(look["sun"]), 0.5) * rise
	_sun.light_energy += _flash * 2.5
	_sun.visible = _sun.light_energy > 0.01
	# Sky, ambient and fog: the style's day colours, warmed at dusk, darkened by night.
	var sky := _style.background_color.lerp(Color(tint, 1.0), tint.a)
	sky = sky.lerp(sky * DUSK_COLOR * 1.3, dusk * 0.5 * day)
	sky = (sky * NIGHT_TINT * 1.2).lerp(sky, day)
	_env.background_color = sky.lerp(Color(0.75, 0.78, 0.9), _flash * 0.6)
	_env.ambient_light_color = _style.ambient_color.lerp(_style.ambient_color * NIGHT_TINT * 2.4, 1.0 - day)
	_env.ambient_light_energy = _style.ambient_energy * lerpf(NIGHT_AMBIENT, 1.0, day) * lerpf(1.0, 0.85, tint.a) + _flash
	_env.fog_enabled = true
	_env.fog_light_color = sky
	_env.fog_density = minf(_base_fog * float(look["fog"]), MAX_FOG_DENSITY)

## ---- Storms ---------------------------------------------------------------

func _tick_storm(delta: float) -> void:
	_thunder_in -= delta
	if _thunder_in > 0.0:
		return
	_thunder_in = _rng.randf_range(THUNDER_INTERVAL.x, THUNDER_INTERVAL.y)
	strike()

## A lightning flash, its flicker, and thunder rolling in after it.
func strike() -> void:
	_flash = 1.0
	get_tree().create_timer(0.12, false).timeout.connect(func() -> void: _flash = maxf(_flash, 0.6))
	get_tree().create_timer(_rng.randf_range(0.3, 1.8), false).timeout.connect(func() -> void:
		AudioManager.play_2d(Ambience.random_thunder(), -4.0))

## ---- Precipitation --------------------------------------------------------

func _build_fall() -> void:
	match weather:
		Weather.RAIN, Weather.STORM:
			_fall = _rain(weather == Weather.STORM)
		Weather.SNOW, Weather.BLIZZARD:
			_fall = _flakes(1000 if weather == Weather.SNOW else 1600, Color(0.95, 0.97, 1.0, 0.85), 1.8 if weather == Weather.SNOW else 4.0, weather == Weather.BLIZZARD)
		Weather.SANDSTORM:
			_fall = _sand()
	if _fall:
		_fall.name = "Precipitation"
		add_child(_fall)
		_fall.emitting = true

## Sand driven sideways in streaks, with big dust clouds rolling through
## (a child emitter, so it follows the camera and goes with the sand).
func _sand() -> GPUParticles3D:
	var dir := Vector3(1.0, -0.08, 0.3).normalized()
	var grains := _box_emitter(1400, 2.2)
	grains.emission_box_extents = Vector3(FALL_AREA * 0.5, FALL_HEIGHT * 0.25, FALL_AREA * 0.5)
	_fall_offset = Vector3(-FALL_AREA * 0.6, FALL_HEIGHT * 0.2, -FALL_AREA * 0.2)
	grains.direction = dir
	grains.spread = 8.0
	grains.initial_velocity_min = 16.0
	grains.initial_velocity_max = 22.0
	grains.gravity = Vector3(0, -0.5, 0)
	grains.particle_flag_align_y = true
	var streak := QuadMesh.new()
	streak.size = Vector2(0.035, 0.7)
	var streak_mat := _fall_material(Color(0.62, 0.46, 0.28, 0.75), false)
	streak_mat.distance_fade_min_distance = 1.5
	streak_mat.distance_fade_max_distance = 4.0
	streak.material = streak_mat
	grains.mesh = streak
	var sand := _on_gpu(grains)
	var clouds := _box_emitter(70, 4.0)
	clouds.emission_box_extents = Vector3(FALL_AREA * 0.5, FALL_HEIGHT * 0.2, FALL_AREA * 0.5)
	clouds.direction = dir
	clouds.spread = 10.0
	clouds.initial_velocity_min = 8.0
	clouds.initial_velocity_max = 12.0
	clouds.gravity = Vector3.ZERO
	clouds.scale_amount_min = 0.7
	clouds.scale_amount_max = 1.4
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE * 3.5
	var puff_mat := _fall_material(Color(0.72, 0.56, 0.36, 0.22), true)
	puff_mat.distance_fade_min_distance = 1.0
	puff_mat.distance_fade_max_distance = 4.0
	puff.material = puff_mat
	clouds.mesh = puff
	var dust := _on_gpu(clouds)
	dust.name = "Dust"
	sand.add_child(dust)
	dust.emitting = true
	return sand

## Wind-slanted rain streaks with grey mist sheets drifting through, the
## same build as the sandstorm (mist is a child, so it follows the camera).
func _rain(storm: bool) -> GPUParticles3D:
	var wind := Vector3(0.5, -1.0, 0.15) if storm else Vector3(0.25, -1.0, 0.08)
	var speed := 30.0 if storm else 26.0
	var drops := _box_emitter(1900 if storm else 1500, FALL_HEIGHT * 1.4 / speed)
	_fall_offset = Vector3(-wind.x, 0.0, -wind.z) * FALL_HEIGHT * 0.6 + Vector3.UP * FALL_HEIGHT * 0.6
	drops.direction = wind.normalized()
	drops.spread = 4.0
	drops.initial_velocity_min = speed * 0.85
	drops.initial_velocity_max = speed
	drops.particle_flag_align_y = true
	var streak := QuadMesh.new()
	streak.size = Vector2(0.04, 1.1)
	var streak_mat := _fall_material(Color(0.55, 0.6, 0.72, 0.6) if storm else Color(0.62, 0.68, 0.8, 0.65), false)
	streak_mat.distance_fade_min_distance = 1.5
	streak_mat.distance_fade_max_distance = 4.0
	streak.material = streak_mat
	drops.mesh = streak
	var rain := _on_gpu(drops)
	var sheets := _box_emitter(80 if storm else 50, 5.0)
	sheets.emission_box_extents = Vector3(FALL_AREA * 0.5, FALL_HEIGHT * 0.15, FALL_AREA * 0.5)
	sheets.direction = Vector3(wind.x, 0.0, wind.z).normalized()
	sheets.spread = 12.0
	sheets.initial_velocity_min = 6.0 if storm else 3.0
	sheets.initial_velocity_max = 9.0 if storm else 5.0
	sheets.gravity = Vector3.ZERO
	sheets.scale_amount_min = 0.8
	sheets.scale_amount_max = 1.5
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE * 4.0
	var puff_mat := _fall_material(Color(0.58, 0.62, 0.7, 0.2 if storm else 0.15), true)
	puff_mat.distance_fade_min_distance = 1.0
	puff_mat.distance_fade_max_distance = 4.0
	puff.material = puff_mat
	sheets.mesh = puff
	var mist := _on_gpu(sheets)
	mist.name = "Mist"
	# Down at head height and upwind, so the sheets drift past the camera.
	mist.position = -_fall_offset + Vector3(-FALL_AREA * 0.3 * signf(wind.x), -0.3, 0.0)
	rain.add_child(mist)
	mist.emitting = true
	return rain

## Snow falls slowly and drifts; blizzards and sandstorms drive it sideways.
func _flakes(amount: int, color: Color, fall: float, driven: bool) -> GPUParticles3D:
	var p := _box_emitter(amount, FALL_HEIGHT * 1.3 / fall if not driven else 3.5)
	p.direction = Vector3(1.0, -0.25, 0.3).normalized() if driven else Vector3.DOWN
	p.spread = 15.0 if driven else 25.0
	p.initial_velocity_min = (9.0 if driven else fall * 0.8)
	p.initial_velocity_max = (14.0 if driven else fall * 1.2)
	p.gravity = Vector3(0, -0.4, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	if driven:
		# Blown in from upwind, from head height up, so it streams past the camera.
		p.emission_box_extents = Vector3(FALL_AREA * 0.5, FALL_HEIGHT * 0.4, FALL_AREA * 0.5)
		_fall_offset = Vector3(-FALL_AREA * 0.6, FALL_HEIGHT * 0.35, -FALL_AREA * 0.2)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (0.07 if weather == Weather.SANDSTORM else 0.13)
	quad.material = _fall_material(color, true)
	p.mesh = quad
	return _on_gpu(p)

func _box_emitter(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(FALL_AREA * 0.5, 0.5, FALL_AREA * 0.5)
	p.gravity = Vector3(0, -2.0, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 1 << (WEATHER_LAYER - 1)
	# Particles live in world space, so the emitter's own bounds never cover them.
	p.visibility_aabb = AABB(Vector3(-FALL_AREA, -FALL_HEIGHT * 2.0, -FALL_AREA), Vector3(FALL_AREA * 2.0, FALL_HEIGHT * 3.0, FALL_AREA * 2.0))
	return p

## Built as CPUParticles3D for its simple setup, then run on the GPU: a
## thousand-plus particles (and their pre-simulated start) cost the CPU
## nothing that way.
func _on_gpu(cpu: CPUParticles3D) -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.convert_from_particles(cpu)
	gpu.preprocess = cpu.preprocess
	gpu.local_coords = false
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.layers = cpu.layers
	gpu.visibility_aabb = cpu.visibility_aabb
	cpu.free()
	return gpu

func _fall_material(color: Color, round: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	if round:
		mat.albedo_texture = GlowTexture.radial()
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
	SpellFx.fade_near_camera(mat)
	mat.distance_fade_min_distance = 0.3
	mat.distance_fade_max_distance = 1.5
	return mat

## The emitter rides above the camera; what has fallen stays where it fell.
func _follow_camera() -> void:
	if _fall == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera:
		_fall.global_position = camera.global_position + _fall_offset
