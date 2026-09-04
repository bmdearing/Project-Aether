extends CharacterBody3D
class_name Player
## First-person controller. Camera lives in Head; WeaponSocket under the
## camera holds the active weapon's visual - a real model where one
## exists (_update_weapon_model()), the placeholder blade otherwise -
## now mounted on ArmRig's Hand bone rather than sitting directly on
## WeaponSocket (2026-08-30, PlayerArmRig). Melee weight (Pillar 2) reads
## through camera shake/swing/hitstop plus the arm's own 3-bone swing.

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 3.0
## 7.0 (was 4.5) - needed to clear the Vault's jump gap + platform rise;
## matches Enemy.jump_velocity, tuned the same way.
@export var jump_velocity: float = 7.0
## Extra gravity while falling (not rising) - standard "snappier jump arc"
## trick, doesn't touch the ascent so Vault gap-clearing (tuned assuming
## the old symmetric gravity through the rise) is unaffected.
const FALL_GRAVITY_MULTIPLIER := 1.7
@export var mouse_sensitivity: float = 0.0035
@export var max_look_up_deg: float = 89.0
@export var stat_sheet: StatSheet

@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_socket: Node3D = $Head/Camera3D/WeaponSocket
## PlayerArmRig reparents WeaponMesh onto its Hand bone during its own
## _ready() (child of WeaponSocket, so it runs before Player's own
## @onready block below resolves) - these paths point at that final
## location, not WeaponMesh's static position in Player.tscn.
@onready var arm_rig: PlayerArmRig = $Head/Camera3D/WeaponSocket/ArmRig
@onready var weapon_mesh: MeshInstance3D = $Head/Camera3D/WeaponSocket/ArmRig/Skeleton3D/HandAttachment/WeaponMesh
@onready var attack_hitbox: Area3D = $Head/Camera3D/WeaponSocket/ArmRig/Skeleton3D/HandAttachment/WeaponMesh/AttackHitbox
@onready var shield_mesh: MeshInstance3D = $Head/Camera3D/ShieldSocket/ShieldMesh
@onready var health: HealthComponent = $HealthComponent
@onready var ward: WardComponent = $WardComponent
@onready var mana: ManaComponent = $ManaComponent
@onready var parry_handler: ParryRiposteHandler = $ParryRiposteHandler
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var ability_loadout: AbilityLoadoutComponent = $AbilityLoadoutComponent
@onready var melee_attack: PlayerMeleeAttack = $PlayerMeleeAttack
@onready var ranged_attack: PlayerRangedAttack = $PlayerRangedAttack
@onready var ability_cast: PlayerAbilityCast = $PlayerAbilityCast
@onready var experience: ExperienceComponent = $ExperienceComponent
@onready var status_effects: StatusEffectComponent = $StatusEffectComponent
@onready var weapon_stance: WeaponStance = $WeaponStance
@onready var cast_time_handler: CastTimeHandler = $CastTimeHandler

## Implementation Brief v3.3 Section 2: distinguishes a light-jab tap from
## a standard-thrust hold, tracked only while a melee weapon is active and
## WeaponStance isn't (charged thrust owns LMB press while stance is
## active, unchanged from before this brief - see _handle_attack_input()).
const STANDARD_THRUST_HOLD_THRESHOLD := 0.6
var _lmb_held_time: float = 0.0
var _lmb_was_held: bool = false

## Implementation Brief v3.4 Section 4 (2026-08-31), user-expanded scope:
## tap X swaps active weapon SET (EquipmentComponent.toggle_weapon_set()),
## hold X toggles the active stance PAGE (WeaponStance.toggle_stance_page())
## instead - same tap-vs-hold shape as the LMB jab/thrust split above, just
## a different threshold/key ("weapon_swap", bound to X).
const WEAPON_SWAP_HOLD_THRESHOLD := 0.25
var _x_held_time: float = 0.0
var _x_triggered_hold: bool = false

