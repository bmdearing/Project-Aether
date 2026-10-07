extends CharacterBody3D
class_name Player
## First-person controller. Camera lives in Head; WeaponSocket under the
## camera hosts ArmRig, the viewmodel that builds and animates the held
## weapon and off-hand item (PlayerArmRig, WeaponModelLibrary).

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
## PlayerArmRig moves WeaponMesh into its grip during its own _ready()
## (a child, so it runs before this @onready block resolves).
@onready var arm_rig: PlayerArmRig = $Head/Camera3D/WeaponSocket/ArmRig
@onready var weapon_mesh: MeshInstance3D = $Head/Camera3D/WeaponSocket/ArmRig/Sway/Main/Grip/WeaponMesh
@onready var attack_hitbox: Area3D = $Head/Camera3D/WeaponSocket/ArmRig/Sway/Main/Grip/WeaponMesh/AttackHitbox
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
var shield_block: ShieldBlock
var stance_attack: StanceAttack
var stance_defense: StanceDefense
var caster_stance: CasterStance
## An LMB press that started a stance charge; its release must not also jab.
var _lmb_owned_by_stance: bool = false
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

## Ground/air acceleration instead of instant velocity: quick to start,
## a short skid to stop, and air momentum that's steerable but not reversible.
const GROUND_ACCELERATION := 70.0
const GROUND_DECELERATION := 50.0
const AIR_ACCELERATION := 18.0
const AIR_DECELERATION := 4.0
## Late jumps off ledges and early presses before landing still jump.
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.12
const IMPULSE_FRICTION := 12.0

var _move_velocity: Vector3 = Vector3.ZERO
var _lunge_velocity: Vector3 = Vector3.ZERO
var _lunge_timer: float = 0.0
var _impulse: Vector3 = Vector3.ZERO
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

