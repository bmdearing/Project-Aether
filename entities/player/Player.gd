extends CharacterBody3D
class_name Player
## First-person controller. Camera lives in Head; WeaponSocket under the
## camera hosts ArmRig, the viewmodel that builds and animates the held
## weapon and off-hand item (PlayerArmRig, WeaponModelLibrary).

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 3.0
## Reaches the same 2.5m apex as the old 7.0 under GRAVITY_MULTIPLIER.
@export var jump_velocity: float = 9.1
## Heavier than default gravity so jumps and knock-ups spend less time in the air.
const GRAVITY_MULTIPLIER := 1.7
## Extra gravity while falling (not rising), on top of GRAVITY_MULTIPLIER.
const FALL_GRAVITY_MULTIPLIER := 1.5
@export var mouse_sensitivity: float = 0.0035
@export var max_look_up_deg: float = 89.0
@export var stat_sheet: StatSheet
## Equipped Unique/Mythic mechanics (created in _ready()).
var unique_effects: UniqueEffects
var gear_effects: GearEffects
var loot_picker: LootPicker

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
@onready var cast_time_handler: CastTimeHandler = $CastTimeHandler

## Implementation Brief v3.3 Section 2: distinguishes a light-jab tap from
## a standard-thrust hold, tracked only while a melee weapon is active and
## WeaponStance isn't (charged thrust owns LMB press while stance is
## active, unchanged from before this brief - see _handle_attack_input()).
const STANDARD_THRUST_HOLD_THRESHOLD := 0.6
var _lmb_held_time: float = 0.0
var _lmb_was_held: bool = false

## "weapon_swap" (X): tap swaps weapon set, hold toggles the stance page.
const WEAPON_SWAP_HOLD_THRESHOLD := 0.25
var _x_held_time: float = 0.0
var _x_triggered_hold: bool = false
## Mouse wheel swaps weapon sets too, at most once per SCROLL_SWAP_COOLDOWN_MSEC.
const SCROLL_SWAP_COOLDOWN_MSEC := 300
var _last_scroll_swap_msec: int = -SCROLL_SWAP_COOLDOWN_MSEC
var fate_board: FateBoard

## The throwable stack selected to throw; null until something sets it.
var active_throwable: ThrowableStack = null

func use_throwable() -> void:
	if active_throwable == null or not active_throwable.can_use():
		return
	active_throwable.consume()
	EventBus.throwable_used.emit(active_throwable.throwable_type)

var _last_active_weapon: Weapon = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * GRAVITY_MULTIPLIER
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
## Downhill (ramps, staircases' hidden ramps) a slide speeds up instead of
## slowing: SLIDE_SLOPE_ACCELERATION x the slope's grade along the slide, up
## to SLIDE_MAX_SPEED, and it lasts as long as the ground keeps dropping.
## Uphill the same grade slows it. Tapping Crouch while moving downhill
## starts a slide without sprinting.
const SLIDE_SLOPE_ACCELERATION := 40.0
const SLIDE_MAX_SPEED := 20.0
## Floors flatter than this grade count as level.
const SLIDE_MIN_GRADE := 0.08

var _is_crouching: bool = false
var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _slide_speed_current: float = 0.0

## Dash: a tap of "sprint" (Shift) fires a decaying burst; holding it then
## sprints as normal. Works in the air and from standing.
const DASH_SPEED := 14.0
const DASH_DURATION := 0.2
const DASH_DECELERATION := 20.0
const DASH_COOLDOWN := 1.0
## Hits (not damage over time) pass through you for this long after a dash starts.
const DASH_IFRAMES := 0.15

## Visceral attacks (ripostes, backstabs): both locked for VISCERAL_LOCK,
## the player invulnerable throughout; the blow lands at VISCERAL_RIP_AT.
const VISCERAL_LOCK := 1.1
const VISCERAL_RIP_AT := 0.55
const VISCERAL_FOV_PUSH := 10.0
var _in_visceral: bool = false

var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_speed_current: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _iframes_remaining: float = 0.0

## Ground/air acceleration instead of instant velocity: quick to start,
## a short skid to stop, and air momentum that's steerable but not reversible.
const GROUND_ACCELERATION := 70.0
const GROUND_DECELERATION := 50.0
const AIR_ACCELERATION := 24.0
const AIR_DECELERATION := 10.0
## Late jumps off ledges and early presses before landing still jump.
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.12
const IMPULSE_FRICTION := 12.0

var _move_velocity: Vector3 = Vector3.ZERO
## Ledge catching and mantling; owns movement while it's busy.
var ledge_climb: LedgeClimb
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

## Thrown straight up `height` metres (a Fire Golem's slam). Until they land
## the player can't steer, jump, dash or attack.
signal knocked_up
const KNOCK_UP_MIN_SEC := 0.2
var _knock_up_time := -1.0

func knock_up(height: float) -> void:
	velocity.y = sqrt(2.0 * _gravity * height)
	_move_velocity = Vector3.ZERO
	_knock_up_time = 0.0
	_is_dashing = false
	_is_sliding = false
	knocked_up.emit()

func is_knocked_up() -> bool:
	return _knock_up_time >= 0.0