## Real weapon models (assets/models/pack1/, a purchased low-poly pack) -
## keyed by Weapon.weapon_type, same string GearShop/DebugOverlay/
## Constants.WEAPON_BASE_CRIT_CHANCE already key off. Anything not listed
## here (e.g. "Service Pistol" - no firearm exists in this melee-focused
## pack; "Rapier"/"Gauntlet" - no matching model in this pack either, see
## PATCH_NOTES.md) falls back to the original placeholder blade, tinted
## by damage type same as before.
const WEAPON_MODEL_SCENES := {
	"Greatsword": preload("res://assets/models/pack1/Low Poly Weapon Pack - by Kickin It Studios.fbx_Great_Sword.fbx"),
	"Dagger": preload("res://assets/models/pack1/Low Poly Weapon Pack - by Kickin It Studios.fbx_Dagger.fbx"),
	"Bow": preload("res://assets/models/pack1/Low Poly Weapon Pack - by Kickin It Studios.fbx_Bow.fbx"),
	"Staff": preload("res://assets/models/pack1/Low Poly Weapon Pack - by Kickin It Studios.fbx_Wizard_Staff.fbx"),
}

var fate_board: FateBoard

## Patch v3.5 Section 3: throwables are a stackable inventory consumable,
## not an equipment slot - just whichever stack is currently selected to
## throw. How the player acquires/selects a stack is out of scope for
## this pass (data architecture + input wiring only, per the brief) -
## starts null until something else sets it.
var active_throwable: ThrowableStack = null

func use_throwable() -> void:
	if active_throwable == null or not active_throwable.can_use():
		return
	active_throwable.consume()
	EventBus.throwable_used.emit(active_throwable.throwable_type)

var _last_active_weapon: Weapon = null
var _weapon_model: Node3D
var _placeholder_blade_mesh: Mesh
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_max_health: float = 0.0
var _base_max_mana: float = 0.0
var _base_mana_regen: float = 0.0

## Crouch/slide: fully invented, no doc-sourced design. Capsule shrinks
## from STANDING to CROUCH height anchored at the feet (not centered),
## head lowers to match. No headroom check standing up - nothing low
## enough to clip into yet.
const STANDING_CAPSULE_HEIGHT := 1.8
const CROUCH_CAPSULE_HEIGHT := 1.0
const STANDING_HEAD_Y := 1.6
const CROUCH_HEAD_Y := 0.8
const CROUCH_TRANSITION_SPEED := 6.0

## Slide: tap Crouch while sprinting + moving, on the floor. Launches
## along the move direction at SLIDE_SPEED (or current sprint speed if
## faster), decelerating to crouch speed. Jumping/leaving the floor
## cancels it; ends into a crouch if Crouch is still held.
const SLIDE_SPEED := 12.0
const SLIDE_DURATION := 0.5
const SLIDE_DECELERATION := 14.0

var _is_crouching: bool = false
var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _slide_speed_current: float = 0.0

## Dash: user request, "Tapping shift and a direction should allow
## players to dash in a direction." Reuses the "sprint" action (already
## bound to Shift) rather than a new key - just_pressed fires once
## regardless of how long the key stays down afterward, so a tap
## triggers a dash burst and holding still sprints normally on top of it,
## no new binding or hold/tap-duration detection needed. Fully invented,
## no doc-sourced design (same status as Crouch/Slide above) - a fixed-
## impulse burst that decays like Slide's own SLIDE_SPEED/
## SLIDE_DECELERATION pattern, not integrated with it (Slide requires
## sprinting+crouch-tap+floor; Dash works in the air and while stationary
## alike, since "dash to reposition/dodge" is the point).
const DASH_SPEED := 14.0
const DASH_DURATION := 0.2
const DASH_DECELERATION := 20.0
const DASH_COOLDOWN := 1.0

var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_speed_current: float = 0.0
var _dash_cooldown_remaining: float = 0.0

## Section 12: Instinct -> Action Speed, split by type ("1% Attack/Cast |
## 0.7% Dodge | 0.5% Move" per point). No Dodge mechanic exists yet.
const INSTINCT_MOVE_SPEED_PCT := 0.005
const INSTINCT_ACTION_SPEED_PCT := 0.01

