extends Node3D
class_name AlmightyArena
## The Sealed King's arena, built by PinnacleArena: a round plaza of white
## marble with a glowing star sigil inlaid at its heart, ringed by tall white
## pillars, with floating crystal shards between them and a skyline of pale
## spires beyond. When he awakens (Almighty, 50% Life) awaken() spreads black
## through the floor, turns the shards and the sigil dark and the sky black.

const RADIUS := 22.0
const BOSS_SPAWN := Vector3(0, 0.05, -9.0)
const PLAYER_SPAWN := Vector3(0, 0.1, 14.0)
const PORTAL_SPOT := Vector3(0, 0.1, 10.0)
const PILLARS := 14
const PILLAR_HEIGHT := 10.0
const PILLAR_RADIUS := 0.85
const SHARDS := 14
const SPIRES := 46
const SPIRE_RING := Vector2(55.0, 120.0)
const SIGIL_COLOR := Color(0.45, 0.75, 1.0)
const AWAKENED_SIGIL_COLOR := Color(0.62, 0.5, 0.95)
const SHARD_COLOR := Color(0.55, 0.82, 1.0)
const AWAKENED_SHARD_COLOR := Color(0.3, 0.22, 0.5)

const FLOOR_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 stone_color : source_color = vec3(0.5, 0.52, 0.56);
uniform vec3 vein_color : source_color = vec3(0.32, 0.35, 0.42);
uniform vec3 sigil_color : source_color = vec3(0.45, 0.75, 1.0);
uniform float sigil_radius = 8.0;
uniform float corruption = 0.0;
uniform float arena_radius = 22.0;

varying vec2 local_xz;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	local_xz = VERTEX.xz;
}

