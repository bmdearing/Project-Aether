extends PinnacleBoss
class_name LordOfTheElements
## First Pinnacle boss (PinnacleArena). He hovers in the crescent's empty bay
## and casts; every attack and every ability that doesn't fix its own
## element takes the next element in ELEMENT_ORDER.
##
## His three floating planets are the elements (Fire, Cold, Lightning). At
## the start of the fight and of each phase he sends them down into the
## crescent, where each burns an ElementSigil: standing in a sigil whose
## element he isn't using protects you, standing in the one he is using
## hurts. The orb of the element he's casting flares, and blasts and pools
## fall as comets thrown from it.
##   Phase 1: Elemental Burst, Conflagration fire pools.
##   Phase 2 (66%): Frozen Expanse, a huge chilling slam; Storm Volley.
##   Phase 3 (33%): Cataclysm rains elemental blasts; Elemental Convergence
##   drags you in for a slam.

signal element_changed(element: int)

const ELEMENT_ORDER: Array[Constants.DamageType] = [
	Constants.DamageType.FIRE,
	Constants.DamageType.COLD,
	Constants.DamageType.LIGHTNING,
]
## The model's planet meshes, per element (each skinned to one planet bone).
const ORB_GEOSETS := {
	Constants.DamageType.FIRE: "Geoset_5",
	Constants.DamageType.COLD: "Geoset_7",
	Constants.DamageType.LIGHTNING: "Geoset_6",
}
## Wide enough that melee can reach him from the crescent's edge.
const BODY_RADIUS := 2.0
const ORB_FLIGHT := 1.2
const ORB_GLOW_RADIUS := 0.32
const ORB_CORE_RADIUS := 0.2
const COMET_SPEED_MIN := 0.35
const BOLT_RANGE := 34.0
const BOLT_COOLDOWN := 2.4

var current_element: Constants.DamageType = ELEMENT_ORDER[0]
var _next_element_index: int = 0
## element -> {"anchor": Node3D on the planet bone, "fx": top-level glow,
## "mesh": the model's planet, "sigil": ElementSigil or null}
var _orbs: Dictionary = {}

func _ready() -> void:
	super._ready()
	immovable = true
	move_speed = 0.0
	_widen_body()
	_add_bolt_attack()
	_setup_orbs()
	_apply_rim()
	element_changed.connect(_update_rim)
	if boss_brain:
		boss_brain.phase_changed.connect(func(_p): place_sigils())
	health.died.connect(_clear_sigils)
	place_sigils.call_deferred()

func begin_attack_telegraph(windup_sec: float) -> void:
	current_element = ELEMENT_ORDER[_next_element_index]
	_next_element_index = (_next_element_index + 1) % ELEMENT_ORDER.size()
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := get_node_or_null(path)
		if attack:
			attack.damage_type = current_element
	element_changed.emit(current_element)
	super.begin_attack_telegraph(windup_sec)

func get_ability_damage_type() -> int:
	return current_element

## Spells and bolts leave from the active element's orb.
func get_cast_origin() -> Vector3:
	var orb: Dictionary = _orbs.get(current_element, {})
	if orb.has("fx") and is_instance_valid(orb["fx"]):
		return orb["fx"].global_position
	return super.get_cast_origin()

## Blasts, pools and slams fall as a comet thrown from the element's orb.
func on_ability_telegraph(ability: BossAbility, target: Vector3, delay: float) -> void:
	var element: int = ability.damage_type if ability.damage_type >= 0 else current_element
	var orb: Dictionary = _orbs.get(element, {})
	if not orb.has("fx"):
		return
	_flare(element)
	var comet := ElementComet.new()
	comet.color = Constants.DAMAGE_TYPE_COLOR.get(element, Color.WHITE)
	get_parent().add_child(comet)
	comet.launch(orb["fx"].global_position, target, maxf(delay, COMET_SPEED_MIN))