func _ready() -> void:
	if stat_sheet == null:
		# Fallback only - Player.tscn assigns player_baseline.tres normally.
		stat_sheet = StatSheet.new()
		stat_sheet.vitality = 10.0
		stat_sheet.strength = 10.0
		stat_sheet.instinct = 10.0
		stat_sheet.arcane = 10.0
		stat_sheet.enigma = 10.0
		stat_sheet.intellect = 10.0
	fate_board = FateBoard.new()
	GameState.player_stat_sheet = stat_sheet
	GameState.fate_board = fate_board
	GameState.player_equipment = equipment
	mouse_sensitivity = GameState.mouse_sensitivity
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	health.died.connect(_on_died)
	# Captured before any gear bonus applies - the .tscn's static values
	# are the class baseline Vitality/Intellect add on top of.
	_base_max_health = health.max_health
	_base_max_mana = mana.max_mana
	_base_mana_regen = mana.regen_per_second
	if collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	_placeholder_blade_mesh = weapon_mesh.mesh
	equipment.equipment_changed.connect(_on_equipment_changed)
	EventBus.slate_placed.connect(func(_id, _pos): _apply_fate_board_bonuses())
	EventBus.slate_removed.connect(func(_id, _pos): _apply_fate_board_bonuses())
	# Wired here, not in either component's own _ready() - Godot calls a
	# child's _ready() before its parent's, so PlayerAbilityCast._ready()
	# connecting to cast_time_handler (a Player @onready var, another
	# sibling child) would hit it before Player._ready() has resolved it.
	# Player._ready() runs last, after every child's own _ready(), so
	# both components are guaranteed live here.
	cast_time_handler.cast_completed.connect(ability_cast._on_cast_time_completed)
	_apply_saved_loadout()
	_apply_saved_experience()
	_apply_saved_fate_board()
	_on_equipment_changed()  # applies stat bonuses + visuals for whatever _apply_saved_loadout() just equipped
	_apply_fate_board_bonuses()  # re-derives StatSheet's Slate fields from whatever _apply_saved_fate_board() just restored (empty on a fresh character)

## Fires on every equip()/unequip(), not just at spawn - also covers a
## shield/weapon equipped into a previously-empty slot.
func _on_equipment_changed() -> void:
	stat_sheet.set_equipment_bonus(equipment.compute_stat_bonuses())
	stat_sheet.set_equipment_resistance(equipment.compute_resistance_bonuses())
	stat_sheet.apply_equipment_affixes(equipment.get_all_equipped_items())
	# Patch v3.7 Section 1: Conduit spell power floor, checked on the
	# primary weapon only (an offhand-slot Conduit doesn't contribute -
	# user direction, keeps this simple rather than summing both slots).
	var primary := equipment.primary_weapon
	stat_sheet.set_conduit_spell_power(primary.get_spell_power() if primary and primary.is_conduit else 0.0)
	_apply_derived_stats()
	_update_shield_mesh()
	_update_active_weapon_visual()
	var active := get_active_weapon()
	if active != _last_active_weapon:
		_last_active_weapon = active
		EventBus.weapon_swapped.emit(self)

## Fires on every FateBoard.place_slate()/remove_slate() (EventBus.
## slate_placed/slate_removed, both already emitted there - this is the
## only listener). Section 10's Slate stat contribution, Mastery, and the
## Mastery-amplified Chain Bonus System all flow through here into
## StatSheet, then _apply_derived_stats() re-runs so Vitality/Intellect
## gained from a placed Slate immediately affects max Health/Mana too,
## same as an equipment change already does.
func _apply_fate_board_bonuses() -> void:
	if fate_board == null:
		return
	stat_sheet.set_slate_bonus(fate_board.compute_stat_bonuses())
	stat_sheet.mastery_by_tag = fate_board.compute_mastery_bonuses()
	var chains := ChainCalculator.compute_chains(fate_board)
	stat_sheet.set_chain_bonus_by_tag(ChainCalculator.amplify_by_mastery(chains, stat_sheet))
	_apply_derived_stats()

