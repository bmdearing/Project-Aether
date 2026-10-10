extends PinnacleBoss
class_name LordOfTheElements
## First Pinnacle boss (PinnacleArena). The fight asks: can you read his
## elemental cycle and break it?
##
## Every attack and every ability that doesn't fix its own element takes the
## next element in the cycle (Fire -> Cold -> Lightning). His three planets
## are the elements; at the start of each phase they land on the crescent as
## ElementSigils and hover over them.
##   - The orb of the element he is using is exposed (ElementOrb): damage it
##     enough and it overloads. That element drops out of the cycle for
##     OVERLOAD_SEC and the backlash stuns him.
##   - His spells react with each other (ElementReactions): cold on a fire
##     pool makes steam he can't see into, lightning runs along chilled
##     ground, fire shatters it. Chains and shards that reach him hurt him.
##   - Cataclysm (phase 2+) is survivable only inside the sigil of the
##     element he will use two casts after it.
##   Phase 1: Elemental Burst, Conflagration fire pools.
##   Phase 2 (66%): Frozen Expanse, Storm Volley, Cataclysm.
##   Phase 3 (33%): Cataclysm, then the orbs fuse into his weapon and he comes
##   down to fight in melee, one parryable combo per element (Fire: three
##   quick hits; Cold: a long windup that freezes; Lightning: a feint, then a
##   late strike) and Elemental Convergence drags you in.

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
const ORB_SCENE := preload("res://entities/enemies/lord_of_the_elements/ElementOrb.tscn")
## Wide enough that melee can reach him from the crescent's edge.
const BODY_RADIUS := 2.0
const ORB_FLIGHT := 1.2
const ORB_GLOW_RADIUS := 0.32
const ORB_CORE_RADIUS := 0.2
const COMET_SPEED_MIN := 0.35
const BOLT_RANGE := 34.0
const BOLT_COOLDOWN := 2.4

## Orb overload: the damage it takes (a share of his max Life), how long its
## element is gone, and the backlash.
const ORB_OVERLOAD_SHARE := 0.035
const OVERLOAD_SEC := 20.0
const OVERLOAD_STUN_SEC := 2.5
const OVERLOAD_STANCE_DAMAGE := 40.0
## A chain or shard burst from his own spells reaching him.
const BACKLASH_SHARE := 0.02
const BACKLASH_STANCE_DAMAGE := 25.0
const BACKLASH_STUN_SEC := 1.0

## Cataclysm: damage outside the safe sigil, in multiples of your Life + Ward.
const CATACLYSM_LETHAL := 4.0
const CATACLYSM_TELEGRAPH := 4.0
const CATACLYSM_COMETS := 10

## Phase 3: he lands here (PinnacleArena.lord_landing_spot()) and walks.
const DESCENT_SEC := 1.6
const PHASE3_MOVE_SPEED := 4.5
const PHASE3_STOP_DISTANCE := 2.6
## Melee combos: reach from his body, Composure a parried blow costs him.
const COMBO_REACH := 2.8
const COMBO_PARRY_STANCE := 15.0
## His ranged spells stay in the air; once he lands he only uses these.
const GROUNDED_ABILITIES := ["cataclysm", "elemental_convergence", "fire_combo", "cold_strike", "lightning_feint"]
const COMBO_ELEMENTS := {
	"fire_combo": Constants.DamageType.FIRE,
	"cold_strike": Constants.DamageType.COLD,
	"lightning_feint": Constants.DamageType.LIGHTNING,
}