## Covers exactly `distance` along `direction` over `duration` (stance
## lunges). Walls and enemies stop it through move_and_slide().
func lunge(direction: Vector3, distance: float, duration: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	_lunge_velocity = flat * distance / maxf(duration, 0.01)
	_lunge_timer = duration

func is_lunging() -> bool:
	return _lunge_timer > 0.0

## Short horizontal shove on top of normal movement (melee lunge).
func apply_impulse(impulse: Vector3) -> void:
	_impulse += Vector3(impulse.x, 0.0, impulse.z)

## Move Speed is gear-affix-only (StatSheet.misc_bonus). Attack Speed is
## gear + Agility (v4.8) - see get_action_speed_multiplier().

func _ready() -> void:
	if stat_sheet == null:
		# Fallback only - Player.tscn assigns player_baseline.tres normally.
		stat_sheet = StatSheet.new()
		stat_sheet.strength = 10.0
		stat_sheet.agility = 10.0
		stat_sheet.intellect = 10.0
	fate_board = FateBoard.new()
	shield_block = ShieldBlock.new()
	shield_block.name = "ShieldBlock"
	add_child(shield_block)
	stance_attack = StanceAttack.new()
	stance_attack.name = "StanceAttack"
	add_child(stance_attack)
	stance_defense = StanceDefense.new()
	stance_defense.name = "StanceDefense"
	add_child(stance_defense)
	caster_stance = CasterStance.new()
	caster_stance.name = "CasterStance"
	add_child(caster_stance)
	GameState.player_stat_sheet = stat_sheet
	GameState.fate_board = fate_board
	GameState.player_equipment = equipment
	_apply_settings()
	EventBus.settings_changed.connect(_apply_settings)
	status_effects.effect_applied.connect(_on_status_effect_applied)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	health.died.connect(_on_died)
	# Captured before any gear bonus applies - the .tscn's static values
	# are the class baseline Strength/Intellect add on top of.
	_base_max_health = health.max_health
	_base_max_mana = mana.max_mana
	_base_mana_regen = mana.regen_per_second
	if collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	equipment.equipment_changed.connect(_on_equipment_changed)
	EventBus.slate_placed.connect(func(_id, _pos): _apply_fate_board_bonuses())
	EventBus.slate_removed.connect(func(_id, _pos): _apply_fate_board_bonuses())
	EventBus.item_stats_changed.connect(_on_item_stats_changed)
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
	stat_sheet.set_misc_bonus(equipment.compute_misc_bonuses())
	stat_sheet.apply_equipment_affixes(equipment.get_all_equipped_items())
	# Primary-slot Conduit only; an offhand Conduit doesn't contribute.
	var primary := equipment.primary_weapon
	stat_sheet.conduit_spell_damage_bonus = primary.get_conduit_spell_damage_bonus() if primary else 0.0
	_apply_derived_stats()
	if arm_rig:
		arm_rig.set_loadout(equipment.primary_weapon, equipment.offhand)
	var active := get_active_weapon()
	if active != _last_active_weapon:
		_last_active_weapon = active
		EventBus.weapon_swapped.emit(self)

## Fires on every FateBoard.place_slate()/remove_slate() (EventBus.
## slate_placed/slate_removed, both already emitted there - this is the
## only listener). Section 10's Slate stat contribution and the Chain Bonus
## System flow through here into StatSheet, then _apply_derived_stats()
## re-runs so Strength/Intellect gained from a placed Slate immediately
## affects max Life/Mana too, same as an equipment change already does.
func _apply_fate_board_bonuses() -> void:
	if fate_board == null:
		return
	var chains := ChainCalculator.compute_chains(fate_board)
	stat_sheet.set_slate_bonus(ChainCalculator.slate_stat_bonuses(fate_board, chains))
	stat_sheet.set_chain_bonus_by_tag(ChainCalculator.bonus_by_tag(chains))
	_apply_derived_stats()

## Section 12: "Resilience / DoT mitigation" - reduces StatusEffectComponent's
## Ignite ticks (DamageCalculator.dot_mitigation()). Not persisted/exported;
## always re-derived in _apply_derived_stats() like every other stat here.
## Patch v3.8: gear-affix-only now (flat_resilience) - Vitality, its old
## source, no longer exists.
var resilience: float = 0.0

## Patch v3.8: Ward's BASE size still comes from armor only (flat_ward
## gear affixes, no baseline pool - see the ward bug fix this comment
## used to describe). Intellect applies an INCREASED% multiplier on it
## (StatSheet.get_ward_increased_from_stats(), 1%/point) - zero armor
## still means zero Ward, a multiplier on 0 is 0. Ward Restoration Rate
## is a "removed expression" (not stat-derived) - restoration_multiplier
## resets to a flat 1.0 until/unless a gear affix drives it.
func _apply_derived_stats() -> void:
	# Life: Strength's +4/point + gear-affix max_life/life_regen.
	health.set_max_health(_base_max_health + stat_sheet.get_max_life_bonus() + stat_sheet.get_misc_bonus("max_life"))
	health.regen_per_second = stat_sheet.get_misc_bonus("life_regen")
	resilience = stat_sheet.get_misc_bonus("flat_resilience")

	# Mana: Intellect's +3/point + gear-affix max_mana/mana_regen.
	mana.max_mana = _base_max_mana + stat_sheet.get_mana_from_stats() + stat_sheet.get_misc_bonus("max_mana")
	mana.regen_per_second = _base_mana_regen + stat_sheet.get_misc_bonus("mana_regen")

	# Evasion (gear x Agility's increased%) - refreshed here for display;
	# take_damage() reads it live.
	stat_sheet.stat_evasion_bonus = stat_sheet.get_total_evasion(equipment)
	# Patch v4.0: gear's own "increased Critical Strike Chance" (crit_
	# chance_increased) combines into the same multiplicative bracket as
	# Agility's contribution, not a separate additive bonus - see
	# DamageCalculator.get_crit_chance()'s 2026-09-07 fix.
	stat_sheet.finesse_crit_bonus = stat_sheet.get_crit_chance_from_stats() + stat_sheet.get_gear_crit_chance_bonus()

	ward.set_max_ward(equipment.compute_ward_bonus() * (1.0 + stat_sheet.get_ward_increased_from_stats()))
	ward.restoration_multiplier = 1.0  # no longer stat-driven - see header
	# Patch v4.0 Faster Ward Delay - WardComponent has no StatSheet
	# reference of its own, so this is pushed in the same way every other
	# derived value on this component already is.
	ward.regen_delay_reduction = stat_sheet.get_ward_delay_reduction()

	# Cast Speed: gear-affix-only now too, feeds the same StatSheet pool
	# Patch v3.7's CastTimeHandler already reads.
	stat_sheet.cast_speed_bonus = stat_sheet.get_misc_bonus("cast_speed")
	# Patch v4.0 "Increased Cooldown Efficiency" - direct assignment, not
	# apply_cast_speed_to_cooldown_conversion()'s += (that Slate-side
	# conversion path has no caller anywhere in the project - dead code,
	# out of scope for this patch - so there's nothing else contributing
	# to this field to preserve).
	stat_sheet.cooldown_recovery_rate = stat_sheet.get_misc_bonus("cooldown_recovery_rate")

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
	stat_sheet.level_bonus = GameState.get_level_stat_bonus()

## Leveling grants +2 Aether (user request, 2026-08-30) and, since v4.7,
## +0.6 to each stat (GameState.get_level_stat_bonus()).
func _on_leveled_up(new_level: int) -> void:
	GameState.player_level = new_level
	stat_sheet.level_bonus = GameState.get_level_stat_bonus()
	_apply_derived_stats()
	fate_board.aether_capacity = FateBoard.capacity_for_level(new_level)
	EventBus.aether_budget_changed.emit(fate_board.aether_used, fate_board.aether_capacity)
	EventBus.player_leveled_up.emit(new_level)

func _on_xp_changed(current: float, _needed: float) -> void:
	GameState.player_xp = current

## Only a stun breaks a cast wind-up; plain damage doesn't.
func _on_status_effect_applied(_effect_id: String) -> void:
	if status_effects.is_stunned() and cast_time_handler.is_casting():
		cast_time_handler.interrupt()

func _apply_settings() -> void:
	mouse_sensitivity = GameState.mouse_sensitivity
	camera.fov = GameState.field_of_view

func _on_died() -> void:
	EventBus.player_died.emit()

## Re-applies GameState's equipment/ability loadout - Player is a fresh
## instance every scene load, so this runs every time, not just at boot.
func _apply_saved_loadout() -> void:
	for ref in GameState.equipment_refs:
		var item := _resolve_equipment_ref(ref)
		if item:
			equipment.equip(item, true)
	# Dual weapon sets (2026-08-31) - restored explicitly by index rather
	# than through the generic loop above, see EquipmentComponent.
	# get_weapon_set_refs()'s own header for why.
	for set_index in range(GameState.weapon_set_refs.size()):
		for ref in GameState.weapon_set_refs[set_index]:
			var item := _resolve_equipment_ref(ref)
			if item:
				equipment.equip(item, true, set_index)
	equipment.active_weapon_set = GameState.active_weapon_set
	# Re-snapshot so refs from older saves pick up fields added since.
	GameState.sync_equipment(equipment)
	GameState.sync_weapon_sets(equipment)
	for i in range(GameState.ability_loadout_paths.size()):
		var path: String = GameState.ability_loadout_paths[i]
		if path != "":
			var ability: Ability = load(path)
			if ability:
				ability_loadout.equip(ability, i)
	_apply_saved_ability_levels()

## A rolled item's ref is a serialized snapshot; equipped items aren't in
## the inventory, so the restored copy is the only instance.
func _resolve_equipment_ref(ref) -> Item:
	if ref is String:
		return load(ref) if ref != "" else null
	if not (ref is Dictionary):
		return null
	return ItemSerializer.from_dict(ref)

## Crafting changed an item in place. If it's equipped, re-run the equip
## path so StatSheet picks up the new affixes, and re-snapshot the refs so
## the next scene load/save doesn't restore the pre-craft version.
func _on_item_stats_changed(item: Item) -> void:
	var equipped: Array = equipment.get_all_equipped_items()
	equipped.append_array(equipment.primary_weapons)
	equipped.append_array(equipment.offhands)
	if not equipped.has(item):
		return
	_on_equipment_changed()
	GameState.sync_equipment(equipment)
	GameState.sync_weapon_sets(equipment)

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

## slate_ref is a resource_path String (hand-authored Slate) or full
## SlateSerializer data (a rolled drop).
func _resolve_slate_ref(ref) -> Slate:
	if ref is String and ref != "":
		return load(ref) as Slate
	if ref is Dictionary:
		return SlateSerializer.from_dict(ref)
	return null

func _apply_saved_ability_levels() -> void:
	if GameState.ability_levels.is_empty():
		return
	var dir_path := "res://data/abilities/instances/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(dir_path + file_name) as Ability
			if ability and GameState.ability_levels.has(ability.ability_id):
				ability.level = clampi(int(GameState.ability_levels[ability.ability_id]), 1, Ability.MAX_LEVEL)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()


## Melee vs ranged attack follows the active Weapon's is_ranged, not
## which slot it's in - see the dispatch in _physics_process(). Ranged
## weapons equip into PRIMARY_WEAPON same as melee ones (see
## worn_pistol.tres), so "active weapon" is just whatever's equipped
## there - no manual weapon-slot toggle needed.
func get_active_weapon() -> Weapon:
	return equipment.primary_weapon

## What delivered a hit, for Evasion (Patch v4.4). ATTACK (melee swings and
## projectiles - the default, so callers that don't say are treated as
## attacks) can be Dodged and Deflected; SPELL can only be Deflected; DOT
## (ignite ticks) is neither - evasion is for hit events only. The brief's
## "source is Ability" test can't work: Ability is a Resource and `source`
## is a Node, so the caller says what it is instead.
enum HitKind { ATTACK, SPELL, DOT }

## Patch v3.2 "Order of Operations - All Damage": Evasion (Patch v4.4:
## Dodge, then Deflection - see DamageCalculator) rolls first, then
## mitigation (Armor for Physical, Resistance for Elemental/Esoteric) applies,
## then Ward absorbs whatever's left regardless of type (the old Esoteric-
## only restriction is gone), then Ward overflow hits Health.
## is_melee: an enemy weapon swing (EnemyMeleeAttack), for Guard.
func take_damage(amount: float, damage_type: Constants.DamageType, source: Node = null, hit_kind: HitKind = HitKind.ATTACK, is_melee: bool = false) -> void:
	if parry_handler and parry_handler.is_invulnerable:
		return
	if hit_kind != HitKind.DOT and shield_block.try_block(amount, source):
		return
	amount = stance_defense.absorb(amount, source, hit_kind, is_melee)
	if amount <= 0.0:
		return
	# Patch v4.4 Evasion: Dodge (attacks only) negates the hit entirely and
	# never interrupts a cast; Deflection (attacks and spells) reduces it.
	if hit_kind != HitKind.DOT:
		var evasion := stat_sheet.get_total_evasion(equipment)
		if evasion > 0.0:
			if hit_kind == HitKind.ATTACK and randf() < DamageCalculator.dodge_chance(evasion):
				EventBus.hit_dodged.emit(self)
				return
			if randf() < DamageCalculator.deflection_chance(evasion):
				amount *= 1.0 - DamageCalculator.deflection_mitigation(evasion)
				EventBus.hit_deflected.emit(self)
	# Patch v4.0 Defensive Mod Pool - % Physical Damage taken as Elemental
	# shifts BEFORE mitigation, per damage type, splitting one hit into
	# several smaller ones the rest of this function then processes
	# independently (each gets its own mitigation/Ward/Health treatment).
	var category = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type)
	if category == Constants.DamageCategory.PHYSICAL:
		var shifts: Array = stat_sheet.get_phys_damage_shift()
		if not shifts.is_empty():
			var remaining := amount
			for shift in shifts:
				var shifted_amount: float = amount * shift[0]
				remaining -= shifted_amount
				_take_damage_single(shifted_amount, shift[1], source)
			_take_damage_single(remaining, damage_type, source)
			return
	_take_damage_single(amount, damage_type, source)