## Section 12 per-point values. Instinct's Stamina pool is still deferred -
## no Stamina/dodge-roll mechanic exists.
const VITALITY_LIFE_PER_POINT := 2.0
const VITALITY_LIFE_REGEN_PER_POINT := 0.1
const VITALITY_RESILIENCE_PER_POINT := 3.0
const INTELLECT_MANA_PER_POINT := 2.0
const INTELLECT_MANA_REGEN_PER_POINT := 0.1

## Section 12: "Resilience / DoT mitigation" - reduces StatusEffectComponent's
## Ignite ticks (DamageCalculator.dot_mitigation()). Not persisted/exported;
## always re-derived in _apply_derived_stats() like every other stat here.
var resilience: float = 0.0

## User direction (clarifying/overriding Patch v3.2's own "gear rolls and
## Enigma investment" wording): Ward's BASE size comes from armor only -
## flat_ward gear affixes, full stop, no baseline pool (an earlier pass
## invented a flat 300 + 60/Enigma-point curve, which meant a fresh,
## ungeared character started with 900 Ward out of nowhere - the bug
## report this fixes). Enigma then applies as an INCREASED% multiplier on
## top of that base, not its own flat contribution - zero armor still
## means zero Ward regardless of Enigma, since a multiplier on 0 is 0.
## No doc-exact rate exists for this specific multiplier (the patch's
## only exact Enigma/Ward number is the restoration-rate one below, a
## different mechanic) - invented, flagged.
const WARD_INCREASED_PER_ENIGMA := 0.02
## Patch v3.2: "Enigma scales it globally (+1% per Enigma point)" - Ward
## Restoration is explicitly a unified stat covering every restoration
## source (passive regen, on-kill, Parry, etc. - see WardComponent.restore()).
const WARD_RESTORATION_PER_ENIGMA := 0.01

func _apply_derived_stats() -> void:
	var vitality := stat_sheet.get_stat(Constants.Stat.VITALITY)
	var intellect := stat_sheet.get_stat(Constants.Stat.INTELLECT)
	var enigma := stat_sheet.get_stat(Constants.Stat.ENIGMA)
	health.set_max_health(_base_max_health + vitality * VITALITY_LIFE_PER_POINT)
	health.regen_per_second = vitality * VITALITY_LIFE_REGEN_PER_POINT
	resilience = vitality * VITALITY_RESILIENCE_PER_POINT
	mana.max_mana = _base_max_mana + intellect * INTELLECT_MANA_PER_POINT
	mana.regen_per_second = _base_mana_regen + intellect * INTELLECT_MANA_REGEN_PER_POINT
	ward.set_max_ward(equipment.compute_ward_bonus() * (1.0 + enigma * WARD_INCREASED_PER_ENIGMA))
	ward.restoration_multiplier = 1.0 + enigma * WARD_RESTORATION_PER_ENIGMA

func get_dot_mitigation() -> float:
	return DamageCalculator.dot_mitigation(resilience)

func _apply_saved_experience() -> void:
	experience.level = GameState.player_level
	experience.xp = GameState.player_xp
	experience.leveled_up.connect(_on_leveled_up)
	experience.xp_changed.connect(_on_xp_changed)
	# Keeps Fate Board Aether budget in sync with whatever level a save
	# restored at - independent of _apply_saved_fate_board()'s own restore
	# order, see place_slate()'s bypass_budget comment for why that matters.
	fate_board.aether_capacity = FateBoard.capacity_for_level(GameState.player_level)

## Section 12: leveling grants no stat points (gear-only), but user
## request (2026-08-30) gives leveling a real Fate Board effect: "gain 2
## points of Aether... every time you level up."
func _on_leveled_up(new_level: int) -> void:
	GameState.player_level = new_level
	fate_board.aether_capacity = FateBoard.capacity_for_level(new_level)
	EventBus.aether_budget_changed.emit(fate_board.aether_used, fate_board.aether_capacity)
	EventBus.player_leveled_up.emit(new_level)

