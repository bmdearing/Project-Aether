extends Node3D
class_name PinnacleArena
## First Pinnacle boss arena: a crescent with the boss in its belly and an
## invisible boundary wall. Spawns the Player, the Lord of the Elements and
## the UI suite itself (same order as GeneratedMap), so it runs standalone
## (F6). Nothing in the game routes here yet.
##
## Built procedurally in code rather than hand-authored in the .tscn -
## same convention GeneratedMap.gd already uses for its own floor/wall
## geometry - since a crescent/lune shape isn't expressible with this
## project's usual BoxShape3D-per-piece approach. CSGShape3D (a Boolean
## geometry op that also generates matching collision via use_collision)
## is the first CSG usage in the project; every other level's floor is a
## simple plane/box.
##
## Crescent construction: two same-radius circles (OUTER_RADIUS/
## CUT_RADIUS), one centered at the origin, one offset along +Z by
## CUT_OFFSET - subtracting the offset one from the origin one leaves a
## lune/crescent sliver on the -Z side. A small CUT_OFFSET relative to
## OUTER_RADIUS means the two circles mostly coincide, which is what
## makes the remaining sliver thin and uniformly curved rather than a
## fat D-shape with one flat-ish bite taken out of it.

const OUTER_RADIUS := 26.0
const CUT_RADIUS := 26.0
const CUT_OFFSET := 9.0
const FLOOR_THICKNESS := 1.0
const WALL_HEIGHT := 6.0
## How far outside the floor's own outer edge / inside its own inner
## (cutout) edge the invisible boundary wall sits - not exactly on the
## edge, so a player's collision capsule doesn't clip through it right at
## the lip.
const WALL_MARGIN := 1.5
## CSGCylinder3D defaults to a low-poly side count (8) - fine for an
## octagonal pillar, but it renders our "circles" as visibly angular
## chevrons/wedges instead of a smooth curve (caught by screenshotting a
## first attempt at this arena - looked like a sharp-angled roof, not a
## crescent). Every cylinder below sets this explicitly.
const CSG_SIDES := 64

## Roughly the crescent's own belly point (farthest from the cutout,
## opposite CUT_OFFSET's direction) - not exact, just a reasonable spot
## on the walkable band for a boss placeholder marker.
const BOSS_SPAWN_LOCAL := Vector3(0, 0.05, -(OUTER_RADIUS - CUT_OFFSET * 0.5))
## One end of the crescent band - a reasonable default player entry point
## for whenever this arena gets wired into the game's actual flow.
const PLAYER_SPAWN_LOCAL := Vector3(OUTER_RADIUS * 0.6, 0.1, -OUTER_RADIUS * 0.55)

const PLAYER_SCENE := preload("res://entities/player/Player.tscn")
const BOSS_SCENES: Array[PackedScene] = [
	preload("res://entities/enemies/lord_of_the_elements/LordOfTheElements.tscn"),
	preload("res://entities/enemies/xalatath/Xalatath.tscn"),
]

const FLOOR_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 crack_color : source_color = vec3(1.0, 0.35, 0.05);
uniform vec3 stone_color : source_color = vec3(0.09, 0.07, 0.075);
uniform float crack_scale = 6.0;
uniform float pulse_speed = 1.2;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float voronoi_edge(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float min_dist = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = neighbor + vec2(hash(cell + neighbor), hash(cell + neighbor + 17.0)) - f;
			min_dist = min(min_dist, length(point));
		}
	}
	return min_dist;
}