## Move Speed is gear-only (StatSheet.misc_bonus); Attack Speed is gear +
## Agility, see get_action_speed_multiplier().

func _ready() -> void:
	if stat_sheet == null:
		# Fallback only - Player.tscn assigns player_baseline.tres normally.
		stat_sheet = StatSheet.new()
		stat_sheet.strength = 10.0
		stat_sheet.agility = 10.0
		stat_sheet.intellect = 10.0
	fate_board = FateBoard.new()
	ledge_climb = LedgeClimb.new(self)
	add_child(RangeRings.new())
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
	collision_mask |= 1 << (WaterBuilder.BANK_WALL_LAYER - 1)  # river banks
	collision_mask |= 1 << (GeneratedMap.CEILING_LAYER - 1)  # indoor ceilings
	health.died.connect(_on_died)
	# Captured before any gear bonus applies - the .tscn's static values
	# are the class baseline Strength/Intellect add on top of.
	_base_max_health = health.max_health
	_base_max_mana = mana.max_mana
	_base_mana_regen = mana.regen_per_second
	if collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	unique_effects = UniqueEffects.new()
	unique_effects.name = "UniqueEffects"
	add_child(unique_effects)
	stat_sheet.unique_effects = unique_effects
	stat_sheet.status_effects = status_effects
	gear_effects = GearEffects.new()
	gear_effects.name = "GearEffects"
	add_child(gear_effects)
	loot_picker = LootPicker.new()
	loot_picker.name = "LootPicker"
	add_child(loot_picker)
	equipment.equipment_changed.connect(_on_equipment_changed)
	EventBus.slate_placed.connect(func(_id, _pos): _apply_fate_board_bonuses())
	EventBus.slate_removed.connect(func(_id, _pos): _apply_fate_board_bonuses())
	EventBus.slate_lenses_changed.connect(func(_id): _apply_fate_board_bonuses())
	EventBus.item_stats_changed.connect(_on_item_stats_changed)
	# Wired here, not in either component's own _ready() - Godot calls a
	# child's _ready() before its parent's, so PlayerAbilityCast._ready()
	# connecting to cast_time_handler (a Player @onready var, another
	# sibling child) would hit it before Player._ready() has resolved it.
	# Player._ready() runs last, after every child's own _ready(), so
	# both components are guaranteed live here.
	cast_time_handler.cast_completed.connect(ability_cast._on_cast_time_completed)
	weapon_stance.stance_entered.connect(stance_attack._on_stance_entered)
	weapon_stance.stance_exited.connect(stance_attack._on_stance_exited)
	weapon_stance.stance_entered.connect(func(): stat_sheet.in_stance = true)
	weapon_stance.stance_exited.connect(func(): stat_sheet.in_stance = false)
	_apply_saved_loadout()
	_apply_saved_experience()
	_apply_saved_fate_board()
	_on_equipment_changed()  # applies stat bonuses + visuals for whatever _apply_saved_loadout() just equipped
	_apply_fate_board_bonuses()  # re-derives StatSheet's Slate fields from whatever _apply_saved_fate_board() just restored (empty on a fresh character)
	# Gear only raises the cap, so start each scene at the full geared Life.
	health.current_health = health.max_health
	health.health_changed.emit(health.current_health, health.max_health)

## Fires on every equip()/unequip(), not just at spawn - also covers a
## shield/weapon equipped into a previously-empty slot.
## Arkanus replaces the spell bar with its four spells while equipped.
func _apply_arkanus_spells() -> void:
	var on := unique_effects != null and unique_effects.has(UniqueEffects.ARKANUS)
	if on == not ability_loadout.override.is_empty():
		return
	var spells: Array[Ability] = []
	if on:
		for path in UniqueEffects.ARKANUS_SPELLS:
			spells.append(load(path) as Ability)
	ability_loadout.set_override(spells)

func _on_equipment_changed() -> void:
	if unique_effects:
		unique_effects.refresh(equipment.get_all_equipped_items())
	_apply_arkanus_spells()
	stat_sheet.set_equipment_bonus(equipment.compute_stat_bonuses())
	stat_sheet.set_equipment_resistance(equipment.compute_resistance_bonuses())
	stat_sheet.set_misc_bonus(equipment.compute_misc_bonuses())
	stat_sheet.apply_equipment_affixes(equipment.get_all_equipped_items())
	# Primary-slot Conduit only; an offhand Conduit doesn't contribute.
	var primary := equipment.primary_weapon
	stat_sheet.conduit_spell_damage_bonus = primary.get_conduit_spell_damage_bonus() if primary else 0.0
	stat_sheet.conduit_additional_projectiles = primary.get_conduit_additional_projectiles() if primary else 0
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
	# Star bonuses (claimed sites, Lenses in lit Stars) ride on the Slate totals.
	var stars := FateStars.totals(fate_board)
	stat_sheet.set_slate_bonus(FateStars.merge(ChainCalculator.slate_stat_bonuses(fate_board, chains), stars["stats"]))
	stat_sheet.set_chain_bonus_by_tag(ChainCalculator.bonus_by_tag(chains))
	stat_sheet.mastery_by_tag = FateStars.merge(ChainCalculator.mastery_by_tag(chains), stars["mastery"])
	stat_sheet.slate_misc_bonus = FateStars.merge(ChainCalculator.slate_misc_bonuses(fate_board), stars["misc"])
	if equipment:
		equipment.board_misc_bonus = stat_sheet.slate_misc_bonus
	_apply_derived_stats()