func _on_xp_changed(current: float, _needed: float) -> void:
	GameState.player_xp = current

func _on_died() -> void:
	EventBus.player_died.emit()

## Re-applies GameState's equipment/ability loadout - Player is a fresh
## instance every scene load, so this runs every time, not just at boot.
func _apply_saved_loadout() -> void:
	for ref in GameState.equipment_refs:
		var item: Item = load(ref) if ref is String and ref != "" else (ItemSerializer.from_dict(ref) if ref is Dictionary else null)
		if item:
			equipment.equip(item, true)
	# Dual weapon sets (2026-08-31) - restored explicitly by index rather
	# than through the generic loop above, see EquipmentComponent.
	# get_weapon_set_refs()'s own header for why.
	for set_index in range(GameState.weapon_set_refs.size()):
		for ref in GameState.weapon_set_refs[set_index]:
			var item: Item = load(ref) if ref is String and ref != "" else (ItemSerializer.from_dict(ref) if ref is Dictionary else null)
			if item:
				equipment.equip(item, true, set_index)
	equipment.active_weapon_set = GameState.active_weapon_set
	for i in range(GameState.ability_loadout_paths.size()):
		var path: String = GameState.ability_loadout_paths[i]
		if path != "":
			var ability: Ability = load(path)
			if ability:
				ability_loadout.equip(ability, i)
	_apply_saved_ability_ranks()

## Re-places every layout entry GameState.fate_board_placements holds -
## Player is a fresh instance every scene load same as _apply_saved_
## loadout() above, and fate_board was just recreated empty a few lines up
## in _ready(). place_slate() re-syncs GameState.fate_board_placements as
## each entry goes back down, which just reproduces the same array it's
## reading from here - harmless. A restore that legitimately can't
## succeed (e.g. hand-edited/corrupted save data implying overlapping
## cells) silently drops that one placement rather than failing the
## whole restore - place_slate() already no-ops safely on failure.
func _apply_saved_fate_board() -> void:
	for entry in GameState.fate_board_placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slate := _resolve_slate_ref(entry.get("slate_ref"))
		if slate == null:
			continue
		var origin_raw = entry.get("origin", [0, 0])
		var origin := Vector2i(int(origin_raw[0]), int(origin_raw[1])) if origin_raw is Array and origin_raw.size() == 2 else Vector2i.ZERO
		fate_board.place_slate(
			slate, origin, int(entry.get("rotation_steps", 0)), bool(entry.get("flipped", false)),
			str(entry.get("designated_ability_id", "")), true
		)

## slate_ref is a resource_path String (hand-authored palette Slate) or an
## index (int, or float once round-tripped through JSON) into
## GameState.owned_slates (a rolled, single-use drop) - see GameState.
## sync_fate_board()'s own doc comment for why owned Slates go by index
## rather than full re-serialization.
func _resolve_slate_ref(ref) -> Slate:
	if ref is String and ref != "":
		return load(ref) as Slate
	if ref is int or ref is float:
		var idx := int(ref)
		if idx >= 0 and idx < GameState.owned_slates.size():
			return GameState.owned_slates[idx]
	return null

func _apply_saved_ability_ranks() -> void:
	if GameState.ability_ranks.is_empty():
		return
	var dir_path := "res://data/abilities/instances/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(dir_path + file_name) as Ability
			if ability and GameState.ability_ranks.has(ability.ability_id):
				ability.rank = GameState.ability_ranks[ability.ability_id]
		file_name = dir.get_next()
	dir.list_dir_end()

