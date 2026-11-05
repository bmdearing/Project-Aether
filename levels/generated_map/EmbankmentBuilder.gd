extends RefCounted
class_name EmbankmentBuilder
## Grassy banks against open-field terrace sides, so a raised terrace reads
## as a hill rather than a box. A smooth noise field over the map picks each
## spot's steepness: most of a side slopes at 12-40 degrees, and where the
## noise peaks the bank tapers away and the sheer rock face shows as a cliff.
## The highest tier (the Vault's plateau) keeps sheer sides to mantle.
## The same noise drives neighbouring sides and the rounded corners between
## them, so banks and cliffs run into each other without seams.
##
## Faces are sampled every SAMPLE_STEP metres along each side; each sample
## keeps its run (how far the bank reaches out) and the ground height it
## lands on. height_at() reads those back for GeneratedMap.terrace_top().

const SAMPLE_STEP := 1.5
const PROFILE_ROWS := 5
const CORNER_STEPS := 7
const MIN_ANGLE_DEG := 12.0
const MAX_ANGLE_DEG := 40.0
## Noise share (0-1) where a bank starts tapering toward a cliff, and where
## it's fully gone.
const CLIFF_FROM := 0.64
const CLIFF_TO := 0.86
const MAX_RUN := 9.0
const MIN_DROP := 0.25
## Banks stop this far short of the field edge, where the boundary ridges sit.
const BOUNDARY_MARGIN := 9.0
const NOISE_FREQUENCY := 0.055
const FOOT_SKIRT := 0.15
## A run this long for its drop is walkable (the profile's steepest point
## is 1.5x its average slope; 1.6 keeps that under ~43 degrees).
const WALKABLE_RUN_PER_DROP := 1.6

var _map: GeneratedMap
var _floor_mat: Material
var _noise := FastNoiseLite.new()
var _field := Rect2()
## {"rect", "axis" (0: the side runs along x, 1: along z), "fixed" (the
## side's coordinate on the other axis), "out_sign", "lo", "hi", "step",
## "top", "runs": PackedFloat32Array, "lows": PackedFloat32Array}
var faces: Array[Dictionary] = []
## {"c": Vector2, "na": Vector2, "nb": Vector2, "top", "runs", "lows"}
var corners: Array[Dictionary] = []
## Sides of the highest tier (the Vault's plateau) stay sheer: every way to
## the Vault still crosses a ledge to mantle (v5.2 verticality).
var _cliff_top: float = INF

func _init(map: GeneratedMap, floor_mat: Material, field: Rect2) -> void:
	_map = map
	_floor_mat = floor_mat
	_field = field
	_noise.seed = map.map_seed ^ 0x5eed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = NOISE_FREQUENCY

## Banks for every given terrace. Call after the terraces exist and before
## climb links are placed (they go where the side is a cliff).
func build(terrace_list: Array[Dictionary]) -> void:
	for t in terrace_list:
		_cliff_top = maxf(_cliff_top if _cliff_top < INF else 0.0, float(t["top"]))
	for t in terrace_list:
		var rect: Rect2 = t["rect"]
		var top: float = t["top"]
		for side in _sides(rect):
			faces.append(_sample_face(rect, top, side))
		for c in _corners(rect):
			var fan := _sample_corner(top, c[0], c[1], c[2])
			if not fan.is_empty():
				corners.append(fan)
	if faces.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		_emit_face(st, f)
	for c in corners:
		_emit_corner(st, c)
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.name = "Embankments"
	_map.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if _floor_mat:
		# The ground shader maps by world XZ; wall mode switches to a side projection
		# on steep faces so steep banks don't smear.
		var mat := _floor_mat.duplicate() as Material
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("wall_mode", true)
		mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)

## [axis, fixed, out_sign, lo, hi] for the rect's four sides.
func _sides(r: Rect2) -> Array:
	return [
		[0, r.position.y, -1.0, r.position.x, r.end.x],
		[0, r.end.y, 1.0, r.position.x, r.end.x],
		[1, r.position.x, -1.0, r.position.y, r.end.y],
		[1, r.end.x, 1.0, r.position.y, r.end.y],
	]

## [corner, outward normal of one side, of the other] for each corner.
func _corners(r: Rect2) -> Array:
	return [
		[r.position, Vector2(0, -1), Vector2(-1, 0)],
		[Vector2(r.end.x, r.position.y), Vector2(1, 0), Vector2(0, -1)],
		[r.end, Vector2(0, 1), Vector2(1, 0)],
		[Vector2(r.position.x, r.end.y), Vector2(-1, 0), Vector2(0, 1)],
	]

