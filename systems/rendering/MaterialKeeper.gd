extends RefCounted
class_name MaterialKeeper
## Godot shares one generated shader per StandardMaterial3D feature set and
## drops it when the last material using it is freed. Spell and death FX
## make short-lived materials with feature sets nothing else uses, so each
## cast or rare kill recompiled them on the spot (Comet: ~50 ms, a rare
## kill's flash: ~9 ms). This keeps one texture-free copy per feature set
## alive for the session, so after SpellWarmup they never compile again.

## Enum and bool properties: together they pick the generated shader.
static var _key_props: PackedStringArray = []
static var _kept: Dictionary = {}       # key -> kept copy
static var _seen: Dictionary = {}       # material instance id -> true
static var _pending: Array[WeakRef] = []
static var _tree: SceneTree

static func start(tree: SceneTree) -> void:
	if _tree:
		return
	_tree = tree
	tree.node_added.connect(_on_node_added)
	tree.process_frame.connect(_flush)

static func kept_count() -> int:
	return _kept.size()

static func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_pending.append(weakref(node))

## Checked a frame later: effects often set materials just after add_child.
static func _flush() -> void:
	if _pending.is_empty():
		return
	var batch := _pending
	_pending = []
	for ref in batch:
		var g := ref.get_ref() as GeometryInstance3D
		if g:
			_scan(g)

static func _scan(g: GeometryInstance3D) -> void:
	_consider(g.material_override)
	_consider(g.material_overlay)
	var mesh: Mesh = null
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		mesh = mi.mesh
		for i in mi.get_surface_override_material_count():
			_consider(mi.get_surface_override_material(i))
	elif g is CPUParticles3D:
		mesh = (g as CPUParticles3D).mesh
	elif g is GPUParticles3D:
		mesh = (g as GPUParticles3D).draw_pass_1
	if mesh:
		for i in mesh.get_surface_count():
			_consider(mesh.surface_get_material(i))

static func _consider(material: Material) -> void:
	var m := material as BaseMaterial3D
	while m:
		var id := m.get_instance_id()
		if _seen.has(id):
			return
		_seen[id] = true
		if _seen.size() > 20000:
			_seen.clear()
		var key := _key(m)
		if not _kept.has(key):
			var copy := m.duplicate() as BaseMaterial3D
			for t in BaseMaterial3D.TEXTURE_MAX:
				copy.set_texture(t, null)
			copy.next_pass = null
			# The shader is only built when something asks for the RID; a copy
			# that never builds it holds nothing, and every flash recompiled.
			copy.get_rid()
			_kept[key] = copy
		m = m.next_pass as BaseMaterial3D

static func _key(m: BaseMaterial3D) -> String:
	if _key_props.is_empty():
		for p in m.get_property_list():
			if (p["usage"] & PROPERTY_USAGE_STORAGE) and p["type"] in [TYPE_BOOL, TYPE_INT] and p["name"] != "render_priority":
				_key_props.append(p["name"])
	var parts := PackedStringArray([m.get_class()])
	for name in _key_props:
		parts.append(str(m.get(name)))
	return ",".join(parts)
