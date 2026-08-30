extends Node
class_name PlayerAbilityCast
## Casts AbilityLoadoutComponent's equipped abilities on ability_1..4
## input, checking/consuming ManaComponent + cooldown per Ability.
##
## Most abilities cast instantly at the player's own position (a self-
## centered nova) on press. Several (Ability.is_ground_targeted) instead
## enter a hold-to-aim mode: holding the key shows a ground ring following
## a raycast from the camera, and releasing casts centered on that point
## instead. Only one targeting session can be active at a time - a second
## targeted key pressed mid-aim is ignored until the first is released.
##
## Execution is otherwise deliberately generic for every ability: consume
## resource_cost, start cooldown, deal damage to every Enemy within the
## ability's own radius of the cast point, then apply Ability.
## applies_status_effects (Section 09, via StatusEffectComponent) to each
## hit. Not each ability's actual described mechanic (Comet/Winter's Eye/
## Frost Armor are distinct real mechanics) - a first pass so the ability
## bar's readouts aren't inert UI. Three abilities break this generic
## shape outright: Blink/Purge deal no damage at all (see _cast()'s early
## returns), and Black Hole/Caltrops layer extra behavior on top via their
## own effect scenes (BlackHoleField/CaltropsField) rather than anything
## this script does directly.

const RANGE_EFFECT_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")
const MAX_TARGET_RANGE := 30.0
const RETICLE_HEIGHT_OFFSET := 0.05

## Ground-targeted abilities with a bespoke cast VFX instead of the
## generic ring - everything else still just uses RANGE_EFFECT_SCENE.
## Meteor ("26 - Ability Staging Ground": "descends from above, crashing
## into a targeted area") reuses Comet's own fall-and-impact VFX outright -
## same mechanic, just a different damage type/color, not worth a second
## near-identical scene.
const SPECIAL_EFFECT_SCENES := {
	"comet": preload("res://entities/effects/comet_impact/CometImpact.tscn"),
	"meteor": preload("res://entities/effects/comet_impact/CometImpact.tscn"),
	"inferno": preload("res://entities/effects/inferno_pillar/InfernoPillar.tscn"),
	"stormcall": preload("res://entities/effects/stormcall_bolt/StormcallBolt.tscn"),
	"black_hole": preload("res://entities/effects/black_hole_field/BlackHoleField.tscn"),
	"caltrops": preload("res://entities/effects/caltrops_field/CaltropsField.tscn"),
}

const BLINK_DISTANCE := 8.0

var _cooldowns: Dictionary = {}  # Ability -> float seconds remaining
var _player: Player
var _targeting_slot: int = -1
var _reticle: MeshInstance3D
## ability_id -> Ability, lazily scanned from data/abilities/instances/ -
## same dir-scan AbilitiesScreen._scan_owned_abilities() already does, kept
## here too since Slate-designated abilities (see below) aren't necessarily
## in the 4-slot hotbar AbilityLoadoutComponent tracks.
var _ability_by_id_cache: Dictionary = {}

func _ready() -> void:
	_player = get_parent()

func _physics_process(delta: float) -> void:
	for ability in _cooldowns.keys():
		_cooldowns[ability] = max(0.0, _cooldowns[ability] - delta)

	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		var action := "ability_%d" % (i + 1)
		if Input.is_action_just_pressed(action):
			_on_ability_pressed(i)
		elif i == _targeting_slot and Input.is_action_just_released(action):
			_release_targeted_cast()

	if _targeting_slot != -1:
		_update_reticle()

	_process_slate_autocasts()

func get_cooldown_remaining(ability: Ability) -> float:
	return _cooldowns.get(ability, 0.0) if ability else 0.0

func _on_ability_pressed(slot_index: int) -> void:
	var ability: Ability = _player.ability_loadout.get_equipped(slot_index)
	if ability == null:
		return
	if ability.is_ground_targeted:
		if _targeting_slot != -1:
			return
		_targeting_slot = slot_index
		_show_reticle(ability)
	else:
		_try_cast(slot_index, _player.global_position)

func _release_targeted_cast() -> void:
	var slot_index := _targeting_slot
	_targeting_slot = -1
	_hide_reticle()
	_try_cast(slot_index, _get_ground_target_point())

