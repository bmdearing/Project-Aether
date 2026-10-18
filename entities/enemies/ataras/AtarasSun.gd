extends Node3D
class_name AtarasSun
## The Fiery Sun Ataras raises over the arena's centre and slams into the
## ground (Ataras._fiery_sun()). Only the look: a burning core, a corona,
## falling embers and its light.

const CORE := Color(1.0, 0.78, 0.35)
const FLAME := Color(1.0, 0.42, 0.1)
const RADIUS := 2.6

var _core: MeshInstance3D
var _corona: MeshInstance3D
var _light: OmniLight3D
var _time := 0.0
## Corona size on top of its pulse; swells as it falls.
var _flare := 1.0

func _ready() -> void:
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	_core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CORE
	_core.material_override = mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_corona = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * RADIUS * 5.0
	_corona.mesh = quad
	_corona.material_override = SpellFx.glow_material(Color(FLAME, 0.9), true, BaseMaterial3D.BILLBOARD_ENABLED)
	_corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_corona)
	var flames := SpellFx.emitter(self, 90, 0.9)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = RADIUS * 0.9
	flames.direction = Vector3.UP
	flames.spread = 180.0
	flames.initial_velocity_min = 0.5
	flames.initial_velocity_max = 2.0
	flames.scale_amount_min = 0.5
	flames.scale_amount_max = 1.1
	flames.scale_amount_curve = SpellFx.curve(1.0, 0.1)
	flames.color_ramp = SpellFx.ramp(Color(1.0, 0.85, 0.5, 0.9), Color(FLAME, 0.6), 0.3)
	flames.mesh = SpellFx.glow_quad()
	flames.emitting = true
	var embers := SpellFx.emitter(self, 50, 2.0)
	embers.local_coords = false
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = RADIUS
	embers.direction = Vector3.DOWN
	embers.spread = 40.0
	embers.gravity = Vector3(0, -3.0, 0)
	embers.initial_velocity_min = 1.0
	embers.initial_velocity_max = 3.0
	embers.scale_amount_min = 0.08
	embers.scale_amount_max = 0.18
	embers.color_ramp = SpellFx.ramp(Color(1.0, 0.8, 0.4, 1.0), Color(FLAME, 0.8), 0.2)
	embers.mesh = SpellFx.glow_quad()
	embers.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = FLAME
	_light.light_energy = ShadowLight.omni(15.0)
	_light.omni_range = 40.0
	_light.shadow_enabled = true
	add_child(_light)
	scale = Vector3.ONE * 0.05

func _process(delta: float) -> void:
	_time += delta
	_core.rotation.y += delta * 0.6
	var pulse := 1.0 + sin(_time * 7.0) * 0.06
	_corona.scale = Vector3.ONE * pulse * _flare

## Swells from a spark to full size.
func grow(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

## Falls onto `spot` and is gone: it flares white-hot and drags a fiery
## trail on the way down.
func slam(spot: Vector3, seconds: float) -> void:
	var trail := SpellFx.emitter(self, 120, 0.8)
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = RADIUS * 0.8
	trail.direction = Vector3.UP
	trail.spread = 20.0
	trail.initial_velocity_min = 2.0
	trail.initial_velocity_max = 6.0
	trail.scale_amount_min = 1.2
	trail.scale_amount_max = 2.4
	trail.scale_amount_curve = SpellFx.curve(1.0, 0.1)
	trail.color_ramp = SpellFx.ramp(Color(1.0, 0.9, 0.6, 1.0), Color(FLAME, 0.8), 0.2)
	trail.mesh = SpellFx.glow_quad()
	trail.emitting = true
	var core_mat := _core.material_override as StandardMaterial3D
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", spot + Vector3.UP * RADIUS * 0.5, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(core_mat, "albedo_color", Color(1.0, 0.97, 0.88), seconds)
	tween.tween_property(_light, "light_energy", ShadowLight.omni(40.0), seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "_flare", 1.6, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()