void fragment() {
	vec2 p = local_xz;
	float r = length(p);
	float ang = atan(p.x, p.y);

	// Marble: soft veins, then ring and radial seams between the slabs.
	float vein = smoothstep(0.46, 0.5, abs(fbm(p * 0.35) - 0.5) + 0.48);
	vec3 col = mix(stone_color, vein_color, (1.0 - vein) * 0.55);
	float ring_seam = 1.0 - smoothstep(0.03, 0.07, abs(fract(r / 3.5 + 0.5) - 0.5) * 3.5);
	float slab = 6.2832 / 24.0;
	float radial_seam = 1.0 - smoothstep(0.03, 0.07, abs(fract(ang / slab + 0.5) - 0.5) * slab * r);
	col *= 1.0 - 0.18 * max(ring_seam, radial_seam * step(sigil_radius + 1.5, r));

	// The sigil: a double ring with a five-pointed star inside.
	float d = abs(r - sigil_radius);
	d = min(d, abs(r - sigil_radius - 0.7));
	for (int i = 0; i < 5; i++) {
		float a0 = 6.2832 * float(i) / 5.0;
		float a1 = 6.2832 * float(i + 2) / 5.0;
		d = min(d, segment(p, sigil_radius * vec2(sin(a0), cos(a0)), sigil_radius * vec2(sin(a1), cos(a1))));
	}
	float sigil = 1.0 - smoothstep(0.06, 0.16, d);
	float halo = 1.0 - smoothstep(0.1, 0.9, d);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.6 - r * 0.4);

	// Corruption: black spreading out from the centre in ragged tongues.
	float reach = corruption * (arena_radius + 6.0);
	float edge = r - reach + (fbm(p * 0.25 + TIME * 0.05) - 0.5) * 9.0;
	float black = 1.0 - smoothstep(-0.5, 0.5, edge);
	col = mix(col, vec3(0.02, 0.02, 0.03), black * 0.94);
	float rim = (1.0 - smoothstep(0.0, 0.9, abs(edge))) * step(0.001, corruption);

	ALBEDO = mix(col, sigil_color, sigil * 0.8);
	EMISSION = sigil_color * (sigil * 2.2 + halo * 0.35) * pulse + vec3(0.35, 0.25, 0.6) * rim * 0.8;
	ROUGHNESS = mix(0.35, 0.8, black);
	SPECULAR = 0.4;
}
"""

var boss: Enemy
var awakened := false

var _floor_mat: ShaderMaterial
var _shard_mat: StandardMaterial3D
var _shards: Array[Node3D] = []
var _time := 0.0

func _ready() -> void:
	add_to_group("almighty_arena")
	_build_floor()
	_build_pillars()
	_build_shards()
	_build_skyline()

func bind_boss(b: Enemy) -> void:
	boss = b

func _process(delta: float) -> void:
	_time += delta
	for i in _shards.size():
		var s := _shards[i]
		s.position.y = s.get_meta("base_y") + sin(_time * 0.9 + i * 1.7) * 0.35
		s.rotation.y += delta * (0.4 + 0.05 * i)

## ---- Build ----------------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "MarbleFloor"
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS + 4.0
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS + 4.0
	disc.bottom_radius = RADIUS + 4.0
	disc.height = 1.0
	disc.radial_segments = 96
	mesh.mesh = disc
	mesh.position.y = -0.5
	_floor_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FLOOR_SHADER_CODE
	_floor_mat.shader = shader
	_floor_mat.set_shader_parameter("sigil_color", SIGIL_COLOR)
	_floor_mat.set_shader_parameter("arena_radius", RADIUS)
	mesh.material_override = _floor_mat
	body.add_child(mesh)

	# The city floor beyond the ring, a step down.
	var outer := MeshInstance3D.new()
	var plane := CylinderMesh.new()
	plane.top_radius = SPIRE_RING.y + 20.0
	plane.bottom_radius = plane.top_radius
	plane.height = 0.2
	plane.radial_segments = 48
	outer.mesh = plane
	outer.position.y = -1.6
	outer.material_override = _stone(Color(0.32, 0.34, 0.38), 0.9)
	add_child(outer)

## White pillars round the rim with an invisible ring wall just outside.
func _build_pillars() -> void:
	var white := _stone(Color(0.6, 0.61, 0.65), 0.55)
	var trim := _stone(Color(0.5, 0.52, 0.57), 0.5)
	for i in PILLARS:
		var angle := TAU * (i + 0.5) / PILLARS
		var at := Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 1.6)
		var pillar := StaticBody3D.new()
		pillar.name = "Pillar%d" % i
		add_child(pillar)
		pillar.position = at
		pillar.rotation.y = angle
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = PILLAR_RADIUS + 0.15
		shape.height = PILLAR_HEIGHT
		col.shape = shape
		col.position.y = PILLAR_HEIGHT / 2.0
		pillar.add_child(col)
		var shaft := CylinderMesh.new()
		shaft.top_radius = PILLAR_RADIUS * 0.88
		shaft.bottom_radius = PILLAR_RADIUS
		shaft.height = PILLAR_HEIGHT
		shaft.radial_segments = 20
		_add_mesh(pillar, shaft, white, Vector3(0, PILLAR_HEIGHT / 2.0, 0))
		var base := BoxMesh.new()
		base.size = Vector3(2.3, 0.6, 2.3)
		_add_mesh(pillar, base, trim, Vector3(0, 0.3, 0))
		var cap := BoxMesh.new()
		cap.size = Vector3(2.4, 0.5, 2.4)
		_add_mesh(pillar, cap, trim, Vector3(0, PILLAR_HEIGHT + 0.25, 0))
		# A glowing band a third of the way up, the sigil's colour.
		var band := CylinderMesh.new()
		band.top_radius = PILLAR_RADIUS + 0.04
		band.bottom_radius = PILLAR_RADIUS + 0.04
		band.height = 0.18
		band.radial_segments = 20
		var band_mesh := _add_mesh(pillar, band, null, Vector3(0, PILLAR_HEIGHT * 0.33, 0))
		band_mesh.material_override = _shard_material()
		band_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var wall := StaticBody3D.new()
		var ws := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * (RADIUS + 2.5) / PILLARS + 0.5, 8.0, 1.0)
		ws.shape = box
		wall.add_child(ws)
		add_child(wall)
		var wall_angle := TAU * i / PILLARS
		wall.position = Vector3(sin(wall_angle), 0, cos(wall_angle)) * (RADIUS + 2.5) + Vector3.UP * 4.0
		wall.rotation.y = wall_angle

## Crystal shards floating between the pillars.
func _build_shards() -> void:
	for i in SHARDS:
		var angle := TAU * i / SHARDS
		var shard := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.5, 1.6, 0.5)
		shard.mesh = prism
		shard.material_override = _shard_material()
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shard)
		shard.position = Vector3(sin(angle), 0, cos(angle)) * (RADIUS + 1.6) + Vector3.UP * (8.0 + 1.2 * sin(i * 2.3))
		shard.set_meta("base_y", shard.position.y)
		_shards.append(shard)

## Pale spires far out, the white city's skyline.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	var mats := [_stone(Color(0.55, 0.57, 0.62), 0.7), _stone(Color(0.46, 0.48, 0.54), 0.7)]
	for i in SPIRES:
		var angle := TAU * i / SPIRES + rng.randf_range(-0.05, 0.05)
		var dist := rng.randf_range(SPIRE_RING.x, SPIRE_RING.y)
		var height := rng.randf_range(14.0, 55.0) * (1.0 + (dist - SPIRE_RING.x) / SPIRE_RING.y)
		var width := rng.randf_range(3.0, 7.0)
		var spire := Node3D.new()
		add_child(spire)
		spire.position = Vector3(sin(angle), -1.6, cos(angle)) * Vector3(dist, 1.0, dist)
		spire.rotation.y = rng.randf() * TAU
		var tower := BoxMesh.new()
		tower.size = Vector3(width, height, width)
		var tower_mesh := _add_mesh(spire, tower, mats[i % 2], Vector3(0, height / 2.0, 0))
		tower_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tip := PrismMesh.new()
		tip.size = Vector3(width, width * 2.5, width)
		var tip_mesh := _add_mesh(spire, tip, mats[(i + 1) % 2], Vector3(0, height + width * 1.25, 0))
		tip_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi

func _stone(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

## One material shared by every shard and pillar band, so awaken() turns them all.
func _shard_material() -> StandardMaterial3D:
	if _shard_mat == null:
		_shard_mat = StandardMaterial3D.new()
		_shard_mat.albedo_color = SHARD_COLOR
		_shard_mat.emission_enabled = true
		_shard_mat.emission = SHARD_COLOR
		_shard_mat.emission_energy_multiplier = 2.5
		_shard_mat.roughness = 0.2
	return _shard_mat

## ---- Awakening ----------------------------------------------------------------

## Black spreads across the floor from the centre, the sigil and shards turn
## violet-dark, and the sky, fog and light go to night over `seconds`.
func awaken(seconds: float) -> void:
	if awakened:
		return
	awakened = true
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(v: float): _floor_mat.set_shader_parameter("corruption", v), 0.0, 1.0, seconds * 2.5)
	tween.tween_method(func(c: Color): _floor_mat.set_shader_parameter("sigil_color", c), SIGIL_COLOR, AWAKENED_SIGIL_COLOR, seconds)
	tween.tween_property(_shard_mat, "albedo_color", Color(0.05, 0.04, 0.08), seconds)
	tween.tween_property(_shard_mat, "emission", AWAKENED_SHARD_COLOR, seconds)
	var world := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world:
		var env := world.environment
		tween.tween_property(env, "ambient_light_color", Color(0.3, 0.27, 0.4), seconds)
		tween.tween_property(env, "ambient_light_energy", 0.55, seconds)
		tween.tween_property(env, "fog_light_color", Color(0.05, 0.04, 0.08), seconds)
		tween.tween_property(env, "fog_density", 0.012, seconds)
		var sky_mat: ShaderMaterial = env.sky.sky_material as ShaderMaterial if env.sky else null
		if sky_mat:
			var target: Dictionary = SkyBuilder.ARENA_SKIES["almighty_awakened"]
			for key in target:
				var from: Variant = sky_mat.get_shader_parameter(key)
				if from is float or from is Color or from is Vector3:
					tween.tween_method(func(v): sky_mat.set_shader_parameter(key, v), from, target[key], seconds)
	var sun := get_parent().get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun:
		tween.tween_property(sun, "light_color", Color(0.6, 0.6, 0.85), seconds)
		tween.tween_property(sun, "light_energy", ShadowLight.directional(0.9), seconds)
