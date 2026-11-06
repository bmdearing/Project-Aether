extends RefCounted
class_name EmbankmentBuilder
## Grassy banks against open-field terrace sides, so a raised terrace reads
## as a hill rather than a box. A smooth noise field over the map shapes
## each spot: most of a side is a full-height bank at 12-27 degrees; where
## the noise peaks the bank sinks into a low scree slope at the cliff's foot
## and then away, leaving the sheer rock face. A bank is never too steep to
## stand on, so there's no crease to get wedged in. The highest tier (the
## Vault's plateau) keeps sheer sides to mantle. The same noise drives
## neighbouring sides and the rounded corners between them, so banks and
## cliffs run into each other without seams.
##
## Faces are sampled every SAMPLE_STEP metres along each side. Each sample is
## Vector3(run, ground, bank top): how far the bank reaches out, the height it
## lands on, and the height it meets the face at. height_at() reads them back
## for GeneratedMap.terrace_top().

const SAMPLE_STEP := 1.5
const PROFILE_ROWS := 5
const CORNER_STEPS := 7
## Average slope; the profile's steepest point is 1.5x this (27 -> ~37 degrees,
## under the player's 45-degree floor limit).
const MIN_ANGLE_DEG := 12.0
const MAX_ANGLE_DEG := 27.0
## Noise share (0-1) where a bank starts sinking toward the cliff's foot, and
## where it's gone.
const CLIFF_FROM := 0.55
const CLIFF_TO := 0.9
## Lower than this, a sinking bank is dropped.
const MIN_BANK_HEIGHT := 0.3
const MAX_RUN := 9.0
const MIN_DROP := 0.25
## Banks stop this far short of the field edge, where the boundary ridges sit.
const BOUNDARY_MARGIN := 9.0
const NOISE_FREQUENCY := 0.055
const FOOT_SKIRT := 0.15
## A full-height stretch at least this long (in samples) means the side can
## be walked up and needs no climb link.
const WALKABLE_STREAK := 3

var _map: GeneratedMap
var _floor_mat: Material
var _noise := FastNoiseLite.new()
var _field := Rect2()
## {"rect", "axis" (0: the side runs along x, 1: along z), "fixed" (the
## side's coordinate on the other axis), "out_sign", "lo", "hi", "step",
## "top", "samples": Array[Vector3]}
var faces: Array[Dictionary] = []
## {"c": Vector2, "na": Vector2, "nb": Vector2, "top", "samples"}
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
	if terrace_list.is_empty():
		return
	_cliff_top = 0.0
	for t in terrace_list:
		_cliff_top = maxf(_cliff_top, float(t["top"]))
	for t in terrace_list:
		var rect: Rect2 = t["rect"]
		var top: float = t["top"]
		for side in _sides(rect):
			faces.append(_sample_face(rect, top, side))
		for c in _corners(rect):
			var fan := _sample_corner(top, c[0], c[1], c[2])
			if not fan.is_empty():
				corners.append(fan)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for f in faces:
		any = _emit_face(st, f) or any
	for c in corners:
		any = _emit_corner(st, c) or any
	if not any:
		return
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.name = "Embankments"
	_map.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if _floor_mat:
		# The ground shader maps by world XZ; wall mode switches to a side
		# projection on steep faces so banks don't smear.
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
	var samples: Array[Vector3] = []
	for i in n + 1:
		samples.append(_sample(_point(axis, lerpf(lo, hi, float(i) / n), side[1]), out, top))
	_limit_along(samples, (hi - lo) / n)
	return {"rect": rect, "axis": axis, "fixed": side[1], "out_sign": side[2], "lo": lo, "hi": hi,
		"step": (hi - lo) / n, "top": top, "samples": samples}

## Caps how fast a bank's height changes along a side, so where it sinks
## toward a cliff its edge stays walkable (lowering only, keeping the slope;
## the end samples are left alone so corners still meet them).
const MAX_ALONG_SLOPE_DEG := 30.0

func _limit_along(samples: Array[Vector3], step: float) -> void:
	var most := step * tan(deg_to_rad(MAX_ALONG_SLOPE_DEG))
	for pass_dir in [1, -1]:
		var order := range(1, samples.size() - 1) if pass_dir == 1 else range(samples.size() - 2, 0, -1)
		for i in order:
			var s := samples[i]
			var n := samples[i - pass_dir]
			var h := s.z - s.y
			var cap := (n.z - n.y) + most
			if s.x > 0.05 and h > cap:
				var k := cap / h
				samples[i] = Vector3(s.x * k, s.y, s.y + cap) if cap >= MIN_BANK_HEIGHT else Vector3(0.0, s.y, s.y)

