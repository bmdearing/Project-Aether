extends Node3D
class_name MemoryNexus
## Builds the Hub as a Memory Nexus: marble platforms with gold inlay that
## dissolve into a glowing void at their edges, floating over darkness full
## of drifting motes, light shafts, floating islands and Dalaran spires.
## The walkable area is one signed-distance shape (CIRCLES + BRIDGES) shared
## by the collision and the floor shader, so what you see is what you stand on.

const DOODADS := "res://entities/environment/doodads/nexus/"
const GROUND := "res://assets/models/doodads/nexus/ground/"

## x, z, radius, gold inlay (1/0).
const CIRCLES: Array[Vector4] = [
	Vector4(0, 0, 10.5, 1),      # centre - waypoint
	Vector4(0, -17, 9.5, 1),     # north dais - Reality Engine
	Vector4(-17, -4, 7.5, 1),    # west stabiliser - vendors
	Vector4(17, -4, 7.5, 1),     # east stabiliser - spells / stash
	Vector4(0, 15.5, 6.0, 0),    # south landing - waygate
]
## Walkways between platforms: from xz, to xz.
const BRIDGES: Array[Vector4] = [
	Vector4(-7, -2.5, -12, -3.5),
	Vector4(7, -2.5, 12, -3.5),
	Vector4(0, 8, 0, 12),
]
const BRIDGE_RADIUS := 2.8
## Collision sits a little inside the drawn edge, where the flakes begin.
const COLLISION_INSET := 0.4

const DAIS_CENTRE := Vector3(0, 0, -17)
## Stepped tiers: radius, top height.
const DAIS_TIERS: Array[Vector2] = [Vector2(8.6, 0.4), Vector2(7.2, 0.8), Vector2(5.8, 1.2)]

const GLOW := Color(0.18, 0.48, 1.0)
const WARM := Color(1.0, 0.74, 0.45)

var _floor_mat: ShaderMaterial
var _floaters: Array = []   # [node, base position, bob amplitude, speed, phase, spin]
var _time := 0.0

func _ready() -> void:
	_floor_mat = _make_floor_material(true)
	_build_environment()
	_build_floor()
	_build_dais()
	_build_crusts()
	_build_landmarks()
	_build_decor()
	_build_void()
	_build_lights()
	_dress_interactables.call_deferred()

func _process(delta: float) -> void:
	_time += delta
	for f in _floaters:
		var node: Node3D = f[0]
		if not is_instance_valid(node):
			continue
		node.position = f[1] + Vector3(0, sin(_time * f[3] + f[4]) * f[2], 0)
		node.rotation.y += f[5] * delta

## ---- Environment -------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.009, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.4, 0.62)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for level in 7:
		env.set_glow_level(level, 1.0 if level in [2, 3, 4, 5] else 0.0)
	env.fog_enabled = true
	env.fog_light_color = Color(0.008, 0.016, 0.045)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var world_env := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null:
		world_env = WorldEnvironment.new()
		add_child(world_env)
	world_env.environment = env

	var moon := get_parent().get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if moon == null:
		moon = DirectionalLight3D.new()
		add_child(moon)
	moon.light_color = Color(0.58, 0.68, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-58, 28, 0)
	moon.directional_shadow_max_distance = 70.0

## ---- Floor & collision -------------------------------------------------------