var current_element: Constants.DamageType = ELEMENT_ORDER[0]
var _next_element_index: int = 0
## element -> {"anchor": Node3D on the planet bone, "fx": top-level glow,
## "mesh": the model's planet, "sigil": ElementSigil or null, "body": ElementOrb}
var _orbs: Dictionary = {}
## element -> Time msec when its overload ends.
var _overloaded_until: Dictionary = {}
var reactions: ElementReactions
## Telegraphed strike spot -> the element it will land as.
var _strike_elements: Dictionary = {}
## Set while Cataclysm is charging: the sigil element that will be safe.
var cataclysm_pending := false
var cataclysm_safe: int = -1
## Whether the last Cataclysm caught the player outside the safe sigil.
var last_cataclysm_struck := false
## Phase 3: down on the crescent with the orbs fused into his weapon.
var descended := false
## Combos and Cataclysm pick their own element: telegraphs don't advance it.
var _hold_element := false

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
		boss_brain.ground_struck.connect(_on_ground_struck)
	health.died.connect(_clear_sigils)
	place_sigils.call_deferred()
	_setup_arena_pieces.call_deferred()

## Orb bodies and the reaction tracker join the arena once it's done building.
func _setup_arena_pieces() -> void:
	if not is_inside_tree():
		return
	reactions = ElementReactions.new()
	reactions.name = "ElementReactions"
	reactions.lord = self
	get_parent().add_child(reactions)
	for element in _orbs:
		var body: ElementOrb = ORB_SCENE.instantiate()
		body.element = element
		body.lord = self
		get_parent().add_child(body)
		body.set_integrity(health.max_health * ORB_OVERLOAD_SHARE)
		_orbs[element]["body"] = body

## ---- The elemental cycle -------------------------------------------------

func is_overloaded(element: int) -> bool:
	return Time.get_ticks_msec() < int(_overloaded_until.get(element, 0))

func _enabled_elements() -> Array[Constants.DamageType]:
	var out: Array[Constants.DamageType] = []
	for e in ELEMENT_ORDER:
		if not is_overloaded(e):
			out.append(e)
	return out

## The element `steps` telegraphs from now (1 = the next one he uses),
## skipping overloaded elements.
func element_after(steps: int) -> int:
	if _enabled_elements().is_empty():
		return ELEMENT_ORDER[(_next_element_index + steps - 1) % ELEMENT_ORDER.size()]
	var index := _next_element_index
	var found: int = ELEMENT_ORDER[index]
	var taken := 0
	for i in ELEMENT_ORDER.size() * (steps + 1):
		var e := ELEMENT_ORDER[index]
		index = (index + 1) % ELEMENT_ORDER.size()
		if is_overloaded(e):
			continue
		taken += 1
		found = e
		if taken == steps:
			break
	return found

func _advance_element() -> void:
	var next := element_after(1)
	current_element = next as Constants.DamageType
	_next_element_index = (ELEMENT_ORDER.find(current_element) + 1) % ELEMENT_ORDER.size()

func _set_element(element: int) -> void:
	current_element = element as Constants.DamageType
	_next_element_index = (ELEMENT_ORDER.find(current_element) + 1) % ELEMENT_ORDER.size()
	_sync_attack_types()
	element_changed.emit(current_element)

func _sync_attack_types() -> void:
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := get_node_or_null(path)
		if attack:
			attack.damage_type = current_element

func begin_attack_telegraph(windup_sec: float) -> void:
	if not _hold_element:
		_advance_element()
		_sync_attack_types()
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

## ---- Orb overload ----------------------------------------------------------

## An orb can be hurt while its element is the one he's using, he's still in
## the air, and it isn't the last element left.
func is_orb_exposed(element: int) -> bool:
	return health.is_alive() and not descended and element == current_element \
		and not is_overloaded(element) and _enabled_elements().size() > 1

## The orb burst: its element leaves the cycle and the backlash stuns him.
func overload(element: int) -> void:
	if is_overloaded(element):
		return
	_overloaded_until[element] = Time.get_ticks_msec() + int(OVERLOAD_SEC * 1000.0)
	_flare(element)
	status_effects.apply_timed_effect("stun", OVERLOAD_STUN_SEC)
	interrupt_attack()
	if stance:
		stance.apply_parry_damage(OVERLOAD_STANCE_DAMAGE)
	var orb: Dictionary = _orbs.get(element, {})
	if orb.has("fx") and is_instance_valid(orb["fx"]):
		var color: Color = Constants.DAMAGE_TYPE_COLOR.get(element, Color.WHITE)
		LightningArc.spawn(get_parent(), orb["fx"].global_position, global_position + Vector3.UP * 2.0, color, 1.6)
		BossTelegraph.circle(get_parent(), Vector3(orb["fx"].global_position.x, global_position.y, orb["fx"].global_position.z), 2.0, 0.4, color)
	if element == current_element:
		_advance_element()
		_sync_attack_types()
		element_changed.emit(current_element)

