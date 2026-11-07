extends RefCounted
class_name ProjectileLook
## Shaped projectile visuals, built in code: bullets with a hot streak,
## arrows and bolts (shaft, head, fletching), javelins, tumbling axes, web
## globs and glowing magic bolts. A shot flies along -Z. Meshes and
## materials are shared per kind and colour; nothing here casts shadows.

enum Kind { NONE, BULLET, ARROW, BOLT, JAVELIN, AXE, WEB, MAGIC }

## Ranged enemies whose shot isn't a magic bolt, by definition file name.
const ENEMY_KINDS := {
	"directorate_rifleman": Kind.BULLET,
	"unchartered_javelineer": Kind.JAVELIN,
	"unchartered_berserker": Kind.AXE,
	"hollowed_crypt_fiend": Kind.WEB,
}
## Radians/s the model tumbles (Projectile.spin).
const SPIN := {Kind.AXE: 14.0, Kind.WEB: 3.0}

const WOOD := Color(0.42, 0.3, 0.19)
const STEEL := Color(0.62, 0.63, 0.67)
const HOT := Color(1.0, 0.86, 0.6)

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _streak_texture: ImageTexture

static func for_enemy(definition: EnemyDefinition) -> Kind:
	var id := definition.resource_path.get_file().get_basename() if definition else ""
	return ENEMY_KINDS.get(id, Kind.MAGIC) as Kind

## The model for `kind`, or null for NONE (the plain ball stays).
static func build(kind: Kind, damage_type: int) -> Node3D:
	var root := Node3D.new()
	var color := glow_of(damage_type)
	match kind:
		Kind.BULLET:
			_part(root, _mesh("bullet_core"), _flat(HOT.lerp(color, 0.25)), Vector3.ZERO, _along_z())
			_glow(root, 0.12, Color(HOT, 0.8))
			_streak(root, 0.035, 1.3, Color(HOT.lerp(color, 0.4), 0.85))
		Kind.ARROW:
			_shafted(root, 0.75, 0.007, 0.07, 0.018, 0.13, color)
			_streak(root, 0.02, 0.6, Color(color, 0.3))
		Kind.BOLT:
			_shafted(root, 0.45, 0.009, 0.06, 0.024, 0.08, color)
			_streak(root, 0.025, 0.5, Color(color, 0.3))
		Kind.JAVELIN:
			_shafted(root, 1.5, 0.016, 0.28, 0.045, 0.0, color)
		Kind.AXE:
			# Handle along +Y so Projectile's spin tumbles it end over end.
			# The blade is a wedge: narrow at the handle, a wide edge outward.
			_part(root, _mesh("axe_handle"), _lit(WOOD), Vector3(0, 0.05, 0), Basis.IDENTITY)
			_part(root, _mesh("axe_blade"), _lit(STEEL, 0.8), Vector3(0.1, 0.22, 0), Basis(Vector3.BACK, PI * 0.5))
			_part(root, _mesh("axe_collar"), _lit(STEEL.darkened(0.3), 0.8), Vector3(0, 0.22, 0), Basis.IDENTITY)
		Kind.WEB:
			_part(root, _mesh("web_core"), _lit(Color(0.78, 0.82, 0.72), 0.0, 0.7), Vector3.ZERO, Basis.IDENTITY)
			for i in 6:
				var b := Basis(Vector3(0.3, 1, 0.5).normalized(), i * PI / 6.0) * Basis(Vector3.RIGHT, i * 0.9)
				_part(root, _mesh("web_strand"), _lit(Color(0.92, 0.94, 0.88)), Vector3.ZERO, b)
			_glow(root, 0.45, Color(0.55, 0.8, 0.45, 0.25))
		Kind.MAGIC:
			_part(root, _mesh("magic_core"), _flat(color.lightened(0.55)), Vector3.ZERO, Basis.IDENTITY)
			_glow(root, 0.6, Color(color, 0.9))
			_streak(root, 0.16, 0.9, Color(color, 0.7))
			var tail := SpellFx.emitter(root, 16, 0.3)
			tail.local_coords = false
			tail.scale_amount_min = 0.1
			tail.scale_amount_max = 0.2
			tail.scale_amount_curve = SpellFx.curve(1.0, 0.0)
			tail.color_ramp = SpellFx.ramp(Color(color.lightened(0.3), 0.8), Color(color, 0.4), 0.1)
			tail.mesh = SpellFx.glow_quad()
			tail.emitting = true
		_:
			root.free()
			return null
	return root

