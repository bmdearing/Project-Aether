extends Node
## Cel-shading switch (Settings > Cel Shading; F7 flips it in dev mode).
## Everything below is undone when it's switched off.
## - Ink: cel_outline.gdshader on a full-screen quad parented to whichever
##   camera is current in the main viewport (SubViewport cameras like the
##   minimap's are left alone).
## - Banded light on MeshInstance surfaces: each lit, opaque BaseMaterial3D
##   gets a ShaderMaterial twin (cel_standard.gdshaderinc: the common
##   StandardMaterial features plus a three-band light()) set as the surface
##   override. The original is never edited, so scripts reading mesh
##   materials still see it.
## - Materials using features the twin lacks, material_override (scripts
##   cast it back to StandardMaterial3D) and MultiMesh materials are edited
##   in place to two-band toon diffuse instead, old values kept in meta.
## Custom ShaderMaterials (terrain, FX) are not touched. SSAO is cut while
## it's on; soft contact shadows muddy the flat bands.

const OUTLINE_SHADER := preload("res://shaders/cel_outline.gdshader")
const TOON_ROUGHNESS := 0.3
const SSAO_SCALE := 0.4
const ORIG := &"_cel_orig"
const ORIG_SURFACES := &"_cel_surfaces"
const ORIG_MESH := &"_cel_mesh"
const ORIG_SSAO := &"_cel_ssao"
const RECHECK_PER_FRAME := 128

const FILTER_HINTS := ["filter_nearest", "filter_linear", "filter_nearest_mipmap", "filter_linear_mipmap",
	"filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic"]
const CULL_MODES := ["cull_back", "cull_front", "cull_disabled"]
const DEPTH_MODES := ["depth_draw_opaque", "depth_draw_always", "depth_draw_never"]

var _active := false
var _outline: MeshInstance3D
var _outline_mat: ShaderMaterial
var _env: Environment
var _pending: Array[GeometryInstance3D] = []
var _converted: Array[WeakRef] = []   # materials edited in place
var _swapped: Array[WeakRef] = []     # MeshInstance3Ds given banded twins
var _twins: Dictionary = {}           # BaseMaterial3D -> ShaderMaterial
var _shaders: Dictionary = {}         # generated code -> Shader (kept across toggles)
var _recheck_at := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.render_priority = Material.RENDER_PRIORITY_MIN
	get_tree().node_added.connect(_on_node_added)
	EventBus.settings_changed.connect(_sync)
	_sync.call_deferred()

func _input(event: InputEvent) -> void:
	if Dev.enabled and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_F7:
		GameState.cel_shading = not GameState.cel_shading
		GameSettings.save()
		GameSettings.apply()

func _sync() -> void:
	if GameState.cel_shading == _active:
		return
	_active = GameState.cel_shading
	if _active:
		_queue_tree(get_tree().root)
	else:
		_pending.clear()
		_restore_materials()
		if is_instance_valid(_outline):
			_outline.queue_free()
		_outline = null
		_set_env(null)

func _process(_delta: float) -> void:
	if not _active:
		return
	for g in _pending:
		if is_instance_valid(g):
			_convert_geometry(g)
	_pending.clear()
	_recheck_swapped()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not is_instance_valid(_outline) or _outline.get_parent() != cam:
		_attach_outline(cam)
	var env := cam.environment if cam.environment else cam.get_world_3d().environment
	if env != _env:
		_set_env(env)

func _on_node_added(node: Node) -> void:
	if _active and node is GeometryInstance3D and node != _outline:
		_pending.append(node)

func _queue_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_pending.append(node)
	for child in node.get_children():
		_queue_tree(child)

## ---- Ink ---------------------------------------------------------------

func _attach_outline(cam: Camera3D) -> void:
	if is_instance_valid(_outline):
		_outline.queue_free()
	_outline = MeshInstance3D.new()
	_outline.name = "CelOutline"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_outline.mesh = quad
	_outline.material_override = _outline_mat
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.extra_cull_margin = 16384.0
	cam.add_child(_outline)