func abilities() -> Array:
	return [
		{"id": "elemental_burst", "display_name": "Elemental Burst", "kind": BossAbility.Kind.BLAST, "cooldown": 6.0, "telegraph": 1.1, "radius": 3.0, "damage_mult": 1.4, "max_range": 40.0},
		{"id": "conflagration", "display_name": "Conflagration", "kind": BossAbility.Kind.HAZARD, "cooldown": 10.0, "telegraph": 1.0, "radius": 3.5, "duration": 6.0, "damage_mult": 1.0, "max_range": 40.0, "damage_type": Constants.DamageType.FIRE},
		{"id": "frozen_expanse", "display_name": "Frozen Expanse", "kind": BossAbility.Kind.BLAST, "cooldown": 15.0, "telegraph": 1.6, "radius": 7.0, "damage_mult": 1.6, "max_range": 40.0, "min_phase": 2, "damage_type": Constants.DamageType.COLD, "status": "chill"},
		{"id": "storm_volley", "display_name": "Storm Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 7.0, "telegraph": 0.8, "count": 5, "spread_degrees": 50.0, "damage_mult": 0.9, "max_range": 40.0, "min_phase": 2, "damage_type": Constants.DamageType.LIGHTNING},
		{"id": "cataclysm", "display_name": "Cataclysm", "kind": BossAbility.Kind.BLAST, "cooldown": 16.0, "telegraph": 1.2, "radius": 3.0, "count": 6, "damage_mult": 1.3, "max_range": 40.0, "min_phase": 3},
		{"id": "elemental_convergence", "display_name": "Elemental Convergence", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.0, "radius": 5.0, "damage_mult": 1.8, "max_range": 30.0, "min_phase": 3},
	]

func phase_openers() -> Dictionary:
	return {2: "frozen_expanse", 3: "cataclysm"}

## ---- Body and attacks ------------------------------------------------------

func _widen_body() -> void:
	body_radius = BODY_RADIUS
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		var capsule := collision.shape.duplicate() as CapsuleShape3D
		capsule.radius = BODY_RADIUS
		capsule.height = maxf(capsule.height, BODY_RADIUS * 2.0 + 0.2)
		collision.shape = capsule
		collision.position.y = capsule.height / 2.0

## He doesn't walk to you: an elemental bolt from the active orb instead.
func _add_bolt_attack() -> void:
	if get_node_or_null("RangedAttack"):
		return
	var bolt := EnemyRangedAttack.new()
	bolt.name = "RangedAttack"
	bolt.fire_range = BOLT_RANGE
	bolt.min_range = 0.0
	bolt.windup_duration = 0.9
	bolt.cooldown_duration = BOLT_COOLDOWN
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	bolt.damage_amount = melee.damage_amount * 0.8 if melee else 30.0
	bolt.projectile_speed = 18.0
	add_child(bolt)

## ---- Orbs ------------------------------------------------------------------

## A glow and light that follow each planet bone, so the orbs read as the
## elements even while they're still on him.
func _setup_orbs() -> void:
	if _model_root == null:
		return
	var skeletons := _model_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0]
	for element in ORB_GEOSETS:
		var mesh := _model_root.find_child(ORB_GEOSETS[element], true, false) as MeshInstance3D
		if mesh == null or mesh.skin == null:
			continue
		var bone_name := _orb_bone(mesh, skeleton)
		if bone_name == "":
			continue
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
		var anchor := Node3D.new()
		anchor.position = _orb_bind_pose(mesh, bone_name) * mesh.get_aabb().get_center()
		attachment.add_child(anchor)
		var fx := _orb_glow(Constants.DAMAGE_TYPE_COLOR.get(element, Color.WHITE), mesh.get_active_material(0))
		add_child(fx)
		fx.top_level = true
		_orbs[element] = {"anchor": anchor, "fx": fx, "mesh": mesh, "sigil": null, "landed": false}

func _orb_bone(mesh: MeshInstance3D, skeleton: Skeleton3D) -> String:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	if bones.is_empty():
		return ""
	var bind := bones[0]
	var name := mesh.skin.get_bind_name(bind)
	return String(name) if name != &"" else skeleton.get_bone_name(mesh.skin.get_bind_bone(bind))

func _orb_bind_pose(mesh: MeshInstance3D, bone_name: String) -> Transform3D:
	for i in mesh.skin.get_bind_count():
		if String(mesh.skin.get_bind_name(i)) == bone_name:
			return mesh.skin.get_bind_pose(i)
	return Transform3D.IDENTITY