## Shaft along Z with a head at the front (-Z) and, when fletch > 0, two
## crossed vanes at the back tinted by the damage type.
static func _shafted(root: Node3D, length: float, radius: float, head_len: float, head_radius: float, fletch: float, color: Color) -> void:
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius
	shaft.bottom_radius = radius
	shaft.height = length
	shaft.radial_segments = 6
	shaft.rings = 1
	_part(root, _mesh("shaft_%s_%s" % [length, radius], shaft), _lit(WOOD), Vector3.ZERO, _along_z())
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = head_radius
	head.height = head_len
	head.radial_segments = 6
	head.rings = 1
	_part(root, _mesh("head_%s_%s" % [head_len, head_radius], head), _lit(STEEL, 0.8), Vector3(0, 0, -(length + head_len) * 0.5), _along_z())
	if fletch <= 0.0:
		return
	var vane := QuadMesh.new()
	vane.size = Vector2(0.045, fletch)
	var mat := _lit(Color.WHITE.lerp(color, 0.55), 0.0, 1.0, true)
	var at := Vector3(0, 0, length * 0.5 - fletch * 0.5)
	_part(root, _mesh("vane_%s" % fletch, vane), mat, at, _flat_along_z())
	_part(root, _mesh("vane_%s" % fletch, vane), mat, at, Basis(Vector3.BACK, PI * 0.5) * _flat_along_z())

## A soft streak trailing behind (+Z), two crossed quads so it reads from
## any side. Fades out near the camera so a fresh shot doesn't glare.
static func _streak(root: Node3D, width: float, length: float, color: Color) -> void:
	var quad := _mesh("streak_%s_%s" % [width, length], _quad(width, length))
	var mat := _streak_material(color, true)
	var at := Vector3(0, 0, length * 0.5)
	_part(root, quad, mat, at, _flat_along_z())
	_part(root, quad, mat, at, Basis(Vector3.BACK, PI * 0.5) * _flat_along_z())

static func _glow(root: Node3D, size: float, color: Color) -> void:
	var key := "glow_%s" % color
	if not _materials.has(key):
		var mat := SpellFx.glow_material(color, true, BaseMaterial3D.BILLBOARD_ENABLED)
		mat.vertex_color_use_as_albedo = false
		_near_fade(mat)
		_materials[key] = mat
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	_part(root, _mesh("glow_%s" % size, quad), _materials[key], Vector3.ZERO, Basis.IDENTITY)

static func _part(root: Node3D, mesh: Mesh, mat: Material, at: Vector3, basis: Basis) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(basis, at)
	root.add_child(mi)
	return mi

## Y-up primitives (cylinders, capsules) turned to point their top at -Z.
static func _along_z() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)

## A quad (XY plane, +Y up) laid flat with its top edge at -Z.
static func _flat_along_z() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)

static func _quad(width: float, length: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(width, length)
	return q

static func _mesh(key: String, made: Mesh = null) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh := made
	if mesh == null:
		match key:
			"bullet_core":
				var c := CapsuleMesh.new()
				c.radius = 0.014
				c.height = 0.08
				c.radial_segments = 6
				c.rings = 2
				mesh = c
			"magic_core":
				var s := SphereMesh.new()
				s.radius = 0.08
				s.height = 0.16
				s.radial_segments = 10
				s.rings = 6
				mesh = s
			"web_core":
				var s := SphereMesh.new()
				s.radius = 0.12
				s.height = 0.2
				s.radial_segments = 8
				s.rings = 5
				mesh = s
			"web_strand":
				var b := BoxMesh.new()
				b.size = Vector3(0.008, 0.008, 0.42)
				mesh = b
			"axe_handle":
				var h := CylinderMesh.new()
				h.top_radius = 0.016
				h.bottom_radius = 0.016
				h.height = 0.5
				h.radial_segments = 6
				h.rings = 1
				mesh = h
			"axe_blade":
				# Apex (+Y) turned to face the handle; the base is the edge.
				var p := PrismMesh.new()
				p.size = Vector3(0.22, 0.17, 0.022)
				p.left_to_right = 0.5
				mesh = p
			"axe_collar":
				var b := BoxMesh.new()
				b.size = Vector3(0.05, 0.07, 0.04)
				mesh = b
	_meshes[key] = mesh
	return mesh

static func _flat(color: Color) -> StandardMaterial3D:
	var key := "flat_%s" % color
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.disable_receive_shadows = true
		_materials[key] = mat
	return _materials[key]

static func _lit(color: Color, metallic: float = 0.0, alpha: float = 1.0, two_sided: bool = false) -> StandardMaterial3D:
	var key := "lit_%s_%s_%s_%s" % [color, metallic, alpha, two_sided]
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color, alpha)
		mat.metallic = metallic
		mat.roughness = 0.4 if metallic > 0.0 else 0.8
		if alpha < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if two_sided:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = mat
	return _materials[key]