## Reduces Ignite ticks (DamageCalculator.dot_mitigation()); gear-only
## (flat_resilience), re-derived in _apply_derived_stats().
var resilience: float = 0.0

## Ward's base comes from armour (flat_ward) only; Intellect multiplies it
## (StatSheet.get_ward_increased_from_stats()), so no armour means no Ward.
const BASE_REGEN_PERCENT := 0.5

func _apply_derived_stats() -> void:
	# Life: Strength's +4/point + flat Life, times increased Life. Level adds
	# nothing directly; defences carry survival.
	var life_mult := (unique_effects.max_life_multiplier() if unique_effects else 1.0) * (1.0 + stat_sheet.get_misc_bonus("life_increased") / 100.0) * (1.0 + stat_sheet.get_misc_bonus("no_ward_recovery_life_bonus") / 100.0)
	var flat_life := stat_sheet.get_misc_bonus("max_life") + stat_sheet.get_misc_bonus("flat_life")
	health.set_max_health((_base_max_health + stat_sheet.get_max_life_bonus() + flat_life) * life_mult)
	# Everyone regenerates BASE_REGEN_PERCENT of max Life/Mana per second on top of gear.
	var life_regen := (health.max_health * BASE_REGEN_PERCENT / 100.0 + stat_sheet.get_misc_bonus("life_regen") + stat_sheet.get_misc_bonus("life_regen_flat")) * (1.0 + stat_sheet.get_misc_bonus("life_regen_increased") / 100.0)
	health.regen_per_second = 0.0 if unique_effects and unique_effects.has(UniqueEffects.NO_LIFE_REGEN) else life_regen
	resilience = stat_sheet.get_misc_bonus("flat_resilience")

	# Mana: Intellect's +3/point + flat Mana, times increased Mana; regen likewise.
	var flat_mana := stat_sheet.get_misc_bonus("max_mana") + stat_sheet.get_misc_bonus("flat_mana")
	mana.set_max_mana((_base_max_mana + stat_sheet.get_mana_from_stats() + flat_mana) * (1.0 + stat_sheet.get_misc_bonus("mana_increased") / 100.0))
	mana.regen_per_second = (_base_mana_regen + mana.max_mana * BASE_REGEN_PERCENT / 100.0 + stat_sheet.get_misc_bonus("mana_regen")) * (1.0 + stat_sheet.get_misc_bonus("mana_regen_increased") / 100.0)
	if unique_effects and unique_effects.has(UniqueEffects.ARKANUS):
		# Arkanus fixes the Mana pool and its regeneration; nothing scales them.
		mana.set_max_mana(unique_effects.value(UniqueEffects.ARKANUS_MANA))
		mana.regen_per_second = unique_effects.value(UniqueEffects.ARKANUS_REGEN)
	# Inner Power: Mana stops recovering; twice its regeneration goes to Life.
	if GameState.toggled_spells.has("inner_power"):
		health.regen_per_second += mana.regen_per_second * ability_cast.inner_power_life_share()
		mana.regen_per_second = 0.0
	stat_sheet.current_max_mana = mana.max_mana
	health.recovery_multiplier = 1.0 + stat_sheet.get_misc_bonus("life_recovery_rate") / 100.0
	mana.recovery_multiplier = 1.0 + stat_sheet.get_misc_bonus("mana_recovery_rate") / 100.0

	# Evasion (gear x Agility's increased%) - refreshed here for display;
	# take_damage() reads it live.
	stat_sheet.stat_evasion_bonus = stat_sheet.get_total_evasion(equipment)
	# Gear's increased Crit Chance shares Agility's multiplicative bracket
	# (DamageCalculator.get_crit_chance()).
	stat_sheet.finesse_crit_bonus = stat_sheet.get_crit_chance_from_stats() + stat_sheet.get_gear_crit_chance_bonus()

	var ward_mult := (unique_effects.ward_multiplier() if unique_effects else 1.0)
	ward.set_max_ward(equipment.compute_ward_bonus() * (1.0 + stat_sheet.get_ward_increased_from_stats()) * ward_mult)
	ward.restoration_multiplier = 1.0 + stat_sheet.get_misc_bonus("ward_recovery_increased") / 100.0
	# WardComponent has no StatSheet, so the delay is pushed in.
	ward.regen_delay_reduction = stat_sheet.get_ward_delay_reduction()

	# Cast Speed: gear affixes plus the primary Conduit's local Cast Speed,
	# into the StatSheet pool CastTimeHandler reads.
	var primary := equipment.primary_weapon if equipment else null
	stat_sheet.cast_speed_bonus = stat_sheet.get_misc_bonus("cast_speed") + (primary.get_conduit_cast_speed_bonus() if primary else 0.0)
	# Gear's Cooldown Recovery Rate, then the Slate affix that converts part
	# of Cast Speed into it.
	stat_sheet.cooldown_recovery_rate = stat_sheet.get_misc_bonus("cooldown_recovery_rate")
	stat_sheet.apply_cast_speed_to_cooldown_conversion(stat_sheet.get_misc_bonus("cast_speed_to_cooldown_recovery"))
	_apply_aether_capacity()

