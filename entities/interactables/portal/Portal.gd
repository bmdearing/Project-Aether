extends Area3D
class_name Portal
## Walk-in portal. In a map it leads to the Hub (GeneratedMap saves the map
## first); in the Hub it leads back into the saved map. Built in code.

signal taken

enum Destination { HUB, MAP }

const RADIUS := 0.9
const HEIGHT := 2.4
## Ignores the player briefly after appearing, so one spawned on top of
## them doesn't fire instantly.
const ARM_DELAY := 0.6
const COLOR_TO_HUB := Color(0.35, 0.65, 1.0)
const COLOR_TO_MAP := Color(1.0, 0.55, 0.25)

@export var destination: Destination = Destination.HUB

var _armed := false
var _used := false

func _ready() -> void:
	monitoring = true
	monitorable = false
	var color := COLOR_TO_HUB if destination == Destination.HUB else COLOR_TO_MAP

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = HEIGHT
	shape.shape = cylinder
	shape.position.y = HEIGHT / 2.0
	add_child(shape)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.8
	torus.outer_radius = RADIUS
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.position.y = HEIGHT / 2.0
	ring.scale = Vector3(1.0, 1.0, HEIGHT / (RADIUS * 2.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 4.0
	light.position.y = HEIGHT / 2.0
	add_child(light)

	var label := Label3D.new()
	label.text = "Portal to Hub" if destination == Destination.HUB else "Portal to Map"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 42
	label.outline_size = 8
	label.position.y = HEIGHT + 0.4
	add_child(label)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(ARM_DELAY).timeout.connect(func(): _armed = true)

func _on_body_entered(body: Node3D) -> void:
	if _armed and not _used and body is Player:
		take()

## Leaves through this portal. Callable directly (tests, menu shortcuts).
func take() -> void:
	if _used:
		return
	_used = true
	taken.emit()
	if destination == Destination.MAP:
		GameState.returning_through_portal = true
		SaveManager.save_game()
		get_tree().paused = false
		get_tree().change_scene_to_file(GameState.MAP_SCENE)