void fragment() {
	vec2 uv = UV * crack_scale;
	float edge = voronoi_edge(uv);
	float crack = 1.0 - smoothstep(0.0, 0.06, edge);
	float pulse = 0.6 + 0.4 * sin(TIME * pulse_speed + UV.x * 3.0 + UV.y * 3.0);
	ALBEDO = mix(stone_color, crack_color, crack);
	EMISSION = crack_color * crack * pulse * 1.8;
	ROUGHNESS = 0.85;
}
"""

func _ready() -> void:
	GameState.initialize_standalone()
	_build_environment()
	_build_lighting()
	_build_floor()
	_build_boundary_walls()
	_build_spawn_markers()
	_build_embers()
	_spawn_player()
	_spawn_boss()
	_spawn_ui()  # after the Player, so the UI's player-group lookups succeed

func _spawn_player() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = $PlayerSpawnPoint.global_position
	player.look_at(Vector3(BOSS_SPAWN_LOCAL.x, player.global_position.y, BOSS_SPAWN_LOCAL.z))

func _spawn_boss() -> void:
	var boss: Enemy = BOSS_SCENES.pick_random().instantiate()
	boss.rank = Constants.EnemyRank.BOSS
	add_child(boss)
	boss.global_position = $BossSpawnPoint.global_position

func _spawn_ui() -> void:
	for scene in GeneratedMap.UI_SCENES:
		add_child(scene.instantiate())

func _build_environment() -> void:
	# First pass at this was unplayably dark (verified by screenshot, not
	# just guessed at) - "terrifying" needs to read as strong CONTRAST
	# between dark stone and glowing cracks/embers, not a scene so dim the
	# floor itself is barely visible. Brightened ambient/key light and
	# thinned the fog considerably from the first attempt.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.015, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.16, 0.12)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.35, 0.08, 0.04)
	env.fog_light_energy = 0.5
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.light_color = Color(0.9, 0.45, 0.3)
	light.light_energy = 1.4
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-55, 35, 0)
	add_child(light)

	# A dim, low, red glow near the boss spot - keeps the floor's cracks
	# readable near the arena's focal point without washing out the
	# darkness the ambient/fog settings above are going for.
	var underlight := OmniLight3D.new()
	underlight.name = "EmberGlow"
	underlight.position = BOSS_SPAWN_LOCAL + Vector3(0, 2.5, 0)
	underlight.light_color = Color(1.0, 0.35, 0.1)
	underlight.light_energy = 4.0
	underlight.omni_range = 32.0
	add_child(underlight)

func _build_floor() -> void:
	var root := CSGCombiner3D.new()
	root.name = "Floor"
	root.use_collision = true
	add_child(root)

	var outer := CSGCylinder3D.new()
	outer.name = "OuterDisc"
	outer.radius = OUTER_RADIUS
	outer.height = FLOOR_THICKNESS
	outer.sides = CSG_SIDES
	outer.position.y = -FLOOR_THICKNESS / 2.0
	outer.operation = CSGShape3D.OPERATION_UNION
	root.add_child(outer)

	var cut := CSGCylinder3D.new()
	cut.name = "InnerCut"
	cut.radius = CUT_RADIUS
	cut.height = FLOOR_THICKNESS * 3.0
	cut.sides = CSG_SIDES
	cut.position = Vector3(0, -FLOOR_THICKNESS / 2.0, CUT_OFFSET)
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_child(cut)

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FLOOR_SHADER_CODE
	mat.shader = shader
	outer.material = mat

func _build_boundary_walls() -> void:
	var root := CSGCombiner3D.new()
	root.name = "Boundary"
	root.use_collision = true
	root.visible = false  # collision-only - "an invisible wall" per the request

	# Outer ring: a tall hollow cylinder tracing OUTER_RADIUS's full
	# circumference. Full 360 degrees rather than just the crescent's own
	# outer arc - the extra wall length past the crescent's ends has no
	# floor near it and is never in the player's way, but building it as
	# a full ring is far simpler than tracing the exact lune boundary.
	var outer_solid := CSGCylinder3D.new()
	outer_solid.radius = OUTER_RADIUS + WALL_MARGIN
	outer_solid.height = WALL_HEIGHT
	outer_solid.sides = CSG_SIDES
	outer_solid.position.y = WALL_HEIGHT / 2.0
	outer_solid.operation = CSGShape3D.OPERATION_UNION
	root.add_child(outer_solid)

	var outer_hollow := CSGCylinder3D.new()
	outer_hollow.radius = OUTER_RADIUS
	outer_hollow.height = WALL_HEIGHT * 1.5
	outer_hollow.sides = CSG_SIDES
	outer_hollow.position.y = WALL_HEIGHT / 2.0
	outer_hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_child(outer_hollow)

	# Inner (cutout) ring: same idea, tracing the boundary of the circle
	# that was subtracted from the floor - stops players walking off the
	# crescent's inner edge into the cutout.
	var inner_solid := CSGCylinder3D.new()
	inner_solid.radius = CUT_RADIUS
	inner_solid.height = WALL_HEIGHT
	inner_solid.sides = CSG_SIDES
	inner_solid.position = Vector3(0, WALL_HEIGHT / 2.0, CUT_OFFSET)
	inner_solid.operation = CSGShape3D.OPERATION_UNION
	root.add_child(inner_solid)

	var inner_hollow := CSGCylinder3D.new()
	inner_hollow.radius = CUT_RADIUS - WALL_MARGIN
	inner_hollow.height = WALL_HEIGHT * 1.5
	inner_hollow.sides = CSG_SIDES
	inner_hollow.position = Vector3(0, WALL_HEIGHT / 2.0, CUT_OFFSET)
	inner_hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_child(inner_hollow)

	add_child(root)

func _build_spawn_markers() -> void:
	var boss_marker := Marker3D.new()
	boss_marker.name = "BossSpawnPoint"
	boss_marker.position = BOSS_SPAWN_LOCAL
	add_child(boss_marker)

	var player_marker := Marker3D.new()
	player_marker.name = "PlayerSpawnPoint"
	player_marker.position = PLAYER_SPAWN_LOCAL
	add_child(player_marker)

func _build_embers() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Embers"
	particles.position = Vector3(0, 0.2, 0)
	particles.amount = 80
	particles.lifetime = 4.0
	particles.visibility_aabb = AABB(
		Vector3(-OUTER_RADIUS, 0, -OUTER_RADIUS - CUT_OFFSET),
		Vector3(OUTER_RADIUS * 2.0, 12.0, OUTER_RADIUS * 2.0 + CUT_OFFSET)
	)

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0, 1, 0)
	process_mat.spread = 20.0
	process_mat.gravity = Vector3(0, 0.4, 0)
	process_mat.initial_velocity_min = 0.5
	process_mat.initial_velocity_max = 1.5
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.15
	process_mat.color = Color(1.0, 0.4, 0.1)
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(OUTER_RADIUS, 0.1, OUTER_RADIUS)
	particles.process_material = process_mat

	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.05
	ember_mesh.height = 0.1
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(1.0, 0.5, 0.15)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.4, 0.1)
	ember_mat.emission_energy_multiplier = 3.0
	ember_mesh.material = ember_mat
	particles.draw_pass_1 = ember_mesh

	add_child(particles)
