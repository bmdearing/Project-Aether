class_name ArkanusFx
## Visuals and sounds for Arkanus' four spells (PlayerAbilityCast), in
## Aurelia's palette and Warcraft III sounds (AureliaSfx, SoundLib boss_*).

const STORM := Color(0.75, 0.82, 1.0)
const FIRE_CORE := Color(1.0, 0.75, 0.35)
const FIRE_GLOW := Color(1.0, 0.4, 0.08)
const VIOLET := Color(0.6, 0.15, 0.8)
const WATER := Color(0.35, 0.65, 1.0)
const EARTH := Color(0.7, 0.55, 0.35)
const ROCK := Color(0.42, 0.36, 0.3)
const FIREBALL_HIT := preload("res://assets/sfx/wc3/boss_fire_01.ogg")

static func _sound(arr: Array[AudioStream], at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	AudioManager.play_at(SoundLib.pick_random(arr), at, volume_db, pitch)

## ---- Elemental Lightning ----------------------------------------------------

static func lightning(scene: Node, at: Vector3, ground: Vector3, shattered: bool, drenched: bool) -> void:
	LightningArc.spawn(scene, at + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), at, STORM, 2.2, true, 4)
	SpellFx.flash(scene, at, Color(0.9, 0.92, 1.0), 4.0, 0.25)
	SpellFx.light_pop(scene, at + Vector3.UP, STORM, 5.0, 10.0, 0.4)
	SpellFx.burst(scene, at, STORM, 22, Vector2(4, 9), 0.35, Vector2(0.04, 0.1), 160.0, -10.0)
	SpellFx.ground_mark(scene, ground, 1.6, SpellFx.Mark.CRACKS, Color(0.1, 0.1, 0.14, 0.5), STORM, 2.0, 0.5)
	AureliaSfx.play("bolt_big", at, 2.0)
	AureliaSfx.play("bolt_big_thunder", at, 0.0, 0.9)
	if shattered:
		SpellFx.shards(scene, at, Color(0.8, 0.95, 1.0), 26, Vector2(4, 8), Vector2(0.08, 0.2), 0.8, 180.0)
		SpellFx.flash(scene, at, Color(0.8, 0.95, 1.0), 3.0, 0.3)
		_sound(SoundLib.library.boss_ice_shatter, at, 2.0)
	if drenched:
		SpellFx.burst(scene, at, WATER, 16, Vector2(2, 5), 0.5, Vector2(0.05, 0.12), 120.0, -9.0)

## ---- Elemental Aether ----------------------------------------------------

const AETHER := Color(0.55, 0.85, 1.0)

## Brighter and bigger for each element on the target.
static func aether(scene: Node, at: Vector3, ground: Vector3, elements: int) -> void:
	var power := 1.0 + 0.35 * elements
	SpellFx.flash(scene, at, AETHER, 2.0 * power, 0.25)
	SpellFx.light_pop(scene, at, AETHER, 3.0 * power, 6.0 * power, 0.4)
	SpellFx.burst(scene, at, AETHER, 18 + 8 * elements, Vector2(3, 7) * power, 0.45, Vector2(0.05, 0.14), 180.0, 0.0)
	SpellFx.shards(scene, at, Color(0.85, 0.95, 1.0), 10 + 4 * elements, Vector2(3, 6), Vector2(0.05, 0.14), 0.6, 180.0)
	SpellFx.shockwave(scene, ground, 1.2 * power, VIOLET.lerp(AETHER, 0.5), 0.3)
	_sound(SoundLib.library.boss_void_burst, at, 2.0, 1.15)

## ---- Elemental Fire -----------------------------------------------------------

static func fire_cast(scene: Node, origin: Vector3, forward: Vector3) -> void:
	SpellFx.flash(scene, origin + forward, FIRE_GLOW, 1.8, 0.18)
	SpellFx.light_pop(scene, origin + forward, FIRE_GLOW, 3.0, 6.0, 0.3)
	AureliaSfx.play("thrust", origin, 0.0)