## A planet core (the model's own planet material), a halo and a light.
func _orb_glow(color: Color, planet: Material) -> Node3D:
	var root := Node3D.new()
	var core := MeshInstance3D.new()
	core.name = "Core"
	var ball := SphereMesh.new()
	ball.radius = ORB_CORE_RADIUS
	ball.height = ORB_CORE_RADIUS * 2.0
	core.mesh = ball
	core.material_override = planet
	root.add_child(core)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var sphere := SphereMesh.new()
	sphere.radius = ORB_GLOW_RADIUS
	sphere.height = ORB_GLOW_RADIUS * 2.0
	halo.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, 0.22)
	halo.material_override = mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 5.0
	root.add_child(light)
	return root

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for element in _orbs:
		var orb: Dictionary = _orbs[element]
		if not is_instance_valid(orb["fx"]):
			continue
		var fx: Node3D = orb["fx"]
		if not orb.get("flying", false):
			if orb["landed"] and is_instance_valid(orb["sigil"]):
				fx.global_position = orb["sigil"].orb_spot() + Vector3(0, sin(t * 2.0 + element) * 0.15, 0)
			elif is_instance_valid(orb["anchor"]):
				fx.global_position = orb["anchor"].global_position
		var active: bool = element == current_element
		var flare: float = orb.get("flare", 0.0)
		orb["flare"] = maxf(flare - delta * 1.5, 0.0)
		var light := fx.get_node("Light") as OmniLight3D
		light.light_energy = (2.4 if active else 0.7) + flare * 4.0
		var size := (1.25 if active else 0.85) + flare * 0.8 + 0.06 * sin(t * 5.0 + element)
		fx.get_node("Halo").scale = Vector3.ONE * size

func _flare(element: int) -> void:
	if _orbs.has(element):
		_orbs[element]["flare"] = 1.0

## ---- Rim light ---------------------------------------------------------
## An additive fresnel overlay in the current element's colour, so his dark
## body reads against the black sky.
const RIM_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 rim_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform float rim_power = 2.2;
uniform float strength = 1.4;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * rim * strength;
}
"""

var _rim: ShaderMaterial

func _apply_rim() -> void:
	if _model_root == null:
		return
	var shader := Shader.new()
	shader.code = RIM_SHADER
	_rim = ShaderMaterial.new()
	_rim.shader = shader
	var orb_meshes: Array = ORB_GEOSETS.values()
	for node in _model_root.find_children("*", "MeshInstance3D", true, false):
		if not orb_meshes.has(String(node.name)):
			(node as MeshInstance3D).material_overlay = _rim
	_update_rim(current_element)

func _update_rim(element: int) -> void:
	if _rim:
		var color: Color = Constants.DAMAGE_TYPE_COLOR.get(element, Color.WHITE)
		_rim.set_shader_parameter("rim_color", color.lerp(Color.WHITE, 0.35))

## ---- Sigils ----------------------------------------------------------------

## Sends each orb down to a sigil spot the arena offers (PinnacleArena.
## sigil_spots()); old sigils fade as their orbs lift off. Called at the
## start and on every phase change.
func place_sigils() -> void:
	var arena := get_parent()
	if not is_inside_tree() or not health.is_alive() or not arena.has_method("sigil_spots"):
		return
	var spots: Array = arena.sigil_spots(_orbs.size())
	var elements := _orbs.keys()
	elements.shuffle()
	for i in mini(elements.size(), spots.size()):
		_send_orb(elements[i], spots[i])

func _send_orb(element: int, spot: Vector3) -> void:
	var orb: Dictionary = _orbs[element]
	if is_instance_valid(orb["sigil"]):
		orb["sigil"].fade_out()
	orb["sigil"] = null
	orb["landed"] = false
	orb["flying"] = true
	# Render layers, not visible: the model's own animation toggles visibility.
	orb["mesh"].layers = 0
	var fx: Node3D = orb["fx"]
	var target := spot + Vector3(0, ElementSigil.ORB_HEIGHT, 0)
	var apex := (fx.global_position + target) / 2.0 + Vector3(0, 6.0, 0)
	var start := fx.global_position
	var fly := func(f: float) -> void:
		if is_instance_valid(fx):
			fx.global_position = start.lerp(apex, f).lerp(apex.lerp(target, f), f)
	var land := func() -> void:
		orb["flying"] = false
		if not health.is_alive():
			return
		var sigil := ElementSigil.new()
		sigil.element = element
		sigil.lord = self
		get_parent().add_child(sigil)
		sigil.global_position = spot
		orb["sigil"] = sigil
		orb["landed"] = true
	var tween := create_tween()
	tween.tween_method(fly, 0.0, 1.0, ORB_FLIGHT)
	tween.tween_callback(land)

func _clear_sigils() -> void:
	for orb in _orbs.values():
		if is_instance_valid(orb["sigil"]):
			orb["sigil"].fade_out()
		if is_instance_valid(orb["fx"]):
			orb["fx"].queue_free()
		orb["fx"] = null