static func _point(axis: int, along: float, fixed: float) -> Vector2:
	return Vector2(along, fixed) if axis == 0 else Vector2(fixed, along)

static func _out(axis: int, out_sign: float) -> Vector2:
	return Vector2(0, out_sign) if axis == 0 else Vector2(out_sign, 0)

func _sample_face(rect: Rect2, top: float, side: Array) -> Dictionary:
	var axis: int = side[0]
	var lo: float = side[3]
	var hi: float = side[4]
	var n := maxi(int(ceil((hi - lo) / SAMPLE_STEP)), 1)
	var out := _out(axis, side[2])
	var runs := PackedFloat32Array()
	var lows := PackedFloat32Array()
	for i in n + 1:
		var p := _point(axis, lerpf(lo, hi, float(i) / n), side[1])
		var s := _run_at(p, out, top)
		runs.append(s.x)
		lows.append(s.y)
	return {"rect": rect, "axis": axis, "fixed": side[1], "out_sign": side[2], "lo": lo, "hi": hi,
		"step": (hi - lo) / n, "top": top, "runs": runs, "lows": lows}

## A rounded fan between two sloped sides; empty where a terrace of the same
## height carries on past the corner (that side has no face there).
func _sample_corner(top: float, c: Vector2, na: Vector2, nb: Vector2) -> Dictionary:
	for beyond in [c + nb * 0.4 - na * 0.4, c + na * 0.4 - nb * 0.4]:
		if _ground(beyond) > top - MIN_DROP:
			return {}
	var runs := PackedFloat32Array()
	var lows := PackedFloat32Array()
	var any := false
	for s in CORNER_STEPS + 1:
		var a := PI / 2.0 * s / CORNER_STEPS
		var sample := _run_at(c, na * cos(a) + nb * sin(a), top)
		runs.append(sample.x)
		lows.append(sample.y)
		any = any or sample.x > 0.05
	if not any:
		return {}
	return {"c": c, "na": na, "nb": nb, "top": top, "runs": runs, "lows": lows}

## Terraces only: the ground the bank lands on.
func _ground(p: Vector2) -> float:
	return _map.terrace_top(Vector3(p.x, 0, p.y), false, false)

## (run, ground height) for a bank leaving the terrace edge at p, heading out.
func _run_at(p: Vector2, out: Vector2, top: float) -> Vector2:
	var low := _ground(p + out * 0.4)
	var drop := top - low
	if drop < MIN_DROP or top >= _cliff_top - 0.01:
		return Vector2(0.0, low)
	var t := clampf(0.5 + _noise.get_noise_2d(p.x, p.y) * 0.9, 0.0, 1.0)
	var angle := deg_to_rad(lerpf(MIN_ANGLE_DEG, MAX_ANGLE_DEG, clampf(t / CLIFF_FROM, 0.0, 1.0)))
	var run := minf(drop / tan(angle) * (1.0 - smoothstep(CLIFF_FROM, CLIFF_TO, t)), MAX_RUN)
	var foot := p + out * run
	if not _field.grow(-BOUNDARY_MARGIN).has_point(foot):
		return Vector2(0.0, low)
	if _map.water and (_map.water.is_wet(Vector3(foot.x, low, foot.y), 1.0) or _map.water.is_wet(Vector3(p.x, low, p.y) + Vector3(out.x, 0, out.y) * run * 0.5, 1.0)):
		return Vector2(0.0, low)
	# The bank must land on flat ground of its own level, not climb another terrace.
	if absf(_ground(foot) - low) > 0.05:
		return Vector2(0.0, low)
	return Vector2(run, low)

## Shoulder to foot: flat at the top edge, steepest midway, easing out at the foot.
static func _profile(u: float) -> float:
	return 1.0 - smoothstep(0.0, 1.0, u)

func _row_vertex(edge: Vector2, out: Vector2, run: float, low: float, top: float, k: int) -> Vector3:
	var u := float(k) / PROFILE_ROWS
	var d := run * u
	var y := low + (top - low) * _profile(u)
	if k == 0:
		d = -0.03  # tucks under the terrace top so no crack shows
		y = top + 0.005
	elif k == PROFILE_ROWS:
		d += 0.1
		y = low - FOOT_SKIRT
	var p := edge + out * d
	return Vector3(p.x, y, p.y)

func _emit_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# a-b along the top row, c-d below them; wound so the face points outward and up.
	for v in [a, c, b, b, c, d]:
		st.set_uv(Vector2(v.x, v.z) * 0.25)
		st.add_vertex(v)

