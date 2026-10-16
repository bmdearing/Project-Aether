extends RefCounted
class_name GroundHit
## Hits marked on the ground (rings, swings) reach a column above their
## ground, so a jump (the player rises ~2.5 m) never clears them. Only
## attacks built to be jumped, like Ataras's Desert Sweep, check height
## themselves.

const ABOVE := 4.0
const BELOW := 3.0

static func in_column(ground: Vector3, point: Vector3) -> bool:
	var dy := point.y - ground.y
	return dy >= -BELOW and dy <= ABOVE

static func in_circle(center: Vector3, radius: float, point: Vector3, margin: float = 0.4) -> bool:
	return in_column(center, point) and Vector2(point.x - center.x, point.z - center.z).length() <= radius + margin
