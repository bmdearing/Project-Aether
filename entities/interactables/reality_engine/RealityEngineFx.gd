extends Node3D
class_name RealityEngineFx
## The Reality Engine's body, built in code: a stepped stone plinth with a
## gold bowl and four prongs, a churning energy core in three gold gyro
## rings, orbiting shards, a light shaft, rising motes and a pulsing light.
## awake (player nearby) spins it up; surge() is a brief flare.

const CORE_HEIGHT := 2.15
const CORE_COLOR := Color(0.5, 0.82, 1.0)
const SHELL_COLOR := Color(0.72, 0.48, 1.0)
const GOLD := Color(0.86, 0.66, 0.34)
const STONE := Color(0.2, 0.165, 0.15)
const SHARD_COUNT := 5
const PRONG_COUNT := 4
const SHARD_ORBIT_SPEED := 0.15

var awake := false

var _speed := 1.0
var _glow := 1.0
var _surge := 0.0
var _t := 0.0
## Shard orbit angle, accumulated so spin changes never make it jump.
var _orbit := 0.0
var _rings: Array[Node3D] = []
var _ring_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP]
var _ring_speeds: Array[float] = [0.55, -0.8, 1.15]
var _shards: Array[MeshInstance3D] = []
var _energy: Array[ShaderMaterial] = []
var _energy_base: Array[float] = []
var _core_root: Node3D
var _light: OmniLight3D
var _halo: MeshInstance3D

func _ready() -> void:
	# Keeps turning behind the selection screen's veil (the tree is paused).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_plinth()
	_core_root = Node3D.new()
	_core_root.position.y = CORE_HEIGHT
	add_child(_core_root)
	_build_core()
	_build_rings()
	_build_prongs()
	_build_shards()
	_build_beam()
	_build_particles()
	_light = OmniLight3D.new()
	_light.light_color = Color(0.62, 0.72, 1.0)
	_light.omni_range = 6.5
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	_core_root.add_child(_light)

func surge() -> void:
	_surge = 1.0

func _process(delta: float) -> void:
	_t += delta
	var target_speed := 2.4 if awake else 1.0
	_speed = lerpf(_speed, target_speed, 1.0 - exp(-delta * 2.0))
	_glow = lerpf(_glow, 1.35 if awake else 1.0, 1.0 - exp(-delta * 2.5))
	_surge = maxf(_surge - delta * 0.9, 0.0)
	var spin := _speed + _surge * 4.0
	for i in _rings.size():
		_rings[i].rotate_object_local(_ring_axes[i], _ring_speeds[i] * spin * delta)
	_orbit += delta * SHARD_ORBIT_SPEED * lerpf(1.0, spin, 0.35)
	for i in _shards.size():
		var a := _orbit + TAU * i / _shards.size()
		var r := 1.2 + 0.08 * sin(_t * 1.3 + i)
		_shards[i].position = Vector3(cos(a) * r, 0.25 * sin(_t * 0.9 + i * 1.7), sin(a) * r)
		_shards[i].rotate_y(delta * 0.6)
	_core_root.position.y = CORE_HEIGHT + 0.05 * sin(_t * 1.1)
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var glow := _glow + _surge * 1.2
	for i in _energy.size():
		_energy[i].set_shader_parameter("intensity", _energy_base[i] * glow * (0.88 + 0.24 * pulse))
	_light.light_energy = (1.6 + 0.5 * pulse) * glow
	_halo.scale = Vector3.ONE * (1.0 + 0.08 * pulse + _surge * 0.6)

func _build_plinth() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.85
	var gold := _gold_material(0.25)
	_cylinder(0.84, 0.96, 0.3, 0.15, stone)
	_torus(0.8, 0.9, 0.31, gold)
	_cylinder(0.5, 0.64, 0.72, 0.66, stone)
	_cylinder(0.64, 0.48, 0.14, 1.09, gold)
	# A glowing rune band round the column and a pool of light in the bowl.
	var band := _torus(0.6, 0.68, 0.6, _energy_mat(CORE_COLOR, 1.4, 0.9))
	band.scale = Vector3(1, 0.6, 1)
	var pool := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.56
	disc.bottom_radius = 0.56
	disc.height = 0.02
	pool.mesh = disc
	pool.position.y = 1.165
	pool.material_override = _energy_mat(SHELL_COLOR, 0.55, 0.5)
	_no_shadow(pool)
	add_child(pool)

