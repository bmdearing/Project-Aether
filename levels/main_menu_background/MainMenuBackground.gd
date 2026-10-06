extends Node3D
class_name MainMenuBackground
## Title-screen storm: a moonlit night over a dark lake, layered mountains
## with mist, a Dalaran spire on a crag, two layers of rain, and lightning
## that forks down onto the far range and lights the clouds, the lake and
## every ridge. Rain and thunder audio are synthesized (ProceduralRain/
## ProceduralThunder). Built in code inside MainMenu.tscn's SubViewport.
## The menu column sits on the left, so the moon, spire and strikes are
## kept right of centre.

const SKY_SHADER := preload("res://shaders/menu_storm_sky.gdshader")
const RIDGE_SHADER := preload("res://shaders/menu_ridge.gdshader")
const LAKE_SHADER := preload("res://shaders/menu_lake.gdshader")
const MIST_SHADER := preload("res://shaders/menu_mist.gdshader")
const SPIRE_SCENE := "res://entities/environment/doodads/nexus/DalaranvioletholdspireSmall.tscn"

const CAMERA_POS := Vector3(0.0, 6.0, 25.0)
const MOON_DIR := Vector3(0.36, 0.34, -0.87)
## Where the moon sits along x at the far mountains, for rim light and the lake path.
const MOON_X := 70.0

var _camera: Camera3D
var _moonlight: DirectionalLight3D
var _moonlight_energy := 0.0
var _sky_mat: ShaderMaterial
var _flash_mats: Array[ShaderMaterial] = []
var _bolt_mat: ShaderMaterial
var _bolt: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _time := 0.0

func _ready() -> void:
	_rng.seed = 7
	_build_environment()
	_build_camera()
	_build_sky()
	_build_lake()
	_build_ridges()
	_build_spire()
	_build_shore()
	_build_mist()
	_build_rain()
	_build_bolt()
	_build_audio()

func _process(delta: float) -> void:
	_time += delta
	if _camera:
		_camera.position = CAMERA_POS + Vector3(sin(_time * 0.05) * 2.0, sin(_time * 0.08) * 0.35, 0.0)
		_camera.rotation_degrees = Vector3(-2.5 + sin(_time * 0.06) * 0.3, sin(_time * 0.04) * 0.6, 0.0)

## ---- World -------------------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.14, 0.22)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.05, 0.085)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	world_env.environment = env
	add_child(world_env)

	_moonlight = DirectionalLight3D.new()
	_moonlight.light_color = Color(0.72, 0.78, 1.0)
	_moonlight.light_energy = 0.6
	_moonlight.look_at_from_position(Vector3.ZERO, -MOON_DIR, Vector3.UP)
	add_child(_moonlight)
	_moonlight_energy = _moonlight.light_energy

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.position = CAMERA_POS
	_camera.fov = 60.0
	_camera.far = 1200.0
	_camera.current = true
	add_child(_camera)

func _build_sky() -> void:
	var sky := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 900.0
	sphere.height = 1800.0
	sky.mesh = sphere
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter("moon_dir", MOON_DIR)
	sky.material_override = _sky_mat
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

func _build_lake() -> void:
	var lake := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 340)
	lake.mesh = plane
	lake.position = Vector3(0, 0, -150)
	var mat := _flash_material(LAKE_SHADER)
	mat.set_shader_parameter("moon_x", MOON_X)
	mat.set_shader_parameter("cam_pos", CAMERA_POS)
	lake.material_override = mat
	add_child(lake)

## Ridge layers back to front: the far range is lighter and mistier, the
## near ones darker with a stronger rim.
func _build_ridges() -> void:
	_ridge(900.0, -340.0, 95.0, 45.0, 3, Color(0.075, 0.085, 0.12), 0.45, 0.85, Vector3.ZERO)
	_ridge(760.0, -230.0, 58.0, 30.0, 11, Color(0.055, 0.062, 0.09), 0.6, 0.7, Vector3.ZERO)
	# The crag the spire stands on, right of centre.
	_ridge(320.0, -105.0, 9.0, 6.0, 21, Color(0.04, 0.045, 0.065), 0.8, 0.45, Vector3(60.0, 24.0, 18.0))

