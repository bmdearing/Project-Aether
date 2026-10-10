extends Node3D
class_name PinnacleArena
## Pinnacle boss arena. For the Lord of the Elements: a crescent with the
## boss in its belly and an invisible boundary wall. For the Herald of the
## Maw: a MawArena (round floor over the void, Anchor pylons) instead.
## Spawns the Player, the chosen Pinnacle boss and the UI suite itself (same order as GeneratedMap), so it runs standalone
## (F6). Reached from the Reality Engine with a full set of Maw Fragments
## (Pinnacle.enter() picks the boss); killing it opens a portal to the Hub.
##
## The crescent is CSG (with use_collision): a circle at the origin minus
## one offset along +Z by CUT_OFFSET, leaving a thin lune on the -Z side.

const OUTER_RADIUS := 26.0
const CUT_RADIUS := 26.0
## The cut circle's offset sets how thick the crescent is (14m at its middle).
const CUT_OFFSET := 14.0
const FLOOR_THICKNESS := 1.0
const WALL_HEIGHT := 6.0
## Boundary wall offset past the floor's edges.
const WALL_MARGIN := 1.5
## CSGCylinder3D's default 8 sides makes the circles visibly angular.
const CSG_SIDES := 64

## Walking bosses start in the crescent's belly; a hovering one (the Lord of
## the Elements) floats in the empty bay, BAY_DEPTH past the inner edge.
const BOSS_SPAWN_LOCAL := Vector3(0, 0.05, -(OUTER_RADIUS + CUT_RADIUS - CUT_OFFSET) * 0.5)
const BAY_DEPTH := 2.6
const BAY_SPAWN_LOCAL := Vector3(0, 0.6, CUT_OFFSET - CUT_RADIUS + BAY_DEPTH)
## The invisible edge wall blocks bodies, not shots: it sits on its own
## layer, which the player and enemies collide with but projectiles don't.
const BARRIER_LAYER := 2
## Sigil spots sit on the band's midline at these angles from -Z.
const SIGIL_ANGLES_DEG: Array[float] = [-64.0, -42.0, -21.0, 0.0, 21.0, 42.0, 64.0]
const SIGIL_MIN_SPACING := 9.0
## One end of the crescent band: where the player enters.
const PLAYER_SPAWN_LOCAL := Vector3(OUTER_RADIUS * 0.6, 0.1, -OUTER_RADIUS * 0.55)

const PLAYER_SCENE := preload("res://entities/player/Player.tscn")
## The portal home appears this far in front of the player spawn.
const PORTAL_OFFSET := Vector3(0, 0, 3.0)

## Pinnacle.BOSSES id of the boss this arena is for.
const MAW_BOSS_ID := "herald_of_the_maw"
const SAND_BOSS_ID := "ataras"

var boss: Enemy
## The Herald's layout, built instead of the crescent (null for the Lord).
var maw: MawArena
var sand: SandArena
var _boss_id := ""
var _floor_mat: ShaderMaterial
var _ember_process: ParticleProcessMaterial
var _ember_mat: StandardMaterial3D

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
	child_entered_tree.connect(_on_child_entered)
	_boss_id = _take_boss_id()
	_build_environment()
	_build_lighting()
	if _boss_id == MAW_BOSS_ID:
		_build_maw()
	elif _boss_id == SAND_BOSS_ID:
		_build_sand()
	else:
		_build_floor()
		_build_boundary_walls()
		_build_spawn_markers(BOSS_SPAWN_LOCAL, PLAYER_SPAWN_LOCAL)
	_build_embers()
	_spawn_player()
	_spawn_boss()
	_spawn_ui()  # after the Player, so the UI's player-group lookups succeed

func _spawn_player() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = $PlayerSpawnPoint.global_position
	var focus := to_global(Vector3.ZERO if maw or sand else BAY_SPAWN_LOCAL)
	player.look_at(Vector3(focus.x, player.global_position.y, focus.z))

