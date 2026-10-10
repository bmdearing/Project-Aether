extends Enemy
class_name SandGlobe
## Ataras's Sand Globe: a floating orb of whirling sand that never moves and
## fires a sand bolt at the player every FIRE_INTERVAL seconds, for a little
## damage. It can be killed.

const HOVER := 1.6
const FIRE_INTERVAL := 2.0
const FIRE_RANGE := 40.0
const BOLT_DAMAGE := 6.0
const COLOR := Color(0.9, 0.72, 0.42)

var _time := 0.0
var _orb: MeshInstance3D

func _ready() -> void:
	super._ready()
	immovable = true
	display_name = "Sand Globe"
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.fire_range = FIRE_RANGE
		ranged.min_range = 0.0
		ranged.windup_duration = 0.4
		ranged.cooldown_duration = FIRE_INTERVAL - 0.4
		ranged.damage_amount = BOLT_DAMAGE
		ranged.damage_type = Constants.DamageType.PIERCING
	var placeholder := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if placeholder:
		placeholder.visible = false
	_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	_orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = COLOR * 0.35
	mat.roughness = 0.9
	_orb.material_override = mat
	_orb.position = Vector3(0, 0.9, 0)
	add_child(_orb)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 0.7
	light.omni_range = 3.0
	light.position = Vector3(0, 0.9, 0)
	add_child(light)

func _process(delta: float) -> void:
	_time += delta
	if _orb:
		_orb.rotation.y += delta * 2.5
		_orb.position.y = 0.9 + sin(_time * 2.0) * 0.12
