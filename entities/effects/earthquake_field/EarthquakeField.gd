extends Node3D
class_name EarthquakeField
## Greataxe Earthquake's rough ground: slows enemies on it, and ruptures once, hitting every enemy
## inside for `damage` (60% of the slam), when the player leaves it or uses
## a Warcry (EventBus.warcry_used). Fizzles after LIFETIME otherwise.

const LIFETIME := 12.0
## The player must be this far past the edge to count as having left.
const LEAVE_MARGIN := 0.3
## Grace before leaving counts, so a slam at the edge doesn't rupture at once.
const ARM_DELAY := 0.4
const RUPTURE_SHARE := 0.6
const GROUND_COLOR := Color(0.32, 0.22, 0.14, 0.75)
const CRACK_COLOR := Color(1.0, 0.55, 0.2)
## Most fields alive at once; a new one ruptures the oldest.
const MAX_FIELDS := 3
## Enemies on the rough ground are slowed ("slow" status), refreshed this often.
const SLOW_REFRESH := 0.25

var radius := 6.0
var damage := 0.0
var damage_type: int = Constants.DamageType.KINETIC
var player: Player
var _age := 0.0
var _ruptured := false
var _slow_timer := 0.0

## A field centred on `at`; damage is the full slam damage (60% ruptures).
static func spawn(parent: Node, at: Vector3, field_radius: float, slam_damage: float, type: int, owner_player: Player) -> EarthquakeField:
	var existing := parent.get_tree().get_nodes_in_group("earthquake_field")
	if existing.size() >= MAX_FIELDS:
		(existing[0] as EarthquakeField).rupture()
	var field := EarthquakeField.new()
	field.radius = field_radius
	field.damage = slam_damage * RUPTURE_SHARE
	field.damage_type = type
	field.player = owner_player
	parent.add_child(field)
	field.global_position = at
	return field

func _ready() -> void:
	add_to_group("earthquake_field")
	EventBus.warcry_used.connect(func(_who): rupture())
	_build_visual()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_slow_timer -= delta
	if _slow_timer <= 0.0:
		_slow_timer = SLOW_REFRESH
		for e in _enemies_inside():
			e.status_effects.apply_timed_effect("slow", SLOW_REFRESH * 2.0)
	if _age < ARM_DELAY or not is_instance_valid(player):
		return
	var offset := player.global_position - global_position
	if Vector2(offset.x, offset.z).length() > radius + LEAVE_MARGIN:
		rupture()

func rupture() -> void:
	if _ruptured or not is_inside_tree():
		return
	_ruptured = true
	for e in _enemies_inside():
		if e.take_damage(damage, damage_type, false, true):
			EventBus.damage_dealt.emit(player, e, damage, damage_type, false, false)
	var ring := StanceAttack.IMPACT_RING_SCENE.instantiate()
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.05
	ring.play(radius, CRACK_COLOR)
	queue_free()

func _enemies_inside() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null or not e.health.is_alive():
			continue
		var offset := e.global_position - global_position
		if Vector2(offset.x, offset.z).length() <= radius + e.body_radius:
			result.append(e)
	return result

func _build_visual() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.03
	mesh.radial_segments = 40
	disc.mesh = mesh
	disc.position.y = 0.03
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GROUND_COLOR
	mat.emission_enabled = true
	mat.emission = CRACK_COLOR
	mat.emission_energy_multiplier = 0.25
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	# Jagged rocks around the rim read as broken ground.
	for i in 10:
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(0.3, 0.6), randf_range(0.2, 0.45), randf_range(0.3, 0.6))
		rock.mesh = box
		var angle := TAU * i / 10.0 + randf() * 0.4
		rock.position = Vector3(cos(angle), 0.1, sin(angle)) * radius * randf_range(0.55, 0.95)
		rock.rotation = Vector3(randf() * 0.6, randf() * TAU, randf() * 0.6)
		var rock_mat := StandardMaterial3D.new()
		rock_mat.albedo_color = Color(0.3, 0.24, 0.18)
		rock.material_override = rock_mat
		add_child(rock)