## A rounded fan between two banked sides; empty where a terrace of the same
## height carries on past the corner (that side has no face there).
func _sample_corner(top: float, c: Vector2, na: Vector2, nb: Vector2) -> Dictionary:
	for beyond in [c + nb * 0.4 - na * 0.4, c + na * 0.4 - nb * 0.4]:
		if _ground(beyond) > top - MIN_DROP:
			return {}
	var samples: Array[Vector3] = []
	var any := false
	for s in CORNER_STEPS + 1:
		var a := PI / 2.0 * s / CORNER_STEPS
		var sample := _sample(c, na * cos(a) + nb * sin(a), top)
		samples.append(sample)
		any = any or sample.x > 0.05
	if not any:
		return {}
	return {"c": c, "na": na, "nb": nb, "top": top, "samples": samples}

## Terraces only: the ground the bank lands on.
func _ground(p: Vector2) -> float:
	return _map.terrace_top(Vector3(p.x, 0, p.y), false, false)

## Vector3(run, ground, bank top) for a bank leaving the terrace edge at p.
## Run 0 means the sheer face shows.
func _sample(p: Vector2, out: Vector2, top: float) -> Vector3:
	var low := _ground(p + out * 0.4)
	var none := Vector3(0.0, low, low)
	var drop := top - low
	if drop < MIN_DROP or top >= _cliff_top - 0.01:
		return none
	var t := clampf(0.5 + _noise.get_noise_2d(p.x, p.y) * 0.9, 0.0, 1.0)
	var height := drop * (1.0 - smoothstep(CLIFF_FROM, CLIFF_TO, t))
	if height < MIN_BANK_HEIGHT:
		return none
	var angle := deg_to_rad(lerpf(MIN_ANGLE_DEG, MAX_ANGLE_DEG, clampf(t / CLIFF_FROM, 0.0, 1.0)))
	var run := height / tan(angle)
	if run > MAX_RUN:
		run = MAX_RUN
		height = minf(height, MAX_RUN * tan(angle))
	# Where the full bank won't fit (water, the field edge, another level),
	# a smaller one does: the same slope, shorter and lower. Cutting it to
	# nothing in one step would leave a steep crease against the face.
	for scale in [1.0, 0.8, 0.6, 0.4, 0.25]:
		if height * scale >= MIN_BANK_HEIGHT and _fits(p, out, run * scale, low):
			return _close_lip(Vector3(run * scale, low, low + height * scale), p, out, top)
	return none

## A bank that ends a little short of the top looks like a ramp but leaves a
## lip the player walks into and stops at. Within LIP_SNAP of the top it goes
## all the way up instead, lengthening its run (if it fits) to stay under
## MAX_SNAP_SLOPE; failing that it keeps its lip, which then reads as a cliff.
const LIP_SNAP := 0.75
## Average slope (tan) a closed bank may reach: the profile's steepest point
## is 1.5x this, ~42 degrees, under the player's 45-degree floor limit.
const MAX_SNAP_SLOPE := 0.6

func _close_lip(s: Vector3, p: Vector2, out: Vector2, top: float) -> Vector3:
	var lip := top - s.z
	if lip <= 0.01 or lip > LIP_SNAP or s.x <= 0.05:
		return s
	var run := maxf(s.x, (top - s.y) / MAX_SNAP_SLOPE)
	if run > MAX_RUN + 0.01 or not _fits(p, out, run, s.y):
		return s
	return Vector3(run, s.y, top)

func _fits(p: Vector2, out: Vector2, run: float, low: float) -> bool:
	var foot := p + out * run
	if not _field.grow(-BOUNDARY_MARGIN).has_point(foot):
		return false
	if _map.water and (_map.water.is_wet(Vector3(foot.x, low, foot.y), 1.0) or _map.water.is_wet(Vector3(p.x, low, p.y) + Vector3(out.x, 0, out.y) * run * 0.5, 1.0)):
		return false
	# The bank must land on flat ground of its own level, not climb another terrace.
	for f in [0.5, 1.0]:
		if absf(_ground(p + out * run * f) - low) > 0.05:
			return false
	return true

## Shoulder to foot: flat at the top edge, steepest midway, easing out at the foot.
static func _profile(u: float) -> float:
	return 1.0 - smoothstep(0.0, 1.0, u)