func _make_floor_material(with_erosion: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nexus_floor.gdshader")
	mat.set_shader_parameter("albedo_a", load(GROUND + "dalaran_whitemarble_diffuse.dds"))
	mat.set_shader_parameter("normal_a", load(GROUND + "dalaran_whitemarble_normal.dds"))
	mat.set_shader_parameter("albedo_b", load(GROUND + "dalaran_blackmarble_diffuse.dds"))
	mat.set_shader_parameter("normal_b", load(GROUND + "dalaran_blackmarble_normal.dds"))
	var circles := PackedVector4Array()
	for c in CIRCLES:
		circles.append(c if with_erosion else Vector4(c.x, c.y, c.z, 0))
	mat.set_shader_parameter("circles", circles)
	mat.set_shader_parameter("circle_count", CIRCLES.size())
	mat.set_shader_parameter("capsules", PackedVector4Array(BRIDGES))
	mat.set_shader_parameter("capsule_count", BRIDGES.size())
	mat.set_shader_parameter("capsule_radius", BRIDGE_RADIUS)
	mat.set_shader_parameter("erosion", with_erosion)
	return mat

func _build_floor() -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(110, 110)
	mesh.subdivide_width = 1
	mesh.subdivide_depth = 1
	plane.mesh = mesh
	plane.material_override = _floor_mat
	plane.position = Vector3(0, 0, -3)
	add_child(plane)

	var body := StaticBody3D.new()
	add_child(body)
	for c in CIRCLES:
		var shape := CylinderShape3D.new()
		shape.radius = c.z - COLLISION_INSET
		shape.height = 1.0
		_add_shape(body, shape, Vector3(c.x, -0.5, c.y), 0.0)
	for b in BRIDGES:
		var a := Vector2(b.x, b.y)
		var e := Vector2(b.z, b.w)
		var box := BoxShape3D.new()
		box.size = Vector3((BRIDGE_RADIUS - COLLISION_INSET) * 2.0, 1.0, a.distance_to(e))
		var mid := (a + e) / 2.0
		_add_shape(body, box, Vector3(mid.x, -0.5, mid.y), atan2(e.x - a.x, e.y - a.y))

func _add_shape(body: StaticBody3D, shape: Shape3D, pos: Vector3, yaw: float) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.rotation.y = yaw
	body.add_child(col)

## Visible stepped tiers over one smooth frustum collider, so the steps can
## be walked up like a ramp.
func _build_dais() -> void:
	var tier_mat := _make_floor_material(false)
	tier_mat.set_shader_parameter("tier_mode", true)
	for tier in DAIS_TIERS:
		var mat := tier_mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("top_y", tier.y)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = tier.x
		cyl.bottom_radius = tier.x
		cyl.height = tier.y + 0.2
		cyl.radial_segments = 64
		mi.mesh = cyl
		mi.material_override = mat
		mi.position = DAIS_CENTRE + Vector3(0, tier.y / 2.0 - 0.1, 0)
		add_child(mi)

	var body := StaticBody3D.new()
	body.position = DAIS_CENTRE
	add_child(body)
	var bottom_r: float = DAIS_TIERS[0].x + 0.6
	var top_r: float = DAIS_TIERS[-1].x
	var top_h: float = DAIS_TIERS[-1].y
	var points := PackedVector3Array()
	for i in 32:
		var a := TAU * i / 32.0
		points.append(Vector3(cos(a) * bottom_r, 0.0, sin(a) * bottom_r))
		points.append(Vector3(cos(a) * top_r, top_h, sin(a) * top_r))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	_add_shape(body, hull, Vector3.ZERO, 0.0)

## Rocky undersides hanging below each platform.
func _build_crusts() -> void:
	for c in CIRCLES:
		var depth: float = c.z * 1.1 + 3.0
		_add_crust(Vector3(c.x, -0.05, c.y), c.z + 0.6, depth)

func _add_crust(top_centre: Vector3, radius: float, depth: float) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nexus_crust.gdshader")
	mat.set_shader_parameter("top_y", top_centre.y)
	mat.set_shader_parameter("depth", depth)
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = radius
	cone.bottom_radius = radius * 0.12
	cone.height = depth
	cone.radial_segments = 40
	cone.rings = 6
	cone.cap_top = false
	mi.mesh = cone
	mi.material_override = mat
	mi.position = top_centre - Vector3(0, depth / 2.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## ---- Props -------------------------------------------------------------------

func _prop(file: String, pos: Vector3, height: float = 0.0, yaw: float = 0.0, animate: bool = true) -> Node3D:
	var node := (load(DOODADS + file + ".tscn") as PackedScene).instantiate() as Node3D
	add_child(node)
	node.position = pos
	node.rotation.y = yaw
	if height > 0.0:
		var b := _bounds(node)
		if b.size.y > 0.01:
			node.scale = Vector3.ONE * (height / b.size.y)
	if animate:
		for p in node.find_children("*", "AnimationPlayer", true, false):
			var player := p as AnimationPlayer
			for clip in ["Stand 1", "Stand", "Stand 2"]:
				if player.has_animation(clip):
					player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					player.play(clip)
					break
	return node

func _bounds(node: Node3D) -> AABB:
	var inv := node.global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var box := inv * mi.global_transform * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

## Box collision around a prop's visible bounds (shrunk a little).
func _solid(node: Node3D, shrink: float = 0.8) -> void:
	var b := _bounds(node)
	var body := StaticBody3D.new()
	node.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(b.size.x * shrink, b.size.y, b.size.z * shrink)
	_add_shape(body, box, b.get_center(), 0.0)

## A floating crystal formation turning over the Reality Engine: one cluster
## upright, one inverted beneath it, inside a rune ring.
func _build_dais_crystal(base: Vector3) -> void:
	var root := Node3D.new()
	root.position = base + Vector3(0, 4.2, 0)
	add_child(root)
	var upper := _prop("IcecrownCrystal4", Vector3.ZERO, 4.2)
	var lower := _prop("IcecrownCrystal0", Vector3.ZERO, 3.2)
	for c in [upper, lower]:
		remove_child(c)
		root.add_child(c)
	upper.position = Vector3(0, -0.4, 0)
	lower.position = Vector3(0, 0.4, 0)
	lower.rotation = Vector3(PI, 0.7, 0)
	_floaters.append([root, root.position, 0.35, 0.5, 0.0, 0.12])
	var ring := Node3D.new()
	ring.position = base + Vector3(0, 4.0, 0)
	add_child(ring)
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(5.5, 5.5)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nexus_runes.gdshader")
	mat.set_shader_parameter("speed", 0.08)
	mat.set_shader_parameter("energy", 1.6)
	mi.material_override = mat
	ring.add_child(mi)
	_floaters.append([ring, ring.position, 0.2, 0.5, 1.2, -0.25])
	_omni(base + Vector3(0, 4.2, 0), Color(0.35, 0.75, 1.0), 2.4, 10.0)

func _build_landmarks() -> void:
	var circle := _prop("Circleofpower", Vector3(0, 0.02, 0))
	var cb := _bounds(circle)
	circle.scale = Vector3.ONE * (6.5 / maxf(cb.size.x, 0.01))
	_rune_disc(Vector3(0, 0.03, 0), 8.6, 0.035, 1.6)

	_build_dais_crystal(DAIS_CENTRE + Vector3(0, DAIS_TIERS[-1].y, -1.5))
	_rune_disc(DAIS_CENTRE + Vector3(0, DAIS_TIERS[-1].y + 0.02, 0), 10.5, -0.03, 1.4)

	var waygate := _prop("Waygate", Vector3(0, 0, 18.3), 7.5, PI)
	_solid(waygate, 0.6)

	for side in [-1.0, 1.0]:
		var c := Vector3(17.0 * side, 0, -4)
		_rune_disc(c + Vector3(0, 0.03, 0), 9.5, 0.04 * side, 1.8)
		var colonnade := _prop("CityColumnsemicircle", c + Vector3(5.6 * side, 0, 0), 6.5, PI / 2.0 * side)
		_solid(colonnade, 0.35)

## ---- Decor -------------------------------------------------------------------

func _build_decor() -> void:
	# Crystal lamps on the centre platform's diagonals.
	for a in [45.0, 135.0, 225.0, 315.0]:
		var dir := Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a)))
		var lamp := _prop("Crystallamp", dir * 8.6, 2.6, randf() * TAU)
		_solid(lamp, 0.5)
		_omni(dir * 8.6 + Vector3(0, 2.4, 0), GLOW, 1.4, 7.0)

	# Ruin crystals and broken columns where the edges crumble.
	var ruin_spots := [Vector3(-9.5, 0, 6.5), Vector3(9.8, 0, 6.0), Vector3(-22.5, 0, 1.5), Vector3(22.5, 0, 1.0), Vector3(-7.5, 0, -24.0), Vector3(7.5, 0, -24.5)]
	for p in ruin_spots:
		_prop("Dalaranruincrystals", p, 2.0, randf() * TAU)
	for p in [Vector3(-12, 0, -12.5), Vector3(12, 0, -12.5), Vector3(-5.0, 0, 19.5), Vector3(5.0, 0, 19.5)]:
		var col := _prop("CityColumnsingle1Ruined" if randf() < 0.5 else "Northrendbrokencolumn0", p, 3.6, randf() * TAU)
		_solid(col, 0.5)

	# Icecrown crystals jutting out of the crumbling rims and hanging beneath.
	var rim := [Vector3(-11.5, -0.6, 3.5), Vector3(11.0, -0.8, 4.0), Vector3(-24.5, -0.5, -6.5), Vector3(24.5, -0.6, -7.0), Vector3(-3.0, -0.8, -27.0), Vector3(4.0, -0.4, 21.5)]
	var crystals := ["IcecrownCrystal0", "IcecrownCrystal2", "IcecrownCrystal4", "IcecrownCrystal6"]
	for i in rim.size():
		var cr := _prop(crystals[i % crystals.size()], rim[i], randf_range(3.5, 5.0), randf() * TAU)
		cr.rotation.x = randf_range(-0.35, 0.35)
		cr.rotation.z = randf_range(-0.35, 0.35)
		_omni(rim[i] + Vector3(0, 2.0, 0), Color(0.3, 0.75, 1.0), 1.1, 6.0)
	for c in CIRCLES:
		for k in 3:
			var a := randf() * TAU
			var r: float = c.z * randf_range(0.3, 0.75)
			var hang := _prop(crystals[randi() % crystals.size()], Vector3(c.x + cos(a) * r, -randf_range(1.5, 4.0), c.y + sin(a) * r), randf_range(3.0, 6.0), randf() * TAU)
			hang.rotation.x = PI + randf_range(-0.3, 0.3)