## GameState.pending_pinnacle's boss, or a random one when run standalone.
func _take_boss_id() -> String:
	var boss_id := GameState.pending_pinnacle
	if not Pinnacle.BOSSES.has(boss_id):
		boss_id = Pinnacle.BOSSES.keys().pick_random()
	GameState.pending_pinnacle = ""
	return boss_id

func _spawn_boss() -> void:
	boss = (load(Pinnacle.BOSSES[_boss_id]["scene"]) as PackedScene).instantiate()
	boss.rank = Constants.EnemyRank.BOSS
	if boss is PinnacleBoss:
		(boss as PinnacleBoss).pinnacle_id = _boss_id
	add_child(boss)
	boss.global_position = to_global(BAY_SPAWN_LOCAL) if boss.immovable else $BossSpawnPoint.global_position
	if boss.has_signal("element_changed"):
		boss.element_changed.connect(_on_element_changed)
		_on_element_changed(boss.get("current_element"))
	if maw:
		maw.bind_boss(boss)
		_on_element_changed(Constants.DamageType.ENTROPIC)
	if sand:
		sand.bind_boss(boss)
	boss.health.died.connect(_on_boss_died)

## A portal home appears by the entry once the boss falls (on the Maw's
## inner ring, which never falls).
func _on_boss_died() -> void:
	var portal := Portal.new()
	portal.destination = Portal.Destination.HUB
	portal.taken.connect(_go_home)
	add_child(portal)
	portal.global_position = to_global(MawArena.PORTAL_SPOT) if maw else (to_global(SandArena.PORTAL_SPOT) if sand else $PlayerSpawnPoint.global_position + PORTAL_OFFSET)

func _go_home() -> void:
	SaveManager.save_game()
	get_tree().paused = false
	LoadingScreen.change_scene(GameState.HUB_SCENE)

func _spawn_ui() -> void:
	for scene in GeneratedMap.UI_SCENES:
		add_child(scene.instantiate())

func _build_environment() -> void:
	# Neutral and dark, so colour comes from the Lord's orbs, the cracks and
	# the sigils rather than the room tinting everything one hue.
	var env := Environment.new()
	# A faint violet horizon behind the dark sky so the Lord stands out.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.025, 0.025, 0.07)
	sky_mat.sky_horizon_color = Color(0.17, 0.11, 0.26)
	sky_mat.ground_horizon_color = Color(0.1, 0.07, 0.16)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.03)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.35, 0.46)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.09, 0.16)
	env.fog_light_energy = 0.5
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	# Tight glow only: the wide levels turned small orb halos into big discs.
	for level in 7:
		env.set_glow_level(level, 1.0 if level < 2 else 0.0)
	env.glow_bloom = 0.0  # bloom on everything blew orb halos up into blobs
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.light_color = Color(0.86, 0.86, 1.0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-55, 35, 0)
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(light)

	# A soft white key on the bay, so the Lord reads in his own colours.
	var key := OmniLight3D.new()
	key.name = "BayLight"
	key.position = BAY_SPAWN_LOCAL + Vector3(0, 4.0, -6.0)
	key.light_color = Color(0.9, 0.9, 1.0)
	key.light_energy = 2.4
	key.omni_range = 18.0
	add_child(key)

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
	_floor_mat = mat
	var shader := Shader.new()
	shader.code = FLOOR_SHADER_CODE
	mat.shader = shader
	outer.material = mat

func _build_boundary_walls() -> void:
	var root := CSGCombiner3D.new()
	root.name = "Boundary"
	root.use_collision = true
	root.visible = false  # collision-only - "an invisible wall" per the request
	root.collision_layer = BARRIER_LAYER
	root.collision_mask = 0

	# Outer ring: a full hollow cylinder, simpler than tracing the lune.
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

	# Inner ring around the cutout circle.
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

