extends AnimatableBody3D
class_name SecretGate
## A barred gate over a secret room's doorway. open_for() lifts it for a few
## seconds; a countdown over it shows how long is left. It won't drop onto
## the player standing under it.

const BAR_SPACING := 0.32
const BAR_THICKNESS := 0.09
const RAISE_SEC := 0.35
const LOWER_SEC := 0.5
const IRON := Color(0.16, 0.15, 0.14)

## Set before entering the tree: width along the wall, height, depth.
var size := Vector3(2.6, 3.0, 0.25)
var _closed_y := 0.0
var _open_left := 0.0
var _is_open := false
var _countdown: Label3D
var _tween: Tween

func _ready() -> void:
	LedgeClimb.forbid(self)
	sync_to_physics = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	add_child(shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = IRON
	mat.metallic = 0.6
	mat.roughness = 0.5
	var wide := size.x >= size.z
	var span := maxf(size.x, size.z)
	var count := maxi(int(span / BAR_SPACING), 2)
	for i in count + 1:
		var t := -span / 2.0 + span * i / count
		_bar(Vector3(BAR_THICKNESS, size.y, BAR_THICKNESS), Vector3(t if wide else 0.0, size.y / 2.0, 0.0 if wide else t), mat)
	for y in [0.15, size.y * 0.55, size.y - 0.12]:
		_bar(Vector3(span if wide else 0.12, 0.12, 0.12 if wide else span), Vector3(0, y, 0), mat)
	_countdown = Label3D.new()
	_countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_countdown.no_depth_test = true
	_countdown.font_size = 64
	_countdown.outline_size = 10
	_countdown.modulate = Color(1.0, 0.82, 0.4)
	_countdown.position.y = size.y + 0.6
	_countdown.visible = false
	add_child(_countdown)
	_closed_y = position.y

func _bar(bar_size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = bar_size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	add_child(mesh)

func is_open() -> bool:
	return _is_open

func open_for(seconds: float) -> void:
	_open_left = maxf(_open_left, seconds)
	_countdown.visible = true
	if _is_open:
		return
	_is_open = true
	_move_to(_closed_y + size.y - 0.1, RAISE_SEC)

func _physics_process(delta: float) -> void:
	if not _is_open:
		return
	_open_left -= delta
	_countdown.text = "%d" % ceili(maxf(_open_left, 0.0))
	if _open_left > 0.0:
		return
	if _player_underneath():
		_open_left = 0.3
		return
	_is_open = false
	_countdown.visible = false
	_move_to(_closed_y, LOWER_SEC)

func _move_to(y: float, seconds: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "position:y", y, seconds).set_trans(Tween.TRANS_QUAD)

func _player_underneath() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var local := global_transform.affine_inverse() * player.global_position
	return absf(local.x) < size.x / 2.0 + 0.5 and absf(local.z) < size.z / 2.0 + 0.6