## ---- Void --------------------------------------------------------------------

func _build_void() -> void:
	var sky := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 700.0
	sphere.height = 1400.0
	sky.mesh = sphere
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/nexus_nebula.gdshader")
	sky.material_override = sky_mat
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	sea.mesh = plane
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = load("res://shaders/nexus_void_sea.gdshader")
	sea.material_override = sea_mat
	sea.position = Vector3(0, -70, -3)
	add_child(sea)

	# Light shafts rising out of the void.
	var beams := [
		[Vector3(-46, -28, -38), Vector3(0.3, 0.6, 0.0), 5.0],
		[Vector3(50, -30, -14), Vector3(-0.28, -0.9, 0.0), 6.5],
		[Vector3(14, -36, 56), Vector3(0.25, 2.8, 0.0), 4.5],
	]
	for b in beams:
		_beam(b[0], b[1], b[2])

	# Floating islands and Dalaran spires drifting in the distance.
	var islands := [Vector3(-34, -6, -6), Vector3(31, -9, -26), Vector3(-24, -14, 27), Vector3(26, -4, 22), Vector3(-6, -11, -42), Vector3(40, -18, 6), Vector3(-44, -22, -34)]
	for p in islands:
		_island(p, randf_range(2.0, 4.0))
	var spires := [["Dalaranvioletholdspire", Vector3(-52, -26, -48), 30.0], ["DalaranvioletholdspireSmall", Vector3(54, -14, -36), 16.0],
		["DalaranvioletholdspireSmall", Vector3(-58, -30, 22), 18.0], ["Dalaranvioletholdspire", Vector3(36, -40, 52), 26.0], ["DalaranvioletholdspireSmall", Vector3(4, -34, -66), 15.0]]
	for s in spires:
		var spire := _prop(s[0], s[1], s[2], randf() * TAU)
		spire.rotation.x = randf_range(-0.25, 0.25)
		spire.rotation.z = randf_range(-0.25, 0.25)
		_floaters.append([spire, spire.position, randf_range(0.6, 1.4), randf_range(0.15, 0.3), randf() * TAU, randf_range(-0.03, 0.03)])
		_add_crust(spire.position + Vector3(0, 0.1, 0), 2.6, 7.0)

	_motes()
	_edge_flakes()