## Cuts SSAO on the new environment (restoring the old one) and pulls the
## ink fade in to where fog would hide the lines anyway.
func _set_env(env: Environment) -> void:
	if _env and _env.has_meta(ORIG_SSAO):
		_env.ssao_intensity = float(_env.get_meta(ORIG_SSAO))
		_env.remove_meta(ORIG_SSAO)
	_env = env
	if env == null:
		return
	env.set_meta(ORIG_SSAO, env.ssao_intensity)
	env.ssao_intensity *= SSAO_SCALE
	var fade_end := 80.0
	if env.fog_enabled:
		fade_end = clampf(MapFog.reach(env), 25.0, 120.0)
	_outline_mat.set_shader_parameter(&"fade_end", fade_end)
	_outline_mat.set_shader_parameter(&"fade_start", fade_end * 0.35)

## ---- Banded light ------------------------------------------------------

func _convert_geometry(g: GeometryInstance3D) -> void:
	_convert(g.material_override)
	if g is MeshInstance3D:
		if g.material_override == null:
			_swap_surfaces(g as MeshInstance3D)
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		var mesh := (g as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for i in mesh.get_surface_count():
				_convert(mesh.surface_get_material(i))

func _swap_surfaces(mi: MeshInstance3D, track := true) -> void:
	if mi.mesh == null or mi.has_meta(ORIG_SURFACES):
		return
	var originals := []
	var any := false
	for i in mi.mesh.get_surface_count():
		var current := mi.get_surface_override_material(i)
		originals.append(current)
		var mat := current if current else mi.mesh.surface_get_material(i)
		var twin := _twin(mat)
		if twin:
			mi.set_surface_override_material(i, twin)
			any = true
		else:
			_convert(mat)
	if any:
		mi.set_meta(ORIG_SURFACES, originals)
		mi.set_meta(ORIG_MESH, mi.mesh)
		if track:
			_swapped.append(weakref(mi))

## A mesh swapped after its surfaces were given twins (the viewmodel on a
## weapon change) keeps the old overrides, so a slice of the swapped list is
## checked each frame and re-done if its mesh changed.
func _recheck_swapped() -> void:
	var n := _swapped.size()
	if n == 0:
		return
	for k in mini(RECHECK_PER_FRAME, n):
		_recheck_at = (_recheck_at + 1) % _swapped.size()
		var mi := _swapped[_recheck_at].get_ref() as MeshInstance3D
		if mi == null:
			_swapped.remove_at(_recheck_at)
			if _swapped.is_empty():
				return
			continue
		if mi.get_meta(ORIG_MESH, null) != mi.mesh:
			_unswap(mi, _twins.values())
			_swap_surfaces(mi, false)

## The banded ShaderMaterial for `material`, or null if it shouldn't be cel
## or uses a feature cel_standard.gdshaderinc doesn't cover.
func _twin(material: Material) -> ShaderMaterial:
	var m := material as BaseMaterial3D
	if m == null or not _wants_cel(m) or not _twin_covers(m):
		return null
	if _twins.has(m):
		return _twins[m]
	var defines := PackedStringArray()
	if m.vertex_color_use_as_albedo:
		defines.append("VCOL")
	if m.vertex_color_is_srgb:
		defines.append("VCOL_SRGB")
	if m.normal_enabled:
		defines.append("CEL_NORMAL")
	if m.emission_enabled:
		defines.append("CEL_EMISSION")
		if m.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY:
			defines.append("CEL_EMISSION_MUL")
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		defines.append("SCISSOR")
	var modes := PackedStringArray(["blend_mix", "specular_disabled", CULL_MODES[m.cull_mode], DEPTH_MODES[m.depth_draw_mode]])
	if m.disable_receive_shadows:
		modes.append("shadows_disabled")
	var code := "shader_type spatial;\nrender_mode %s;\n" % ", ".join(modes)
	for d in defines:
		code += "#define %s\n" % d
	code += "#define TEX_HINTS %s, %s\n" % [FILTER_HINTS[m.texture_filter], "repeat_enable" if m.texture_repeat else "repeat_disable"]
	code += "#include \"res://shaders/cel_standard.gdshaderinc\"\n"
	var shader: Shader = _shaders.get(code)
	if shader == null:
		shader = Shader.new()
		shader.code = code
		_shaders[code] = shader
	var twin := ShaderMaterial.new()
	twin.shader = shader
	twin.render_priority = m.render_priority
	twin.next_pass = m.next_pass
	twin.set_shader_parameter(&"albedo", m.albedo_color)
	twin.set_shader_parameter(&"texture_albedo", m.albedo_texture)
	twin.set_shader_parameter(&"uv1_scale", m.uv1_scale)
	twin.set_shader_parameter(&"uv1_offset", m.uv1_offset)
	twin.set_shader_parameter(&"roughness", m.roughness)
	twin.set_shader_parameter(&"metallic", m.metallic)
	twin.set_shader_parameter(&"specular", m.metallic_specular)
	if m.normal_enabled:
		twin.set_shader_parameter(&"texture_normal", m.normal_texture)
		twin.set_shader_parameter(&"normal_scale", m.normal_scale)
	if m.emission_enabled:
		twin.set_shader_parameter(&"emission", m.emission)
		twin.set_shader_parameter(&"emission_energy", m.emission_energy_multiplier)
		twin.set_shader_parameter(&"texture_emission", m.emission_texture)
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		twin.set_shader_parameter(&"alpha_scissor_threshold", m.alpha_scissor_threshold)
	_twins[m] = twin
	return twin

func _twin_covers(m: BaseMaterial3D) -> bool:
	return m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			and m.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] \
			and m.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
			and not (m.uv1_triplanar or m.detail_enabled or m.rim_enabled or m.clearcoat_enabled \
				or m.anisotropy_enabled or m.ao_enabled or m.heightmap_enabled or m.subsurf_scatter_enabled \
				or m.backlight_enabled or m.refraction_enabled or m.proximity_fade_enabled \
				or m.use_point_size or m.fixed_size or m.albedo_texture_msdf or m.disable_ambient_light \
				or m.grow or m.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED)

