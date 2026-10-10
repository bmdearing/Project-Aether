extends Node3D
class_name AbilityRangeEffect
## "Range pulse" VFX: a soft shockwave (spell_ring.gdshader), colored by
## damage type, that races from the centre out to the ability's actual
## radius and fades, so its range is visible. Frees itself when done.

@export var expand_duration: float = 0.35

const RING_SHADER := preload("res://shaders/spell_ring.gdshader")
const MARGIN := 1.08

@onready var ring: MeshInstance3D = $Ring

func play(radius: float, color: Color) -> void:
	radius = maxf(radius, 0.2)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0 * MARGIN
	ring.mesh = plane
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("color", Color(color.lightened(0.15), 1.0))
	# Same on-screen thickness whatever the radius.
	mat.set_shader_parameter("width", clampf(0.22 / radius, 0.015, 0.12))
	ring.material_override = mat

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(func(p: float) -> void: mat.set_shader_parameter("progress", p), 0.05, 1.0 / MARGIN, expand_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(a: float) -> void: mat.set_shader_parameter("alpha", a), 1.0, 0.0, expand_duration * 1.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
