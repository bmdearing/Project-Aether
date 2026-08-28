extends Enemy
class_name MobileBruiser
## Trinity Rule: Fast + Tanky. Hard to hit and hard to kill,
## lower individual damage.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.MOBILE_BRUISER
	move_speed = 4.5
	health.max_health = 180.0
	_set_placeholder_color(Color(0.2, 0.5, 0.9))  # blue - fast/tanky

func _set_placeholder_color(c: Color) -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mesh.set_surface_override_material(0, mat)