## Shared unless `shared` is false (a tracer fades its own copy).
static func _streak_material(color: Color, shared: bool) -> StandardMaterial3D:
	var key := "streak_%s" % color
	if shared and _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.albedo_texture = _streak_tex()
	mat.disable_receive_shadows = true
	_near_fade(mat)
	if shared:
		_materials[key] = mat
	return mat

static func _near_fade(mat: BaseMaterial3D) -> void:
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.6
	mat.distance_fade_max_distance = 2.0

## Bright at the top edge (the shot's head), fading to the tail and soft
## at both sides.
static func _streak_tex() -> ImageTexture:
	if _streak_texture:
		return _streak_texture
	var w := 16
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var along := pow(1.0 - float(y) / float(h - 1), 1.6)
		for x in w:
			var across := 1.0 - absf(float(x) / float(w - 1) * 2.0 - 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, along * across * across))
	_streak_texture = ImageTexture.create_from_image(img)
	return _streak_texture

## A hitscan shot: a faint line to the hit that fades, and a short bright
## streak racing along it.
static func tracer(parent: Node, from: Vector3, to: Vector3, damage_type: int, seconds: float) -> void:
	var length := from.distance_to(to)
	if length < 0.05 or parent == null:
		return
	var color := HOT.lerp(glow_of(damage_type), 0.35)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var root := Node3D.new()
	parent.add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(dir, up), from)
	var line_mat := _streak_material(Color(color, 0.45), false)
	var line := _quad(0.02, length)
	var at := Vector3(0, 0, -length * 0.5)
	_part(root, line, line_mat, at, _flat_along_z())
	_part(root, line, line_mat, at, Basis(Vector3.BACK, PI * 0.5) * _flat_along_z())
	var head := Node3D.new()
	root.add_child(head)
	var streak_len := minf(2.5, length)
	var head_mat := _streak_material(Color(color, 0.95), false)
	var head_quad := _quad(0.045, streak_len)
	_part(head, head_quad, head_mat, Vector3(0, 0, streak_len * 0.5), _flat_along_z())
	_part(head, head_quad, head_mat, Vector3(0, 0, streak_len * 0.5), Basis(Vector3.BACK, PI * 0.5) * _flat_along_z())
	head.position = Vector3(0, 0, -streak_len)
	var tween := root.create_tween()
	tween.tween_property(head, "position:z", -length, seconds)
	tween.parallel().tween_property(line_mat, "albedo_color:a", 0.0, seconds * 1.6)
	tween.parallel().tween_property(head_mat, "albedo_color:a", 0.0, seconds).set_delay(seconds * 0.5)
	tween.tween_callback(root.queue_free)

## Damage-type colours lifted to read on dark floors (as BossFx.glow_of).
static func glow_of(damage_type: int) -> Color:
	match damage_type:
		Constants.DamageType.ENTROPIC: return Color(0.78, 0.42, 1.0)
		Constants.DamageType.FIRE: return Color(1.0, 0.45, 0.15)
		Constants.DamageType.KINETIC, Constants.DamageType.PIERCING: return Color(0.95, 0.8, 0.55)
	var base: Color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color(1.0, 0.35, 0.2))
	return base.lightened(0.15)
