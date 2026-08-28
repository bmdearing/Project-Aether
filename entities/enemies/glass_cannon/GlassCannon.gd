extends Enemy
class_name GlassCannon
## Trinity Rule: Fast + Lethal. Rushes aggressively, dangerous if it
## connects, dies quickly. Tune via exported values on the base Enemy scene.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.GLASS_CANNON
	move_speed = 5.5
	health.max_health = 60.0
	_set_placeholder_color(Color(0.95, 0.85, 0.2))  # yellow - fast/fragile

func _set_placeholder_color(c: Color) -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mesh.set_surface_override_material(0, mat)