## A weapon with a real model (WEAPON_MODEL_SCENES) shows that model
## instanced under weapon_mesh, in its own baked materials - untinted,
## unlike the placeholder blade below, since flattening a model that
## already has real wood/metal materials to one flat color would look
## worse than the placeholder it's replacing. Anything unmapped (no
## model for that weapon_type yet) falls back to exactly the old
## tinted-box placeholder.
func _update_weapon_model() -> void:
	if _weapon_model:
		_weapon_model.queue_free()
		_weapon_model = null
	var weapon := equipment.primary_weapon
	var scene: PackedScene = WEAPON_MODEL_SCENES.get(weapon.weapon_type) if weapon else null
	if scene:
		_weapon_model = scene.instantiate()
		weapon_mesh.add_child(_weapon_model)
		weapon_mesh.mesh = null
		weapon_mesh.material_override = null
		# Scaled down and tucked toward the bottom-right, closer to camera -
		# the pack's own FBX->Godot axis correction already leaves the
		# blade pointing roughly forward at rest (confirmed by screenshot,
		# not assumed), it just needed to be smaller and positioned like a
		# held weapon instead of life-size and centered. Approximate,
		# tuned by eye via screenshot, not exact hand-placement math.
		_weapon_model.scale = Vector3.ONE * 0.45
		_weapon_model.rotation_degrees = Vector3(15.0, -20.0, 10.0)
		_weapon_model.position = Vector3(0.4, -0.4, 0.35)
	elif weapon:
		weapon_mesh.mesh = _placeholder_blade_mesh
		weapon_mesh.material_override = _unshaded_material(Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color.WHITE))

func _update_active_weapon_visual() -> void:
	_update_weapon_model()
	if weapon_mesh:
		weapon_mesh.visible = equipment.primary_weapon != null
	# User request (2026-08-30): "Two handed weapons should clearly need
	# two hands." primary_weapon rather than get_active_weapon() - a
	# two-handed ranged weapon isn't a concept that exists (Service
	# Pistol.is_two_handed is false), but reading straight off the equipped
	# weapon's own flag rather than re-deriving "is this melee" keeps this
	# correct if that ever changes.
	if arm_rig:
		var weapon := equipment.primary_weapon
		arm_rig.set_two_handed(weapon != null and weapon.is_two_handed)

func _update_shield_mesh() -> void:
	if shield_mesh == null:
		return
	var offhand_item := equipment.offhand
	if offhand_item == null:
		shield_mesh.visible = false
		return
	shield_mesh.visible = true
	shield_mesh.material_override = _unshaded_material(Constants.ITEM_RARITY_COLOR.get(offhand_item.rarity, Color.WHITE))

func _unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

## Melee vs ranged attack follows the active Weapon's is_ranged, not
## which slot it's in - see the dispatch in _physics_process(). Ranged
## weapons equip into PRIMARY_WEAPON same as melee ones (see
## worn_pistol.tres), so "active weapon" is just whatever's equipped
## there - no manual weapon-slot toggle needed.
func get_active_weapon() -> Weapon:
	return equipment.primary_weapon