## Level capacity plus gear's flat Aether, times increased Aether capacity.
func _apply_aether_capacity() -> void:
	var capacity := (FateBoard.capacity_for_level(GameState.player_level) + stat_sheet.get_misc_bonus("flat_aether")) * (1.0 + stat_sheet.get_misc_bonus("increased_aether_capacity") / 100.0)
	if int(capacity) != fate_board.aether_capacity:
		fate_board.aether_capacity = int(capacity)
		EventBus.aether_budget_changed.emit(fate_board.aether_used, fate_board.aether_capacity)

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

## Each level grants +2 Aether and +0.6 to each stat
## (GameState.get_level_stat_bonus()).
func _on_leveled_up(new_level: int) -> void:
	GameState.player_level = new_level
	stat_sheet.level_bonus = GameState.get_level_stat_bonus()
	_apply_derived_stats()
	EventBus.aether_budget_changed.emit(fate_board.aether_used, fate_board.aether_capacity)
	EventBus.player_leveled_up.emit(new_level)
	_queue_level_up_banner(new_level)

## The level the pending banner starts from; -1 when none is queued. Several
## levels from one XP grant show one banner rolling to the final level.
var _level_up_from := -1

func _queue_level_up_banner(new_level: int) -> void:
	if _level_up_from == -1:
		_level_up_from = new_level - 1
		_show_level_up_banner.call_deferred()

func _show_level_up_banner() -> void:
	AudioManager.play_2d(SoundLib.library.level_up, -4.0)
	LevelUpBanner.play(self, _level_up_from, GameState.player_level)
	_level_up_from = -1

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
	# Weapon sets restore by index (see EquipmentComponent.get_weapon_set_refs()).
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
## cells) returns that Slate to the inventory rather than failing the
## whole restore.
func _apply_saved_fate_board() -> void:
	# place_slate() re-syncs GameState, so read the saved Star Lenses and layout first.
	var saved_stars: Dictionary = GameState.fate_board_star_lenses.duplicate()
	var shift := FateBoard.LEGACY_SHIFT if GameState.fate_board_layout < FateBoard.LAYOUT_VERSION else Vector2i.ZERO
	for entry in GameState.fate_board_placements.duplicate():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slate := _resolve_slate_ref(entry.get("slate_ref"))
		if slate == null:
			continue
		var origin_raw = entry.get("origin", [0, 0])
		var origin := Vector2i(int(origin_raw[0]), int(origin_raw[1])) if origin_raw is Array and origin_raw.size() == 2 else Vector2i.ZERO
		origin += shift
		var placed := fate_board.place_slate(
			slate, origin, int(entry.get("rotation_steps", 0)), bool(entry.get("flipped", false)),
			str(entry.get("designated_ability_id", "")), true, int(entry.get("aether_paid", -1))
		)
		# Never lose a Slate the board can't take back: return it to the bag.
		if placed == "":
			GameState.add_to_inventory(slate)
	for key in saved_stars:
		var lens: Lens = ItemSerializer.from_dict(saved_stars[key]) as Lens if saved_stars[key] is Dictionary else null
		if lens and fate_board.set_star_lens(int(key), lens, false) != "":
			GameState.add_to_inventory(lens)
	GameState.sync_fate_board(fate_board)

## slate_ref is a resource_path String (hand-authored Slate) or full
## SlateSerializer data (a rolled drop).
func _resolve_slate_ref(ref) -> Slate:
	if ref is String and ref != "":
		return load(ref) as Slate
	if ref is Dictionary:
		return SlateSerializer.from_dict(ref)
	return null

func _apply_saved_ability_levels() -> void:
	if GameState.ability_levels.is_empty() and GameState.skill_webs.is_empty():
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
			if ability and GameState.skill_webs.has(ability.ability_id):
				var saved: Dictionary = GameState.skill_webs[ability.ability_id]
				ability.web_points = {}
				for node_id in saved:
					if SkillWeb.find(ability, str(node_id)):
						ability.web_points[str(node_id)] = int(saved[node_id])
				SkillWeb.trim_to_available(ability)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()


## Drops content (an Item, Slate or currency id) on the floor in front of
## you, as a pickup you take back with Interact (never collected on touch).
const DROP_DISTANCE := 1.2

func drop_to_ground(content, count: int = 1) -> void:
	var pickup: LootPickup = (load("res://entities/pickups/loot_pickup/LootPickup.tscn") as PackedScene).instantiate()
	if content is Slate:
		pickup.slate = content
	elif content is Item:
		pickup.item = content
	else:
		pickup.currency_id = StringName(content)
		pickup.currency_count = count
	pickup.dropped_by_player = true
	var ahead := -global_transform.basis.z
	ahead.y = 0.0
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = global_position + ahead.normalized() * DROP_DISTANCE + Vector3.UP * LootPickup.DEFAULT_HOVER