## Mana/cooldown are checked here, not when targeting starts - a targeted
## cast only spends/starts cooldown on an actual release, same as an
## instant cast only ever fires once, at the moment its checks pass.
func _try_cast(slot_index: int, cast_position: Vector3) -> void:
	var ability: Ability = _player.ability_loadout.get_equipped(slot_index)
	if ability == null:
		return
	if get_cooldown_remaining(ability) > 0.0:
		EventBus.ability_cast_failed.emit(_player, ability, "On cooldown")
		return
	if _player.mana.current_mana < ability.resource_cost:
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	_player.mana.spend(ability.resource_cost)
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" - divides
	# the authored cooldown, same treatment PlayerMeleeAttack/
	# PlayerRangedAttack give their own timings.
	_cooldowns[ability] = ability.get_effective_cooldown() / _player.get_action_speed_multiplier()
	_cast(ability, cast_position)

## Each enemy rolls its own crit independently (roll_damage() per-target,
## not once and reused) - a shared roll would make them all crit together.
## damage_multiplier/apply_composure exist for _auto_cast() below (Slate-
## designated auto-cast damage is reduced and doesn't apply Composure
## damage per The Unbound Chorus's own modifiers) - a real player press
## always calls this with both at their defaults.
func _cast(ability: Ability, cast_position: Vector3, damage_multiplier: float = 1.0, apply_composure: bool = true) -> void:
	# Blink/Purge ("26 - Ability Staging Ground", Utility) have "No damage
	# component" per the doc itself - the only two abilities in this
	# project that skip the generic enemy-damage loop entirely.
	if ability.ability_id == "blink":
		_perform_blink()
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "purge":
		_player.status_effects.clear_all_effects()
		EventBus.ability_cast.emit(_player, ability)
		return

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if cast_position.distance_to(enemy.global_position) > ability.radius:
			continue
		var hit := ability.roll_damage(_player.stat_sheet)
		var damage: float = hit["final_damage"] * damage_multiplier
		var is_critical: bool = hit["is_critical"]
		enemy.take_damage(damage, ability.damage_type)
		if apply_composure and enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
		EventBus.damage_dealt.emit(_player, enemy, damage, ability.damage_type, false, is_critical)
		for effect_id in ability.applies_status_effects:
			enemy.status_effects.apply_effect(effect_id, _player, damage)

	_play_range_effect(ability, cast_position)
	EventBus.ability_cast.emit(_player, ability)

## Section 10 Unique "The Unbound Chorus": "Designate one Spell skill -
## that skill automatically triggers when its cooldown expires." Scoped to
## exactly that one doc-sourced mechanic (auto_cast_designated_spell) for
## now - Slate.requires_spell_designation and FateBoard.PlacedSlateData.
## designated_ability_id are the general "a Slate is bound to a spell"
## framework this reads from; other interaction types (buff/retrigger/
## modify a designated spell) would need their own concrete Slate designs
## to implement against, same as this one did.
func _process_slate_autocasts() -> void:
	if _player.fate_board == null:
		return
	for placement_id in _player.fate_board.placements:
		var data: FateBoard.PlacedSlateData = _player.fate_board.placements[placement_id]
		if data.designated_ability_id == "" or not _has_modifier(data.slate, "auto_cast_designated_spell"):
			continue
		var ability := _resolve_ability_by_id(data.designated_ability_id)
		if ability == null or get_cooldown_remaining(ability) > 0.0:
			continue
		_auto_cast(ability, data.slate)

## Modifiers 2-4 off The Unbound Chorus specifically: 60% damage
## (auto_cast_damage_percent), no resource cost (satisfied structurally -
## this never calls ManaComponent.spend(), unlike _try_cast()), no
## Riposte window/Composure damage (apply_composure=false).
func _auto_cast(ability: Ability, slate: Slate) -> void:
	_cooldowns[ability] = ability.get_effective_cooldown() / _player.get_action_speed_multiplier()
	var damage_percent := _modifier_value(slate, "auto_cast_damage_percent", 100.0)
	_cast(ability, _player.global_position, damage_percent / 100.0, false)

