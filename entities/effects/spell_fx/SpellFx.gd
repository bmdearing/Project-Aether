class_name SpellFx
## Shared building blocks for spell visuals, in the style TornadoField and
## BlackHoleField use: soft additive glow sprites, CPU particle bursts and
## shards, flashes, short light pops, shockwave rings and ground marks.
## Everything spawned here frees itself.

enum Mark { SCORCH, FROST, ROT, CRACKS }

const RING_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")
const MARK_SHADER := preload("res://shaders/spell_ground_mark.gdshader")
## Longer ranges reach the camera and show their cut-off edge as a line on the floor.
const MAX_LIGHT_RANGE := 7.0

## Soft round sprite material. Additive glows read best against the dark
## dungeons; non-additive is for smoke and dust.
static func glow_material(color: Color = Color.WHITE, additive: bool = true, billboard: int = BaseMaterial3D.BILLBOARD_PARTICLES) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.albedo_texture = GlowTexture.radial(Vector2(0.3, 0.55)) if additive else GlowTexture.radial()
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = billboard as BaseMaterial3D.BillboardMode
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	return mat

static func glow_quad(additive: bool = true) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.material = glow_material(Color.WHITE, additive)
	return quad

## A CPU emitter with this project's defaults, added under parent.
static func emitter(parent: Node, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gravity = Vector3.ZERO
	parent.add_child(p)
	return p

## Fades from `from` through `peak` (at 0.25 of the life) to clear.
static func ramp(from: Color, peak: Color, peak_at: float = 0.25) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, Color(peak, 0.0))
	g.add_point(peak_at, peak)
	return g

static func curve(start: float, end: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, start))
	c.add_point(Vector2(1, end))
	return c

## A one-shot spray of glowing sparks.
static func burst(parent: Node, at: Vector3, color: Color, amount: int = 24, speed: Vector2 = Vector2(3, 6), lifetime: float = 0.5, size: Vector2 = Vector2(0.08, 0.18), spread: float = 180.0, gravity: float = -4.0) -> CPUParticles3D:
	var p := emitter(parent, amount, lifetime)
	p.global_position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = spread
	p.gravity = Vector3(0, gravity, 0)
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.damping_min = speed.x * 0.5
	p.damping_max = speed.y * 0.5
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = curve(1.0, 0.25)
	p.color_ramp = ramp(Color(color.lightened(0.6), 1.0), Color(color.lightened(0.2), 0.9), 0.15)
	p.mesh = glow_quad()
	p.emitting = true
	free_after(p, lifetime + 0.3)
	return p

## Tumbling solid chunks (ice, rock, bone) thrown out and falling.
static func shards(parent: Node, at: Vector3, color: Color, amount: int = 14, speed: Vector2 = Vector2(3, 6.5), size: Vector2 = Vector2(0.06, 0.16), lifetime: float = 0.7, spread: float = 70.0, emissive: bool = true) -> CPUParticles3D:
	var p := emitter(parent, amount, lifetime)
	p.global_position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = spread
	p.gravity = Vector3(0, -14.0, 0)
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = curve(1.0, 0.6)
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.0, 1.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35
	if emissive:
		mat.emission_enabled = true
		mat.emission = color * 0.6
	mesh.material = mat
	p.mesh = mesh
	p.emitting = true
	free_after(p, lifetime + 0.2)
	return p

## A camera-facing glow that swells and fades.
static func flash(parent: Node, at: Vector3, color: Color, size: float = 2.0, duration: float = 0.22) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	mi.mesh = quad
	var mat := glow_material(color, true, BaseMaterial3D.BILLBOARD_ENABLED)
	mat.vertex_color_use_as_albedo = false
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3.ONE * 1.4, duration).from(Vector3.ONE * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)

## A brief shadowless light, so a spell lights up the dark room it lands in.
static func light_pop(parent: Node, at: Vector3, color: Color, energy: float = 3.0, light_range: float = 6.0, duration: float = 0.35) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = minf(light_range, MAX_LIGHT_RANGE)
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(light.queue_free)
	return light

## The soft expanding ground ring (AbilityRangeEffect).
static func shockwave(parent: Node, at: Vector3, radius: float, color: Color, duration: float = 0.35) -> AbilityRangeEffect:
	var ring: AbilityRangeEffect = RING_SCENE.instantiate()
	ring.expand_duration = duration
	parent.add_child(ring)
	ring.global_position = at
	ring.play(radius, color)
	return ring