## Melee vs ranged attack follows the active Weapon's is_ranged, not
## which slot it's in - see the dispatch in _physics_process(). Ranged
## weapons equip into PRIMARY_WEAPON same as melee ones (see
## worn_pistol.tres), so "active weapon" is just whatever's equipped
## there - no manual weapon-slot toggle needed.
func get_active_weapon() -> Weapon:
	return equipment.primary_weapon

## ---- Dual wielding ---------------------------------------------------------
## A one-handed weapon in each hand (Weapon.can_dual_wield). Attacks say which
## hand swings or fires (attack_hand); melee and ranged roll that weapon.
enum Hand { MAIN, OFF }
const DUAL_WIELD_ATTACK_SPEED := 1.1  # more attack speed while dual wielding
var attack_hand: Hand = Hand.MAIN

## The offhand weapon when dual wielding, else null.
func get_offhand_weapon() -> Weapon:
	var main := get_active_weapon()
	var off := equipment.offhand as Weapon if equipment else null
	if main == null or off == null or not main.can_dual_wield() or not off.can_dual_wield():
		return null
	return off

func is_dual_wielding() -> bool:
	return get_offhand_weapon() != null

## "melee", "guns", "mixed" (one of each), or "" when not dual wielding.
func dual_wield_kind() -> String:
	var off := get_offhand_weapon()
	if off == null:
		return ""
	var main := get_active_weapon()
	if main.is_ranged and off.is_ranged:
		return "guns"
	return "mixed" if main.is_ranged or off.is_ranged else "melee"

## The weapon in the hand that's attacking.
func get_attack_weapon() -> Weapon:
	if attack_hand == Hand.OFF and is_dual_wielding():
		return get_offhand_weapon()
	return get_active_weapon()

## Action speed for an attack with `weapon` (its own local attack speed),
## plus dual wielding's bonus.
func get_attack_speed_multiplier(weapon: Weapon = null) -> float:
	if weapon == null:
		weapon = get_attack_weapon()
	var local := weapon.get_local_multiplier("local_increased_attack_speed") if weapon else 1.0
	# Ranged weapons (guns, bows, throwing) use Fire Rate in place of Attack Speed.
	var gear_speed := stat_sheet.get_misc_bonus("fire_rate" if weapon and weapon.is_ranged else "attack_speed")
	var speed := (1.0 + gear_speed / 100.0 + stat_sheet.get_attack_speed_from_stats()) * local
	return speed * (DUAL_WIELD_ATTACK_SPEED if is_dual_wielding() else 1.0) * (ability_cast.charged_reflexes_fire_rate() if weapon and weapon.is_ranged and GameState.toggled_spells.has("charged_reflexes") else 1.0)

## What delivered a hit, for Evasion: ATTACK (the default) can be Dodged
## and Deflected, SPELL only Deflected, DOT neither.
enum HitKind { ATTACK, SPELL, DOT }

## Order: Evasion (Dodge, then Deflection), mitigation (Armour for
## Physical, Resistance otherwise), Ward, then Health.
## is_melee: an enemy weapon swing (EnemyMeleeAttack), for Guard.
## Hits taken in the air (not mantling a ledge) deal this much more.
const AIRBORNE_DAMAGE_TAKEN := 1.1

func is_airborne() -> bool:
	return not is_on_floor() and not (ledge_climb and ledge_climb.busy())