## One of his own chains or shard bursts reached him.
func take_reaction_backlash(element: int) -> void:
	if not health.is_alive():
		return
	var amount := health.max_health * BACKLASH_SHARE
	if take_damage(amount, element as Constants.DamageType, true):
		EventBus.damage_dealt.emit(get_tree().get_first_node_in_group("player"), self, amount, element, true, false)
	flash_hit()
	if stance:
		stance.apply_parry_damage(BACKLASH_STANCE_DAMAGE)
	status_effects.apply_timed_effect("stun", BACKLASH_STUN_SEC)

## ---- Abilities -------------------------------------------------------------

## Blasts, pools and slams fall as a comet thrown from the element's orb.
func on_ability_telegraph(ability: BossAbility, target: Vector3, delay: float) -> void:
	var element: int = ability.damage_type if ability.damage_type >= 0 else current_element
	_strike_elements[target] = element
	var orb: Dictionary = _orbs.get(element, {})
	if not orb.has("fx") or not is_instance_valid(orb["fx"]):
		return
	_flare(element)
	var comet := ElementComet.new()
	comet.color = Constants.DAMAGE_TYPE_COLOR.get(element, Color.WHITE)
	get_parent().add_child(comet)
	comet.launch(orb["fx"].global_position, target, maxf(delay, COMET_SPEED_MIN))

## Every ground strike feeds the reactions: cold puts out fire pools as
## steam, and each element reacts with chilled ground.
func _on_ground_struck(ability: BossAbility, center: Vector3, radius: float) -> void:
	var element: int = _strike_elements.get(center, ability.damage_type if ability.damage_type >= 0 else current_element)
	_strike_elements.erase(center)
	if reactions == null or not is_instance_valid(reactions):
		return
	var damage := get_ability_base_damage() * ability.damage_mult
	if element == Constants.DamageType.COLD and boss_brain:
		for pool in boss_brain.extinguish_hazards(center, radius, func(a: BossAbility): return a.damage_type == Constants.DamageType.FIRE):
			reactions.on_cold_over_fire(pool["center"], pool["radius"])
	reactions.on_strike(element, center, radius, damage)

## Hidden in steam, he can't aim at you; once down on the crescent he
## only fights up close.
func can_use_ability(a: BossAbility) -> bool:
	if descended and not GROUNDED_ABILITIES.has(a.id):
		return false
	if COMBO_ELEMENTS.has(a.id):
		return descended and COMBO_ELEMENTS[a.id] == element_after(1)
	if a.id == "cataclysm":
		return not sigils().is_empty()
	var aimed := a.kind == BossAbility.Kind.BLAST or a.kind == BossAbility.Kind.HAZARD or a.kind == BossAbility.Kind.VOLLEY
	return not (aimed and player_hidden())

func player_hidden() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player != null and reactions != null and is_instance_valid(reactions) and reactions.in_steam(player.global_position)