func _take_damage_single(amount: float, damage_type: Constants.DamageType, source: Node = null) -> void:
	var mitigated := amount * status_effects.get_damage_taken_multiplier(damage_type)
	var category = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type)
	if category == Constants.DamageCategory.PHYSICAL:
		var armor := equipment.get_total_armor() if equipment else 0.0
		mitigated *= (1.0 - DamageCalculator.physical_mitigation(armor, mitigated))
		mitigated *= (1.0 - stat_sheet.get_reduced_damage_taken(Constants.DamageCategory.PHYSICAL))
	elif category == Constants.DamageCategory.ELEMENTAL or category == Constants.DamageCategory.ESOTERIC:
		var resistance := stat_sheet.get_resistance(damage_type) - status_effects.get_resistance_shred()
		mitigated *= (1.0 - DamageCalculator.resistance_mitigation(resistance))
		# Patch v4.0 "% of Armor applies to Elemental" - Elemental only,
		# per the doc's own Item Slots note (Body Armour/Helmet/Amulet,
		# same slots the doc scopes every Elemental-flavored defensive mod
		# to) - a portion of the player's real Armor value applied through
		# the SAME physical_mitigation curve, as bonus Elemental mitigation
		# on top of Resistance.
		if category == Constants.DamageCategory.ELEMENTAL:
			var armor_to_elemental_pct := stat_sheet.get_misc_bonus("armor_to_elemental") / 100.0
			if armor_to_elemental_pct > 0.0 and equipment:
				var bonus_armor := equipment.get_total_armor() * armor_to_elemental_pct
				mitigated *= (1.0 - DamageCalculator.physical_mitigation(bonus_armor, mitigated))
		mitigated *= (1.0 - stat_sheet.get_reduced_damage_taken(category))
	# Patch v4.0 "% of Damage from Mana before Life" - drains Mana for a
	# portion of the mitigated hit before Ward/Health ever see it.
	var mana_shield_pct := stat_sheet.get_damage_from_mana_percent()
	if mana_shield_pct > 0.0 and mana and mana.current_mana > 0.0:
		var mana_portion := mitigated * mana_shield_pct
		var actual_drain: float = min(mana_portion, mana.current_mana)
		mana.spend(actual_drain)
		mitigated -= actual_drain
	var overflow := ward.absorb(mitigated)
	health.apply_damage(overflow)
	EventBus.damage_dealt.emit(source, self, mitigated, damage_type, false, false)

