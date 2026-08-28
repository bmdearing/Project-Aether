extends Enemy
class_name HeavyHitter
## Trinity Rule: Lethal + Tanky. Slow, telegraphed, devastating
## if contact is made.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.HEAVY_HITTER
	move_speed = 1.8
	health.max_health = 220.0
	_set_placeholder_color(Color(0.5, 0.08, 0.08))  # dark red - slow/lethal/tanky

func _set_placeholder_color(c: Color) -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mesh.set_surface_override_material(0, mat)