func abilities() -> Array:
	var fire := Constants.DamageType.FIRE
	var cold := Constants.DamageType.COLD
	var lightning := Constants.DamageType.LIGHTNING
	return [
		{"id": "elemental_burst", "display_name": "Elemental Burst", "kind": BossAbility.Kind.BLAST, "cooldown": 6.0, "telegraph": 1.1, "radius": 3.0, "damage_mult": 1.4, "max_range": 40.0,
			"description": "Bursts on your spot in his current element. Cold ones leave chilled ground."},
		{"id": "conflagration", "display_name": "Conflagration", "kind": BossAbility.Kind.HAZARD, "cooldown": 10.0, "telegraph": 1.0, "radius": 3.5, "duration": 6.0, "damage_mult": 1.0, "max_range": 40.0, "damage_type": fire,
			"description": "A burning pool. Cold landing on it turns it to steam he can't see into."},
		{"id": "frozen_expanse", "display_name": "Frozen Expanse", "kind": BossAbility.Kind.BLAST, "cooldown": 15.0, "telegraph": 1.6, "radius": 7.0, "damage_mult": 1.6, "max_range": 40.0, "min_phase": 2, "damage_type": cold, "status": "chill",
			"description": "A wide chilling blast that leaves a sheet of chilled ground. Lightning runs along it; fire shatters it."},
		{"id": "storm_volley", "display_name": "Storm Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 7.0, "telegraph": 0.8, "count": 5, "spread_degrees": 50.0, "damage_mult": 0.9, "max_range": 40.0, "min_phase": 2, "damage_type": lightning},
		{"id": "cataclysm", "display_name": "Cataclysm", "kind": BossAbility.Kind.CUSTOM, "cooldown": 26.0, "telegraph": CATACLYSM_TELEGRAPH, "max_range": 60.0, "min_phase": 2,
			"description": "Only the sigil of the element he will use two casts later shelters you."},
		{"id": "elemental_convergence", "display_name": "Elemental Convergence", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.0, "radius": 5.0, "damage_mult": 1.8, "max_range": 30.0, "min_phase": 3},
		{"id": "fire_combo", "display_name": "Fire Combo", "kind": BossAbility.Kind.CUSTOM, "cooldown": 5.0, "telegraph": 0.45, "damage_mult": 0.7, "max_range": 7.0, "min_phase": 3, "damage_type": fire, "status": "ignite",
			"description": "Three quick blows. Parry each one."},
		{"id": "cold_strike", "display_name": "Cold Strike", "kind": BossAbility.Kind.CUSTOM, "cooldown": 5.0, "telegraph": 1.6, "damage_mult": 1.8, "max_range": 7.0, "min_phase": 3, "damage_type": cold,
			"description": "A long windup, then one blow that freezes you if it lands."},
		{"id": "lightning_feint", "display_name": "Lightning Feint", "kind": BossAbility.Kind.CUSTOM, "cooldown": 5.0, "telegraph": 0.7, "damage_mult": 1.4, "max_range": 7.0, "min_phase": 3, "damage_type": lightning, "status": "shock",
			"description": "Starts a swing and pulls it back, then strikes late."},
	]

func phase_openers() -> Dictionary:
	return {2: "frozen_expanse", 3: "cataclysm"}

func cast_custom(a: BossAbility) -> void:
	match a.id:
		"cataclysm":
			await _cataclysm(a)
			if boss_brain and boss_brain.phase >= 3 and not descended:
				await _descend()
		"fire_combo":
			_hold_element = true
			_set_element(Constants.DamageType.FIRE)
			for windup in [a.telegraph, 0.35, 0.35]:
				await _combo_strike(a, windup)
				if not health.is_alive():
					break
			_hold_element = false
		"cold_strike":
			_hold_element = true
			_set_element(Constants.DamageType.COLD)
			await _combo_strike(a, a.telegraph)
			_hold_element = false
		"lightning_feint":
			_hold_element = true
			_set_element(Constants.DamageType.LIGHTNING)
			await _feint(a)
			await _combo_strike(a, 0.3)
			_hold_element = false
		_:
			await get_tree().process_frame

## ---- Cataclysm ---------------------------------------------------------------

func sigils() -> Array:
	var out: Array = []
	for orb in _orbs.values():
		if is_instance_valid(orb.get("sigil")):
			out.append(orb["sigil"])
	return out

func _cataclysm(a: BossAbility) -> void:
	begin_attack_telegraph(a.telegraph)
	cataclysm_safe = element_after(2)
	cataclysm_pending = true
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(current_element, Color.WHITE)
	var arena := get_parent()
	var centre: Vector3 = arena.to_global(Vector3.ZERO) if arena is Node3D else global_position
	BossTelegraph.circle(arena, centre, 30.0, a.telegraph, color)
	# Comets streak down across the crescent as it charges.
	for i in CATACLYSM_COMETS:
		get_tree().create_timer(a.telegraph * float(i) / CATACLYSM_COMETS, false).timeout.connect(_cataclysm_comet.bind(centre))
	await get_tree().create_timer(a.telegraph, false).timeout
	cataclysm_pending = false
	if not health.is_alive():
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	var safe := sigils().filter(func(s): return s.element == cataclysm_safe)
	for s in sigils():
		s.call("resolve_flash", s.element == cataclysm_safe)
	last_cataclysm_struck = false
	if player and player.health.is_alive() and not safe.is_empty() and not safe.any(func(s): return s.contains(player.global_position)):
		last_cataclysm_struck = true
		var lethal := (player.health.max_health + (player.ward.max_ward if player.ward else 0.0)) * CATACLYSM_LETHAL
		player.take_damage(lethal, current_element, self, Player.HitKind.SPELL)
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.explosion), centre, 0.0, 0.6)

