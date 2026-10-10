extends PinnacleBoss
class_name Xalatath
## Second Pinnacle boss, shown as "Herald of the Maw" (a placeholder: the
## model and ids are Xalatath's, which is Blizzard's and must be replaced).
## Entropic. Melee within reach, Entropic bolts beyond it. Fought in the
## MawArena (PinnacleArena builds it for her): a round floor over the void
## with four Anchor pylons.
##   Phase 1: Void Rift pools crack the floor when they run out; Shadow Lunge.
##   Luring the Lunge into a pylon stuns her, drains her Composure and opens
##   a Riposte window.
##   Phase 2 (66%): Mindbenders go for the pylons and shatter them;
##   Entropic Volley. Every pylon you save anchors you against Unmaking,
##   stays a stun wall, raises her Lens chance and weakens the Maw's opening.
##   Phase 3 (33%): the Maw opens under the dais. Unmaking drags you to its
##   lip for a slam unless a pylon anchors you; Collapse rains blasts; Feed
##   the Maw: she channels at the lip for a bigger, faster bite unless you
##   hit her hard enough to break it.
## The floor works against her too: a Riposte or a heavy Explosive hit knocks
## her back, and with no plate behind her she clings to the lip and the Maw
## drags at her (a big damage window, MawArena.cling()).

const DISPLAY_NAME := "Herald of the Maw"
const BOLT_RANGE := 20.0
const BOLT_MIN_RANGE := 5.0
const BOLT_COOLDOWN := 2.8
const LUNGE_STUN_SEC := 2.0
const LUNGE_STANCE_DAMAGE := 60.0
## Knockback: a heavy Explosive hit is at least this share of her max Life.
const HEAVY_EXPLOSIVE_SHARE := 0.015
const KNOCKBACK_DISTANCE := 3.5
## Feed the Maw: damage (share of max Life) that breaks the channel.
const FEED_BREAK_SHARE := 0.04
const FEED_CHANNEL_SEC := 3.5
const FEED_STANCE_DAMAGE := 50.0

var feeding := false
var _feed_damage := 0.0

var _arena: MawArena

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.fire_range = BOLT_RANGE
		ranged.min_range = BOLT_MIN_RANGE
		ranged.cooldown_duration = BOLT_COOLDOWN
	EventBus.riposte_executed.connect(_on_riposte)
	if boss_brain:
		boss_brain.phase_changed.connect(_on_phase)
	EventBus.damage_dealt.connect(_on_damage_dealt)

func abilities() -> Array:
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "void_rift", "display_name": "Void Rift", "kind": BossAbility.Kind.HAZARD, "cooldown": 9.0, "telegraph": 1.0, "radius": 3.5, "duration": 7.0, "damage_mult": 1.0, "damage_type": entropic},
		{"id": "shadow_lunge", "display_name": "Shadow Lunge", "kind": BossAbility.Kind.CHARGE, "cooldown": 8.0, "telegraph": 0.9, "damage_mult": 1.5, "min_range": 5.0, "max_range": 16.0, "damage_type": entropic},
		{"id": "call_the_hollow", "display_name": "Call the Hollow", "kind": BossAbility.Kind.SUMMON, "cooldown": 30.0, "telegraph": 1.2, "count": 2, "unit_id": "veilborne_mindbender", "min_phase": 2},
		{"id": "entropic_volley", "display_name": "Entropic Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 8.0, "telegraph": 0.9, "count": 7, "spread_degrees": 70.0, "damage_mult": 0.8, "min_range": 4.0, "max_range": 24.0, "min_phase": 2, "damage_type": entropic},
		{"id": "unmaking", "display_name": "Unmaking", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.1, "radius": MawArena.MAW_RADIUS + 3.5, "pull_stop": MawArena.MAW_RADIUS + 1.5, "damage_mult": 2.0, "max_range": MawArena.OUTER_RADIUS + 4.0, "min_phase": 3, "damage_type": entropic},
		{"id": "collapse", "display_name": "Collapse", "kind": BossAbility.Kind.BLAST, "cooldown": 12.0, "telegraph": 1.2, "radius": 3.0, "count": 5, "damage_mult": 1.3, "max_range": 24.0, "min_phase": 3, "damage_type": entropic},
		{"id": "feed_the_maw", "display_name": "Feed the Maw", "kind": BossAbility.Kind.CUSTOM, "cooldown": 22.0, "telegraph": FEED_CHANNEL_SEC, "max_range": 60.0, "min_phase": 3,
			"description": "She stands at the Maw's lip and feeds it: two plates fall at once and the next bite comes sooner. Hit her hard enough to break the channel."},
	]