func _build_spawn_markers(boss_spawn: Vector3, player_spawn: Vector3) -> void:
	var boss_marker := Marker3D.new()
	boss_marker.name = "BossSpawnPoint"
	boss_marker.position = boss_spawn
	add_child(boss_marker)

	var player_marker := Marker3D.new()
	player_marker.name = "PlayerSpawnPoint"
	player_marker.position = player_spawn
	add_child(player_marker)

## The Herald of the Maw's round floor, pylons and Maw (MawArena), with no
## edge wall: falling off kills.
func _build_maw() -> void:
	maw = MawArena.new()
	maw.name = "MawArena"
	add_child(maw)
	_build_spawn_markers(MawArena.BOSS_SPAWN, MawArena.PLAYER_SPAWN)
	var key := get_node("BayLight") as OmniLight3D
	key.position = Vector3(0, 9.0, 0)
	key.omni_range = 30.0
	key.light_energy = 1.6

## Ataras's sand arena (SandArena): a round sand floor ringed by rock, lit
## warm like a desert evening.
func _build_sand() -> void:
	sand = SandArena.new()
	sand.name = "SandArena"
	add_child(sand)
	_build_spawn_markers(SandArena.BOSS_SPAWN, SandArena.PLAYER_SPAWN)
	var key := get_node("BayLight") as OmniLight3D
	key.position = Vector3(0, 12.0, 0)
	key.omni_range = 40.0
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.82, 0.6)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 30, 0)
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

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
	_ember_process = process_mat
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
	_ember_mat = ember_mat
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(1.0, 0.5, 0.15)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.4, 0.1)
	ember_mat.emission_energy_multiplier = 3.0
	ember_mesh.material = ember_mat
	particles.draw_pass_1 = ember_mesh

	add_child(particles)

## Bosses and the player collide with the edge wall's layer; shots don't.
func _on_child_entered(node: Node) -> void:
	if node is CharacterBody3D:
		node.collision_mask |= BARRIER_LAYER

## The floor's cracks and the embers take the Lord's current element.
func _on_element_changed(element: int) -> void:
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(element, Color(1.0, 0.35, 0.05))
	if _floor_mat:
		var current: Variant = _floor_mat.get_shader_parameter("crack_color")
		var from: Color = current if current is Color else Color(1.0, 0.35, 0.05)  # the shader default until first set
		var tween := create_tween()
		tween.tween_method(func(c: Color): _floor_mat.set_shader_parameter("crack_color", c), from, color, 0.6)
	if _ember_process:
		_ember_process.color = color
	if _ember_mat:
		_ember_mat.albedo_color = color.lightened(0.2)
		_ember_mat.emission = color

## Up to `count` sigil spots on the crescent's midline, spread apart, for the
## Lord of the Elements' orbs (LordOfTheElements.place_sigils()).
func sigil_spots(count: int) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	for angle in SIGIL_ANGLES_DEG:
		candidates.append(to_global(band_midpoint(deg_to_rad(angle))))
	candidates.shuffle()
	var chosen: Array[Vector3] = []
	for c in candidates:
		if chosen.size() >= count:
			break
		if chosen.all(func(o: Vector3): return o.distance_to(c) >= SIGIL_MIN_SPACING):
			chosen.append(c)
	return chosen

## Where the Lord of the Elements comes down in phase 3: the crescent's
## middle, straight out from his bay.
func lord_landing_spot() -> Vector3:
	return to_global(band_midpoint(0.0) + Vector3(0, 0.05, 0))

## The middle of the crescent's band along the direction `angle` from -Z.
static func band_midpoint(angle: float) -> Vector3:
	var dir := Vector3(sin(angle), 0.0, -cos(angle))
	var centre := Vector3(0, 0, CUT_OFFSET)
	var b := dir.dot(centre)
	var inner := b + sqrt(b * b - centre.length_squared() + CUT_RADIUS * CUT_RADIUS)
	return dir * (inner + OUTER_RADIUS) * 0.5