func _cataclysm_comet(centre: Vector3) -> void:
	if not is_inside_tree() or not health.is_alive():
		return
	var orb: Dictionary = _orbs.get(current_element, {})
	var from: Vector3 = orb["fx"].global_position if orb.has("fx") and is_instance_valid(orb["fx"]) else global_position + Vector3.UP * 4.0
	var angle := randf_range(-1.1, 1.1)
	var spot := centre + Vector3(sin(angle), 0, -cos(angle)) * randf_range(14.0, 24.0)
	var comet := ElementComet.new()
	comet.color = Constants.DAMAGE_TYPE_COLOR.get(current_element, Color.WHITE)
	get_parent().add_child(comet)
	comet.launch(from, spot, 0.8)

## ---- Phase 3: down to melee ---------------------------------------------------

func _descend() -> void:
	var arena := get_parent()
	if not arena.has_method("lord_landing_spot"):
		return
	var landing: Vector3 = arena.lord_landing_spot()
	begin_attack_telegraph(DESCENT_SEC)
	BossTelegraph.circle(arena, landing, BODY_RADIUS + 1.0, DESCENT_SEC, Color(1.0, 0.85, 0.5))
	var tween := create_tween()
	tween.tween_property(self, "global_position", landing, DESCENT_SEC).set_trans(Tween.TRANS_SINE)
	await tween.finished
	if not health.is_alive():
		return
	descended = true
	immovable = false
	move_speed = PHASE3_MOVE_SPEED
	stop_distance = PHASE3_STOP_DISTANCE
	var bolt := get_node_or_null("RangedAttack")
	if bolt:
		bolt.process_mode = Node.PROCESS_MODE_DISABLED
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.explosion), landing, 0.0, 0.7)

## One parryable blow: windup, then everything within reach in front of him.
func _combo_strike(a: BossAbility, windup: float) -> void:
	_play_attack(windup)
	var ahead := _ahead_spot()
	var telegraph := BossTelegraph.circle(get_parent(), ahead, COMBO_REACH * 0.8, windup, Constants.DAMAGE_TYPE_COLOR.get(current_element, Color.WHITE))
	await get_tree().create_timer(windup, false).timeout
	if not health.is_alive() or status_effects.is_stunned():
		if is_instance_valid(telegraph):
			telegraph.queue_free()
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or distance_to_body(player.global_position) > COMBO_REACH:
		return
	var parried: bool = player.parry_handler != null and player.parry_handler.attempt_parry(self, player.ward)
	if parried:
		if stance:
			stance.apply_parry_damage(COMBO_PARRY_STANCE)
	elif not player.try_block_melee_hit():
		var amount := get_ability_base_damage() * a.damage_mult
		player.take_damage(amount, current_element, self, Player.HitKind.ATTACK, true)
		if player.status_effects:
			if a.id == "cold_strike":
				for i in StatusEffectComponent.CHILL_STACKS_TO_FREEZE:
					player.status_effects.apply_effect("chill", self, amount)
			elif a.status != "":
				player.status_effects.apply_effect(a.status, self, amount)
	EventBus.enemy_attack_resolved.emit(self, player, true, parried)

