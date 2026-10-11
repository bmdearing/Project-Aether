extends Node
## One-shot generator for the Pale family's doodad kit: bones, pitted
## boulders and meaningless chalk structures built from primitive meshes.
## Run headlessly: Godot --headless --path . res://tools/generate_pale_doodads.tscn
## Writes entities/environment/doodads/pale/ (scenes) and its materials/.
## Doodads face +X like the WC3 ones; buildings' fronts are +X.

const OUT := "res://entities/environment/doodads/pale/"
const MAT_DIR := OUT + "materials/"
const BONE_SHADER := preload("res://shaders/pale_bone.gdshader")

var _rng := RandomNumberGenerator.new()
var _bone: Material
var _bone_lumpy: Material
var _chalk: Material
var _chalk_pitted: Material
var _hive: Material
var _glow: Material

func _ready() -> void:
	_rng.seed = 1919
	DirAccess.make_dir_recursive_absolute(MAT_DIR)
	_make_materials()
	_bone_flats_kit()
	_structures_kit()
	_buildings_kit()
	print("PALE_DOODADS_DONE")
	get_tree().quit()

## ---- Materials -------------------------------------------------------------

func _make_materials() -> void:
	_bone = _bone_material("bone", Color(0.92, 0.89, 0.82), Color(0.74, 0.69, 0.6), 0.5, 0.35, 0.0)
	_bone_lumpy = _bone_material("bone_lumpy", Color(0.9, 0.87, 0.8), Color(0.7, 0.65, 0.56), 0.6, 0.3, 0.22)
	_chalk = _bone_material("chalk", Color(0.8, 0.79, 0.76), Color(0.7, 0.69, 0.66), 0.0, 0.5, 0.0, 0.5)
	_chalk_pitted = _bone_material("chalk_pitted", Color(0.8, 0.79, 0.76), Color(0.7, 0.69, 0.66), 0.35, 0.5, 0.0, 0.5)
	_hive = _bone_material("hive", Color(0.9, 0.87, 0.8), Color(0.76, 0.71, 0.62), 0.8, 0.45, 0.0)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.97, 0.9)
	ResourceSaver.save(glow, MAT_DIR + "glow.tres")
	_glow = load(MAT_DIR + "glow.tres")

func _bone_material(mat_name: String, albedo: Color, mottle: Color, pits: float, pit_scale: float, lump: float, mottle_scale: float = 1.6) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = BONE_SHADER
	mat.set_shader_parameter("albedo", albedo)
	mat.set_shader_parameter("mottle", mottle)
	mat.set_shader_parameter("mottle_scale", mottle_scale)
	mat.set_shader_parameter("pit_amount", pits)
	mat.set_shader_parameter("pit_scale", pit_scale)
	mat.set_shader_parameter("pit_color", Color(0.1, 0.06, 0.055))
	mat.set_shader_parameter("lump", lump)
	mat.set_shader_parameter("lump_freq", 1.4)
	var path := MAT_DIR + mat_name + ".tres"
	ResourceSaver.save(mat, path)
	return load(path)

## ---- Bone Flats: bones and pitted boulders ---------------------------------

func _bone_flats_kit() -> void:
	var root := _root("PitBoulder")
	_part(root, _sphere(1.2, 1.7), _bone_lumpy, Vector3(0, 0.45, 0))
	_part(root, _sphere(0.5, 0.75), _bone_lumpy, Vector3(0.9, 0.12, 0.7))
	_save(root)

	root = _root("PitBoulderPile")
	_part(root, _sphere(0.9, 1.3), _bone_lumpy, Vector3(0, 0.35, 0))
	_part(root, _sphere(0.7, 1.0), _bone_lumpy, Vector3(1.1, 0.25, -0.4))
	_part(root, _sphere(0.5, 0.8), _bone_lumpy, Vector3(-0.5, 0.2, 1.0))
	_part(root, _sphere(0.3, 0.45), _bone_lumpy, Vector3(0.6, 0.1, 0.9))
	_save(root)

	root = _root("PitMound")
	_part(root, _sphere(2.2, 2.4), _bone_lumpy, Vector3(0, 0.3, 0))
	_part(root, _sphere(1.1, 1.4), _bone_lumpy, Vector3(1.6, 0.2, 1.2))
	_save(root)

	root = _root("PitPebbles")
	for i in 5:
		var r := _rng.randf_range(0.12, 0.28)
		_part(root, _sphere(r, r * 1.4), _bone_lumpy, Vector3(_rng.randf_range(-0.8, 0.8), r * 0.25, _rng.randf_range(-0.8, 0.8)))
	_save(root)

	_rib_cage()
	_vertebrae()

	root = _root("BoneSpire")
	var spire := _cylinder(0.05, 0.55, 5.0)
	_part(root, spire, _bone, Vector3(0, 2.4, 0), Vector3(0, 0, 10))
	for i in 6:
		var a := TAU * i / 6.0 + _rng.randf() * 0.4
		_part(root, _sphere(0.22, 0.3), _bone_lumpy, Vector3(cos(a) * 0.75, 0.05, sin(a) * 0.75))
	_save(root)

	root = _root("Tusk")
	_arc(root, Vector3.ZERO, 3.2, -0.15, PI * 0.62, 7, 0.42, 0.06, _bone, Vector3(0, 0, 1))
	_save(root)

