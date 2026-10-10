extends Node3D
class_name SteamVent
## A street grate that vents steam every few seconds (City Figments): a
## SmokePuff burst and a steam hiss. Decoration only; it doesn't hurt.

const SOUNDS := ["steam_burst_01", "steam_burst_02", "steam_burst_03", "steam_burst_04", "steam_burst_05"]
const SOUND_DIR := "res://assets/sfx/world/"
const INTERVAL := Vector2(4.0, 9.0)
const HEARING_RANGE := 30.0
const GRATE_SIZE := Vector3(1.2, 0.06, 0.8)

var _timer := 0.0

func _ready() -> void:
	var grate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = GRATE_SIZE
	grate.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.14)
	mat.metallic = 0.8
	mat.roughness = 0.5
	grate.material_override = mat
	grate.position.y = GRATE_SIZE.y / 2.0
	add_child(grate)
	_timer = randf_range(0.5, INTERVAL.y)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(INTERVAL.x, INTERVAL.y)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.global_position.distance_to(global_position) > HEARING_RANGE * 2.0:
		return
	SmokePuff.spawn(get_parent(), global_position + Vector3(0, 0.3, 0), 1.4, Color(0.82, 0.82, 0.85))
	if player.global_position.distance_to(global_position) <= HEARING_RANGE:
		var stream := load(SOUND_DIR + String(SOUNDS.pick_random()) + ".ogg") as AudioStream
		if stream:
			AudioManager.play_at(stream, global_position, -8.0)
