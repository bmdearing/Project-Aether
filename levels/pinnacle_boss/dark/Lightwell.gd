extends Node3D
class_name Lightwell
## A brazier in the Darkness Dragon's arena (DarkArena). Lit, it throws a
## pool of light LIGHT_RADIUS wide: the player standing in it sheds Dread
## instead of gaining it. The dragon's Shadow Breath, Nightfall and Shades
## put it out. The player relights it by holding Interact beside it for
## RELIGHT_SEC, or at once by landing a Fire hit while beside it
## (DarkArena._on_damage_dealt). A locked well (Eclipse) can't be relit.

signal lit_changed(well: Lightwell, lit: bool)

const LIGHT_RADIUS := 6.0
const REACH := 2.8
const RELIGHT_SEC := 1.5
const FLAME_COLOR := Color(1.0, 0.7, 0.36)
const LIGHT_ENERGY := 7.0
const LIGHT_HEIGHT := 3.4
const BRAZIER_SCENE := "res://entities/environment/doodads/dungeon/Brazier0.tscn"

var lit := true
var locked := false
var relight_progress := 0.0
## Shade channel progress (0..1): the flame gutters as it rises.
var strain := 0.0
## Eclipse: the next well to take the light, shown by a pulsing ring.
var marked := false

var _light: OmniLight3D
var _flame: CPUParticles3D
var _ring_mat: StandardMaterial3D
var _prompt: Label3D
var _t := 0.0

func _ready() -> void:
	add_to_group("lightwell")
	_build()

func _build() -> void:
	if ResourceLoader.exists(BRAZIER_SCENE):
		var brazier := (load(BRAZIER_SCENE) as PackedScene).instantiate() as Node3D
		brazier.scale = Vector3.ONE * 1.6
		add_child(brazier)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.7
	cyl.height = 2.0
	shape.shape = cyl
	shape.position.y = 1.0
	body.add_child(shape)
	add_child(body)

	_flame = SpellFx.emitter(self, 60, 0.9)
	_flame.position.y = 1.7
	_flame.direction = Vector3.UP
	_flame.spread = 14.0
	_flame.initial_velocity_min = 1.2
	_flame.initial_velocity_max = 2.4
	_flame.gravity = Vector3(0, 1.0, 0)
	_flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flame.emission_sphere_radius = 0.3
	_flame.scale_amount_min = 0.35
	_flame.scale_amount_max = 0.7
	_flame.scale_amount_curve = SpellFx.curve(1.0, 0.1)
	_flame.color_ramp = SpellFx.ramp(Color(1.0, 0.95, 0.75, 1.0), Color(FLAME_COLOR, 0.9), 0.15)
	_flame.mesh = SpellFx.glow_quad()

	_light = OmniLight3D.new()
	_light.light_color = FLAME_COLOR
	_light.light_energy = ShadowLight.omni(LIGHT_ENERGY)
	_light.omni_range = LIGHT_RADIUS * 1.35
	_light.omni_attenuation = 1.1
	_light.shadow_enabled = true
	_light.position.y = LIGHT_HEIGHT
	add_child(_light)

	# The edge of the safe pool, faint on the floor.
	_ring_mat = SpellFx.glow_material(FLAME_COLOR, true, BaseMaterial3D.BILLBOARD_DISABLED)
	_ring_mat.albedo_color = Color(FLAME_COLOR, 0.35)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = LIGHT_RADIUS - 0.12
	torus.outer_radius = LIGHT_RADIUS
	torus.rings = 64
	ring.mesh = torus
	ring.scale = Vector3(1, 0.04, 1)
	ring.position.y = 0.05
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 8
	_prompt.position.y = 3.0
	_prompt.visible = false
	add_child(_prompt)

func _physics_process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Player
	var near := player != null and player.health.is_alive() and is_beside(player.global_position)
	var can_relight := near and not lit and not locked
	if can_relight and Input.is_action_pressed("interact") and not AetherStyle.menu_open(get_tree()):
		relight_progress += delta / RELIGHT_SEC
		if relight_progress >= 1.0:
			set_lit(true)
	else:
		relight_progress = maxf(relight_progress - delta, 0.0)
	_prompt.visible = can_relight
	if can_relight:
		_prompt.text = "Hold %s to relight" % GameSettings.key_name("interact") if relight_progress <= 0.0 else "Relighting %d%%" % int(relight_progress * 100.0)

func _process(_delta: float) -> void:
	if lit:
		var gutter := 1.0 - strain * 0.6 * (0.5 + 0.5 * sin(_t * (10.0 + strain * 30.0)))
		_light.light_energy = ShadowLight.omni(LIGHT_ENERGY) * (gutter + 0.06 * sin(_t * 7.3))
	var ring_alpha := 0.35 if lit else 0.08
	if marked:
		ring_alpha = 0.25 + 0.35 * (0.5 + 0.5 * sin(_t * 8.0))
	_ring_mat.albedo_color.a = ring_alpha

func is_beside(point: Vector3) -> bool:
	return _flat_distance(point) <= REACH

## In this well's pool of light (lit wells only).
func lights(point: Vector3) -> bool:
	return lit and _flat_distance(point) <= LIGHT_RADIUS

func _flat_distance(point: Vector3) -> float:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length()

func set_lit(on: bool) -> void:
	if on and locked:
		return
	relight_progress = 0.0
	strain = 0.0
	if lit == on:
		return
	lit = on
	_flame.emitting = on
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", ShadowLight.omni(LIGHT_ENERGY) if on else 0.0, 0.25 if on else 0.6)
	var color := FLAME_COLOR if on else Color(0.45, 0.3, 0.7)
	SpellFx.burst(get_parent(), global_position + Vector3.UP * 1.7, color, 30 if on else 18, Vector2(1.5, 4.0), 0.6, Vector2(0.1, 0.22), 60.0, 1.0)
	if on:
		SpellFx.light_pop(get_parent(), global_position + Vector3.UP * LIGHT_HEIGHT, FLAME_COLOR, 5.0, LIGHT_RADIUS * 2.0, 0.4)
	lit_changed.emit(self, on)