## The feint: the swing and its warning start, then he pulls it back.
func _feint(a: BossAbility) -> void:
	_play_attack(a.telegraph)
	var telegraph := BossTelegraph.circle(get_parent(), _ahead_spot(), COMBO_REACH * 0.8, a.telegraph, Constants.DAMAGE_TYPE_COLOR.get(current_element, Color.WHITE))
	await get_tree().create_timer(a.telegraph * 0.6, false).timeout
	if is_instance_valid(telegraph):
		telegraph.queue_free()
	if _anim_controller and health.is_alive():
		_anim_controller.play_stagger()
	await get_tree().create_timer(0.55, false).timeout

func _play_attack(windup: float) -> void:
	if _anim_controller:
		_anim_controller.play_attack(windup)

func _ahead_spot() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var dir := (player.global_position - global_position) if player else -global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3.FORWARD
	return global_position + dir * BODY_RADIUS

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
	# A spinning ring marks the orb you can hurt right now.
	var ring := MeshInstance3D.new()
	ring.name = "Exposed"
	var torus := TorusMesh.new()
	torus.inner_radius = ORB_GLOW_RADIUS * 1.6
	torus.outer_radius = ORB_GLOW_RADIUS * 1.85
	ring.mesh = torus
	ring.rotation.x = 0.5
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = Color(1, 1, 1, 0.85)
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	root.add_child(ring)
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
		if descended and not orb.get("flying", false):
			# Fused: the three circle the weapon arm.
			var a := t * 2.2 + TAU * ELEMENT_ORDER.find(element) / 3.0
			fx.global_position = global_position + global_transform.basis * Vector3(0.9, 1.9, -0.6) + Vector3(cos(a), sin(a * 0.7) * 0.4, sin(a)) * 0.55
		elif not orb.get("flying", false):
			if orb["landed"] and is_instance_valid(orb["sigil"]):
				fx.global_position = orb["sigil"].orb_spot() + Vector3(0, sin(t * 2.0 + element) * 0.15, 0)
			elif is_instance_valid(orb["anchor"]):
				fx.global_position = orb["anchor"].global_position
		var active: bool = element == current_element
		var flare: float = orb.get("flare", 0.0)
		orb["flare"] = maxf(flare - delta * 1.5, 0.0)
		var spent := is_overloaded(element)
		var exposed := is_orb_exposed(element)
		var light := fx.get_node("Light") as OmniLight3D
		light.light_energy = 0.15 if spent else (2.4 if active else 0.7) + flare * 4.0
		var size := (0.6 if spent else (1.25 if active else 0.85)) + flare * 0.8 + 0.06 * sin(t * 5.0 + element)
		fx.get_node("Halo").scale = Vector3.ONE * size
		var ring := fx.get_node_or_null("Exposed") as MeshInstance3D
		if ring:
			ring.visible = exposed
			ring.rotation.y += delta * 3.0
			ring.scale = Vector3.ONE * (1.0 + 0.15 * sin(t * 8.0))
		var body: ElementOrb = orb.get("body")
		if is_instance_valid(body):
			body.follow(fx.global_position)

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
		if is_instance_valid(orb.get("body")):
			orb["body"].queue_free()
		if is_instance_valid(orb["sigil"]):
			orb["sigil"].fade_out()
		if is_instance_valid(orb["fx"]):
			orb["fx"].queue_free()
		orb["fx"] = null
	if is_instance_valid(reactions):
		reactions.queue_free()