func _island(pos: Vector3, radius: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var top := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.3
	cyl.radial_segments = 24
	top.mesh = cyl
	var mat := _make_floor_material(false)
	mat.set_shader_parameter("tier_mode", true)
	mat.set_shader_parameter("top_y", pos.y + 0.15)
	top.material_override = mat
	root.add_child(top)
	var crust_mat := ShaderMaterial.new()
	crust_mat.shader = load("res://shaders/nexus_crust.gdshader")
	var depth := radius * 1.8
	crust_mat.set_shader_parameter("top_y", pos.y - 0.15)
	crust_mat.set_shader_parameter("depth", depth)
	var crust := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = radius
	cone.bottom_radius = radius * 0.1
	cone.height = depth
	cone.radial_segments = 24
	crust.mesh = cone
	crust.material_override = crust_mat
	crust.position = Vector3(0, -0.15 - depth / 2.0, 0)
	root.add_child(crust)
	if randf() < 0.6:
		var deco: String = ["Dalaranruincrystals", "Northrendbrokencolumn0", "Crystallamp"][randi() % 3]
		var prop := _prop(deco, Vector3.ZERO, randf_range(1.6, 2.6), randf() * TAU)
		remove_child(prop)
		root.add_child(prop)
		prop.position = Vector3(randf_range(-0.5, 0.5), 0.15, randf_range(-0.5, 0.5))
	# Crust uniforms are world-space, so islands bob without moving: just spin.
	_floaters.append([root, pos, 0.0, 0.0, 0.0, randf_range(-0.04, 0.04)])

func _beam(pos: Vector3, rot: Vector3, width: float) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, 90.0)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nexus_beam.gdshader")
	mat.set_shader_parameter("energy", randf_range(0.25, 0.45))
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Second quad crossed at 90 degrees so the shaft has volume from any side.
	var cross := mi.duplicate() as MeshInstance3D
	add_child(cross)
	cross.rotation = rot
	cross.rotate_object_local(Vector3.UP, PI / 2.0)