func take_damage(amount: float, damage_type: Constants.DamageType, source: Node = null, hit_kind: HitKind = HitKind.ATTACK, is_melee: bool = false) -> void:
	if parry_handler and parry_handler.is_invulnerable:
		return
	if hit_kind != HitKind.DOT and has_dash_iframes():
		EventBus.hit_dodged.emit(self)
		return
	if hit_kind != HitKind.DOT and shield_block.try_block(amount, source):
		return
	amount = stance_defense.absorb(amount, source, hit_kind, is_melee)
	if amount <= 0.0:
		return
	# Caught in the air: jumping over attacks has a cost.
	if hit_kind != HitKind.DOT and is_airborne():
		amount *= AIRBORNE_DAMAGE_TAKEN
	# Dodge (attacks only) negates the hit and never interrupts a cast;
	# Deflection (attacks and spells) reduces it.
	if hit_kind != HitKind.DOT:
		var evasion := stat_sheet.get_total_evasion(equipment)
		if evasion > 0.0:
			var dodge := DamageCalculator.player_dodge_chance(evasion)
			if hit_kind != HitKind.ATTACK:
				dodge *= stat_sheet.get_misc_bonus("evasion_to_spells") / 100.0  # "% of Evasion applies to Spell Hits"
			if randf() < dodge:
				EventBus.hit_dodged.emit(self)
				return
			if randf() < DamageCalculator.player_deflection_chance(evasion):
				amount *= 1.0 - DamageCalculator.player_deflection_mitigation(evasion)
				EventBus.hit_deflected.emit(self)
	if unique_effects:
		amount *= unique_effects.damage_taken_multiplier(hit_kind == HitKind.SPELL)
	# Monsters far above your level (past your XP zone) hit much harder.
	if source is Enemy:
		amount *= AreaLevel.gap_damage_multiplier((source as Enemy).level, GameState.player_level)
	# Ground zones like the Lord of the Elements' sigils.
	for zone in get_tree().get_nodes_in_group("damage_zone"):
		amount *= zone.damage_multiplier_for(self, damage_type)
	# Figment conversion mod: part of an enemy's hit arrives as another type,
	# mitigated on its own.
	var enemy_source := source as Enemy
	if enemy_source and hit_kind != HitKind.DOT:
		var conversion := enemy_source.get_map_conversion()
		if not conversion.is_empty() and int(conversion[1]) != damage_type:
			var converted: float = amount * float(conversion[0])
			_take_damage_single(converted, int(conversion[1]) as Constants.DamageType, source)
			amount -= converted
	# Physical taken as Elemental splits the hit before mitigation; each
	# part is mitigated on its own.
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
		if status_effects.has_effect("stone_skin"):
			armor += STONE_SKIN_ARMOUR
		mitigated *= (1.0 - DamageCalculator.player_physical_mitigation(armor, mitigated, _attacker_level(source)))
		mitigated *= (1.0 - stat_sheet.get_reduced_damage_taken(Constants.DamageCategory.PHYSICAL))
	elif category == Constants.DamageCategory.ELEMENTAL or category == Constants.DamageCategory.ESOTERIC:
		var resistance := stat_sheet.get_effective_resistance(damage_type, status_effects.get_resistance_shred())
		mitigated *= (1.0 - DamageCalculator.resistance_mitigation(resistance))
		# "% of Armour applies to Elemental": that share of Armour, through
		# the physical curve, on top of Resistance (Elemental only).
		if category == Constants.DamageCategory.ELEMENTAL:
			var armor_to_elemental_pct := stat_sheet.get_misc_bonus("armor_to_elemental") / 100.0
			if armor_to_elemental_pct > 0.0 and equipment:
				var bonus_armor := equipment.get_total_armor() * armor_to_elemental_pct
				mitigated *= (1.0 - DamageCalculator.player_physical_mitigation(bonus_armor, mitigated, _attacker_level(source)))
		mitigated *= (1.0 - stat_sheet.get_reduced_damage_taken(category))
		if status_effects.has_effect("stone_skin"):
			mitigated *= 1.0 - STONE_SKIN_MAGIC_REDUCTION
	if unique_effects:
		mitigated = unique_effects.absorb_esoteric(mitigated, damage_type)
		unique_effects.record_damage_taken(mitigated)
	# "% of Damage from Mana before Life": Mana pays its share before Ward.
	var mana_shield_pct := stat_sheet.get_damage_from_mana_percent()
	if mana_shield_pct > 0.0 and mana and mana.current_mana > 0.0:
		var mana_portion := mitigated * mana_shield_pct
		var actual_drain: float = min(mana_portion, mana.current_mana)
		mana.spend(actual_drain)
		mitigated -= actual_drain
	var overflow := ward.absorb(mitigated)
	health.apply_damage(overflow)
	EventBus.damage_dealt.emit(source, self, mitigated, damage_type, false, false)

## The level whose damage scale a hit is measured against (Armour): the
## attacking monster's, else the current area's.
func _attacker_level(source: Node) -> int:
	if source is Enemy:
		return maxi((source as Enemy).level, 1)
	return maxi(AreaLevel.current(), 1)

## Elemental Earth (Arkanus): Stone Skin's Armour and less Elemental and
## Esoteric damage taken.
const STONE_SKIN_ARMOUR := 1500.0
const STONE_SKIN_MAGIC_REDUCTION := 0.12

const BLOCK_CHANCE_CAP := 0.75

## Rolls the shield's block chance (capped at 75%) against one melee hit.
## Only EnemyMeleeAttack asks: spells, projectiles and DoTs can't be blocked.
func try_block_melee_hit() -> bool:
	var shield := equipment.offhand as Shield if equipment else null
	if shield == null or shield_block.is_raised:
		return false  # a raised shield blocks (or doesn't) in take_damage()
	var chance: float = min((shield.block_chance + stat_sheet.get_block_chance_bonus()) * stat_sheet.get_block_chance_multiplier(), BLOCK_CHANCE_CAP)
	if randf() < chance:
		EventBus.hit_blocked.emit(self)
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Slower look through a scope, in step with its zoom.
		var sensitivity := mouse_sensitivity * (camera.fov / GameState.field_of_view if weapon_stance.is_scoped() else 1.0)
		rotate_y(-event.relative.x * sensitivity)
		head.rotate_x(-event.relative.y * sensitivity)
		var clamped_x: float = clamp(head.rotation.x, deg_to_rad(-max_look_up_deg), deg_to_rad(max_look_up_deg))
		head.rotation.x = clamped_x
	elif event.is_action_pressed("weapon_swap_scroll") and not is_action_locked():
		# One swap per flick: a wheel notch fires several events.
		var now := Time.get_ticks_msec()
		if now - _last_scroll_swap_msec >= SCROLL_SWAP_COOLDOWN_MSEC:
			_last_scroll_swap_msec = now
			_tap_weapon_swap()