const BLOCK_CHANCE_CAP := 0.75

## Patch v4.3. Rolls the equipped shield's block chance (plus any "of
## Steadying" bonus, hard-capped at 75%) against one incoming MELEE hit.
## Deliberately not inside take_damage(): that function is also the entry
## for spells, projectiles and DoT ticks, none of which may be blocked, and
## it has no way to tell them apart - the one melee call site
## (EnemyMeleeAttack._resolve_hit()) asks this instead.
func try_block_melee_hit() -> bool:
	var shield := equipment.offhand as Shield if equipment else null
	if shield == null or shield_block.is_raised:
		return false  # a raised shield blocks (or doesn't) in take_damage()
	var chance: float = min(shield.block_chance + stat_sheet.get_block_chance_bonus(), BLOCK_CHANCE_CAP)
	if randf() < chance:
		EventBus.hit_blocked.emit(self)
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var clamped_x: float = clamp(head.rotation.x, deg_to_rad(-max_look_up_deg), deg_to_rad(max_look_up_deg))
		head.rotation.x = clamped_x

## Non-pausing menus (the inventory) show the cursor; combat input is
## ignored while they do, movement isn't.
## Headless runs (tests) can't capture the mouse, so they never count as blocked.
func is_input_blocked() -> bool:
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless"

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		var gravity_scale := FALL_GRAVITY_MULTIPLIER if velocity.y < 0.0 else 1.0
		velocity.y -= _gravity * gravity_scale * delta
		_is_sliding = false
	# Electrocute/Freeze ("disrupts target action" / "full immobilization") -
	# movement itself is already zeroed via _effective_speed()'s status
	# multiplier below; this additionally blocks jump/parry/attack input.
	var stunned := status_effects.is_stunned()
	_coyote_timer = COYOTE_TIME if is_on_floor() else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = JUMP_BUFFER_TIME if Input.is_action_just_pressed("jump") else maxf(_jump_buffer_timer - delta, 0.0)
	var rooted := stance_defense.is_rooted() or (stance_attack.is_charging and stance_attack.get_move_speed_multiplier() <= 0.0)
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not stunned and not rooted:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
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
	if Input.is_action_just_pressed("sprint") and not stunned and not rooted and not _is_dashing and not _is_sliding \
			and _dash_cooldown_remaining <= 0.0 and move_dir.length() > 0.1:
		_start_dash(move_dir)

	if Input.is_action_just_pressed("crouch") and is_on_floor() and not rooted and not _is_sliding and not _is_dashing and sprinting and move_dir.length() > 0.1:
		_start_slide(move_dir)

	if _lunge_timer > 0.0:
		var share := minf(_lunge_timer / delta, 1.0)  # last frame covers only what's left
		_lunge_timer -= delta
		velocity.x = _lunge_velocity.x * share
		velocity.z = _lunge_velocity.z * share
		_move_velocity = _lunge_velocity * 0.15
	elif _is_dashing:
		_dash_timer -= delta
		_dash_speed_current = max(_dash_speed_current - DASH_DECELERATION * delta, 0.0)
		velocity.x = _dash_direction.x * _dash_speed_current
		velocity.z = _dash_direction.z * _dash_speed_current
		_move_velocity = Vector3(velocity.x, 0.0, velocity.z)
		if _dash_timer <= 0.0:
			_is_dashing = false
	elif _is_sliding:
		_slide_timer -= delta
		_slide_speed_current = max(_slide_speed_current - SLIDE_DECELERATION * delta, _effective_speed(crouch_speed))
		velocity.x = _slide_direction.x * _slide_speed_current
		velocity.z = _slide_direction.z * _slide_speed_current
		_is_crouching = true
		_move_velocity = Vector3(velocity.x, 0.0, velocity.z)
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide(crouch_held)
	else:
		_is_crouching = crouch_held
		var speed := _effective_speed(crouch_speed) if _is_crouching else _effective_speed(sprint_speed if sprinting else move_speed)
		var target := move_dir * speed
		var rate: float
		if is_on_floor():
			rate = GROUND_ACCELERATION if move_dir != Vector3.ZERO else GROUND_DECELERATION
		else:
			rate = AIR_ACCELERATION if move_dir != Vector3.ZERO else AIR_DECELERATION
		_move_velocity = _move_velocity.move_toward(target, rate * delta)
		velocity.x = _move_velocity.x + _impulse.x
		velocity.z = _move_velocity.z + _impulse.z
	_impulse = _impulse.move_toward(Vector3.ZERO, IMPULSE_FRICTION * delta)

	_update_crouch_visual(delta)
	move_and_slide()

	if stunned or is_input_blocked():
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
	if shield_block.is_raised:
		_lmb_held_time = 0.0
		_lmb_was_held = false
		return
	var active_weapon := get_active_weapon()
	var is_wand := active_weapon != null and active_weapon.weapon_type == "Wand"
	var is_melee := active_weapon != null and not active_weapon.is_ranged and not is_wand

	# Implementation Brief v3.3 Section 2: light jab (release <0.6s hold)
	# vs standard thrust (release at >=0.6s) - only tracked for melee
	# weapons outside stance. Charged thrust (stance active) and ranged
	# fire below are still edge-triggered on press, exactly as before this
	# brief - holding LMB in stance or with a ranged weapon out never
	# accumulated hold time to begin with, so resetting here on every
	# frame that doesn't apply is a no-op for those cases, not a behavior
	# change.
	if _lmb_owned_by_stance:
		if not Input.is_action_pressed("attack"):
			_lmb_owned_by_stance = false
			stance_attack.release()
	elif is_melee and not weapon_stance.is_active:
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
		if caster_stance.try_stance_attack():
			pass
		elif is_wand:
			caster_stance.try_primary_attack()
		elif active_weapon and active_weapon.is_ranged:
			ranged_attack.try_attack(weapon_stance.is_active)
		elif weapon_stance.is_active:
			if stance_attack.begin_charge():
				_lmb_owned_by_stance = true
			elif not stance_attack.try_instant():
				melee_attack.try_charged_thrust()
	# Full-auto weapons fire every frame the button is held (they ignore
	# try_attack() above); every other fire mode returns immediately.
	if Input.is_action_pressed("attack") and active_weapon and active_weapon.is_ranged:
		ranged_attack.try_attack_held(weapon_stance.is_active)
	if Input.is_action_just_pressed("reload") and active_weapon and active_weapon.is_ranged:
		ranged_attack.try_manual_reload()

func get_move_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_misc_bonus("move_speed") / 100.0

func _effective_speed(base: float) -> float:
	return base * get_move_speed_multiplier() * status_effects.get_move_speed_multiplier() \
		* melee_attack.get_move_speed_multiplier() * ability_cast.get_move_speed_multiplier() \
		* weapon_stance.get_move_speed_multiplier() * shield_block.get_move_speed_multiplier() \
		* stance_attack.get_move_speed_multiplier() * stance_defense.get_move_speed_multiplier()

## Gear attack_speed + Agility's +1%/point, one increased% bracket.
func get_action_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_misc_bonus("attack_speed") / 100.0 + stat_sheet.get_attack_speed_from_stats()

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
