extends RefCounted
class_name SkyBuilder
## Skies for maps and arenas: map_sky.gdshader with a preset of uniforms.
## Outdoor map families get a day sky whose horizon is the style's fog
## colour, so distant fog meets the sky; dungeons and dark styles keep their
## flat background.

const SHADER := preload("res://shaders/map_sky.gdshader")

## Per map family. horizon comes from the style (fog_color).
const FAMILY_SKIES := {
	"forest": {"zenith_color": Color(0.2, 0.42, 0.8), "sun_color": Color(1.0, 0.93, 0.78), "cloud_cover": 0.45,
		"cloud_shade": Color(0.58, 0.64, 0.74)},
	"desert": {"zenith_color": Color(0.22, 0.44, 0.82), "sun_color": Color(1.0, 0.88, 0.66), "sun_glow": 0.55, "sun_size": 0.03,
		"cloud_cover": 0.18, "cloud_shade": Color(0.78, 0.64, 0.52)},
	"snow": {"zenith_color": Color(0.4, 0.5, 0.64), "sun_color": Color(0.95, 0.96, 1.0), "sun_energy": 3.0, "sun_glow": 0.2,
		"cloud_cover": 0.68, "cloud_softness": 0.35, "cloud_color": Color(0.9, 0.92, 0.96), "cloud_shade": Color(0.55, 0.6, 0.68)},
	"city": {"zenith_color": Color(0.3, 0.36, 0.46), "sun_color": Color(1.0, 0.85, 0.65), "sun_energy": 4.0,
		"cloud_cover": 0.6, "cloud_color": Color(0.82, 0.78, 0.72), "cloud_shade": Color(0.42, 0.38, 0.36)},
	"pale": {"zenith_color": Color(0.66, 0.66, 0.68), "sun_color": Color(1.0, 1.0, 0.97), "sun_energy": 2.5, "sun_glow": 0.25,
		"sun_size": 0.05, "cloud_cover": 0.5, "cloud_color": Color(0.96, 0.95, 0.93), "cloud_shade": Color(0.7, 0.7, 0.7),
		"cloud_speed": 0.004},
}

## Set on every sky so MapAtmosphere can read them back (same as the shader's defaults).
const DEFAULTS := {
	"zenith_color": Color(0.18, 0.36, 0.72), "cloud_color": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.55, 0.6, 0.7),
	"cloud_cover": 0.45, "sun_energy": 6.0, "sun_glow": 0.35,
}