## Non-pausing menus (the inventory) show the cursor; combat input is
## ignored while they do, movement isn't.
## Headless runs (tests) can't capture the mouse, so they never count as blocked.
func is_input_blocked() -> bool:
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless"

## Combat input is off: a menu is open, or the player hangs on or mantles a ledge.
func is_action_locked() -> bool:
	return is_input_blocked() or ledge_climb.busy()

## Swinging, shooting, parrying, casting or reloading: too busy to catch a ledge.
func is_mid_action() -> bool:
	return arm_rig.is_animating() or not melee_attack.is_idle() or cast_time_handler.is_casting() or ranged_attack.is_reloading()

func _physics_process(delta: float) -> void:
	if ledge_climb.busy():
		ledge_climb.process(delta)
		_update_crouch_visual(delta)
		return
	if not is_on_floor():
		var gravity_scale := FALL_GRAVITY_MULTIPLIER if velocity.y < 0.0 else 1.0
		velocity.y -= _gravity * gravity_scale * delta
		_is_sliding = false
	# Electrocute/Freeze ("disrupts target action" / "full immobilization") -
	# movement itself is already zeroed via _effective_speed()'s status
	# multiplier below; this additionally blocks jump/parry/attack input.
	if _knock_up_time >= 0.0:
		_knock_up_time += delta
		if _knock_up_time > KNOCK_UP_MIN_SEC and is_on_floor():
			_knock_up_time = -1.0
	var stunned := status_effects.is_stunned() or is_knocked_up() or is_in_visceral()
	_coyote_timer = COYOTE_TIME if is_on_floor() else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = JUMP_BUFFER_TIME if Input.is_action_just_pressed("jump") else maxf(_jump_buffer_timer - delta, 0.0)
	var rooted := stance_defense.is_rooted() or status_effects.has_effect("entangle") or (stance_attack.is_charging and stance_attack.get_move_speed_multiplier() <= 0.0)
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
	_iframes_remaining = maxf(_iframes_remaining - delta, 0.0)
	# just_pressed fires once on the initial keydown regardless of how long
	# Shift stays held afterward - a tap dashes, continuing to hold still
	# sprints normally on top of it (see the const block's own comment).
	if Input.is_action_just_pressed("sprint") and not stunned and not rooted and not _is_dashing and not _is_sliding \
			and _dash_cooldown_remaining <= 0.0 and move_dir.length() > 0.1:
		_start_dash(move_dir)

	if Input.is_action_just_pressed("crouch") and is_on_floor() and not rooted and not _is_sliding and not _is_dashing and move_dir.length() > 0.1 \
			and (sprinting or downhill_grade(move_dir) > SLIDE_MIN_GRADE):
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
		var grade := downhill_grade(_slide_direction)
		if grade > SLIDE_MIN_GRADE:
			_slide_speed_current = minf(_slide_speed_current + SLIDE_SLOPE_ACCELERATION * grade * delta, maxf(SLIDE_MAX_SPEED, _slide_speed_current))
			_slide_timer = maxf(_slide_timer, 0.15)
		else:
			_slide_timer -= delta
			var slowdown := SLIDE_DECELERATION - SLIDE_SLOPE_ACCELERATION * minf(grade, 0.0)
			_slide_speed_current = max(_slide_speed_current - slowdown * delta, _effective_speed(crouch_speed))
		velocity.x = _slide_direction.x * _slide_speed_current
		velocity.z = _slide_direction.z * _slide_speed_current
		# Follow the slope down rather than launching off it at speed.
		if is_on_floor() and grade > SLIDE_MIN_GRADE:
			var n := get_floor_normal()
			velocity.y = -(n.x * velocity.x + n.z * velocity.z) / maxf(n.y, 0.1)
		_is_crouching = true
		_move_velocity = Vector3(velocity.x, 0.0, velocity.z)
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide(crouch_held)
	else:
		_is_crouching = crouch_held
		var speed := _effective_speed(crouch_speed) if _is_crouching else _effective_speed(sprint_speed if sprinting else move_speed)
		var target := Vector3.ZERO if is_knocked_up() else move_dir * speed
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
	if not stunned and not rooted:
		ledge_climb.try_catch(delta)

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
			_tap_weapon_swap()
		_x_held_time = 0.0
		_x_triggered_hold = false

## With an empty second set, a tap swaps the main hand's stance page instead
## (when it has one) rather than swapping to bare hands.
func _tap_weapon_swap() -> void:
	var other_set := 1 - equipment.active_weapon_set
	var other_empty := equipment.primary_weapons[other_set] == null and equipment.offhands[other_set] == null
	if other_empty and (weapon_stance.has_page_b(equipment.primary_weapon) or weapon_stance.active_page == WeaponStance.StancePage.B):
		weapon_stance.toggle_stance_page()
		return
	equipment.toggle_weapon_set()
	GameState.sync_weapon_sets(equipment)