func phase_openers() -> Dictionary:
	return {2: "call_the_hollow", 3: "unmaking"}

func arena() -> MawArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("maw_arena") as MawArena
	return _arena

## Unmaking drags you to the open Maw rather than to her.
func get_pull_center() -> Vector3:
	var a := arena()
	return a.maw_center() if a and a.maw_open else super.get_pull_center()

func is_player_anchored(player_node: Player) -> bool:
	var a := arena()
	return a != null and a.is_anchored(player_node.global_position)

## Shadow Lunge into a pylon: she stops dead, stunned.
func blocks_charge(direction: Vector3) -> bool:
	var a := arena()
	if a == null or a.pylon_in_path(global_position, direction, body_radius + 0.4) == null:
		return false
	status_effects.apply_timed_effect("stun", LUNGE_STUN_SEC)
	interrupt_attack()
	# Slammed into the pylon: Composure drained and a Riposte window open.
	if stance:
		stance.apply_parry_damage(LUNGE_STANCE_DAMAGE)
	if composure and not composure.is_broken:
		composure.enter_broken_state()
	return true

## Her Mindbenders go for the pylons while any stand.
func on_unit_summoned(unit: Enemy) -> void:
	var a := arena()
	if a == null or a.pylons_standing() == 0:
		return
	var channel := MawChannel.new()
	channel.arena = a
	unit.add_child(channel)

## Phase 3: every pylon saved weakens the Maw's opening Unmaking.
func _on_phase(p: int) -> void:
	var a := arena()
	var unmaking := boss_brain.find("unmaking") if boss_brain else null
	if p >= 3 and a and unmaking:
		unmaking.damage_mult *= a.opening_strength()

func _on_died() -> void:
	var a := arena()
	if randf() < Pinnacle.maw_lens_chance(a.pylons_standing() if a else 0):
		var lens := Pinnacle.make_maw_lens(_compute_item_level())
		if lens:
			_spawn_pickup(lens)
	super._on_died()

## ---- The floor works against her too --------------------------------------

func _on_riposte(_source: Node, target: Node) -> void:
	if target == self:
		_knock_back()

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, _more: bool, _crit: bool) -> void:
	if target != self or not source is Player:
		return
	if feeding:
		_feed_damage += amount
	if damage_type == Constants.DamageType.EXPLOSIVE and amount >= health.max_health * HEAVY_EXPLOSIVE_SHARE:
		_knock_back()

## Shoved away from the player; over missing floor she clings to the lip.
func _knock_back() -> void:
	var a := arena()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if a == null or player == null or not health.is_alive() or a.is_clinging():
		return
	var away := global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -global_transform.basis.z
	if not a.cling(self, away, KNOCKBACK_DISTANCE):
		# An impulse decays at KNOCKBACK_FRICTION, travelling v^2 / 2f.
		_knockback += away * sqrt(2.0 * KNOCKBACK_FRICTION * KNOCKBACK_DISTANCE)

## While she clings, hits land harder.
func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false, can_evade: bool = false, is_dot: bool = false, ignore_armor: bool = false) -> bool:
	var a := arena()
	if a and a.is_clinging():
		amount *= MawArena.CLING_DAMAGE_TAKEN
	return super.take_damage(amount, damage_type, is_spell, can_evade, is_dot, ignore_armor)

## Phase 3: no ranged pressure while she feeds, and only with the Maw open.
func can_use_ability(a: BossAbility) -> bool:
	if a.id == "feed_the_maw":
		var ar := arena()
		return ar != null and ar.maw_open and not ar.is_clinging()
	return true

func cast_custom(a: BossAbility) -> void:
	if a.id != "feed_the_maw":
		await get_tree().process_frame
		return
	var ar := arena()
	if ar == null:
		return
	var lip := ar.lip_point(global_position)
	var tween := create_tween()
	tween.tween_property(self, "global_position", lip, 0.5)
	await tween.finished
	if not health.is_alive():
		return
	feeding = true
	_feed_damage = 0.0
	begin_attack_telegraph(a.telegraph)
	var targets := ar.mark_feed_targets(a.telegraph)
	var left := a.telegraph
	while left > 0.0 and health.is_alive():
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
		if _feed_damage >= health.max_health * FEED_BREAK_SHARE or status_effects.is_stunned():
			break
	feeding = false
	if not health.is_alive():
		return
	if left > 0.0:
		# Broken: the bite is called off and she reels.
		ar.cancel_feed(targets)
		interrupt_attack()
		if stance:
			stance.apply_parry_damage(FEED_STANCE_DAMAGE)
		status_effects.apply_timed_effect("stun", 1.5)
	else:
		ar.feed(targets)
