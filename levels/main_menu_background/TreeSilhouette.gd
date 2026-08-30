extends MeshInstance3D
class_name TreeSilhouette
## Procedural pine-tree silhouette - same cheap flat-facing-camera trick
## MountainRange.gd already uses for the mountain layers, giving the Main
## Menu backdrop a foreground depth layer instead of just two mountain
## ridges (user request: "add trees to the landscape"). A trunk sliver
## plus 3 stacked, narrowing triangular tiers reads as a conifer at
## silhouette distance without needing a real tree mesh/texture.

@export var trunk_height: float = 1.2
@export var trunk_width: float = 0.35
@export var canopy_height: float = 5.5
@export var canopy_base_width: float = 2.4
@export var tier_count: int = 3
@export var color: Color = Color(0.03, 0.035, 0.05)
@export var seed_value: int = 0

func _ready() -> void:
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Slight per-tree irregularity so a cluster doesn't look copy-pasted.
	var height_jitter: float = rng.randf_range(0.85, 1.15)
	var width_jitter: float = rng.randf_range(0.85, 1.15)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Trunk: a thin quad from the ground to where the canopy starts.
	_add_quad(st, Vector3(-trunk_width / 2.0, 0.0, 0.0), Vector3(trunk_width / 2.0, 0.0, 0.0),
		Vector3(-trunk_width / 2.0, trunk_height, 0.0), Vector3(trunk_width / 2.0, trunk_height, 0.0))

	# Canopy: stacked triangular tiers, each narrower and shorter than the
	# one below, overlapping slightly at the seams so no gap shows.
	var tier_h := (canopy_height * height_jitter) / float(tier_count)
	var overlap := tier_h * 0.35
	for i in range(tier_count):
		var t: float = float(i) / float(tier_count - 1) if tier_count > 1 else 0.0
		var base_w: float = lerp(canopy_base_width * width_jitter, canopy_base_width * width_jitter * 0.3, t)
		var y0: float = trunk_height + i * (tier_h - overlap)
		var y1: float = y0 + tier_h
		var half := base_w / 2.0
		st.add_vertex(Vector3(-half, y0, 0.0))
		st.add_vertex(Vector3(0.0, y1, 0.0))
		st.add_vertex(Vector3(half, y0, 0.0))

	st.generate_normals()
	mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_quad(st: SurfaceTool, bl: Vector3, br: Vector3, tl: Vector3, tr: Vector3) -> void:
	st.add_vertex(bl)
	st.add_vertex(tl)
	st.add_vertex(tr)
	st.add_vertex(bl)
	st.add_vertex(tr)
	st.add_vertex(br)
