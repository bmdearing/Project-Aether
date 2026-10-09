extends StaticBody3D
class_name MawPylon
## An Anchor pylon in the Herald of the Maw's arena (MawArena), one per Maw
## Fragment. It stands on its own spire out of the void, so it outlives the
## plates around it. While it stands it:
##   - blocks shots (it's on the default physics layer),
##   - stuns the Herald when her Shadow Lunge runs into it,
##   - anchors a player within SHELTER_RADIUS against Unmaking's pull,
##   - raises the Herald's Lens drop chance (Pinnacle.maw_lens_chance()).
## Mindbenders channel at it; a finished channel shatters it.

signal shattered(pylon: MawPylon)

const RADIUS := 0.9
const HEIGHT := 6.5
## The spire reaches this far down into the void.
const SPIRE_DEPTH := 40.0
const SHELTER_RADIUS := 4.0
const CRYSTAL_HEIGHT := HEIGHT + 0.9

var fragment_id: StringName = &""
var color := Color(0.6, 0.35, 0.9)
var alive := true
## Channel progress from Mindbenders (0..1), shown as flicker and strain.
var strain := 0.0
var _crystal: MeshInstance3D
var _crystal_mat: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0

func _ready() -> void:
	add_to_group("maw_pylon")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.1, 0.09, 0.12)
	stone.roughness = 0.85

	var spire := MeshInstance3D.new()
	var spire_mesh := CylinderMesh.new()
	spire_mesh.top_radius = RADIUS
	spire_mesh.bottom_radius = RADIUS * 0.35
	spire_mesh.height = HEIGHT + SPIRE_DEPTH
	spire_mesh.radial_segments = 6
	spire.mesh = spire_mesh
	spire.position.y = (HEIGHT - SPIRE_DEPTH) / 2.0
	spire.material_override = stone
	add_child(spire)

	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT + SPIRE_DEPTH
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = spire.position.y
	add_child(collision)

	_rune_mat = _glow_material(color, 2.0)
	for i in 3:
		var band := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = RADIUS * 0.98
		torus.outer_radius = RADIUS * 1.08
		band.mesh = torus
		band.position.y = 1.4 + i * 1.7
		band.scale = Vector3(1, 0.5, 1)
		band.material_override = _rune_mat
		add_child(band)

	_crystal_mat = _glow_material(color, 3.0)
	_crystal = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = 0.55
	gem.height = 1.6
	gem.radial_segments = 4
	gem.rings = 2
	_crystal.mesh = gem
	_crystal.position.y = CRYSTAL_HEIGHT
	_crystal.material_override = _crystal_mat
	add_child(_crystal)

	# The shelter radius, faint on the floor.
	_ring_mat = _glow_material(color, 0.8)
	_ring_mat.albedo_color.a = 0.5
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = SHELTER_RADIUS - 0.1
	ring_mesh.outer_radius = SHELTER_RADIUS
	ring_mesh.rings = 48
	ring.mesh = ring_mesh
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.04
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.6
	_light.omni_range = 9.0
	_light.position.y = CRYSTAL_HEIGHT
	add_child(_light)

func _process(delta: float) -> void:
	if not alive:
		return
	_t += delta
	_crystal.rotation.y += delta * (0.6 + strain * 4.0)
	_crystal.position.y = CRYSTAL_HEIGHT + sin(_t * 1.3) * 0.15
	# A strained pylon flickers harder as the channel nears completion.
	var flicker := 1.0 - strain * 0.7 * (0.5 + 0.5 * sin(_t * (8.0 + strain * 30.0)))
	_light.light_energy = 1.6 * flicker
	_crystal_mat.emission_energy_multiplier = 3.0 * flicker

func shelters(point: Vector3) -> bool:
	if not alive:
		return false
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() <= SHELTER_RADIUS

func shatter() -> void:
	if not alive:
		return
	alive = false
	strain = 0.0
	collision_layer = 0
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	shattered.emit(self)
	var tween := create_tween().set_parallel()
	tween.tween_property(_crystal, "scale", Vector3.ONE * 0.05, 0.5)
	tween.tween_property(_light, "light_energy", 0.0, 0.6)
	tween.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.6)
	tween.tween_property(self, "position:y", position.y - 30.0, 3.0).set_delay(0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(hide)

static func _glow_material(c: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = energy
	return mat
