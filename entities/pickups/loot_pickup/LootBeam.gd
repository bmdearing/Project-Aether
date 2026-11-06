extends RefCounted
class_name LootBeam
## The light column over a rarer drop, built from the Inventory Item pack's
## flare and shockwave textures (its own beams are PopcornFX, which Godot
## can't play). Three tiers: Rare, Unique / Monster Infrequent, Mythic; each
## is taller and wider with more going on at its foot.
##   pillar  - soft Y-billboard column, white-hot core (loot_beam.gdshader)
##   glow    - a flat flare on the floor
##   rings   - shockwaves pulsing out from the foot (loot_beam_ring.gdshader)
##   motes   - sparks drifting up the column
##   light   - a small unshadowed light tinting the floor (Unique and up)

const PILLAR_SHADER := preload("res://shaders/loot_beam.gdshader")
const RING_SHADER := preload("res://shaders/loot_beam_ring.gdshader")
const FLARE_SOFT := preload("res://assets/textures/fx/loot_beam/flare_soft.png")
const FLARE_POINT := preload("res://assets/textures/fx/loot_beam/flare_point.png")
const SHOCKWAVE := preload("res://assets/textures/fx/loot_beam/shockwave_soft.png")

const RARE := 1
const UNIQUE := 2
const MYTHIC := 3

## Per tier (index 1-3): pillar height and width, ground glow and ring size,
## ring count, mote count, light energy.
const HEIGHT: Array[float] = [0.0, 3.6, 5.5, 8.0]
const WIDTH: Array[float] = [0.0, 0.32, 0.5, 0.7]
const GLOW: Array[float] = [0.0, 0.7, 1.0, 1.4]
const RING: Array[float] = [0.0, 0.9, 1.3, 1.8]
const RINGS: Array[int] = [0, 1, 1, 2]
const MOTES: Array[int] = [0, 0, 10, 20]
const LIGHT: Array[float] = [0.0, 0.0, 0.3, 0.5]

## The rarity colours are pastel for text; a beam reads better a little
## richer, or (peach Mythic) it washes out to white.
static func beam_color(c: Color) -> Color:
	return Color.from_hsv(c.h, minf(c.s * 1.25 + 0.05, 1.0), maxf(c.v, 0.85))

## Builds the beam under `parent` with its foot at `foot`.
static func build(parent: Node3D, foot: Vector3, rarity_color: Color, tier: int) -> void:
	tier = clampi(tier, RARE, MYTHIC)
	var color := beam_color(rarity_color)
	var pillar := MeshInstance3D.new()
	pillar.name = "Beam"
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH[tier], HEIGHT[tier])
	pillar.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = PILLAR_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("energy", 1.6 + 0.4 * tier)
	mat.set_shader_parameter("profile", FLARE_SOFT)
	pillar.material_override = mat
	pillar.position = foot + Vector3(0, HEIGHT[tier] / 2.0, 0)
	# Its box would otherwise be the flat quad's; the billboard turns.
	pillar.custom_aabb = AABB(Vector3(-WIDTH[tier], -HEIGHT[tier] / 2.0, -WIDTH[tier]), Vector3(WIDTH[tier] * 2.0, HEIGHT[tier], WIDTH[tier] * 2.0))
	_fx(pillar)
	parent.add_child(pillar)

	var glow := MeshInstance3D.new()
	glow.name = "Flare"
	glow.mesh = _flat_quad(GLOW[tier])
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.albedo_texture = FLARE_SOFT
	gmat.albedo_color = Color(color, 0.55)
	glow.material_override = gmat
	glow.position = foot + Vector3(0, 0.015, 0)
	_fx(glow)
	parent.add_child(glow)

	for i in RINGS[tier]:
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % i
		ring.mesh = _flat_quad(RING[tier])
		var rmat := ShaderMaterial.new()
		rmat.shader = RING_SHADER
		rmat.set_shader_parameter("color", color)
		rmat.set_shader_parameter("ring", SHOCKWAVE)
		rmat.set_shader_parameter("offset", float(i) / RINGS[tier])
		rmat.set_shader_parameter("period", 2.4 - 0.2 * tier)
		ring.material_override = rmat
		ring.position = foot + Vector3(0, 0.025 + 0.005 * i, 0)
		_fx(ring)
		parent.add_child(ring)

	if MOTES[tier] > 0:
		var motes := SpellFx.emitter(parent, MOTES[tier], 2.6)
		motes.name = "Motes"
		motes.position = foot + Vector3(0, 0.1, 0)
		motes.preprocess = 2.6
		motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		motes.emission_ring_axis = Vector3.UP
		motes.emission_ring_radius = WIDTH[tier] * 0.6
		motes.emission_ring_inner_radius = 0.0
		motes.emission_ring_height = 0.0
		motes.direction = Vector3.UP
		motes.spread = 8.0
		motes.initial_velocity_min = 0.7
		motes.initial_velocity_max = 1.4 + 0.2 * tier
		motes.scale_amount_min = 0.05
		motes.scale_amount_max = 0.11
		motes.color_ramp = SpellFx.ramp(Color(color * 2.0, 0.0), Color(color * 2.0, 1.0), 0.2)
		var pmat := SpellFx.glow_material(Color.WHITE)
		pmat.albedo_texture = FLARE_POINT
		motes.mesh = SpellFx.glow_quad()
		motes.material_override = pmat

	if LIGHT[tier] > 0.0:
		var light := OmniLight3D.new()
		light.name = "BeamLight"
		light.light_color = color
		light.light_energy = LIGHT[tier]
		light.omni_range = 2.0 + 0.4 * tier
		light.shadow_enabled = false
		light.light_specular = 0.0
		light.position = foot + Vector3(0, 0.6, 0)
		light.distance_fade_enabled = true
		light.distance_fade_begin = 30.0
		light.distance_fade_length = 10.0
		parent.add_child(light)

static func _flat_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	return q

static func _fx(m: MeshInstance3D) -> void:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