## A flat ridge strip facing the camera. bump = (x, height, width) adds a
## single crag.
func _ridge(width: float, z: float, height: float, variance: float, seed_value: int, color: Color, rim: float, mist: float, bump: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var segments := 90
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array[float] = []
	var h := height
	for i in segments + 1:
		h = lerpf(h, height + rng.randf_range(-variance, variance), 0.35)
		var x := -width / 2.0 + width * i / segments
		var crag := bump.y * exp(-pow((x - bump.x) / maxf(bump.z, 1.0), 2.0)) if bump != Vector3.ZERO else 0.0
		tops.append(h + crag + rng.randf_range(-variance, variance) * 0.08)
	var bottom := -20.0
	for i in segments:
		var x0 := -width / 2.0 + width * i / segments
		var x1 := -width / 2.0 + width * (i + 1) / segments
		var top_max := maxf(tops[i], tops[i + 1])
		var verts := [Vector3(x0, tops[i], 0), Vector3(x1, tops[i + 1], 0), Vector3(x1, bottom, 0), Vector3(x0, bottom, 0)]
		var uvs := []
		for v in verts:
			uvs.append(Vector2(0, (top_max - v.y) / (top_max - bottom)))
		uvs[0].y = 0.0
		uvs[1].y = 0.0
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = Vector3(0, 0, z)
	var mat := _flash_material(RIDGE_SHADER)
	mat.set_shader_parameter("rock", color)
	mat.set_shader_parameter("rim_strength", rim)
	mat.set_shader_parameter("mist_amount", mist)
	mat.set_shader_parameter("moon_x", MOON_X)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_spire() -> void:
	if not ResourceLoader.exists(SPIRE_SCENE):
		return
	var spire := (load(SPIRE_SCENE) as PackedScene).instantiate() as Node3D
	add_child(spire)
	spire.position = Vector3(60.0, 30.0, -106.0)
	spire.scale = Vector3.ONE * 1.6
	spire.rotation.y = 0.6
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 0.45, 1.0)
	glow.light_energy = 3.0
	glow.omni_range = 18.0
	glow.position = Vector3(60.0, 50.0, -100.0)
	add_child(glow)
	var lamp := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.6
	orb.height = 1.2
	lamp.mesh = orb
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(0.85, 0.6, 1.0) * 3.0
	lamp.material_override = orb_mat
	lamp.position = Vector3(60.0, 49.5, -105.0)
	add_child(lamp)