## Pinnacle arenas.
const ARENA_SKIES := {
	# Aurelia: a fel eclipse - a black sun in a violet corona, fel aurora, stars.
	"aurelia": {"zenith_color": Color(0.02, 0.0, 0.05), "horizon_color": Color(0.3, 0.06, 0.36),
		"ground_color": Color(0.02, 0.0, 0.04), "horizon_curve": 0.55,
		"sun_color": Color(0.8, 0.35, 1.0), "sun_size": 0.06, "sun_energy": 0.0, "sun_glow": 1.4, "sun_glow_tightness": 40.0,
		"cloud_cover": 0.32, "cloud_color": Color(0.34, 0.1, 0.42), "cloud_shade": Color(0.04, 0.0, 0.06), "cloud_opacity": 0.75,
		"star_amount": 0.9, "aurora_color": Color(0.75, 0.3, 1.0), "aurora_amount":  0.45,
		"follow_light": false, "sun_direction": Vector3(-0.2, 0.42, -1.0)},
	# Herald of the Maw: a violet storm wheeling round a black eye overhead.
	"maw": {"zenith_color": Color(0.02, 0.0, 0.04), "horizon_color": Color(0.3, 0.05, 0.34),
		"ground_color": Color(0.02, 0.0, 0.04), "horizon_curve": 0.6,
		"sun_energy": 0.0, "sun_glow": 0.0,
		"cloud_cover": 0.42, "cloud_color": Color(0.28, 0.05, 0.22), "cloud_shade": Color(0.05, 0.0, 0.07), "cloud_speed": 0.02,
		"vortex_color": Color(0.5, 0.06, 0.22), "vortex_amount": 1.0, "star_amount": 0.4},
	# The Sealed King: a cold silver noon over a white city.
	"almighty": {"zenith_color": Color(0.36, 0.5, 0.72), "horizon_color": Color(0.86, 0.9, 0.96),
		"ground_color": Color(0.6, 0.64, 0.7), "horizon_curve": 0.4,
		"sun_color": Color(0.9, 0.95, 1.0), "sun_size": 0.035, "sun_energy": 5.0, "sun_glow": 0.45, "sun_glow_tightness": 8.0,
		"cloud_cover": 0.5, "cloud_color": Color(0.97, 0.98, 1.0), "cloud_shade": Color(0.62, 0.68, 0.78), "cloud_speed": 0.006,
		"star_amount": 0.0, "vortex_color": Color(0.05, 0.0, 0.08), "vortex_amount": 0.0,
		"follow_light": false, "sun_direction": Vector3(0.3, 0.55, -1.0)},
	# The Almighty: the same sky gone black, a dark wheel turning overhead.
	"almighty_awakened": {"zenith_color": Color(0.0, 0.0, 0.01), "horizon_color": Color(0.12, 0.1, 0.16),
		"ground_color": Color(0.01, 0.01, 0.02), "horizon_curve": 0.4,
		"sun_color": Color(0.55, 0.6, 0.9), "sun_size": 0.035, "sun_energy": 0.0, "sun_glow": 0.9, "sun_glow_tightness": 30.0,
		"cloud_cover": 0.55, "cloud_color": Color(0.1, 0.09, 0.14), "cloud_shade": Color(0.0, 0.0, 0.0), "cloud_speed": 0.02,
		"star_amount": 0.2, "vortex_color": Color(0.32, 0.3, 0.45), "vortex_amount": 0.8,
		"follow_light": false, "sun_direction": Vector3(0.3, 0.55, -1.0)},
	# Ataras: desert dusk with a low, hot sun.
	"sand": {"zenith_color": Color(0.16, 0.18, 0.4), "horizon_color": Color(0.95, 0.56, 0.32),
		"ground_color": Color(0.35, 0.22, 0.14), "horizon_curve": 0.45,
		"sun_color": Color(1.0, 0.68, 0.38), "sun_size": 0.045, "sun_energy": 7.0, "sun_glow": 0.7, "sun_glow_tightness": 4.0,
		"cloud_cover": 0.36, "cloud_color": Color(1.0, 0.72, 0.52), "cloud_shade": Color(0.42, 0.24, 0.26), "star_amount": 0.25,
		"follow_light": false, "sun_direction": Vector3(0.35, 0.16, -1.0)},
}

static func make(params: Dictionary) -> Sky:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var all := DEFAULTS.merged(params, true)
	for key in all:
		mat.set_shader_parameter(key, all[key])
	var sky := Sky.new()
	sky.sky_material = mat
	# Clouds move with TIME; incremental radiance keeps that cheap.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	return sky

## The sky for a map style, or null when it should keep a flat background
## (dungeons and dark styles).
static func for_style(family: String, fog_color: Color, background_color: Color) -> Sky:
	if not FAMILY_SKIES.has(family) or background_color.get_luminance() < 0.2:
		return null
	var params: Dictionary = (FAMILY_SKIES[family] as Dictionary).duplicate()
	params["horizon_color"] = fog_color
	params["ground_color"] = fog_color.darkened(0.35)
	return make(params)

static func for_arena(id: String) -> Sky:
	return make(ARENA_SKIES[id])

## Puts `sky` behind `env` with a light fog veil, leaving its ambient light alone.
static func apply(env: Environment, sky: Sky, fog_sky_affect: float = 0.15) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_sky_affect = fog_sky_affect