## A half-buried rib cage: a spine along +X with ribs arching into the sand.
func _rib_cage() -> void:
	var root := _root("RibCage")
	var length := 5.0
	var ribs := 6
	for i in ribs:
		var x := -length / 2.0 + i * length / (ribs - 1)
		var r := lerpf(2.3, 1.4, float(i) / (ribs - 1))
		var lean := deg_to_rad(-12.0)
		for side in [-1.0, 1.0]:
			# Some ribs are broken off short.
			var reach := PI * 0.5 * (0.55 if _rng.randf() < 0.25 else 1.0)
			var steps := 5
			var prev := Vector3.ZERO
			for s in steps + 1:
				var t := PI * 0.5 - reach * float(s) / steps
				var p := Vector3(x + sin(lean) * r * (1.0 - sin(t)), r * 1.15 * sin(t), side * r * cos(t))
				if s > 0:
					_segment(root, prev, p, lerpf(0.16, 0.1, float(s) / steps), _bone)
				prev = p
	_segment(root, Vector3(-length / 2.0 - 0.8, 2.3 * 1.15, 0), Vector3(length / 2.0 + 0.4, 1.4 * 1.15, 0), 0.24, _bone)
	_save(root)

func _vertebrae() -> void:
	var root := _root("Vertebrae")
	var x := 0.0
	for i in 5:
		var s := lerpf(1.0, 0.55, i / 4.0)
		_part(root, _sphere(0.55 * s, 0.7 * s), _bone, Vector3(x, 0.15 * s, 0), Vector3(0, 0, 0), Vector3(1, 1, 1.25))
		_segment(root, Vector3(x, 0.3 * s, 0), Vector3(x - 0.25 * s, 1.2 * s, 0), 0.1 * s, _bone)
		_segment(root, Vector3(x, 0.2 * s, -0.4 * s), Vector3(x, 0.3 * s, -0.95 * s), 0.08 * s, _bone)
		_segment(root, Vector3(x, 0.2 * s, 0.4 * s), Vector3(x, 0.3 * s, 0.95 * s), 0.08 * s, _bone)
		x += 1.15 * s
	_save(root)

## ---- Meaningless structures ------------------------------------------------

func _structures_kit() -> void:
	var root := _root("StairsNowhere")
	for i in 7:
		_part(root, _box(Vector3(1.0, 0.35 * (i + 1), 2.4)), _chalk, Vector3(i * 1.0, 0.175 * (i + 1), 0))
	_save(root)

	root = _root("ArchNowhere")
	_arch(root, Vector3.ZERO, 2.8, 4.0, 0.6)
	_save(root)

	root = _root("Monolith")
	_part(root, _box(Vector3(0.5, 5.5, 2.0)), _chalk, Vector3(0, 2.6, 0), Vector3(4, 0, 2))
	_save(root)

	root = _root("StandingRing")
	_part(root, _torus(1.45, 1.85), _chalk, Vector3(0, 2.05, 0), Vector3(0, 0, 90))
	_part(root, _box(Vector3(0.8, 0.3, 1.2)), _chalk, Vector3(0, 0.15, 0))
	_save(root)

	root = _root("OrbPedestal")
	_part(root, _box(Vector3(1.0, 0.3, 1.0)), _chalk, Vector3(0, 0.15, 0))
	_part(root, _cylinder(0.3, 0.35, 1.3), _chalk, Vector3(0, 0.95, 0))
	_part(root, _sphere(0.55, 1.1), _chalk_pitted, Vector3(0, 2.15, 0))
	_save(root)

	root = _root("BuriedCube")
	_part(root, _box(Vector3(2.4, 2.4, 2.4)), _chalk, Vector3(0, 0.75, 0), Vector3(35, 20, 45))
	_save(root)

	root = _root("PaleLamp")
	_part(root, _cylinder(0.05, 0.08, 4.0), _chalk, Vector3(0, 2.0, 0))
	var orb := _part(root, _sphere(0.24, 0.48), _glow, Vector3(0, 4.15, 0))
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_save(root)

	# Landmarks.
	root = _root("Obelisk")
	_part(root, _box(Vector3(3.0, 0.6, 3.0)), _chalk, Vector3(0, 0.3, 0))
	_part(root, _cylinder(0.45, 1.1, 12.0, 4), _chalk, Vector3(0, 6.6, 0), Vector3(0, 45, 0))
	_part(root, _sphere(0.7, 1.4), _chalk_pitted, Vector3(0, 14.2, 0))
	_save(root)

	root = _root("GiantRing")
	_part(root, _torus(3.8, 4.9), _chalk_pitted, Vector3(0, 3.6, 0), Vector3(0, 0, 90))
	_save(root)

	root = _root("SkyStairs")
	for i in 16:
		var y := 0.55 * (i + 1)
		_part(root, _box(Vector3(0.9, 0.3, 2.2)), _chalk, Vector3(i * 0.9 - 6.75, y, 0))
		if i % 4 == 3:
			_part(root, _box(Vector3(0.35, y - 0.15, 0.35)), _chalk, Vector3(i * 0.9 - 6.75, (y - 0.15) / 2.0, 0))
	_save(root)

