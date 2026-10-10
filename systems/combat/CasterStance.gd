extends Node
class_name CasterStance
## Conduit (caster weapon) stances - Patch v3.4 Caster Stance System with
## Patch v3.6's per-line behaviour. Stance A is the main-hand conduit's,
## stance B the offhand conduit's (falling back to the main hand's); a
## non-conduit main hand keeps its weapon stance on page A. Behaviour comes
## from the source conduit's conduit_stance_type:
## - spell_library: the 1-4 keys cast the stance page (loadout slots 5-8)
##   while RMB is held; spell_page_tag limits it to Esoteric or Elemental
##   spells, spell_page_modifier changes what they do.
## - unleash: Unleashable spells cast in stance fire unleash_copy_count copies.
## - stance_buff: spell damage, Esoteric damage or Ward on cast while held.
## - mana_stars: LMB in stance fires Mana Stars.
## - battlemage: Staff strikes on RMB; Spell Gauntlet punches, and a landed
##   punch follows up with a Mana Star.
## - passive (Rod): no stance.
## Wands also fire energy bolts on LMB outside stance (v3.4 table).

const PAGE_TAG_CATEGORY := {
	"esoteric": Constants.DamageCategory.ESOTERIC,
	"elemental": Constants.DamageCategory.ELEMENTAL,
}
const SPELL_DAMAGE_BUFF := 1.25
const ESOTERIC_DAMAGE_BUFF := 1.3
const WARD_RESTORE_PER_CAST := 0.08   # share of max Ward
const MIN_UNLEASH_COPIES := 2
const UNLEASH_SPREAD_DEG := 8.0
const UNLEASH_TARGET_SPACING := 2.5

const BOLT_MOTION_VALUE := 1.0
const WAND_BOLT_COOLDOWN := 0.45  # 2026-10-08: was 0.35, slowed with the other non-gun weapons
const MANA_STAR_MOTION_VALUE := 1.0
const MANA_STAR_COOLDOWN := 0.25
const MANA_STAR_MANA_COST := 4.0
const PROJECTILE_SPEED := 30.0
const PROJECTILE_SCENE := preload("res://entities/projectile/Projectile.tscn")
const PUNCH_MOTION_VALUE := 1.2
const REACH_STRIKE_MOTION_VALUE := 1.3
const REACH_STRIKE_SHAPE := {"reach": 4.2, "half_angle": 14.0, "splash": 0.6, "max_targets": 2}

## Sands of Time (Mythic): its stance is Time Stop instead.
const TIME_STOP_UNIQUE := "sands_of_time"

var _player: Player
var _bolt_cooldown: float = 0.0
## Time msec when Time Stop is ready again.
var _time_stop_ready_msec: int = 0

func _ready() -> void:
	_player = get_parent()

func _physics_process(delta: float) -> void:
	_bolt_cooldown = maxf(_bolt_cooldown - delta, 0.0)

## The conduit whose stance the current page uses, or null.
func get_source() -> Weapon:
	var main := _player.equipment.primary_weapon if _player.equipment else null
	var off := _player.equipment.offhand as Weapon if _player.equipment else null
	var main_conduit := main if main and main.is_conduit and not main.is_offhand and main.conduit_stance_type != "passive" else null
	var off_conduit := off if off and off.is_conduit and off.conduit_stance_type != "passive" else null
	if _player.weapon_stance.active_page == WeaponStance.StancePage.B and off_conduit:
		return off_conduit
	return main_conduit

func is_active() -> bool:
	return _player.weapon_stance.is_active and get_source() != null

func get_kind() -> String:
	var source := get_source()
	if source and source.unique_id == TIME_STOP_UNIQUE:
		return "time_stop"
	return source.conduit_stance_type if source else ""

## The 1-4 keys cast the stance page.
func uses_spell_page() -> bool:
	return is_active() and get_kind() == "spell_library"

func _damage_type(weapon: Weapon) -> Constants.DamageType:
	return weapon.get_damage_type()

## What a cast in the current stance really casts: a copy of the spell
## carrying the stance's changes, how many copies fly, and whether to
## restore Ward. {"error": reason} when the stance page refuses the spell.
func prepare_cast(ability: Ability, from_spell_page: bool) -> Dictionary:
	var plan := {"ability": ability, "copies": 1, "ward_restore": false}
	var source := get_source() if is_active() else null
	if source == null:
		return plan
	var cast := ability.duplicate() as Ability
	var statuses: Array[String] = ability.applies_status_effects.duplicate()
	if from_spell_page:
		if PAGE_TAG_CATEGORY.has(source.spell_page_tag) and Constants.DAMAGE_TYPE_CATEGORY.get(ability.damage_type) != PAGE_TAG_CATEGORY[source.spell_page_tag]:
			return {"error": "Stance page takes %s spells" % source.spell_page_tag.capitalize()}
		match source.spell_page_modifier:
			"double_status":
				statuses.append_array(ability.applies_status_effects)
			"enhanced_status":
				statuses.assign(statuses.map(func(id): return "enhanced:" + id))
			"pallid":
				if not statuses.has("pallid"):
					statuses.append("pallid")
				cast.guaranteed_statuses = ["pallid"]
	cast.applies_status_effects = statuses
	match source.conduit_stance_type:
		"unleash":
			if ability.unleashable:
				plan["copies"] = maxi(source.unleash_copy_count, MIN_UNLEASH_COPIES)
		"stance_buff":
			match source.stance_buff:
				"spell_damage":
					cast.extra_more *= SPELL_DAMAGE_BUFF
				"esoteric_damage":
					if Constants.DAMAGE_TYPE_CATEGORY.get(ability.damage_type) == Constants.DamageCategory.ESOTERIC:
						cast.extra_more *= ESOTERIC_DAMAGE_BUFF
				"ward_restore":
					plan["ward_restore"] = true
	plan["ability"] = cast
	return plan