func _has_modifier(slate: Slate, stat_key: String) -> bool:
	for m in slate.modifiers:
		if m.stat_key == stat_key:
			return true
	return false

func _modifier_value(slate: Slate, stat_key: String, fallback: float) -> float:
	for m in slate.modifiers:
		if m.stat_key == stat_key:
			return m.value
	return fallback

func _resolve_ability_by_id(ability_id: String) -> Ability:
	if _ability_by_id_cache.is_empty():
		var dir := DirAccess.open("res://data/abilities/instances/")
		if dir:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tres"):
					var ability: Ability = load("res://data/abilities/instances/" + file_name) as Ability
					if ability:
						_ability_by_id_cache[ability.ability_id] = ability
				file_name = dir.get_next()
			dir.list_dir_end()
	return _ability_by_id_cache.get(ability_id)

func _play_range_effect(ability: Ability, cast_position: Vector3) -> void:
	var scene: PackedScene = SPECIAL_EFFECT_SCENES.get(ability.ability_id, RANGE_EFFECT_SCENE)
	var effect: Node3D = scene.instantiate()
	_player.get_tree().current_scene.add_child(effect)
	effect.global_position = cast_position
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	if ability.ability_id == "caltrops":
		# CaltropsField needs the ability + StatSheet directly (it rolls its
		# own damage per tick rather than reusing one hit's damage repeatedly).
		effect.call("play", ability.radius, color, ability, _player.stat_sheet, _player)
	else:
		effect.call("play", ability.radius, color)

## "26 - Ability Staging Ground", Utility - Blink: "Teleport a short
## distance in a targeted direction. No attack component." Raycasts along
## the camera's forward direction (flattened to the horizontal plane, so
## looking up/down doesn't launch the player into the air or the floor)
## so the player can't blink through a wall - stops just short of
## whatever it hits, or travels the full BLINK_DISTANCE if nothing's there.
## Cast from the CAMERA's height, not the player's feet-level
## global_position - a horizontal ray started exactly at floor height
## grazes the floor collider and reports an immediate 0-distance "hit" at
## the origin itself, which zeroed out every blink (caught by
## scratch_big_test.gd during verification).
func _perform_blink() -> void:
	var camera := _player.camera
	var ray_origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = -_player.global_transform.basis.z
	direction = direction.normalized()
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction * BLINK_DISTANCE)
	query.exclude = [_player.get_rid()]
	var result := space_state.intersect_ray(query)
	var distance: float = max(ray_origin.distance_to(result["position"]) - 0.5, 0.0) if result else BLINK_DISTANCE
	_player.global_position += direction * distance

## Ray from the camera through the (fixed, first-person) crosshair to
## whatever it's aimed at - floor, wall, or enemy collision all work as a
## target surface. Aiming at open sky (nothing hit) falls back to
## projecting onto a horizontal plane at the player's own feet height, so
## there's always a sensible point rather than an undefined one. Capped
## at MAX_TARGET_RANGE either way.
func _get_ground_target_point() -> Vector3:
	var camera := _player.camera
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MAX_TARGET_RANGE)
	query.exclude = [_player.get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		return result["position"]
	if direction.y < -0.01:
		var t: float = (_player.global_position.y - origin.y) / direction.y
		return origin + direction * clamp(t, 0.0, MAX_TARGET_RANGE)
	return origin + direction * MAX_TARGET_RANGE

func _show_reticle(ability: Ability) -> void:
	if _reticle == null:
		_reticle = MeshInstance3D.new()
		_reticle.mesh = TorusMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_reticle.material_override = mat
		_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_player.get_tree().current_scene.add_child(_reticle)

	var mesh: TorusMesh = _reticle.mesh
	mesh.outer_radius = max(ability.radius, 0.2)
	mesh.inner_radius = max(ability.radius - 0.15, 0.05)
	var mat: StandardMaterial3D = _reticle.material_override
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	color.a = 0.75
	mat.albedo_color = color
	_reticle.visible = true
	_update_reticle()

func _update_reticle() -> void:
	if _reticle == null:
		return
	_reticle.global_position = _get_ground_target_point() + Vector3(0, RETICLE_HEIGHT_OFFSET, 0)

func _hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false