## A blazing core, halo, ember trail and light on a plain Projectile.
static func dress_fireball(ball: Projectile) -> void:
	ball.mesh.scale = Vector3.ONE * 2.2
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = FIRE_CORE
	ball.mesh.material_override = core
	ball.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.9
	halo.mesh = quad
	var mat := SpellFx.glow_material(Color(FIRE_GLOW, 0.9), true, BaseMaterial3D.BILLBOARD_ENABLED)
	mat.vertex_color_use_as_albedo = false
	# Launched from the camera: no glare in the first metre.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.8
	mat.distance_fade_max_distance = 2.5
	halo.material_override = mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.add_child(halo)
	var trail := SpellFx.emitter(ball, 30, 0.4)
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.12
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.gravity = Vector3(0, 1.5, 0)
	trail.scale_amount_min = 0.08
	trail.scale_amount_max = 0.2
	trail.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	trail.color_ramp = SpellFx.ramp(Color(FIRE_CORE, 1.0), Color(FIRE_GLOW, 0.85), 0.2)
	trail.mesh = SpellFx.glow_quad()
	trail.emitting = true
	var light := OmniLight3D.new()
	light.light_color = FIRE_GLOW
	light.light_energy = 1.0
	light.omni_range = 3.0
	ball.add_child(light)

static func fireball_hit(scene: Node, at: Vector3) -> void:
	SpellFx.burst(scene, at, FIRE_GLOW, 18, Vector2(2, 5), 0.45, Vector2(0.08, 0.18), 120.0, 2.0)
	SpellFx.flash(scene, at, FIRE_GLOW, 1.6, 0.15)
	AudioManager.play_at(FIREBALL_HIT, at, -4.0)

## The Entangled target bursts into Forbidden Flame.
static func forbidden_blast(scene: Node, centre: Vector3, ground: Vector3, radius: float) -> void:
	SpellFx.burst(scene, centre, Color(0.35, 0.05, 0.5), 40, Vector2(4, 9), 0.6, Vector2(0.1, 0.25))
	SpellFx.shockwave(scene, ground, radius, VIOLET, 0.35)
	SpellFx.light_pop(scene, centre, VIOLET, 4.0, radius * 2.0, 0.4)
	SpellFx.ground_mark(scene, ground, radius, SpellFx.Mark.SCORCH, Color(0.04, 0.0, 0.06, 0.85), VIOLET, 3.5, 1.2)
	SmokePuff.spawn(scene, ground, 1.2, Color(0.04, 0.0, 0.06))
	AureliaSfx.play("combo_forbidden_fire", centre, 4.0)
	AureliaSfx.play("amaterasu_ignite", centre, 0.0, 1.1)

## Black flame on an enemy while Forbidden Flame burns it; a new burn refreshes it.
static func enemy_flame(enemy: Enemy, seconds: float) -> void:
	var flame := enemy.get_node_or_null("ArkanusFlame") as MeshInstance3D
	if flame == null:
		flame = MeshInstance3D.new()
		flame.name = "ArkanusFlame"
		flame.mesh = SpellFx.tube(0.6, 0.25, 1.6, 8, 24, 0.8)
		var mat := ShaderMaterial.new()
		mat.shader = ForbiddenFire.FLAME_SHADER
		mat.set_shader_parameter("tiles", 6.0)
		mat.set_shader_parameter("period", 7.0)
		mat.set_shader_parameter("fill", 0.34)
		flame.material_override = mat
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		enemy.add_child(flame)
	var burn: int = flame.get_meta("burn", 0) + 1
	flame.set_meta("burn", burn)
	enemy.get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(flame) and flame.get_meta("burn") == burn:
			flame.queue_free())

## ---- Elemental Water ----------------------------------------------------------

