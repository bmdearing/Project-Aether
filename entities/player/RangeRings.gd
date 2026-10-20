extends Node3D
class_name RangeRings
## Hold Alt in the world to see distance from the player: solid rings at 5
## and 10 m, dashed mark rings at 15, 20 and 25 m, each labelled on the side
## you're looking. Drawn as a decal so the rings lie on slopes and steps.

const SOLID := [5.0, 10.0]
const MARKS := [15.0, 20.0, 25.0]
const MAX_RADIUS := 25.0
const PX_PER_M := 20
const LINE_M := 0.07
const DASHES := 48
const COLOR := Color(1.0, 0.86, 0.55)
const MARK_ALPHA := 0.6
const HEIGHT := 8.0
## Label bearing per ring (degrees off the line of sight, negative = right).
const LABEL_ANGLES := [-9.0, -7.0, 5.0, -5.0, 4.0]

static var _texture: ImageTexture

var _decal: Decal
var _labels: Array[Label3D] = []
var _player: Player

func _ready() -> void:
	_player = get_parent() as Player
	top_level = true
	_decal = Decal.new()
	var span := MAX_RADIUS * 2.0 + 0.5
	_decal.size = Vector3(span, HEIGHT, span)
	_decal.texture_albedo = _ring_texture()
	_decal.texture_emission = _decal.texture_albedo
	_decal.emission_energy = 0.3
	_decal.albedo_mix = 1.0
	_decal.modulate = Color(1, 1, 1, 0.85)
	_decal.upper_fade = 0.15
	_decal.lower_fade = 0.15
	_decal.cull_mask = 1
	add_child(_decal)
	for r in SOLID + MARKS:
		var label := Label3D.new()
		label.text = "%d m" % int(r)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0015
		label.font_size = 26
		label.outline_size = 8
		label.modulate = COLOR if SOLID.has(r) else Color(COLOR, 0.8)
		label.set_meta(&"radius", r)
		add_child(label)
		_labels.append(label)
	visible = false

func _process(_delta: float) -> void:
	var on := Input.is_key_pressed(KEY_ALT) and not get_tree().paused and _player != null
	visible = on
	if not on:
		return
	global_position = _player.global_position
	var forward := -_player.camera.global_transform.basis.z if _player.camera else -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	# Labels sit beside the line of sight, alternating sides so the far ones don't stack.
	for i in _labels.size():
		var label := _labels[i]
		var side := forward.rotated(Vector3.UP, deg_to_rad(LABEL_ANGLES[i]))
		label.position = side * float(label.get_meta(&"radius")) + Vector3.UP * 0.25

## The rings, drawn once: solid rings full strength, mark rings dashed and fainter.
static func _ring_texture() -> ImageTexture:
	if _texture:
		return _texture
	var size := int((MAX_RADIUS * 2.0 + 0.5) * PX_PER_M)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var centre := Vector2(size, size) * 0.5
	var half_line := LINE_M * PX_PER_M * 0.5
	for r in SOLID + MARKS:
		var dashed: bool = MARKS.has(r)
		var color := Color(COLOR, 1.0 if not dashed else MARK_ALPHA)
		var radius_px := float(r) * PX_PER_M
		var steps := int(TAU * radius_px * 1.5)
		for i in steps:
			var a := TAU * i / steps
			if dashed and fmod(a / TAU * DASHES * 2.0, 2.0) > 1.0:
				continue
			var dir := Vector2(cos(a), sin(a))
			var t := -half_line - 1.0
			while t <= half_line + 1.0:
				var p := centre + dir * (radius_px + t)
				var edge := clampf(half_line + 1.0 - absf(t), 0.0, 1.0)
				var x := int(p.x)
				var y := int(p.y)
				if x >= 0 and y >= 0 and x < size and y < size and img.get_pixel(x, y).a < color.a * edge:
					img.set_pixel(x, y, Color(color, color.a * edge))
				t += 0.5
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture
