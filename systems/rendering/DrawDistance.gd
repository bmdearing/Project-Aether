extends RefCounted
class_name DrawDistance
## Distance culling via GeometryInstance3D.visibility_range_end, so the
## renderer skips small things far from the camera. The range grows with
## an object's size; anything big enough to read as landscape is never culled.

const SMALL_SIZE := 2.5    # metres, the largest dimension
const MEDIUM_SIZE := 6.0
const SMALL_RANGE := 60.0
const MEDIUM_RANGE := 100.0
## Enemies: past this they're drawn off and their animation stops.
const ACTOR_RANGE := 95.0
## Hysteresis so an object on the boundary doesn't flicker.
const MARGIN := 4.0

static func range_for_size(largest_dimension: float) -> float:
	if largest_dimension < SMALL_SIZE:
		return SMALL_RANGE
	if largest_dimension < MEDIUM_SIZE:
		return MEDIUM_RANGE
	return 0.0

## Sets the range on every mesh under root (0 = always drawn).
static func apply(root: Node, range_end: float) -> void:
	if range_end <= 0.0:
		return
	var geometry: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		geometry.append(root)
	for node in geometry:
		var g := node as GeometryInstance3D
		g.visibility_range_end = range_end
		g.visibility_range_end_margin = MARGIN