func _build_core() -> void:
	var hot := _sphere(0.13, _core_material())
	_core_root.add_child(hot)
	_core_root.add_child(_sphere(0.27, _energy_mat(CORE_COLOR, 1.8, 0.8)))
	var shell := _sphere(0.44, _energy_mat(SHELL_COLOR, 1.1, 0.0))
	(shell.material_override as ShaderMaterial).set_shader_parameter("rim_power", 3.0)
	_core_root.add_child(shell)
	_halo = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	var mat := SpellFx.glow_material(Color(0.55, 0.7, 1.0, 0.32))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	_halo.mesh = quad
	_no_shadow(_halo)
	_core_root.add_child(_halo)

func _build_rings() -> void:
	var gold := _gold_material(0.6)
	var sizes := [Vector2(0.58, 0.64), Vector2(0.74, 0.79), Vector2(0.9, 0.94)]
	var tilts := [Vector3(0, 0, 0.5), Vector3(0.6, 0, 0), Vector3(0.35, 0.8, 0)]
	for i in sizes.size():
		var pivot := Node3D.new()
		pivot.rotation = tilts[i]
		_core_root.add_child(pivot)
		var ring := Node3D.new()
		pivot.add_child(ring)
		var torus := TorusMesh.new()
		torus.inner_radius = sizes[i].x
		torus.outer_radius = sizes[i].y
		torus.rings = 64
		torus.ring_segments = 8
		var metal := MeshInstance3D.new()
		metal.mesh = torus
		metal.material_override = gold
		ring.add_child(metal)
		# An energy film along the inside of each ring.
		var film := TorusMesh.new()
		film.inner_radius = sizes[i].x - 0.015
		film.outer_radius = sizes[i].x + 0.02
		film.rings = 64
		film.ring_segments = 6
		var glow := MeshInstance3D.new()
		glow.mesh = film
		glow.material_override = _energy_mat(CORE_COLOR if i != 1 else SHELL_COLOR, 2.0, 1.0)
		_no_shadow(glow)
		ring.add_child(glow)
		# Rune studs round the ring.
		var studs := 6 + i * 2
		for k in studs:
			var stud := _sphere(0.03, _energy_mat(Color(1.0, 0.85, 0.55), 2.6, 1.0))
			var a := TAU * k / studs
			stud.position = Vector3(cos(a), 0, sin(a)) * (sizes[i].x + sizes[i].y) * 0.5
			ring.add_child(stud)
		_rings.append(ring)

func _build_prongs() -> void:
	var gold := _gold_material(0.2)
	for i in PRONG_COUNT:
		var a := TAU * (i + 0.5) / PRONG_COUNT
		var out := Vector3(cos(a), 0, sin(a))
		var pivot := Node3D.new()
		pivot.position = out * 0.46 + Vector3.UP * 1.12
		# Leans outward so the tips clear the outer gyro ring.
		pivot.basis = Basis(Vector3.UP.cross(out).normalized(), 0.7) * Basis(Vector3.UP, -a)
		add_child(pivot)
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 0.85, 0.07)
		arm.mesh = box
		arm.material_override = gold
		arm.position.y = 0.42
		pivot.add_child(arm)
		var tip := MeshInstance3D.new()
		var gem := SphereMesh.new()
		gem.radius = 0.07
		gem.height = 0.3
		gem.radial_segments = 4
		gem.rings = 2
		tip.mesh = gem
		tip.material_override = _energy_mat(CORE_COLOR, 2.2, 0.8)
		tip.position.y = 0.9
		_no_shadow(tip)
		pivot.add_child(tip)
		# A thin tether from the prong tip into the core.
		var tip_pos: Vector3 = pivot.position + pivot.basis * Vector3(0, 0.9, 0)
		var core := Vector3(0, CORE_HEIGHT, 0)
		var tether := MeshInstance3D.new()
		var line := CylinderMesh.new()
		line.top_radius = 0.012
		line.bottom_radius = 0.02
		line.height = tip_pos.distance_to(core)
		line.radial_segments = 6
		tether.mesh = line
		tether.material_override = _energy_mat(SHELL_COLOR, 2.4, 1.0)
		_no_shadow(tether)
		add_child(tether)
		tether.position = (tip_pos + core) * 0.5
		tether.basis = _basis_along(core - tip_pos)

