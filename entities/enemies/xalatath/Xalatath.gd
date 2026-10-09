extends PinnacleBoss
class_name Xalatath
## Second Pinnacle boss, shown as "Herald of the Maw" (a placeholder: the
## model and ids are Xalatath's, which is Blizzard's and must be replaced).
## Entropic. Melee within reach, Entropic bolts beyond it. Fought in the
## MawArena (PinnacleArena builds it for her): a round floor over the void
## with four Anchor pylons.
##   Phase 1: Void Rift pools crack the floor when they run out; Shadow Lunge
##   (running into a pylon stuns her).
##   Phase 2 (66%): Mindbenders go for the pylons and shatter them;
##   Entropic Volley.
##   Phase 3 (33%): the Maw opens under the dais. Unmaking drags you to its
##   lip for a slam unless a pylon anchors you; Collapse rains blasts.
## Pylons still standing when she dies raise her Lens drop chance.

const DISPLAY_NAME := "Herald of the Maw"
const BOLT_RANGE := 20.0
const BOLT_MIN_RANGE := 5.0
const BOLT_COOLDOWN := 2.8
const LUNGE_STUN_SEC := 2.0

var _arena: MawArena

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.fire_range = BOLT_RANGE
		ranged.min_range = BOLT_MIN_RANGE
		ranged.cooldown_duration = BOLT_COOLDOWN

func abilities() -> Array:
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "void_rift", "display_name": "Void Rift", "kind": BossAbility.Kind.HAZARD, "cooldown": 9.0, "telegraph": 1.0, "radius": 3.5, "duration": 7.0, "damage_mult": 1.0, "damage_type": entropic},
		{"id": "shadow_lunge", "display_name": "Shadow Lunge", "kind": BossAbility.Kind.CHARGE, "cooldown": 8.0, "telegraph": 0.9, "damage_mult": 1.5, "min_range": 5.0, "max_range": 16.0, "damage_type": entropic},
		{"id": "call_the_hollow", "display_name": "Call the Hollow", "kind": BossAbility.Kind.SUMMON, "cooldown": 30.0, "telegraph": 1.2, "count": 2, "unit_id": "veilborne_mindbender", "min_phase": 2},
		{"id": "entropic_volley", "display_name": "Entropic Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 8.0, "telegraph": 0.9, "count": 7, "spread_degrees": 70.0, "damage_mult": 0.8, "min_range": 4.0, "max_range": 24.0, "min_phase": 2, "damage_type": entropic},
		{"id": "unmaking", "display_name": "Unmaking", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.1, "radius": MawArena.MAW_RADIUS + 3.5, "pull_stop": MawArena.MAW_RADIUS + 1.5, "damage_mult": 2.0, "max_range": MawArena.OUTER_RADIUS + 4.0, "min_phase": 3, "damage_type": entropic},
		{"id": "collapse", "display_name": "Collapse", "kind": BossAbility.Kind.BLAST, "cooldown": 12.0, "telegraph": 1.2, "radius": 3.0, "count": 5, "damage_mult": 1.3, "max_range": 24.0, "min_phase": 3, "damage_type": entropic},
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
	return true

## Her Mindbenders go for the pylons while any stand.
func on_unit_summoned(unit: Enemy) -> void:
	var a := arena()
	if a == null or a.pylons_standing() == 0:
		return
	var channel := MawChannel.new()
	channel.arena = a
	unit.add_child(channel)

func _on_died() -> void:
	var a := arena()
	if randf() < Pinnacle.maw_lens_chance(a.pylons_standing() if a else 0):
		var lens := Pinnacle.make_maw_lens(_compute_item_level())
		if lens:
			_spawn_pickup(lens)
	super._on_died()
