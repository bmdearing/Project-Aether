extends Node3D
class_name TornadoField
## Tornado: a funnel that drifts across the arena for its lifetime, steering
## toward the nearest enemy within SEEK_RADIUS (gradually, via STEER_RATE)
## and wandering when nothing is in range, damaging everything inside its
## radius every tick. PlayerAbilityCast caps how many exist at once by
## counting the "tornado_field" group.
##
## Visuals: two lathed funnel shells (tornado_funnel.gdshader) narrow at the
## ground and flaring up, with spiralling wind streaks and a serpentine sway;
## debris and dust carried round by a spinning node; a churning dust ring at
## the base left behind as it travels; a dark scoured patch underneath.

const DURATION := 6.0
const TICK_INTERVAL := 0.4
const TICK_DAMAGE_PERCENT := 0.35
const MOVE_SPEED := 2.6
const SEEK_RADIUS := 14.0
const STEER_RATE := 4.0  # radians/sec heading can turn toward its target
const WANDER_REDIRECT_INTERVAL := 1.5

const FUNNEL_SHADER := preload("res://shaders/tornado_funnel.gdshader")
const SPIN_SPEED := 4.5  # radians/sec the debris orbits at
const FADE_IN := 0.4
const FADE_OUT := 0.7
const DUST := Color(0.62, 0.57, 0.5)

var _radius: float = 3.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0
var _wander_timer: float = 0.0
var _heading: Vector3 = Vector3.FORWARD
var _duration: float = DURATION

var _spinner: Node3D
var _shell_mats: Array[ShaderMaterial] = []
var _emitters: Array[CPUParticles3D] = []

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	_pick_new_wander_heading()
	_build_visuals(radius, color)
	add_to_group("tornado_field")

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return

	_steer(delta)
	global_position += _heading * MOVE_SPEED * delta
	_animate(delta)

	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += TICK_INTERVAL
	if _ability == null or _stat_sheet == null:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if global_position.distance_to(enemy.global_position) > _radius:
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, _ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		for effect_id in _ability.applies_status_effects:
			enemy.status_effects.apply_effect(effect_id, _source, damage)

## Nearest living enemy within SEEK_RADIUS steers the heading; otherwise a
## periodic random redirect keeps it covering ground.
func _steer(delta: float) -> void:
	var target := _find_nearest_enemy()
	var desired: Vector3 = _heading
	if target:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.05:
			desired = to_target.normalized()
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_new_wander_heading()
		desired = _heading

	var current_angle := atan2(_heading.x, _heading.z)
	var desired_angle := atan2(desired.x, desired.z)
	var delta_angle := wrapf(desired_angle - current_angle, -PI, PI)
	var max_turn := STEER_RATE * delta
	current_angle += clamp(delta_angle, -max_turn, max_turn)
	_heading = Vector3(sin(current_angle), 0.0, cos(current_angle))

func _pick_new_wander_heading() -> void:
	_wander_timer = WANDER_REDIRECT_INTERVAL
	var angle := randf() * TAU
	_heading = Vector3(sin(angle), 0.0, cos(angle))

func _find_nearest_enemy() -> Enemy:
	var nearest: Enemy = null
	var nearest_dist := SEEK_RADIUS
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest

## ---- Visuals -----------------------------------------------------------------

func _build_visuals(radius: float, color: Color) -> void:
	var height := radius * 1.6 + 1.6
	var tint := DUST.lerp(color, 0.3)
	_spinner = Node3D.new()
	add_child(_spinner)
	# Outer wind wall and a tighter, darker, faster core.
	_add_shell(0.35, radius, height, tint.lightened(0.25), tint.darkened(0.45), 0.55, 0.8, 2.0)
	_add_shell(0.18, radius * 0.5, height * 0.92, tint.lightened(0.1), tint.darkened(0.3), 0.6, 1.5, 2.8)
	_add_ground_patch(radius)
	_add_debris(radius, height)
	_add_dust_motes(radius)
	_add_base_dust(radius)

