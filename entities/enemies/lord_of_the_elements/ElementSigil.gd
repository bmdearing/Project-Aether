extends Node3D
class_name ElementSigil
## A sigil one of the Lord of the Elements' orbs burns into the crescent.
## Standing in it changes the damage you take: hits of any other element are
## reduced (PROTECTED_MULTIPLIER), hits of its own element are increased
## (MATCHED_MULTIPLIER). So you want the sigil whose element he isn't using.
## Player.take_damage() asks every node in the "damage_zone" group.

const RADIUS := 3.0
const PROTECTED_MULTIPLIER := 0.6
const MATCHED_MULTIPLIER := 1.25
const FADE_IN := 0.6
## The orb that made it hovers this high over the centre.
const ORB_HEIGHT := 1.6

var element: int = Constants.DamageType.FIRE
## The boss whose current element decides safe vs. dangerous.
var lord: Node
var _ring: MeshInstance3D
var _glyph: MeshInstance3D
var _column: MeshInstance3D
var _light: OmniLight3D
var _ring_mat: StandardMaterial3D
var _glyph_mat: StandardMaterial3D
var _column_mat: StandardMaterial3D
var _age := 0.0
var _fading := false

func _ready() -> void:
	add_to_group("damage_zone")
	add_to_group("element_sigil")
	var color := _color()
	_ring_mat = _material(color, 0.9)
	_glyph_mat = _material(color, 0.55)
	_column_mat = _material(color, 0.0)
	_column_mat.cull_mode = BaseMaterial3D.CULL_BACK  # seen from outside only; from inside it would tint the whole view
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.18
	torus.outer_radius = RADIUS
	torus.rings = 48
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.06, 1)
	_ring.position.y = 0.05
	_ring.material_override = _ring_mat
	add_child(_ring)
	_glyph = MeshInstance3D.new()
	_glyph.mesh = _glyph_mesh()
	_glyph.position.y = 0.06
	_glyph.material_override = _glyph_mat
	add_child(_glyph)
	_column = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS * 0.95
	cylinder.bottom_radius = RADIUS
	cylinder.height = 3.0
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	_column.mesh = cylinder
	_column.position.y = 1.5
	_column.material_override = _column_mat
	add_child(_column)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.0
	_light.omni_range = RADIUS * 2.2
	_light.position.y = 1.0
	add_child(_light)
	for m in [_ring, _glyph, _column]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Where the orb hovers once it has landed.
func orb_spot() -> Vector3:
	return global_position + Vector3(0, ORB_HEIGHT, 0)

func contains(point: Vector3) -> bool:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() <= RADIUS and absf(offset.y) < 3.0

## Player.take_damage() hook: a hit of damage_type taken by player.
func damage_multiplier_for(player: Node3D, damage_type: int) -> float:
	if _fading or _age < FADE_IN or not contains(player.global_position):
		return 1.0
	return MATCHED_MULTIPLIER if damage_type == element else PROTECTED_MULTIPLIER

## True while he's using this sigil's element (standing in it is a mistake).
func is_dangerous() -> bool:
	return is_instance_valid(lord) and lord.get("current_element") == element

func fade_out() -> void:
	_fading = true
	remove_from_group("damage_zone")
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 1, 0.01), 0.5)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	_age += delta
	var appear := clampf(_age / FADE_IN, 0.0, 1.0)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var inside := player != null and contains(player.global_position)
	var danger := is_dangerous()
	var pulse := 0.5 + 0.5 * sin(_age * (9.0 if danger else 3.0))
	var color := _color()
	var tint := color.lerp(Color(1.0, 0.15, 0.1), 0.65) if danger else color
	var strength := (1.0 if inside else 0.55) * appear
	_ring_mat.albedo_color = Color(tint, (0.6 + 0.4 * pulse) * strength)
	_glyph_mat.albedo_color = Color(tint, (0.3 + 0.3 * pulse) * strength)
	_column_mat.albedo_color = Color(color, (0.1 + 0.05 * pulse) * appear if inside and not danger else 0.0)
	_light.light_color = tint
	_light.light_energy = (1.6 if inside else 0.8) * appear
	_glyph.rotation.y += delta * (0.6 if danger else 0.25)

func _color() -> Color:
	return Constants.DAMAGE_TYPE_COLOR.get(element, Color.WHITE)

func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, alpha)
	return mat

## Inner rune: an inner ring plus a star whose point count marks the element
## (Fire 3, Cold 6, Lightning 4), as flat strips on the ground.
func _glyph_mesh() -> ArrayMesh:
	var points: int = {Constants.DamageType.FIRE: 3, Constants.DamageType.COLD: 6, Constants.DamageType.LIGHTNING: 4}.get(element, 5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RADIUS * 0.78
	var corners: Array[Vector3] = []
	for i in points:
		var a := TAU * i / points
		corners.append(Vector3(sin(a), 0, cos(a)) * r)
	for i in points:
		_strip(st, corners[i], corners[(i + (2 if points > 4 else 1)) % points], 0.08)
	for i in 32:
		var a0 := TAU * i / 32.0
		var a1 := TAU * (i + 1) / 32.0
		_strip(st, Vector3(sin(a0), 0, cos(a0)) * r * 0.55, Vector3(sin(a1), 0, cos(a1)) * r * 0.55, 0.06)
	return st.commit()

func _strip(st: SurfaceTool, a: Vector3, b: Vector3, width: float) -> void:
	var side := (b - a).cross(Vector3.UP).normalized() * width
	st.add_vertex(a - side)
	st.add_vertex(a + side)
	st.add_vertex(b + side)
	st.add_vertex(a - side)
	st.add_vertex(b + side)
	st.add_vertex(b - side)