func _handle_attack_input(delta: float) -> void:
	if shield_block.is_raised or parry_handler.is_busy():
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
		if caster_stance.try_stance_attack():
			pass
		elif is_wand:
			caster_stance.try_primary_attack()
		elif active_weapon and active_weapon.is_ranged:
			ranged_attack.try_attack(weapon_stance.is_active)
		elif weapon_stance.is_active:
			if stance_attack.is_charged_stance():
				pass  # charged stances charge from holding RMB alone
			elif not stance_attack.try_instant():
				melee_attack.try_charged_thrust()
	# Full-auto weapons fire every frame the button is held (they ignore
	# try_attack() above); every other fire mode returns immediately.
	if Input.is_action_pressed("attack") and active_weapon and active_weapon.is_ranged:
		ranged_attack.try_attack_held(weapon_stance.is_active)
	if Input.is_action_just_pressed("reload") and not ranged_attack.get_guns().is_empty():
		ranged_attack.try_manual_reload()
	# Mixed pair (a blade and a gun): the offhand weapon has its own key.
	if Input.is_action_just_pressed("offhand_attack") and dual_wield_kind() == "mixed":
		if get_offhand_weapon().is_ranged:
			ranged_attack.try_offhand_fire(weapon_stance.is_active)
		else:
			melee_attack.try_offhand_swing()
	if Input.is_action_just_pressed("gun_bash") and active_weapon and active_weapon.is_ranged:
		ranged_attack.try_bash()

func get_move_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_misc_bonus("move_speed") / 100.0

func _effective_speed(base: float) -> float:
	if is_in_visceral():
		return 0.0
	return base * get_move_speed_multiplier() * status_effects.get_move_speed_multiplier() * WaterBuilder.wading_factor(global_position) \
		* melee_attack.get_move_speed_multiplier() * ability_cast.get_move_speed_multiplier() \
		* weapon_stance.get_move_speed_multiplier() * shield_block.get_move_speed_multiplier() \
		* stance_attack.get_move_speed_multiplier() * stance_defense.get_move_speed_multiplier()

## Gear attack_speed + Agility's +1%/point, one increased% bracket, times
## the active weapon's own local attack speed mods.
func get_action_speed_multiplier() -> float:
	var weapon := get_active_weapon()
	var local := weapon.get_local_multiplier("local_increased_attack_speed") if weapon else 1.0
	return (1.0 + stat_sheet.get_misc_bonus("attack_speed") / 100.0 + stat_sheet.get_attack_speed_from_stats()) * local

## Gear and Slate reload_speed, one increased% bracket.
func get_reload_speed_multiplier() -> float:
	return (1.0 + stat_sheet.get_misc_bonus("reload_speed") / 100.0) * (ability_cast.charged_reflexes_reload() if GameState.toggled_spells.has("charged_reflexes") else 1.0)

func _start_dash(move_dir: Vector3) -> void:
	_is_dashing = true
	_dash_timer = DASH_DURATION
	_dash_direction = move_dir
	_dash_speed_current = DASH_SPEED * (1.0 + stat_sheet.get_misc_bonus("dash_speed") / 100.0)
	_dash_cooldown_remaining = DASH_COOLDOWN
	_iframes_remaining = DASH_IFRAMES
	melee_attack.cancel_recovery()

func is_in_visceral() -> bool:
	return _in_visceral

## Turns to the target, plunges the weapon in, and calls on_rip as it tears out.
func start_visceral(target: Enemy, on_rip: Callable) -> void:
	_in_visceral = true
	get_tree().create_timer(VISCERAL_LOCK).timeout.connect(func() -> void: _in_visceral = false)
	parry_handler.grant_invulnerability(VISCERAL_LOCK + 0.2)
	target.hold_for_visceral(VISCERAL_LOCK)
	_move_velocity = Vector3.ZERO
	_impulse = Vector3.ZERO
	_is_dashing = false
	var to := target.global_position - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		var yaw := atan2(-to.x, -to.z)
		create_tween().tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, yaw), 0.12)
	if arm_rig:
		arm_rig.play_visceral(VISCERAL_RIP_AT, VISCERAL_LOCK - VISCERAL_RIP_AT)
	var fov := camera.create_tween()
	fov.tween_property(camera, "fov", GameState.field_of_view - VISCERAL_FOV_PUSH, VISCERAL_RIP_AT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	fov.tween_property(camera, "fov", GameState.field_of_view, VISCERAL_LOCK - VISCERAL_RIP_AT).set_ease(Tween.EASE_IN_OUT)
	get_tree().create_timer(VISCERAL_RIP_AT).timeout.connect(on_rip)

func has_dash_iframes() -> bool:
	return _iframes_remaining > 0.0

## Dagger's stance special lunge; shares the Shift dash's cooldown. False
## when the dash is unavailable (the thrust still lands, without the lunge).
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

## How steeply the floor drops along `direction` (horizontal, unit): the
## sine of the slope angle when heading straight down it, negative uphill,
## 0 on level ground or in the air.
func downhill_grade(direction: Vector3) -> float:
	if not is_on_floor():
		return 0.0
	var n := get_floor_normal()
	return Vector3(n.x, 0.0, n.z).dot(direction)

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