## Patch v3.2 "Order of Operations - All Damage": mitigation (Armor for
## Physical, Resistance for Elemental/Esoteric - Evasion isn't modeled,
## no dodge/deflection mechanic exists in this project) applies first,
## then Ward absorbs whatever's left regardless of type (the old Esoteric-
## only restriction is gone), then Ward overflow hits Health.
func take_damage(amount: float, damage_type: Constants.DamageType, source: Node = null) -> void:
	if parry_handler and parry_handler.is_invulnerable:
		return
	var mitigated := amount * status_effects.get_damage_taken_multiplier(damage_type)
	var category = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type)
	if category == Constants.DamageCategory.PHYSICAL:
		var armor := equipment.get_total_armor() if equipment else 0.0
		mitigated *= (1.0 - DamageCalculator.physical_mitigation(armor, mitigated))
	elif category == Constants.DamageCategory.ELEMENTAL or category == Constants.DamageCategory.ESOTERIC:
		var resistance := stat_sheet.get_resistance(damage_type) - status_effects.get_resistance_shred()
		mitigated *= (1.0 - DamageCalculator.resistance_mitigation(resistance))
	var overflow := ward.absorb(mitigated)
	health.apply_damage(overflow)
	EventBus.damage_dealt.emit(source, self, mitigated, damage_type, false, false)
	# Patch v3.7 Section 2: taking damage interrupts a CAST_TIME windup.
	# is_casting() is only ever true mid-CAST_TIME (INSTANT/CHANNELED
	# both complete synchronously and never set it), so this can't
	# accidentally interrupt either of those - no extra type check needed.
	if cast_time_handler.is_casting():
		cast_time_handler.interrupt()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var clamped_x: float = clamp(head.rotation.x, deg_to_rad(-max_look_up_deg), deg_to_rad(max_look_up_deg))
		head.rotation.x = clamped_x

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		var gravity_scale := FALL_GRAVITY_MULTIPLIER if velocity.y < 0.0 else 1.0
		velocity.y -= _gravity * gravity_scale * delta
		_is_sliding = false
	# Electrocute/Freeze ("disrupts target action" / "full immobilization") -
	# movement itself is already zeroed via _effective_speed()'s status
	# multiplier below; this additionally blocks jump/parry/attack input.
	var stunned := status_effects.is_stunned()
	if Input.is_action_just_pressed("jump") and is_on_floor() and not stunned:
		velocity.y = jump_velocity
		_is_sliding = false

	var crouch_held := Input.is_action_pressed("crouch")
	var sprinting := Input.is_action_pressed("sprint")
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining -= delta
	# just_pressed fires once on the initial keydown regardless of how long
	# Shift stays held afterward - a tap dashes, continuing to hold still
	# sprints normally on top of it (see the const block's own comment).
	if Input.is_action_just_pressed("sprint") and not stunned and not _is_dashing and not _is_sliding \
			and _dash_cooldown_remaining <= 0.0 and move_dir.length() > 0.1:
		_start_dash(move_dir)

	if Input.is_action_just_pressed("crouch") and is_on_floor() and not _is_sliding and not _is_dashing and sprinting and move_dir.length() > 0.1:
		_start_slide(move_dir)

	if _is_dashing:
		_dash_timer -= delta
		_dash_speed_current = max(_dash_speed_current - DASH_DECELERATION * delta, 0.0)
		velocity.x = _dash_direction.x * _dash_speed_current
		velocity.z = _dash_direction.z * _dash_speed_current
		if _dash_timer <= 0.0:
			_is_dashing = false
	elif _is_sliding:
		_slide_timer -= delta
		_slide_speed_current = max(_slide_speed_current - SLIDE_DECELERATION * delta, _effective_speed(crouch_speed))
		velocity.x = _slide_direction.x * _slide_speed_current
		velocity.z = _slide_direction.z * _slide_speed_current
		_is_crouching = true
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide(crouch_held)
	else:
		_is_crouching = crouch_held
		var speed := _effective_speed(crouch_speed) if _is_crouching else _effective_speed(sprint_speed if sprinting else move_speed)
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed

	_update_crouch_visual(delta)
	move_and_slide()

	if stunned:
		return

	if Input.is_action_just_pressed("parry"):
		parry_handler.start_parry_window()

	if Input.is_action_just_pressed("throw_secondary"):
		use_throwable()

	_handle_attack_input(delta)
	_handle_weapon_swap_input(delta)

## Tap X (release before WEAPON_SWAP_HOLD_THRESHOLD) swaps the active
## weapon set; holding past it toggles the stance page instead and the
## eventual release doesn't ALSO swap sets (the "not _x_triggered_hold"
## guard) - same tap-vs-hold split PlayerAbilityCast/melee-attack hold
## detection already use elsewhere in this project.
func _handle_weapon_swap_input(delta: float) -> void:
	if Input.is_action_pressed("weapon_swap"):
		_x_held_time += delta
		if _x_held_time >= WEAPON_SWAP_HOLD_THRESHOLD and not _x_triggered_hold:
			_x_triggered_hold = true
			weapon_stance.toggle_stance_page()
	elif _x_held_time > 0.0:
		if not _x_triggered_hold:
			equipment.toggle_weapon_set()
			GameState.sync_weapon_sets(equipment)
		_x_held_time = 0.0
		_x_triggered_hold = false