## A lathed funnel: narrow at the ground, flaring toward the top.
func _add_shell(base_r: float, top_r: float, height: float, light: Color, dark: Color, opacity: float, spin: float, twist: float) -> void:
	var rings := 16
	var segments := 36
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for ri in rings:
		for si in segments:
			var pos: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			var nrms: Array[Vector3] = []
			for c in corners:
				var t := float(ri + c.y) / rings
				var a := TAU * float(si + c.x) / segments
				var r := lerpf(base_r, top_r, pow(t, 1.5))
				pos.append(Vector3(cos(a) * r, t * height, sin(a) * r))
				uvs.append(Vector2(float(si + c.x) / segments, t))
				nrms.append(Vector3(cos(a), 0.35, sin(a)).normalized())
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[idx])
				st.set_normal(nrms[idx])
				st.add_vertex(pos[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = FUNNEL_SHADER
	mat.set_shader_parameter("color", light)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("spin", spin)
	mat.set_shader_parameter("twist", twist)
	mat.set_shader_parameter("fade", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_shell_mats.append(mat)

func _soft_material(color: Color, billboard: bool) -> StandardMaterial3D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	return mat

## Dark, wind-scoured patch under the funnel.
func _add_ground_patch(radius: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.6
	mi.mesh = plane
	mi.position.y = 0.04
	mi.material_override = _soft_material(Color(0.05, 0.04, 0.03, 0.45), false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _particles(parent: Node3D, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	_emitters.append(p)
	return p

func _fade_ramp(peak: float) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, peak))
	return ramp

## Rocks and grit carried round by the spin, spiralling up and outward.
func _add_debris(radius: float, height: float) -> void:
	var p := _particles(_spinner, 70, 2.4)
	p.local_coords = true
	p.emission_ring_radius = radius * 0.45
	p.emission_ring_inner_radius = radius * 0.2
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = height * 0.25
	p.initial_velocity_max = height * 0.45
	p.radial_accel_min = 0.6
	p.radial_accel_max = 1.4
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.22
	var rock := BoxMesh.new()
	rock.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.19, 0.16)
	mat.roughness = 1.0
	rock.material = mat
	p.mesh = rock

## Soft dust puffs lifted up the inside of the funnel.
func _add_dust_motes(radius: float) -> void:
	var p := _particles(_spinner, 45, 2.0)
	p.local_coords = true
	p.emission_ring_radius = radius * 0.35
	p.emission_ring_inner_radius = 0.1
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.radial_accel_min = 0.8
	p.radial_accel_max = 1.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _fade_ramp(0.65)
	var quad := QuadMesh.new()
	quad.material = _soft_material(Color(DUST.lightened(0.15), 0.65), true)
	p.mesh = quad

## Churning dust ring at the base, left behind as the tornado travels.
func _add_base_dust(radius: float) -> void:
	var p := _particles(self, 50, 1.6)
	p.local_coords = false
	p.position.y = 0.25
	p.emission_ring_radius = radius * 0.5
	p.emission_ring_inner_radius = radius * 0.25
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3(0, -0.5, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.radial_accel_min = 1.5
	p.radial_accel_max = 3.0
	p.tangential_accel_min = 4.0
	p.tangential_accel_max = 7.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	p.color_ramp = _fade_ramp(0.7)
	var quad := QuadMesh.new()
	quad.material = _soft_material(Color(DUST.darkened(0.1), 0.7), true)
	p.mesh = quad

func _animate(delta: float) -> void:
	if _spinner:
		_spinner.rotate_y(SPIN_SPEED * delta)
	var fade := clampf(minf(_elapsed / FADE_IN, (_duration - _elapsed) / FADE_OUT), 0.0, 1.0)
	for mat in _shell_mats:
		mat.set_shader_parameter("fade", fade)
	if _duration - _elapsed < FADE_OUT:
		for p in _emitters:
			p.emitting = false
