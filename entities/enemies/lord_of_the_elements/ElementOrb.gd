extends Enemy
class_name ElementOrb
## The hittable body of one of the Lord of the Elements' orbs. It follows the
## orb's glow (LordOfTheElements._process) and only takes damage while it is
## exposed: its element is the one he is using, it isn't already overloaded,
## and he is still in phase 1 or 2. Damage fills an overload meter instead of
## killing it; when the meter fills the Lord loses that element for a while
## and is staggered by the backlash (LordOfTheElements.overload()).

## The orb's centre sits this high above the node (the capsule's middle).
const CENTRE_HEIGHT := 0.9
const HIT_RADIUS := 0.7

var element: int = Constants.DamageType.FIRE
var lord: LordOfTheElements
## Damage still needed to overload it.
var integrity: float = 1.0
var integrity_max: float = 1.0

func _ready() -> void:
	super._ready()
	immovable = true
	move_speed = 0.0
	display_name = "%s Orb" % Constants.DAMAGE_TYPE_NAME.get(element, "Elemental")
	var placeholder := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if placeholder:
		placeholder.visible = false
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision:
		var sphere := SphereShape3D.new()
		sphere.radius = HIT_RADIUS
		collision.shape = sphere
		collision.position.y = CENTRE_HEIGHT
	var head := get_node_or_null("HeadZone") as Node3D
	if head:
		head.queue_free()
	# Never pushes or blocks the player: shots and swings still find it.
	collision_mask = 0

func set_integrity(amount: float) -> void:
	integrity_max = maxf(amount, 1.0)
	integrity = integrity_max
	health.max_health = integrity_max
	health.current_health = integrity_max

func is_exposed() -> bool:
	return is_instance_valid(lord) and lord.is_orb_exposed(element)

## Moves the orb's body so its centre sits at `centre`.
func follow(centre: Vector3) -> void:
	global_position = centre - Vector3(0, CENTRE_HEIGHT, 0)

## Damage wears the overload meter down instead of the orb's life.
func take_damage(amount: float, damage_type: Constants.DamageType, _is_spell: bool = false, _can_evade: bool = false, _is_dot: bool = false, _ignore_armor: bool = false) -> bool:
	if not is_exposed() or amount <= 0.0:
		return false
	_last_combat_msec = Time.get_ticks_msec()
	_spawn_damage_number(amount, damage_type)
	integrity -= amount
	if integrity <= 0.0:
		integrity = integrity_max
		lord.overload(element)
	health.current_health = maxf(integrity, 1.0)
	return true

## Lets the hover bar and melee sweeps treat it like a live target.
func _on_died() -> void:
	pass