func _handle_attack_input(delta: float) -> void:
	var active_weapon := get_active_weapon()
	var is_melee := active_weapon != null and not active_weapon.is_ranged

	# Implementation Brief v3.3 Section 2: light jab (release <0.6s hold)
	# vs standard thrust (release at >=0.6s) - only tracked for melee
	# weapons outside stance. Charged thrust (stance active) and ranged
	# fire below are still edge-triggered on press, exactly as before this
	# brief - holding LMB in stance or with a ranged weapon out never
	# accumulated hold time to begin with, so resetting here on every
	# frame that doesn't apply is a no-op for those cases, not a behavior
	# change.
	if is_melee and not weapon_stance.is_active:
		if Input.is_action_pressed("attack"):
			_lmb_held_time += delta
			_lmb_was_held = true
		elif _lmb_was_held:
			_lmb_was_held = false
			if _lmb_held_time >= STANDARD_THRUST_HOLD_THRESHOLD:
				melee_attack.try_standard_thrust()
			else:
				melee_attack.try_light_jab()
			_lmb_held_time = 0.0
	else:
		_lmb_held_time = 0.0
		_lmb_was_held = false

	if Input.is_action_just_pressed("attack"):
		if active_weapon and active_weapon.is_ranged:
			ranged_attack.try_attack(weapon_stance.is_active)
		elif weapon_stance.is_active:
			melee_attack.try_charged_thrust()

func get_move_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_stat(Constants.Stat.INSTINCT) * INSTINCT_MOVE_SPEED_PCT

func _effective_speed(base: float) -> float:
	return base * get_move_speed_multiplier() * status_effects.get_move_speed_multiplier() \
		* melee_attack.get_move_speed_multiplier() * ability_cast.get_move_speed_multiplier() \
		* weapon_stance.get_move_speed_multiplier()

func get_action_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_stat(Constants.Stat.INSTINCT) * INSTINCT_ACTION_SPEED_PCT

func _start_dash(move_dir: Vector3) -> void:
	_is_dashing = true
	_dash_timer = DASH_DURATION
	_dash_direction = move_dir
	_dash_speed_current = DASH_SPEED
	_dash_cooldown_remaining = DASH_COOLDOWN

## User request (2026-08-30): Dagger's stance special ("a rapier might
## dash and thrust in one direction") - called from
## PlayerMeleeAttack.try_special_attack(). Reuses the exact same dash
## state/cooldown as the Shift-tap dash rather than a separate free dash
## resource, so this and the movement dash share one budget. Returns
## whether the dash actually fired - the thrust itself still lands even
## when this returns false (dash on cooldown), just without the lunge.
func try_special_dash(direction: Vector3) -> bool:
	if status_effects.is_stunned() or _is_dashing or _is_sliding or _dash_cooldown_remaining > 0.0:
		return false
	_start_dash(direction)
	return true

func _start_slide(move_dir: Vector3) -> void:
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	_slide_direction = move_dir
	_slide_speed_current = max(_effective_speed(sprint_speed), SLIDE_SPEED)

func _end_slide(keep_crouching: bool) -> void:
	_is_sliding = false
	_is_crouching = keep_crouching

func _update_crouch_visual(delta: float) -> void:
	var crouched := _is_crouching or _is_sliding
	var target_height := CROUCH_CAPSULE_HEIGHT if crouched else STANDING_CAPSULE_HEIGHT
	var target_head_y := CROUCH_HEAD_Y if crouched else STANDING_HEAD_Y
	var shape := collision_shape.shape as CapsuleShape3D
	if shape:
		shape.height = move_toward(shape.height, target_height, CROUCH_TRANSITION_SPEED * delta)
		collision_shape.position.y = shape.height / 2.0
	head.position.y = move_toward(head.position.y, target_head_y, CROUCH_TRANSITION_SPEED * delta)
