extends Node3D
class_name MainMenuBackground
## Procedural night-storm backdrop for the Main Menu: mountains, a
## shader-driven night sky, rain particles, and rain/thunder audio
## synthesized at runtime (ProceduralRain/ProceduralThunder) - no
## external art or audio assets anywhere, matching the rest of the
## project's placeholder-art convention. Built entirely in code rather
## than scene-authored, so it can live as a single node inside
## MainMenu.tscn's SubViewport without a second .tscn file.

const NIGHT_SKY_SHADER := preload("res://shaders/night_sky.gdshader")

var _sky_material: ShaderMaterial
var _moonlight: DirectionalLight3D

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_sky()
	_build_mountains()
	_build_rain()
	_build_audio()

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.14)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.1)
	env.fog_density = 0.01
	env.fog_sky_affect = 0.0
	world_env.environment = env
	add_child(world_env)

	_moonlight = DirectionalLight3D.new()
	_moonlight.light_color = Color(0.7, 0.75, 0.95)
	_moonlight.light_energy = 0.4
	_moonlight.rotation_degrees = Vector3(-40.0, 25.0, 0.0)
	_moonlight.shadow_enabled = false
	add_child(_moonlight)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 6.0, 25.0)
	camera.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
	camera.fov = 60.0
	camera.current = true
	add_child(camera)

func _build_sky() -> void:
	var sky_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 400.0
	sphere.height = 800.0
	sphere.flip_faces = true
	sky_mesh.mesh = sphere
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = NIGHT_SKY_SHADER
	sky_mesh.material_override = _sky_material
	sky_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky_mesh)

func _build_mountains() -> void:
	var far := MountainRange.new()
	far.width = 700.0
	far.base_height = 70.0
	far.peak_variance = 30.0
	far.color = Color(0.05, 0.06, 0.09)
	far.seed_value = 1
	far.position = Vector3(0.0, -35.0, -260.0)
	add_child(far)

	var near := MountainRange.new()
	near.width = 550.0
	near.base_height = 42.0
	near.peak_variance = 20.0
	near.color = Color(0.08, 0.09, 0.13)
	near.seed_value = 7
	near.position = Vector3(0.0, -30.0, -130.0)
	add_child(near)

func _build_rain() -> void:
	var rain := CPUParticles3D.new()
	rain.amount = 900
	rain.lifetime = 1.1
	rain.emitting = true
	rain.local_coords = true
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(90.0, 1.0, 90.0)
	rain.position = Vector3(0.0, 45.0, -80.0)
	rain.direction = Vector3(0.15, -1.0, 0.0)
	rain.spread = 4.0
	rain.gravity = Vector3(0.0, -28.0, 0.0)
	rain.initial_velocity_min = 14.0
	rain.initial_velocity_max = 20.0

	var streak := BoxMesh.new()
	streak.size = Vector3(0.025, 0.55, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.65, 0.72, 0.85, 0.35)
	streak.material = mat
	rain.mesh = streak
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(rain)

func _build_audio() -> void:
	add_child(ProceduralRain.new())

	var thunder := ProceduralThunder.new()
	add_child(thunder)
	thunder.thunder_started.connect(_on_thunder_started)

func _on_thunder_started() -> void:
	var flash_tween := create_tween()
	flash_tween.tween_method(_set_flash, 1.0, 0.0, 0.6) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if _moonlight:
		var base_energy := _moonlight.light_energy
		_moonlight.light_energy = base_energy + 2.5
		var light_tween := create_tween()
		light_tween.tween_property(_moonlight, "light_energy", base_energy, 0.5) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _set_flash(value: float) -> void:
	if _sky_material:
		_sky_material.set_shader_parameter("flash_intensity", value)