func restore_ward_for_cast() -> void:
	_player.ward.restore(_player.ward.max_ward * WARD_RESTORE_PER_CAST)

## Unleash copy i of n: yaw offset for aimed spells, position offset for targeted ones.
func unleash_offset(index: int, count: int) -> float:
	return index - (count - 1) / 2.0

## LMB outside stance. True when handled (a Wand's energy bolt).
const WAND_SLING_WINDUP := 0.06
const WAND_SLING_STRIKE := 0.07
const WAND_SLING_RECOVERY := 0.2

func try_primary_attack() -> bool:
	var weapon := _player.get_active_weapon()
	if weapon == null or weapon.weapon_type != "Wand":
		return false
	if _bolt_cooldown <= 0.0:
		_bolt_cooldown = WAND_BOLT_COOLDOWN / _player.get_action_speed_multiplier()
		_fire_bolt(weapon, BOLT_MOTION_VALUE)
		if _player.arm_rig:
			_player.arm_rig.play_attack(PlayerArmRig.Attack.FIRE, WAND_SLING_WINDUP, WAND_SLING_STRIKE, WAND_SLING_RECOVERY)
	return true

## LMB in a conduit stance. True when handled.
func try_stance_attack() -> bool:
	if not is_active():
		return false
	var source := get_source()
	var weapon := _player.get_active_weapon()
	match source.conduit_stance_type:
		"mana_stars":
			_fire_mana_star(source)
			return true
		"battlemage":
			if source.weapon_type == "Spell Gauntlet" and _player.melee_attack.is_idle():
				_player.melee_attack.release_stance_attack({
					"kind": PlayerArmRig.Attack.LIGHT,
					"motion_mult": PUNCH_MOTION_VALUE,
					"on_hit": _mana_star_follow_up.bind(source),
				})
				return true
	return weapon != null and weapon.weapon_type == "Wand" and try_primary_attack()

## Sands of Time: entering stance stops time, if it's off cooldown.
func try_time_stop() -> bool:
	var now := Time.get_ticks_msec()
	if now < _time_stop_ready_msec:
		EventBus.stance_on_cooldown.emit(_player, (_time_stop_ready_msec - now) / 1000.0)
		return false
	if TimeStop.is_running():
		return false
	_time_stop_ready_msec = now + int(TimeStop.COOLDOWN * 1000.0)
	TimeStop.start(get_tree())
	return true

## Battlemage Staff: entering stance (RMB) is a reach strike.
func on_stance_entered() -> void:
	var source := get_source()
	if get_kind() == "time_stop":
		try_time_stop()
		return
	if source and source.conduit_stance_type == "battlemage" and source.weapon_type == "Staff" and _player.melee_attack.is_idle():
		_player.melee_attack.release_stance_attack({
			"kind": PlayerArmRig.Attack.HEAVY,
			"motion_mult": REACH_STRIKE_MOTION_VALUE,
			"shape": REACH_STRIKE_SHAPE,
		})

func _fire_mana_star(weapon: Weapon) -> void:
	if _bolt_cooldown > 0.0:
		return
	if _player.mana.current_mana < MANA_STAR_MANA_COST:
		EventBus.ability_cast_failed.emit(_player, null, "Not enough Mana")
		return
	_player.mana.spend(MANA_STAR_MANA_COST)
	_bolt_cooldown = MANA_STAR_COOLDOWN / _player.get_action_speed_multiplier()
	_fire_bolt(weapon, MANA_STAR_MOTION_VALUE)

## A punch that lands sends a free Mana Star at the same target.
func _mana_star_follow_up(target: Enemy, _damage: float, weapon: Weapon) -> void:
	if is_instance_valid(target):
		_fire_bolt(weapon, MANA_STAR_MOTION_VALUE, target.global_position + Vector3.UP)

## Wand bolts and Mana Stars: the weapon's damage and infusion, scaled by
## Spell Power (Intellect) - v3.4 "Mana Stars scale with Spell Power".
func _fire_bolt(weapon: Weapon, motion_value: float, aim_at: Variant = null) -> void:
	var hit := weapon.roll_damage(motion_value, _player.stat_sheet)
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = hit["final_damage"] * (1.0 + _player.stat_sheet.get_spell_power_from_stats())
	projectile.is_critical = hit["is_critical"]
	projectile.damage_type = _damage_type(weapon)
	projectile.source = _player
	projectile.speed = PROJECTILE_SPEED
	_player.get_tree().current_scene.add_child(projectile)
	var xform: Transform3D = _player.weapon_socket.global_transform
	if aim_at is Vector3:
		xform = xform.looking_at(aim_at, Vector3.UP)
	projectile.global_transform = xform
	AudioManager.play_at(SoundLib.get_fire_sound(Constants.AmmoType.ARROW), _player.global_position)
