extends Node3D
class_name AureliaRoots
## Aurelia's Entangling Roots: one line of roots tearing up out of the
## ground from her toward the player, SPEED metres a second. Catching the
## player Entangles them (AureliaAilments.entangle()) and deals the hit,
## once per cast (lines of one cast share `caught`). bind() also wraps a
## ring of roots round an Entangled player's feet.

const SPEED := 13.0
const LENGTH := 20.0
const WIDTH := 1.6
const SPIKE_STEP := 0.7
const SPIKE_HOLD := 2.2
const BARK := Color(0.24, 0.15, 0.08)
const MOSS := Color(0.3, 0.55, 0.15)

var direction := Vector3.FORWARD
var damage := 10.0
var source: Enemy
## Shared by every line of one cast: {"hit": bool}.
var caught: Dictionary = {"hit": false}

var _tip := 0.0
var _next_spike := 0.0
var _player: Player

static var _bark_mat: StandardMaterial3D
static var _spike_mesh: CylinderMesh

static func send(parent: Node, origin: Vector3, dir: Vector3, hit: float, from: Enemy, shared: Dictionary) -> AureliaRoots:
	var roots := AureliaRoots.new()
	roots.direction = Vector3(dir.x, 0.0, dir.z).normalized()
	roots.damage = hit
	roots.source = from
	roots.caught = shared
	parent.add_child(roots)
	roots.global_position = origin
	return roots

## A ring of roots clamped round an Entangled target's feet for `seconds`.
static func bind(target: Node3D, seconds: float) -> void:
	var ring := Node3D.new()
	target.get_parent().add_child(ring)
	ring.global_position = target.global_position
	for i in 7:
		var a := TAU * i / 7.0 + randf_range(-0.2, 0.2)
		var spike := _spike(1.0, 1.4)
		ring.add_child(spike)
		spike.position = Vector3(cos(a), 0, sin(a)) * 0.55
		# Leaning in over the target.
		spike.rotation = Vector3(sin(a) * 0.5, 0.0, -cos(a) * 0.5)
		_grow(spike, seconds)
	SpellFx.burst(ring, ring.global_position + Vector3.UP * 0.3, MOSS, 16, Vector2(1, 3), 0.6, Vector2(0.06, 0.14), 70.0, -4.0)
	SpellFx.free_after(ring, seconds + 0.6)

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player

func _physics_process(delta: float) -> void:
	var from := _tip
	_tip = minf(_tip + SPEED * delta, LENGTH)
	while _next_spike <= _tip:
		_spawn_spike(_next_spike)
		_next_spike += SPIKE_STEP
	_check_hit(from, _tip)
	if _tip >= LENGTH:
		set_physics_process(false)
		SpellFx.free_after(self, SPIKE_HOLD + 0.8)

func _spawn_spike(along: float) -> void:
	var at := direction * along + direction.cross(Vector3.UP) * randf_range(-0.35, 0.35)
	var spike := _spike(0.8, 1.6)
	add_child(spike)
	spike.position = at
	spike.rotation = Vector3(randf_range(-0.45, 0.45), randf() * TAU, randf_range(-0.45, 0.45))
	_grow(spike, SPIKE_HOLD)
	if int(along / SPIKE_STEP) % 3 == 0:
		var world := global_position + at
		SpellFx.shards(get_parent(), world + Vector3.UP * 0.2, Color(0.32, 0.24, 0.16), 5, Vector2(2, 5), Vector2(0.06, 0.14), 0.6, 40.0, false)
		SpellFx.burst(get_parent(), world + Vector3.UP * 0.4, MOSS, 6, Vector2(1, 2.5), 0.6, Vector2(0.05, 0.1), 60.0, -3.0)

func _check_hit(from: float, to: float) -> void:
	if caught["hit"] or not is_instance_valid(_player) or not _player.health.is_alive():
		return
	var rel := _player.global_position - global_position
	if rel.y > 1.6:
		return
	rel.y = 0.0
	var along := rel.dot(direction)
	if along < from - 0.5 or along > to + 0.5:
		return
	if (rel - direction * along).length() > WIDTH * 0.5 + 0.4:
		return
	caught["hit"] = true
	AureliaAilments.entangle(_player)
	AureliaAilments.hit(_player, damage, Constants.DamageType.KINETIC, source)

static func _spike(min_h: float, max_h: float) -> MeshInstance3D:
	if _spike_mesh == null:
		_spike_mesh = CylinderMesh.new()
		_spike_mesh.top_radius = 0.0
		_spike_mesh.bottom_radius = 0.16
		_spike_mesh.height = 1.0
		_spike_mesh.radial_segments = 6
		_spike_mesh.rings = 2
		_bark_mat = StandardMaterial3D.new()
		_bark_mat.albedo_color = BARK
		_bark_mat.roughness = 0.95
		_bark_mat.emission_enabled = true
		_bark_mat.emission = MOSS * 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = _spike_mesh
	mi.material_override = _bark_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var h := randf_range(min_h, max_h)
	mi.set_meta("height", h)
	return mi

## Bursts up, holds, then sinks back into the ground and frees itself.
static func _grow(spike: MeshInstance3D, hold: float) -> void:
	var h: float = spike.get_meta("height", 1.0)
	spike.scale = Vector3(1.0, 0.01, 1.0)
	var base_y := spike.position.y
	var tween := spike.create_tween()
	tween.tween_property(spike, "scale", Vector3(1.0, h, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(spike, "position:y", base_y + h * 0.4, 0.12)
	tween.tween_interval(hold)
	tween.tween_property(spike, "position:y", base_y - h * 0.6, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(spike.queue_free)
