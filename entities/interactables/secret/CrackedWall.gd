extends StaticBody3D
class_name CrackedWall
## A weak patch in a dungeon wall with a secret room behind it. Its tells are
## faint: a few hairline cracks and some grit at its foot. HITS_TO_BREAK
## strikes bring it down: a melee swing that meets it
## (PlayerMeleeAttack._strike_breakables()) or one of the player's shots
## (Projectile). Each strike spreads the cracks.

signal broken

const HITS_TO_BREAK := 3
## Pellets from one shot land together; they count once.
const STRIKE_COOLDOWN_MSEC := 250
const CRACK_WIDTH := 0.06
const CRACK_COLOR := Color(0.04, 0.035, 0.03, 0.85)
const DEBRIS_LIFETIME := 4.0
## The patch is a shade dustier than the wall around it.
const DUST_TINT := Color(1.4, 1.3, 1.15)

## Set before entering the tree: width along the wall, height, thickness.
## The node stands at the patch's bottom centre; its +Z is the room side.
var size := Vector3(2.2, 2.6, 0.5)
var material: Material
var hits := 0
var _last_strike_msec := -100000
var _cracks: Array[PackedVector2Array] = []
var _crack_mesh: MeshInstance3D

func _ready() -> void:
	LedgeClimb.forbid(self)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _dusty(material)
	mesh.position.y = size.y / 2.0
	add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = size.y / 2.0
	add_child(collision)
	_crack_mesh = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CRACK_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mesh.material_override = mat
	_crack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack_mesh.position.z = size.z / 2.0 + 0.004
	add_child(_crack_mesh)
	for i in 3:
		_grow_crack(Vector2(randf_range(-0.25, 0.25) * size.x, randf_range(0.3, 0.6) * size.y), randi_range(3, 4))
	_rebuild_cracks()
	_scatter_grit()

## One strike against the patch.
func strike() -> void:
	var now := Time.get_ticks_msec()
	if hits >= HITS_TO_BREAK or now - _last_strike_msec < STRIKE_COOLDOWN_MSEC:
		return
	_last_strike_msec = now
	hits += 1
	var face := global_transform.basis.z
	AudioManager.play_at(SoundLib.get_impact_sound("stone"), global_position + Vector3.UP * size.y * 0.5, 0.0)
	if hits >= HITS_TO_BREAK:
		shatter(false)
		return
	for i in 2 + hits:
		var from: PackedVector2Array = _cracks[randi() % _cracks.size()]
		_grow_crack(from[randi() % from.size()], randi_range(3, 5))
	_rebuild_cracks()
	_debris(4, 0.08, face)

## Brings the patch down; `quiet` (a portal return) leaves no dust or noise.
func shatter(quiet: bool) -> void:
	hits = HITS_TO_BREAK
	if not quiet:
		AudioManager.play_at(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), global_position + Vector3.UP, -2.0)
		_debris(16, 0.18, global_transform.basis.z)
	# Grit stays put when the patch comes down.
	for child in get_children():
		if child.is_in_group(&"crack_grit"):
			child.reparent(get_parent())
	broken.emit()
	queue_free()

## A crack that wanders out from `start` in `segments` jagged steps.
func _grow_crack(start: Vector2, segments: int) -> void:
	var pts := PackedVector2Array([start])
	var heading := randf() * TAU
	var p := start
	var half := Vector2(size.x, size.y) / 2.0 - Vector2.ONE * 0.05
	for i in segments:
		heading += randf_range(-0.9, 0.9)
		p += Vector2(cos(heading), sin(heading)) * randf_range(0.12, 0.28)
		p = Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, 0.05, size.y - 0.05))
		pts.append(p)
	_cracks.append(pts)

func _rebuild_cracks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for pts in _cracks:
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var side := (b - a).orthogonal().normalized() * CRACK_WIDTH * (1.0 - float(i) / pts.size() * 0.5)
			for v in [a - side, b - side, b + side, a - side, b + side, a + side]:
				st.add_vertex(Vector3(v.x, v.y, 0.0))
	_crack_mesh.mesh = st.commit()

## A little grit at the foot, as if the patch were already crumbling.
func _scatter_grit() -> void:
	for i in randi_range(6, 9):
		var grit := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := randf_range(0.07, 0.18)
		box.size = Vector3(s, s * randf_range(0.5, 0.9), s * randf_range(0.7, 1.2))
		grit.mesh = box
		grit.material_override = material
		grit.position = Vector3(randf_range(-0.45, 0.45) * size.x, box.size.y / 2.0, size.z / 2.0 + randf_range(0.08, 0.5))
		grit.rotation = Vector3(randf() * 0.4, randf() * TAU, randf() * 0.4)
		grit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grit.add_to_group(&"crack_grit")
		add_child(grit)

## Chunks that tumble out of the face and fade. They collide with the world
## only, so they never block the player.
func _debris(count: int, scale: float, face: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in count:
		var chunk := RigidBody3D.new()
		chunk.collision_layer = 0
		chunk.collision_mask = 1
		var s := randf_range(0.5, 1.5) * scale
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(s, s * randf_range(0.6, 1.0), s * randf_range(0.6, 1.2))
		mesh.mesh = box
		mesh.material_override = material
		chunk.add_child(mesh)
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box.size
		shape.shape = b
		chunk.add_child(shape)
		parent.add_child(chunk)
		var local := Vector3(randf_range(-0.45, 0.45) * size.x, randf_range(0.1, 0.9) * size.y, size.z / 2.0)
		chunk.global_position = global_transform * local
		chunk.linear_velocity = face * randf_range(1.0, 3.0) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1))
		chunk.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		chunk.get_tree().create_timer(DEBRIS_LIFETIME).timeout.connect(chunk.queue_free)

func _dusty(base: Material) -> Material:
	var mat := base.duplicate() as Material
	if mat is ShaderMaterial:
		var tint: Variant = (mat as ShaderMaterial).get_shader_parameter("tint")
		if tint is Color:
			(mat as ShaderMaterial).set_shader_parameter("tint", (tint as Color) * DUST_TINT)
	elif mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color *= DUST_TINT
	return mat
