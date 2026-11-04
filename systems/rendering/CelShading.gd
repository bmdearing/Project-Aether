extends Node
## Cel-shading switch (Settings > Cel Shading; F7 flips it in dev mode).
## Two parts, both undone when it's switched off:
## - Ink: cel_outline.gdshader on a full-screen quad parented to whichever
##   camera is current in the main viewport (SubViewport cameras like the
##   minimap's are left alone).
## - Banded light: every lit, opaque BaseMaterial3D on screen goes to toon
##   diffuse with a narrow terminator and no specular. Materials are shared
##   resources, so each is changed once and its old values kept in meta.
##   Custom ShaderMaterials (terrain, FX) are not touched.
## SSAO is cut while it's on; soft contact shadows muddy the flat bands.

const OUTLINE_SHADER := preload("res://shaders/cel_outline.gdshader")
const TOON_ROUGHNESS := 0.12
const SSAO_SCALE := 0.4
const ORIG := &"_cel_orig"
const ORIG_SSAO := &"_cel_ssao"

var _active := false
var _outline: MeshInstance3D
var _outline_mat: ShaderMaterial
var _env: Environment
var _pending: Array[GeometryInstance3D] = []
var _converted: Array[WeakRef] = []

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
	if env.fog_enabled and env.fog_density > 0.0:
		fade_end = clampf(1.6 / env.fog_density, 25.0, 120.0)  # ~80% fogged
	_outline_mat.set_shader_parameter(&"fade_end", fade_end)
	_outline_mat.set_shader_parameter(&"fade_start", fade_end * 0.35)

## ---- Banded light ------------------------------------------------------

func _convert_geometry(g: GeometryInstance3D) -> void:
	_convert(g.material_override)
	var mesh: Mesh = null
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		mesh = mi.mesh
		for i in mi.get_surface_override_material_count():
			_convert(mi.get_surface_override_material(i))
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		mesh = (g as MultiMeshInstance3D).multimesh.mesh
	if mesh:
		for i in mesh.get_surface_count():
			_convert(mesh.surface_get_material(i))

func _convert(material: Material) -> void:
	var m := material as BaseMaterial3D
	if m == null or m.has_meta(ORIG):
		return
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			or m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			or m.blend_mode != BaseMaterial3D.BLEND_MODE_MIX \
			or m.no_depth_test:
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