func _rune_disc(pos: Vector3, size: float, speed: float, energy: float) -> void:
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nexus_runes.gdshader")
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("energy", energy)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _glow_particle_material(base: Color) -> StandardMaterial3D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.25, Color(1, 1, 1, 0.6))
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = base
	mat.albedo_texture = tex
	mat.disable_receive_shadows = true
	return mat

## Faint motes rising through the whole void.
func _motes() -> void:
	var p := CPUParticles3D.new()
	p.amount = 900
	p.lifetime = 26.0
	p.preprocess = 26.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(80, 22, 80)
	p.position = Vector3(0, -32, -3)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.05, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.07
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.4, 0.75, 1.0, 0.0))
	ramp.set_color(1, Color(0.2, 0.45, 1.0, 0.0))
	ramp.add_point(0.2, Color(0.45, 0.8, 1.0, 1.0))
	ramp.add_point(0.8, Color(0.25, 0.5, 1.0, 0.8))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _glow_particle_material(Color(0.5, 0.75, 1.0) * 0.9)
	p.mesh = quad
	add_child(p)

## Flakes peeling up off the dissolving edges.
func _edge_flakes() -> void:
	var points := PackedVector3Array()
	for c in CIRCLES:
		for i in 90:
			var a := TAU * i / 90.0
			var p2 := Vector2(c.x, c.y) + Vector2(cos(a), sin(a)) * (c.z + 0.8)
			if _sd(p2) > 0.4:
				points.append(Vector3(p2.x, 0.05, p2.y))
	var p := CPUParticles3D.new()
	p.amount = 300
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0, 0.12, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.06
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.85, 1.0, 1.0))
	ramp.set_color(1, Color(0.15, 0.35, 1.0, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.material = _glow_particle_material(Color(0.5, 0.8, 1.0) * 1.4)
	p.mesh = quad
	add_child(p)

func _sd(p: Vector2) -> float:
	var d := 1e5
	for c in CIRCLES:
		d = minf(d, p.distance_to(Vector2(c.x, c.y)) - c.z)
	for b in BRIDGES:
		var a := Vector2(b.x, b.y)
		var e := Vector2(b.z, b.w)
		var h := clampf((p - a).dot(e - a) / (e - a).length_squared(), 0.0, 1.0)
		d = minf(d, p.distance_to(a + (e - a) * h) - BRIDGE_RADIUS)
	return d

## ---- Lights ------------------------------------------------------------------

func _omni(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	add_child(l)
	return l

func _build_lights() -> void:
	_omni(Vector3(0, 6.5, 0), WARM, 3.2, 17.0).shadow_enabled = true
	_omni(DAIS_CENTRE + Vector3(0, 8, 2), WARM, 2.4, 16.0)
	_omni(Vector3(-17, 5.0, -4), WARM, 2.4, 12.0)
	_omni(Vector3(17, 5.0, -4), WARM, 2.4, 12.0)
	_omni(Vector3(0, 4, 15.5), WARM, 1.2, 9.0)
	_omni(Vector3(0, 0.8, 0), GLOW, 1.8, 6.0)
	_omni(Vector3(-17, 0.8, -4), GLOW, 1.6, 7.0)
	_omni(Vector3(17, 0.8, -4), GLOW, 1.6, 7.0)
	_omni(DAIS_CENTRE + Vector3(0, 2.2, 0), GLOW, 1.6, 8.0)
	# Cold uplight from the void onto the platforms' undersides.
	_omni(Vector3(0, -10, -3), Color(0.2, 0.45, 1.0), 3.0, 30.0)

## ---- Interactables -----------------------------------------------------------

## Swaps the vendors' and stash's placeholder boxes for WC3 models, keeping
## their own collision and prompt.
func _dress_interactables() -> void:
	var hub := get_parent()
	_dress(hub.get_node_or_null("GearShop"), "Arcanevault", 4.6)
	_dress(hub.get_node_or_null("AmmoStore"), "Cratesunit", 1.3)
	var spell := _dress(hub.get_node_or_null("SpellTestShop"), "Magicvault", 2.0)
	if spell:
		var tome := _prop("Tomeblue", Vector3.ZERO, 0.7)
		remove_child(tome)
		spell.add_child(tome)
		tome.position = Vector3(0, 2.6, 0)
		_floaters.append([tome, tome.position, 0.15, 1.6, 0.0, 0.8])
		_omni(spell.global_position + Vector3(0, 2.8, 0), GLOW, 1.4, 4.0)
	_dress(hub.get_node_or_null("StashChest"), "Treasurechest", 1.3)
	var engine := hub.get_node_or_null("RealityEngine") as Node3D
	if engine:
		for mi in engine.find_children("*", "MeshInstance3D", true, false):
			if mi.get_parent() is StaticBody3D:
				mi.visible = false
		var plinth := _prop("Northrendbrokencolumn0", Vector3.ZERO, 1.25)
		remove_child(plinth)
		engine.add_child(plinth)
		plinth.position = Vector3.ZERO
		var orb := engine.get_node_or_null("Orb") as MeshInstance3D
		if orb:
			var orb_mat := StandardMaterial3D.new()
			orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			orb_mat.albedo_color = Color(0.55, 0.85, 1.0)
			orb_mat.emission_enabled = true
			orb_mat.emission = Color(0.35, 0.7, 1.0)
			orb_mat.emission_energy_multiplier = 4.0
			orb.material_override = orb_mat
		_omni(engine.global_position + Vector3(0, 2.0, 0), Color(0.75, 0.55, 1.0), 1.6, 6.0)

func _dress(target: Node3D, model: String, height: float) -> Node3D:
	if target == null:
		return null
	for mi in target.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() is StaticBody3D:
			mi.visible = false
	var node := _prop(model, Vector3.ZERO, height)
	remove_child(node)
	target.add_child(node)
	node.position = Vector3.ZERO
	node.rotation.y = 0.0
	var b := _bounds(node)
	node.position.y = -b.position.y * node.scale.y
	node.look_at(Vector3(0, node.global_position.y, 0), Vector3.UP)
	node.rotate_y(PI / 2.0)
	return target
