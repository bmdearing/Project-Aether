class_name BloodFx
## Bloodborne-style hit feedback: blood thrown off along the blow, a mist,
## a pool under the body, and wet gore sounds on heavy blows. Golems, orbs
## and other constructs throw sparks and grit instead (Enemy.bleeds()).

const BLOOD := Color(0.5, 0.02, 0.03)
const MIST := Color(0.55, 0.03, 0.04, 0.7)
const POOL := Color(0.16, 0.0, 0.01, 0.85)
const GRIT := Color(0.45, 0.4, 0.35)
const SPARK := Color(1.0, 0.8, 0.45)
const POOL_SECONDS := 9.0

static var _gore: Array[AudioStream] = []
static var _flesh: Array[AudioStream] = []
static var _bone: Array[AudioStream] = []

static func _sounds(prefix: String, count: int) -> Array[AudioStream]:
	var found: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path := "res://assets/sfx/combat/%s_%02d.ogg" % [prefix, i]
		if ResourceLoader.exists(path):
			found.append(load(path))
	return found

static func _play(arr: Array[AudioStream], at: Vector3, volume_db: float) -> void:
	if not arr.is_empty():
		AudioManager.play_at(arr.pick_random(), at, volume_db)

## A landed blow. `dir`: the way it travelled. weight 1 is a normal hit;
## crits, kills and heavy weapons go higher.
static func hit(target: Enemy, dir: Vector3, weight: float = 1.0, killed: bool = false) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var parent := target.get_parent()
	var at := target.global_position + Vector3.UP * target.body_height * 0.6 - dir * 0.25
	if not target.bleeds():
		SpellFx.burst(parent, at, SPARK, int(10 * weight), Vector2(3, 7), 0.25, Vector2(0.03, 0.07), 60.0, -12.0).direction = dir
		SpellFx.shards(parent, at, GRIT, int(6 * weight), Vector2(2, 5), Vector2(0.04, 0.1), 0.6, 60.0, false).direction = dir + Vector3.UP * 0.5
		return
	if _flesh.is_empty():
		_flesh = _sounds("melee_flesh_hit", 5)
		_gore = _sounds("gore_splat", 5)
		_bone = _sounds("bone_break", 6)
	_spray(parent, at, dir, int(14 * weight), weight)
	_mist(parent, at, weight)
	if weight >= 1.4 or killed:
		_spray(parent, at, -dir + Vector3.UP * 0.3, int(6 * weight), weight * 0.7)
		_play(_gore, at, -2.0)
	else:
		_play(_flesh, at, -6.0)
	if killed or weight >= 2.0:
		SpellFx.ground_mark(parent, target.global_position, randf_range(0.7, 1.1) * clampf(weight, 1.0, 2.0), SpellFx.Mark.SCORCH, POOL, POOL, POOL_SECONDS, 0.1)

## A visceral riposte: the body bursts, bones crack, a wide pool.
static func visceral(target: Enemy, dir: Vector3) -> void:
	hit(target, dir, 2.5, true)
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.bleeds():
		return
	var at := target.global_position + Vector3.UP * target.body_height * 0.6
	_spray(target.get_parent(), at, Vector3.UP, 40, 2.5, 160.0)
	_play(_bone, at, 0.0)

static func _spray(parent: Node, at: Vector3, dir: Vector3, amount: int, weight: float, spread: float = 35.0) -> void:
	var drops := SpellFx.shards(parent, at, BLOOD, amount, Vector2(3, 7) * clampf(weight, 0.8, 1.6), Vector2(0.06, 0.14), 0.7, spread, false)
	drops.direction = (dir.normalized() + Vector3.UP * 0.35).normalized()
	drops.angular_velocity_min = 0.0
	drops.angular_velocity_max = 0.0
	((drops.mesh as PrimitiveMesh).material as StandardMaterial3D).roughness = 0.15

static func _mist(parent: Node, at: Vector3, weight: float) -> void:
	var p := SpellFx.emitter(parent, int(10 * weight), 0.5)
	p.global_position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.45 * weight
	p.scale_amount_max = 0.8 * weight
	p.scale_amount_curve = SpellFx.curve(0.6, 1.0)
	p.color_ramp = SpellFx.ramp(MIST, MIST, 0.1)
	p.mesh = SpellFx.glow_quad(false)
	p.emitting = true
	SpellFx.free_after(p, 0.8)
