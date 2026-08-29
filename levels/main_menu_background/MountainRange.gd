extends MeshInstance3D
class_name MountainRange
## Procedural mountain silhouette - a single jagged flat facing the
## camera, unshaded flat color, no back/sides. Same layered-2D-flats
## trick classic side-scrollers use for parallax backdrops; cheapest way
## to fake a mountain range with no height-map/terrain assets.

@export var width: float = 400.0
@export var base_height: float = 40.0
@export var peak_variance: float = 35.0
@export var segment_count: int = 24
@export var base_y: float = 0.0
@export var color: Color = Color(0.1, 0.12, 0.18)
@export var seed_value: int = 0

func _ready() -> void:
	_build()

func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var half_width := width / 2.0
	var step := width / float(segment_count)
	# A smoothed random walk (each point pulled toward the last) reads as
	# a connected ridge instead of independent spikes.
	var heights: Array[float] = []
	var prev_height := base_height
	for i in range(segment_count + 1):
		var h: float = base_height + rng.randf_range(-peak_variance, peak_variance)
		h = lerp(prev_height, h, 0.6)
		heights.append(h)
		prev_height = h

	for i in range(segment_count):
		var x0 := -half_width + step * i
		var x1 := -half_width + step * (i + 1)
		var y0 := base_y + heights[i]
		var y1 := base_y + heights[i + 1]
		var bl := Vector3(x0, base_y, 0.0)
		var br := Vector3(x1, base_y, 0.0)
		var tl := Vector3(x0, y0, 0.0)
		var tr := Vector3(x1, y1, 0.0)
		st.add_vertex(bl)
		st.add_vertex(tl)
		st.add_vertex(tr)
		st.add_vertex(bl)
		st.add_vertex(tr)
		st.add_vertex(br)

	st.generate_normals()
	mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
