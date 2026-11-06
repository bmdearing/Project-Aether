class_name MapFog
## Map fog as depth fog with a clear zone around the player: nothing within
## CLEAR_RANGE is fogged, so enemies at fighting range keep their colour, and
## past it the fog ramps to full where an exponential fog of the same density
## would be ~80% (1.6 / density). Styles and weather still speak in
## exponential densities; this turns them into begin/end distances.

## Metres around the camera the fog never touches.
const CLEAR_RANGE := 14.0
const _DENSITY := &"_map_fog_density"

static func apply(env: Environment, density: float) -> void:
	env.set_meta(_DENSITY, density)
	if density <= 0.0:
		env.fog_enabled = false
		return
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0   # depth fog's maximum opacity
	env.fog_depth_begin = CLEAR_RANGE
	env.fog_depth_end = CLEAR_RANGE + 1.6 / density
	env.fog_depth_curve = 1.0

## The exponential density last applied (or the env's own for non-map envs).
static func density_of(env: Environment) -> float:
	if env.has_meta(_DENSITY):
		return float(env.get_meta(_DENSITY))
	return env.fog_density if env.fog_enabled else 0.0

## Distance at which the fog has all but swallowed things.
static func reach(env: Environment) -> float:
	if not env.fog_enabled:
		return INF
	if env.fog_mode == Environment.FOG_MODE_DEPTH:
		return env.fog_depth_end
	return 1.6 / maxf(env.fog_density, 0.0001)