## A mark left on the ground: its accent (embers, frost glints) cools over
## `cool` seconds and the whole mark fades out over the last third of `duration`.
static func ground_mark(parent: Node, at: Vector3, radius: float, pattern: Mark, base: Color, accent: Color, duration: float = 3.0, cool: float = 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = MARK_SHADER
	mat.set_shader_parameter("base", base)
	mat.set_shader_parameter("glow", accent)
	mat.set_shader_parameter("pattern", int(pattern))
	mat.set_shader_parameter("seed", randf() * 10.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = randf() * TAU
	parent.add_child(mi)
	mi.global_position = at + Vector3.UP * 0.03
	var tween := mi.create_tween()
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("heat", v), 1.0, 0.0, cool)
	tween.parallel().tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v), 1.0, 0.0, duration / 3.0) \
		.set_delay(duration * 2.0 / 3.0)
	tween.tween_callback(mi.queue_free)
	return mi

static func free_after(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(seconds, false).timeout.connect(node.queue_free)

## An open tube from base_r at the ground to top_r at `height` (radius eased
## by `taper`), UV.x around 0..1 and UV.y bottom 0 -> top 1. Flames, funnels.
static func tube(base_r: float, top_r: float, height: float, rings: int = 12, segments: int = 32, taper: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for ri in rings:
		for si in segments:
			var pos: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			var nrms: Array[Vector3] = []
			for c in corners:
				var t := float(ri + c.y) / rings
				var a := TAU * float(si + c.x) / segments
				var r := lerpf(base_r, top_r, pow(t, taper))
				pos.append(Vector3(cos(a) * r, t * height, sin(a) * r))
				uvs.append(Vector2(float(si + c.x) / segments, t))
				nrms.append(Vector3(cos(a), 0.0, sin(a)))
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[idx])
				st.set_normal(nrms[idx])
				st.add_vertex(pos[idx])
	return st.commit()

const SWEEP_SHADER := preload("res://shaders/spell_sweep.gdshader")

## A blade of light sweeping across an arc in front of `origin` (Reap's
## scythe): a crescent band standing on a cylinder round the caster at 75% of
## the radius, `half_deg` either side of `forward`, slanted like a slash so it
## faces a first-person camera all along. sign -1 sweeps the other way.
static func sweep(parent: Node, origin: Vector3, forward: Vector3, radius: float, half_deg: float, color: Color, duration: float = 0.22, sign: float = 1.0, height: float = 1.0) -> MeshInstance3D:
	var segments := 40
	var r := radius * 0.75
	var half := deg_to_rad(half_deg)
	var band := clampf(radius * 0.22, 0.5, 1.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := lerpf(-half, half, float(i) / segments)
		var a1 := lerpf(-half, half, float(i + 1) / segments)
		var u0 := float(i) / segments
		var u1 := float(i + 1) / segments
		# Crescent: thickest mid-swing; slanted top-left to bottom-right.
		var h0 := band * (0.25 + 0.75 * sin(u0 * PI))
		var h1 := band * (0.25 + 0.75 * sin(u1 * PI))
		var s0 := (0.5 - u0) * band * 1.4 * sign
		var s1 := (0.5 - u1) * band * 1.4 * sign
		var quad := [
			[Vector3(sin(a0) * r, s0 - h0 * 0.5, -cos(a0) * r), Vector2(u0, 0)],
			[Vector3(sin(a1) * r, s1 - h1 * 0.5, -cos(a1) * r), Vector2(u1, 0)],
			[Vector3(sin(a1) * r, s1 + h1 * 0.5, -cos(a1) * r), Vector2(u1, 1)],
			[Vector3(sin(a0) * r, s0 + h0 * 0.5, -cos(a0) * r), Vector2(u0, 1)],
		]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad[idx][1])
			st.set_normal(Vector3.BACK)
			st.add_vertex(quad[idx][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = SWEEP_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("reverse", 1.0 if sign < 0.0 else 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	mi.global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), origin + Vector3.UP * height)
	var tween := mi.create_tween()
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("sweep", v), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v), 1.0, 0.0, duration * 1.2)
	tween.tween_callback(mi.queue_free)
	return mi