## Near shore under the menu column: a dark rise with pines.
func _build_shore() -> void:
	_ridge(160.0, -12.0, 5.0, 2.5, 33, Color(0.018, 0.02, 0.03), 0.35, 0.0, Vector3(-55.0, 9.0, 22.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 18:
		var tree := TreeSilhouette.new()
		var s := rng.randf_range(0.7, 1.5)
		tree.trunk_height = 1.0 * s
		tree.canopy_height = 6.0 * s
		tree.canopy_base_width = 2.2 * s
		tree.color = Color(0.012, 0.014, 0.02)
		tree.seed_value = 100 + i
		var x := rng.randf_range(-85.0, -15.0)
		tree.position = Vector3(x, 3.0 + 9.0 * exp(-pow((x + 55.0) / 22.0, 2.0)), -12.5 + rng.randf_range(-1.0, 1.0))
		add_child(tree)

func _build_mist() -> void:
	for m in [[Vector3(0, 8, -220), Vector2(700, 40), 0.35], [Vector3(40, 4, -100), Vector2(320, 18), 0.3], [Vector3(-20, 2.5, -40), Vector2(260, 9), 0.22]]:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = m[1]
		mi.mesh = quad
		var mat := _flash_material(MIST_SHADER)
		mat.set_shader_parameter("opacity", m[2])
		mat.set_shader_parameter("speed", _rng.randf_range(0.006, 0.015))
		mi.material_override = mat
		mi.position = m[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _flash_material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_flash_mats.append(mat)
	return mat

## ---- Rain --------------------------------------------------------------------

func _build_rain() -> void:
	_rain_layer(450, Vector3(0, 22, 8), Vector3(40, 1, 14), Vector2(0.035, 1.3), 0.32, 30.0)
	_rain_layer(1600, Vector3(10, 60, -90), Vector3(170, 1, 90), Vector2(0.06, 2.4), 0.16, 42.0)

func _rain_layer(amount: int, pos: Vector3, extents: Vector3, size: Vector2, alpha: float, speed: float) -> void:
	var rain := CPUParticles3D.new()
	rain.amount = amount
	rain.lifetime = 2.6
	rain.preprocess = 2.6
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = extents
	rain.position = pos
	rain.direction = Vector3(0.18, -1.0, 0.0)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -12, 0)
	rain.initial_velocity_min = speed * 0.85
	rain.initial_velocity_max = speed
	rain.particle_flag_align_y = true
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.76, 0.9, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	rain.mesh = quad
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

## ---- Lightning ---------------------------------------------------------------

func _build_bolt() -> void:
	_bolt = MeshInstance3D.new()
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = preload("res://shaders/menu_bolt.gdshader")
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bolt)

## A jagged bolt from the clouds down to the far range, with a few forks,
## as flat quads facing the camera.
func _make_bolt(start: Vector3, ground_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bolt_branch(st, start, ground_y, 3.2, 0)
	return st.commit()

func _bolt_branch(st: SurfaceTool, start: Vector3, end_y: float, width: float, depth: int) -> void:
	var p := start
	var steps := 14 if depth == 0 else 6
	var dy := (start.y - end_y) / steps
	for i in steps:
		var next := p + Vector3(_rng.randf_range(-1.0, 1.0) * dy * 0.55, -dy * _rng.randf_range(0.7, 1.2), 0.0)
		if i == steps - 1 and depth == 0:
			next.y = end_y
		var w := width * (1.0 - float(i) / steps * 0.6)
		var side := Vector3(-(next - p).normalized().y, (next - p).normalized().x, 0) * w * 0.5
		for v in [p - side, p + side, next + side, p - side, next + side, next - side]:
			st.add_vertex(v)
		if depth < 2 and _rng.randf() < 0.22:
			_bolt_branch(st, next, next.y - dy * _rng.randf_range(2.0, 4.0), width * 0.45, depth + 1)
		p = next

func _strike() -> Vector3:
	var x := _rng.randf_range(-20.0, 190.0)
	var z := -320.0
	_bolt.mesh = _make_bolt(Vector3(x, 230.0, z), 95.0)
	var t := create_tween()
	for level in [1.0, 0.15, 0.9, 0.3]:
		t.tween_method(_set_bolt, level, level, 0.05)
	t.tween_method(_set_bolt, 0.6, 0.0, 0.3)
	return (Vector3(x, 160.0, z) - CAMERA_POS).normalized()

func _set_bolt(level: float) -> void:
	_bolt_mat.set_shader_parameter("intensity", level)

## ---- Audio & flashes ---------------------------------------------------------

func _build_audio() -> void:
	add_child(ProceduralRain.new())
	var thunder := ProceduralThunder.new()
	thunder.min_interval_sec = 6.0
	thunder.max_interval_sec = 15.0
	add_child(thunder)
	thunder.thunder_started.connect(_on_thunder_started)

func _on_thunder_started() -> void:
	var dir := _strike()
	_sky_mat.set_shader_parameter("flash_dir", dir)
	_flash_once(1.0, 0.7)
	var flicker := create_tween()
	flicker.tween_interval(0.12)
	flicker.tween_callback(func(): _flash_once(0.6, 0.4))

func _flash_once(peak: float, fall: float) -> void:
	create_tween().tween_method(_set_flash, peak, 0.0, fall).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_moonlight.light_energy = _moonlight_energy + 2.0 * peak
	create_tween().tween_property(_moonlight, "light_energy", _moonlight_energy, fall).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _set_flash(value: float) -> void:
	_sky_mat.set_shader_parameter("flash", value)
	for mat in _flash_mats:
		mat.set_shader_parameter("flash", value * 0.6)