func _wants_cel(m: BaseMaterial3D) -> bool:
	return m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
			and m.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA \
			and m.blend_mode == BaseMaterial3D.BLEND_MODE_MIX \
			and not m.no_depth_test

func _convert(material: Material) -> void:
	var m := material as BaseMaterial3D
	if m == null or m.has_meta(ORIG) or not _wants_cel(m):
		return
	m.set_meta(ORIG, [m.diffuse_mode, m.specular_mode, m.roughness, m.metallic_specular, m.metallic])
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = TOON_ROUGHNESS  # toon diffuse uses roughness as the terminator width
	m.metallic_specular = 0.0     # the low roughness would otherwise mirror the sky
	m.metallic = 0.0
	_converted.append(weakref(m))

func _restore_materials() -> void:
	for ref in _converted:
		var m := ref.get_ref() as BaseMaterial3D
		if m == null or not m.has_meta(ORIG):
			continue
		var orig: Array = m.get_meta(ORIG)
		m.diffuse_mode = orig[0]
		m.specular_mode = orig[1]
		m.roughness = orig[2]
		m.metallic_specular = orig[3]
		m.metallic = orig[4]
		m.remove_meta(ORIG)
	_converted.clear()
	var twins := _twins.values()
	for ref in _swapped:
		var mi := ref.get_ref() as MeshInstance3D
		if mi:
			_unswap(mi, twins)
	_swapped.clear()
	_twins.clear()

func _unswap(mi: MeshInstance3D, twins: Array) -> void:
	if not mi.has_meta(ORIG_SURFACES):
		return
	var originals: Array = mi.get_meta(ORIG_SURFACES)
	for i in mini(originals.size(), mi.get_surface_override_material_count()):
		# A script may have set its own override since; leave that one.
		if twins.has(mi.get_surface_override_material(i)):
			mi.set_surface_override_material(i, originals[i])
	mi.remove_meta(ORIG_SURFACES)
	mi.remove_meta(ORIG_MESH)