func _row_vertex(edge: Vector2, out: Vector2, s: Vector3, k: int) -> Vector3:
	var u := float(k) / PROFILE_ROWS
	var d := s.x * u
	var y := s.y + (s.z - s.y) * _profile(u)
	if k == 0:
		d = -0.03  # tucks into the face so no crack shows
		y = s.z + 0.005
	elif k == PROFILE_ROWS:
		d += 0.1
		y = s.y - FOOT_SKIRT
	var p := edge + out * d
	return Vector3(p.x, y, p.y)

func _emit_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# a-b along the top row, c-d below them; wound so the face points outward and up.
	for v in [a, c, b, b, c, d]:
		st.set_uv(Vector2(v.x, v.z) * 0.25)
		st.add_vertex(v)

func _emit_strip(st: SurfaceTool, edges: Array, outs: Array, samples: Array[Vector3], flip: bool) -> bool:
	var any := false
	for i in edges.size() - 1:
		var s0 := samples[i]
		var s1 := samples[i + 1]
		if s0.x < 0.05 and s1.x < 0.05:
			continue  # cliff: the rock face shows
		any = true
		for k in PROFILE_ROWS:
			var a := _row_vertex(edges[i], outs[i], s0, k)
			var b := _row_vertex(edges[i + 1], outs[i + 1], s1, k)
			var c := _row_vertex(edges[i], outs[i], s0, k + 1)
			var d := _row_vertex(edges[i + 1], outs[i + 1], s1, k + 1)
			if flip:
				_emit_quad(st, b, a, d, c)
			else:
				_emit_quad(st, a, b, c, d)
	return any

func _emit_face(st: SurfaceTool, f: Dictionary) -> bool:
	var out := _out(f["axis"], f["out_sign"])
	var edges := []
	var outs := []
	var samples: Array[Vector3] = f["samples"]
	for i in samples.size():
		edges.append(_point(f["axis"], float(f["lo"]) + float(f["step"]) * i, f["fixed"]))
		outs.append(out)
	var along := Vector2(1, 0) if int(f["axis"]) == 0 else Vector2(0, 1)
	return _emit_strip(st, edges, outs, samples, along.cross(out) > 0.0)

func _emit_corner(st: SurfaceTool, c: Dictionary) -> bool:
	var edges := []
	var outs := []
	var na: Vector2 = c["na"]
	var nb: Vector2 = c["nb"]
	for s in CORNER_STEPS + 1:
		var a := PI / 2.0 * s / CORNER_STEPS
		edges.append(c["c"])
		outs.append(na * cos(a) + nb * sin(a))
	return _emit_strip(st, edges, outs, c["samples"], na.cross(nb) > 0.0)

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
		var s := _interp(f["samples"], (along - float(f["lo"])) / float(f["step"]))
		if d < s.x:
			best = maxf(best, s.y + (s.z - s.y) * _profile(d / s.x))
	for c in corners:
		var v: Vector2 = p - (c["c"] as Vector2)
		var x := v.dot(c["na"])
		var y := v.dot(c["nb"])
		if x < 0.0 or y < 0.0 or v.length() > MAX_RUN:
			continue
		var s := _interp(c["samples"], atan2(y, x) / (PI / 2.0) * CORNER_STEPS)
		if v.length() < s.x:
			best = maxf(best, s.y + (s.z - s.y) * _profile(v.length() / s.x))
	return best

static func _interp(samples: Array[Vector3], f: float) -> Vector3:
	var i := clampi(int(floor(f)), 0, samples.size() - 1)
	var j := mini(i + 1, samples.size() - 1)
	return samples[i].lerp(samples[j], clampf(f - i, 0.0, 1.0))

## The face on rect's side facing out, or {}.
func face_for(rect: Rect2, out: Vector2) -> Dictionary:
	for f in faces:
		if f["rect"] == rect and _out(f["axis"], f["out_sign"]).is_equal_approx(out):
			return f
	return {}

## [along, run] of the best climb spot on a face (sheer, or the lowest bank
## there), or [] when a full-height stretch makes the side walkable.
func link_spot(f: Dictionary) -> Array:
	var samples: Array[Vector3] = f["samples"]
	var top: float = f["top"]
	var best := 0
	var streak := 0
	for i in samples.size():
		var s := samples[i]
		if s.z - s.y < samples[best].z - samples[best].y:
			best = i
		streak = streak + 1 if s.x > 0.05 and s.z >= top - 0.05 else 0
		if streak >= WALKABLE_STREAK:
			return []
	return [float(f["lo"]) + float(f["step"]) * best, samples[best].x]