## ---- Buildings (fronts face +X) --------------------------------------------

func _buildings_kit() -> void:
	# A blank block with a grid of square reliefs where windows would be.
	var root := _root("NicheBlock")
	_part(root, _box(Vector3(8, 9, 10)), _chalk, Vector3(0, 4.5, 0))
	for row in 3:
		for col in 3:
			_part(root, _box(Vector3(0.3, 1.3, 1.3)), _chalk, Vector3(4.1, 2.8 + row * 2.4, -3.0 + col * 3.0))
	_arch(root, Vector3(4.3, 0, 0), 1.8, 2.4, 0.35)
	_save(root)

	root = _root("Ziggurat")
	var tiers := [Vector3(8, 3, 11), Vector3(6.4, 3, 9), Vector3(4.8, 3, 7), Vector3(3.2, 3, 5)]
	for i in tiers.size():
		var size: Vector3 = tiers[i]
		_part(root, _box(size), _chalk, Vector3((size.x - 8.0) / 2.0, 1.5 + i * 3.0, 0))
	_save(root)

	# Stairs climbing the front to a doorway in a solid wall.
	root = _root("StairFacade")
	_part(root, _box(Vector3(5, 10, 12)), _chalk, Vector3(-1.5, 5, 0))
	for i in 10:
		var h := 0.5 * (i + 1)
		_part(root, _box(Vector3(1.6, h, 0.8)), _chalk, Vector3(1.8, h / 2.0, -5.4 + i * 0.8))
	_part(root, _box(Vector3(1.6, 5.0, 2.0)), _chalk, Vector3(1.8, 2.5, 3.6))
	_arch(root, Vector3(1.4, 5.0, 3.6), 1.4, 2.6, 0.3)
	_save(root)

	root = _root("PittedMass")
	_part(root, _box(Vector3(8, 7, 10)), _chalk_pitted, Vector3(0, 3.5, 0))
	_part(root, _cylinder(2.4, 2.4, 4.0, 24), _chalk, Vector3(-0.5, 9.0, -1.0))
	_part(root, _sphere(1.6, 3.2), _chalk_pitted, Vector3(1.5, 7.0, 2.6))
	_save(root)

	# Columns holding up a lintel in front of a blank wall.
	root = _root("Colonnade")
	_part(root, _box(Vector3(4, 8.5, 12)), _chalk, Vector3(-2, 4.25, 0))
	for i in 5:
		_part(root, _cylinder(0.45, 0.5, 7.0, 16), _chalk, Vector3(2.0, 3.5, -4.8 + i * 2.4))
	_part(root, _box(Vector3(1.6, 0.8, 12.4)), _chalk, Vector3(2.0, 7.4, 0))
	_save(root)

	root = _root("HiveBlock")
	_part(root, _box(Vector3(7, 10, 9)), _hive, Vector3(0, 5, 0))
	_part(root, _box(Vector3(5, 3, 6)), _hive, Vector3(-0.5, 11.5, 0.5))
	_save(root)

## ---- Helpers ---------------------------------------------------------------

func _root(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	return root

func _save(root: Node3D) -> void:
	for child in root.find_children("*", "", true, false):
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT + String(root.name) + ".tscn")
	if err != OK:
		push_error("Failed to save %s: %d" % [root.name, err])
	root.free()

func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Part%d" % root.get_child_count()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	root.add_child(mi)
	return mi

## A capsule from a to b.
func _segment(root: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = a.distance_to(b) + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 4
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	var mi := _part(root, mesh, mat, (a + b) / 2.0)
	mi.basis = Basis(x, y, z)

## A tapering horn rising from base along an arc bending toward `bend`.
func _arc(root: Node3D, base: Vector3, radius: float, start: float, sweep: float, steps: int, r0: float, r1: float, mat: Material, bend: Vector3) -> void:
	var prev := base
	for s in steps:
		var t := start + sweep * float(s + 1) / steps
		var p := base + Vector3.UP * radius * sin(t) + bend * radius * (1.0 - cos(t))
		_segment(root, prev, p, lerpf(r0, r1, float(s) / steps), mat)
		prev = p

## Two pillars and a lintel spanning `span` (along Z), centred on base.
func _arch(root: Node3D, base: Vector3, span: float, height: float, thick: float) -> void:
	for side in [-1.0, 1.0]:
		_part(root, _box(Vector3(thick, height, thick)), _chalk, base + Vector3(0, height / 2.0, side * span / 2.0))
	_part(root, _box(Vector3(thick * 1.3, thick, span + thick * 2.0)), _chalk, base + Vector3(0, height + thick / 2.0, 0))

func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 32
	m.rings = 16
	return m

func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _cylinder(top: float, bottom: float, h: float, segments: int = 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segments
	return m

func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 48
	m.ring_segments = 16
	return m