func _emit_strip(st: SurfaceTool, edges: Array, outs: Array, runs: PackedFloat32Array, lows: PackedFloat32Array, top: float, flip: bool) -> void:
	for i in edges.size() - 1:
		if runs[i] < 0.05 and runs[i + 1] < 0.05:
			continue  # cliff: the rock face shows
		for k in PROFILE_ROWS:
			var a := _row_vertex(edges[i], outs[i], runs[i], lows[i], top, k)
			var b := _row_vertex(edges[i + 1], outs[i + 1], runs[i + 1], lows[i + 1], top, k)
			var c := _row_vertex(edges[i], outs[i], runs[i], lows[i], top, k + 1)
			var d := _row_vertex(edges[i + 1], outs[i + 1], runs[i + 1], lows[i + 1], top, k + 1)
			if flip:
				_emit_quad(st, b, a, d, c)
			else:
				_emit_quad(st, a, b, c, d)

func _emit_face(st: SurfaceTool, f: Dictionary) -> void:
	var out := _out(f["axis"], f["out_sign"])
	var edges := []
	var outs := []
	for i in (f["runs"] as PackedFloat32Array).size():
		edges.append(_point(f["axis"], float(f["lo"]) + float(f["step"]) * i, f["fixed"]))
		outs.append(out)
	# Winding depends on which way the side runs relative to its outward normal.
	var along := Vector2(1, 0) if int(f["axis"]) == 0 else Vector2(0, 1)
	_emit_strip(st, edges, outs, f["runs"], f["lows"], f["top"], along.cross(out) > 0.0)

func _emit_corner(st: SurfaceTool, c: Dictionary) -> void:
	var edges := []
	var outs := []
	var na: Vector2 = c["na"]
	var nb: Vector2 = c["nb"]
	for s in CORNER_STEPS + 1:
		var a := PI / 2.0 * s / CORNER_STEPS
		edges.append(c["c"])
		outs.append(na * cos(a) + nb * sin(a))
	_emit_strip(st, edges, outs, c["runs"], c["lows"], c["top"], na.cross(nb) > 0.0)

## The bank's surface height at p, or -INF off every bank.
func height_at(p: Vector2) -> float:
	var best := -INF
	for f in faces:
		var axis: int = f["axis"]
		var along := p.x if axis == 0 else p.y
		if along < float(f["lo"]) or along > float(f["hi"]):
			continue
		var d := ((p.y if axis == 0 else p.x) - float(f["fixed"])) * float(f["out_sign"])
		if d < 0.0 or d > MAX_RUN:
			continue
		var s := _interp(f["runs"], f["lows"], (along - float(f["lo"])) / float(f["step"]))
		if d < s.x:
			best = maxf(best, s.y + (float(f["top"]) - s.y) * _profile(d / s.x))
	for c in corners:
		var v: Vector2 = p - (c["c"] as Vector2)
		var x := v.dot(c["na"])
		var y := v.dot(c["nb"])
		if x < 0.0 or y < 0.0 or v.length() > MAX_RUN:
			continue
		var s := _interp(c["runs"], c["lows"], atan2(y, x) / (PI / 2.0) * CORNER_STEPS)
		if v.length() < s.x:
			best = maxf(best, s.y + (float(c["top"]) - s.y) * _profile(v.length() / s.x))
	return best

static func _interp(runs: PackedFloat32Array, lows: PackedFloat32Array, f: float) -> Vector2:
	var i := clampi(int(floor(f)), 0, runs.size() - 1)
	var j := mini(i + 1, runs.size() - 1)
	var t := clampf(f - i, 0.0, 1.0)
	return Vector2(lerpf(runs[i], runs[j], t), lerpf(lows[i], lows[j], t))

## The face on rect's side facing out, or {}.
func face_for(rect: Rect2, out: Vector2) -> Dictionary:
	for f in faces:
		if f["rect"] == rect and _out(f["axis"], f["out_sign"]).is_equal_approx(out):
			return f
	return {}

## [along, run] of the cliffiest sample on a face (where a climb link goes),
## or [] when the face has a walkable stretch and needs no link.
func link_spot(f: Dictionary) -> Array:
	var runs: PackedFloat32Array = f["runs"]
	var lows: PackedFloat32Array = f["lows"]
	var best := 0
	var walkable_streak := 0
	for i in runs.size():
		if runs[i] < runs[best]:
			best = i
		var drop: float = float(f["top"]) - lows[i]
		walkable_streak = walkable_streak + 1 if drop > 0.0 and runs[i] >= drop * WALKABLE_RUN_PER_DROP else 0
		if walkable_streak >= 3:
			return []
	return [float(f["lo"]) + float(f["step"]) * best, runs[best]]