static func water(scene: Node, centre: Vector3, radius: float, entangling: bool) -> void:
	var ground := centre + Vector3.UP * 0.05
	SpellFx.shockwave(scene, ground, radius, WATER, 0.4)
	SpellFx.shards(scene, centre + Vector3.UP * 0.5, WATER, 30, Vector2(5, 9), Vector2(0.06, 0.16), 0.6, 180.0)
	SpellFx.burst(scene, centre + Vector3.UP * 0.4, WATER.lightened(0.3), 50, Vector2(radius * 0.8, radius * 1.6), 0.7, Vector2(0.06, 0.14), 75.0, -12.0)
	SpellCastFx.mist_ring(scene, centre, radius, WATER.lightened(0.4))
	SpellFx.ground_mark(scene, centre, radius * 0.9, SpellFx.Mark.FROST, Color(0.2, 0.35, 0.55, 0.45), WATER.lightened(0.3), 3.0, 1.5)
	SpellFx.light_pop(scene, centre + Vector3.UP, WATER, 3.0, radius * 1.5, 0.45)
	AureliaSfx.play("spears_cast", centre, 2.0)
	if entangling:
		AureliaSfx.play("roots_erupt", centre, 2.0)

## Water dripping off a Drenched enemy for `seconds`.
static func drench(enemy: Enemy, seconds: float) -> void:
	var old := enemy.get_node_or_null("ArkanusDrip")
	if old:
		old.queue_free()
	var drip := SpellFx.emitter(enemy, 18, 0.7)
	drip.name = "ArkanusDrip"
	drip.position = Vector3.UP * 1.4
	drip.local_coords = false
	drip.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	drip.emission_sphere_radius = 0.45
	drip.direction = Vector3.DOWN
	drip.spread = 10.0
	drip.initial_velocity_min = 0.2
	drip.initial_velocity_max = 0.6
	drip.gravity = Vector3(0, -9.0, 0)
	drip.scale_amount_min = 0.03
	drip.scale_amount_max = 0.07
	drip.color_ramp = SpellFx.ramp(Color(WATER, 0.9), Color(WATER.lightened(0.4), 0.6), 0.3)
	drip.mesh = SpellFx.glow_quad()
	drip.emitting = true
	SpellFx.free_after(drip, seconds)

## ---- Elemental Earth ----------------------------------------------------------

## Stone Skin: rocks heave up round the player and a ring of stones orbits
## them for `seconds`.
static func stone_skin(player: Player, seconds: float) -> void:
	var scene := player.get_parent()
	var at := player.global_position
	SpellFx.burst(scene, at + Vector3.UP * 0.6, EARTH, 36, Vector2(2, 5), 0.6, Vector2(0.1, 0.22), 180.0, -9.0)
	SpellFx.shards(scene, at + Vector3.UP * 0.3, ROCK, 18, Vector2(3, 6), Vector2(0.1, 0.24), 0.8, 60.0, false)
	SpellFx.shockwave(scene, at + Vector3.UP * 0.05, 2.5, EARTH, 0.35)
	SpellFx.ground_mark(scene, at, 2.2, SpellFx.Mark.CRACKS, Color(0.12, 0.1, 0.08, 0.7), EARTH, 2.5, 0.6)
	SmokePuff.spawn(scene, at, 0.8, Color(0.55, 0.5, 0.42))
	AureliaSfx.play("golem_slam", at, 2.0)
	AureliaSfx.play("quake", at, -2.0, 1.2)
	var old := player.get_node_or_null("ArkanusStoneSkin")
	if old:
		old.queue_free()
	var shell := Node3D.new()
	shell.name = "ArkanusStoneSkin"
	player.add_child(shell)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROCK
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = EARTH * 0.25
	for i in 6:
		var a := TAU * i / 6.0
		var stone := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22, 0.16, 0.18) * randf_range(0.8, 1.2)
		box.material = mat
		stone.mesh = box
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stone.position = Vector3(cos(a) * 1.2, 0.3 + 0.15 * sin(a * 2.0), sin(a) * 1.2)
		stone.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
		shell.add_child(stone)
	var spin := shell.create_tween().set_loops()
	spin.tween_property(shell, "rotation:y", TAU, 2.5).from(0.0)
	var fade := shell.create_tween()
	fade.tween_interval(seconds - 0.3)
	fade.tween_property(shell, "scale", Vector3.ONE * 0.01, 0.3)
	fade.tween_callback(shell.queue_free)
