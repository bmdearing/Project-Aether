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
## Unshaded flat-color materials (mountains AND trees) don't react to
## _moonlight's own energy pulse at all - a lightning flash used to be
## sky-only and easy to miss (user-reported: "I haven't seen lightning
## flashes"). Tracked here so _on_thunder_started() can brighten every
## silhouette layer's own albedo directly, on top of the sky/moonlight.
var _silhouette_materials: Array[StandardMaterial3D] = []
var _silhouette_base_colors: Array[Color] = []
var _moonlight_base_energy: float = 0.0

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_sky()
	_build_mountains()
	_build_trees()
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
	_moonlight_base_energy = _moonlight.light_energy

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
	_register_silhouette(far)

	var near := MountainRange.new()
	near.width = 550.0
	near.base_height = 42.0
	near.peak_variance = 20.0
	near.color = Color(0.08, 0.09, 0.13)
	near.seed_value = 7
	near.position = Vector3(0.0, -30.0, -130.0)
	add_child(near)
	_register_silhouette(near)

## User request: "add trees to the landscape... make it more interesting."
## A foreground silhouette band, closer to the camera than either
## mountain layer, adding a 3rd depth step to the existing far/near
## mountain parallax instead of the camera looking straight past bare
## ridgelines at nothing. Same cheap flat-facing-camera trick as
## MountainRange - see TreeSilhouette.gd.
const TREE_COUNT := 22
const TREE_BAND_WIDTH := 480.0
const TREE_BAND_Z := -55.0
const TREE_BAND_Z_JITTER := 12.0

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(TREE_COUNT):
		var tree := TreeSilhouette.new()
		var scale_factor := rng.randf_range(0.6, 1.3)
		tree.trunk_height = 1.2 * scale_factor
		tree.canopy_height = 5.5 * scale_factor
		tree.canopy_base_width = 2.4 * scale_factor
		# Darker/bluer than the near mountain range so it reads as the
		# closest, most silhouetted layer against the lighter sky/mountains
		# behind it.
		tree.color = Color(0.02, 0.022, 0.03)
		tree.seed_value = 100 + i
		var x := rng.randf_range(-TREE_BAND_WIDTH / 2.0, TREE_BAND_WIDTH / 2.0)
		var z := TREE_BAND_Z + rng.randf_range(-TREE_BAND_Z_JITTER, TREE_BAND_Z_JITTER)
		tree.position = Vector3(x, -6.0, z)
		add_child(tree)
		_register_silhouette(tree)

## TreeSilhouette/MountainRange build their own mesh + material_override
## inside their own _ready(), which Godot runs synchronously as part of
## add_child() when the parent is already inside an active tree (true
## here - this only ever runs from MainMenuBackground's OWN _ready()) -
## material_override is already set by the time the caller gets here.
func _register_silhouette(mesh_instance: MeshInstance3D) -> void:
	var mat := mesh_instance.material_override as StandardMaterial3D
	if mat:
		_silhouette_materials.append(mat)
		_silhouette_base_colors.append(mat.albedo_color)

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
	# Tightened from the class default (14-32s) - user-reported: "I
	# haven't seen lightning flashes." Rarity was part of the problem on
	# top of the real visibility bugs fixed above/below (the flash was
	# damped to near-zero exactly where the camera looks, and never
	# touched the unshaded mountains/trees at all).
	thunder.min_interval_sec = 6.0
	thunder.max_interval_sec = 16.0
	add_child(thunder)
	thunder.thunder_started.connect(_on_thunder_started)

## Real lightning rarely reads as one clean pulse - a slightly dimmer
## second flicker ~0.12s after the first sells it better than a single
## fade.
func _on_thunder_started() -> void:
	_flash_once(1.0, 0.6, 0.0)
	var flicker_tween := create_tween()
	flicker_tween.tween_interval(0.12)
	flicker_tween.tween_callback(func(): _flash_once(0.6, 0.3, 0.0))

func _flash_once(peak: float, fall_duration: float, delay: float) -> void:
	var flash_tween := create_tween()
	if delay > 0.0:
		flash_tween.tween_interval(delay)
	flash_tween.tween_method(_set_flash, peak, 0.0, fall_duration) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if _moonlight:
		_moonlight.light_energy = _moonlight_base_energy + 2.5 * peak
		var light_tween := create_tween()
		light_tween.tween_property(_moonlight, "light_energy", _moonlight_base_energy, fall_duration) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

## Drives the sky shader's flash AND every registered silhouette
## material's own albedo (mountains, trees) - unshaded materials ignore
## _moonlight entirely, so without this the flash was sky-only and easy
## to miss behind the mountain line filling most of the frame.
func _set_flash(value: float) -> void:
	if _sky_material:
		_sky_material.set_shader_parameter("flash_intensity", value)
	for i in range(_silhouette_materials.size()):
		_silhouette_materials[i].albedo_color = _silhouette_base_colors[i].lerp(Color(0.85, 0.88, 1.0), value * 0.7)