func _build_shards() -> void:
	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		var gem := SphereMesh.new()
		gem.radius = 0.08
		gem.height = 0.34
		gem.radial_segments = 4
		gem.rings = 2
		shard.mesh = gem
		shard.material_override = _energy_mat(CORE_COLOR if i % 2 == 0 else SHELL_COLOR, 2.0, 0.75)
		_no_shadow(shard)
		_core_root.add_child(shard)
		_shards.append(shard)

func _build_beam() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nexus_beam.gdshader")
	mat.set_shader_parameter("color", Color(0.45, 0.6, 1.0))
	mat.set_shader_parameter("energy", 0.9)
	mat.set_shader_parameter("scroll_speed", -0.12)
	for k in 2:
		var shaft := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.1, 8.0)
		shaft.mesh = quad
		shaft.material_override = mat
		shaft.position.y = CORE_HEIGHT + 3.4
		shaft.rotation.y = PI / 2.0 * k
		_no_shadow(shaft)
		add_child(shaft)

func _build_particles() -> void:
	# Motes spiralling up from the plinth into the core.
	var motes := SpellFx.emitter(self, 56, 2.6)
	motes.mesh = SpellFx.glow_quad()
	motes.position.y = 1.15
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 0.95
	motes.emission_ring_inner_radius = 0.75
	motes.emission_ring_height = 0.05
	motes.direction = Vector3.UP
	motes.spread = 10.0
	motes.initial_velocity_min = 0.35
	motes.initial_velocity_max = 0.6
	motes.tangential_accel_min = 0.9
	motes.tangential_accel_max = 1.3
	motes.radial_accel_min = -0.35
	motes.radial_accel_max = -0.25
	motes.scale_amount_min = 0.05
	motes.scale_amount_max = 0.11
	motes.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	motes.color_ramp = SpellFx.ramp(Color(0.5, 0.85, 1.0, 0.0), Color(0.7, 0.6, 1.0, 1.0), 0.3)
	# Sparks shed by the core, and an updraft along the shaft.
	var sparks := SpellFx.emitter(_core_root, 24, 1.3)
	sparks.mesh = SpellFx.glow_quad()
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.3
	sparks.spread = 180.0
	sparks.initial_velocity_min = 0.3
	sparks.initial_velocity_max = 0.9
	sparks.damping_min = 0.4
	sparks.damping_max = 0.8
	sparks.scale_amount_min = 0.03
	sparks.scale_amount_max = 0.06
	sparks.color_ramp = SpellFx.ramp(Color(1, 1, 1, 1), Color(0.55, 0.8, 1.0, 1.0), 0.2)
	var updraft := SpellFx.emitter(_core_root, 18, 3.2)
	updraft.mesh = SpellFx.glow_quad()
	updraft.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	updraft.emission_sphere_radius = 0.2
	updraft.direction = Vector3.UP
	updraft.spread = 6.0
	updraft.initial_velocity_min = 1.0
	updraft.initial_velocity_max = 1.8
	updraft.scale_amount_min = 0.05
	updraft.scale_amount_max = 0.09
	updraft.color_ramp = SpellFx.ramp(Color(0.6, 0.75, 1.0, 0.0), Color(0.6, 0.75, 1.0, 0.8), 0.15)

func _energy_mat(color: Color, intensity: float, fill: float) -> ShaderMaterial:
	var mat := SpellFx.energy_material(color, intensity, fill)
	_energy.append(mat)
	_energy_base.append(intensity)
	return mat

func _core_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.6, 1.8, 2.2)
	return mat

func _gold_material(emission: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GOLD
	mat.metallic = 0.9
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = GOLD
	mat.emission_energy_multiplier = emission
	return mat

func _cylinder(top: float, bottom: float, height: float, y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	mi.rotation.y = PI / 8.0
	add_child(mi)
	return mi

func _torus(inner: float, outer: float, y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 48
	mesh.ring_segments = 8
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	if mat is ShaderMaterial:
		_no_shadow(mi)
	add_child(mi)
	return mi

func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mi.mesh = mesh
	mi.material_override = mat
	_no_shadow(mi)
	return mi

func _no_shadow(mi: GeometryInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## A basis whose Y axis points along `dir`.
func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))
