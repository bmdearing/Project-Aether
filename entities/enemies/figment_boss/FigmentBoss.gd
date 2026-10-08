extends Enemy
class_name FigmentBoss
## The Figment's boss, spawned on the Vault's platform by GeneratedMap: one
## of PROFILES, picked with the map's seed (so a portal return rebuilds the
## same one). The elite leaders that used to guard the Vault as a pack are
## now its possible bosses. Each has a BossBrain with its own abilities and
## a second phase at half health. Its death fires EventBus.figment_completed
## (Figment Tree points) and drops one Maw Fragment (Pinnacle).
##
## Stats are set directly rather than from a definition: a definition's level
## curve would replace this health on every Map (see _apply_map_modifiers()).

const BOSS_HEALTH := 700.0
const BOSS_HEALTH_GROWTH_PER_TIER := 0.35
const BOSS_XP_REWARD := 250.0
const BOSS_GOLD_REWARD := 120
const PHASE_TWO_AT := 0.5

## Abilities are BossAbility fields (see BossAbility.make()). Kinds:
## SLAM 0, BLAST 1, HAZARD 2, CHARGE 3, VOLLEY 4, SUMMON 5, PULL 6.
const PROFILES := {
	"chieftain": {
		"name": "Figment Chieftain", "definition": "unchartered_chieftain", "scale": 1.5,
		"damage_type": Constants.DamageType.KINETIC, "move_speed": 1.4, "stop_distance": 2.6,
		"opener": "rally",
		"abilities": [
			{"id": "cleaving_leap", "display_name": "Cleaving Leap", "kind": BossAbility.Kind.CHARGE, "cooldown": 9.0, "telegraph": 1.0, "damage_mult": 1.5, "min_range": 5.0, "max_range": 14.0},
			{"id": "war_stomp", "display_name": "War Stomp", "kind": BossAbility.Kind.SLAM, "cooldown": 7.0, "telegraph": 1.1, "radius": 5.0, "damage_mult": 1.3, "max_range": 5.0},
			{"id": "rally", "display_name": "Rally the Raiders", "kind": BossAbility.Kind.SUMMON, "cooldown": 25.0, "telegraph": 1.0, "count": 2, "unit_id": "unchartered_cutthroat", "min_phase": 2},
		],
	},
	"adjudicator": {
		"name": "The Adjudicator", "definition": "directorate_adjudicator", "scale": 1.45,
		"damage_type": Constants.DamageType.KINETIC, "move_speed": 1.3, "stop_distance": 2.6,
		"opener": "verdict",
		"abilities": [
			{"id": "hammer_of_judgement", "display_name": "Hammer of Judgement", "kind": BossAbility.Kind.BLAST, "cooldown": 6.0, "telegraph": 1.2, "radius": 3.0, "damage_mult": 1.6, "max_range": 18.0},
			{"id": "consecrate", "display_name": "Consecrate", "kind": BossAbility.Kind.HAZARD, "cooldown": 11.0, "telegraph": 0.9, "radius": 3.5, "duration": 6.0, "damage_mult": 1.0, "damage_type": Constants.DamageType.FIRE},
			{"id": "verdict", "display_name": "Verdict", "kind": BossAbility.Kind.BLAST, "cooldown": 14.0, "telegraph": 1.3, "radius": 2.5, "count": 4, "damage_mult": 1.3, "min_phase": 2},
		],
	},
	"threshold_knight": {
		"name": "The Threshold Knight", "definition": "legion_threshold_knight", "scale": 1.45,
		"damage_type": Constants.DamageType.PALE, "move_speed": 1.8, "stop_distance": 2.4,
		"opener": "pale_ruin",
		"abilities": [
			{"id": "relentless_charge", "display_name": "Relentless Charge", "kind": BossAbility.Kind.CHARGE, "cooldown": 8.0, "telegraph": 0.9, "damage_mult": 1.4, "min_range": 4.0, "max_range": 16.0, "status": "pallid"},
			{"id": "soul_chains", "display_name": "Soul Chains", "kind": BossAbility.Kind.PULL, "cooldown": 12.0, "telegraph": 1.0, "radius": 4.0, "damage_mult": 1.3, "min_range": 5.0, "max_range": 14.0},
			{"id": "pale_ruin", "display_name": "Pale Ruin", "kind": BossAbility.Kind.SLAM, "cooldown": 12.0, "telegraph": 1.4, "radius": 6.0, "damage_mult": 1.6, "min_phase": 2, "status": "pallid"},
		],
	},
	"exarch": {
		"name": "The Exarch", "definition": "synod_exarch", "scale": 1.4,
		"damage_type": Constants.DamageType.COLD, "move_speed": 1.6, "stop_distance": 8.0, "ranged": true,
		"opener": "blizzard",
		"abilities": [
			{"id": "frost_lance", "display_name": "Frost Lance", "kind": BossAbility.Kind.VOLLEY, "cooldown": 5.0, "telegraph": 0.8, "count": 3, "spread_degrees": 20.0, "damage_mult": 0.9, "min_range": 4.0, "max_range": 22.0},
			{"id": "glacial_spike", "display_name": "Glacial Spike", "kind": BossAbility.Kind.BLAST, "cooldown": 9.0, "telegraph": 1.2, "radius": 2.5, "count": 3, "damage_mult": 1.2, "status": "chill"},
			{"id": "frost_nova", "display_name": "Frost Nova", "kind": BossAbility.Kind.SLAM, "cooldown": 8.0, "telegraph": 1.0, "radius": 5.0, "damage_mult": 1.2, "max_range": 5.0, "status": "chill"},
			{"id": "blizzard", "display_name": "Blizzard", "kind": BossAbility.Kind.HAZARD, "cooldown": 14.0, "telegraph": 1.0, "radius": 4.0, "duration": 7.0, "damage_mult": 1.1, "min_phase": 2, "status": "chill"},
		],
	},
}

## Which PROFILES entry this boss is; empty picks one at random in _ready().
@export var profile_id: String = ""

static func pick_profile_id() -> String:
	var ids := PROFILES.keys()
	return ids[randi() % ids.size()]

func _ready() -> void:
	if profile_id == "" or not PROFILES.has(profile_id):
		profile_id = pick_profile_id()
	super._ready()
	var profile: Dictionary = PROFILES[profile_id]
	var definition_res := EnemyRoster.load_definition(profile["definition"])
	display_name = profile["name"]
	move_speed = profile["move_speed"]
	stop_distance = profile["stop_distance"]
	var tier: int = GameState.active_map.tier if GameState.active_map else 1
	health.max_health = BOSS_HEALTH * (1.0 + BOSS_HEALTH_GROWTH_PER_TIER * (tier - 1))
	health.current_health = health.max_health
	xp_reward = BOSS_XP_REWARD
	gold_reward = BOSS_GOLD_REWARD
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.damage_type = profile["damage_type"]
	if profile.get("ranged", false):
		_add_ranged_attack(profile["damage_type"])
	_install_model(definition_res.model_scene, definition_res.animation_set, definition_res.scale_modifier * profile["scale"], definition_res.model_yaw_offset)
	_add_brain(profile)

func _add_ranged_attack(damage_type: int) -> void:
	var ranged := EnemyRangedAttack.new()
	ranged.name = "RangedAttack"
	ranged.fire_range = 18.0
	ranged.min_range = 3.0
	ranged.windup_duration = 0.9
	ranged.cooldown_duration = 2.2
	ranged.damage_amount = 30.0
	ranged.damage_type = damage_type
	ranged.projectile_speed = 16.0
	add_child(ranged)

func _add_brain(profile: Dictionary) -> void:
	var brain := BossBrain.new()
	brain.name = "BossBrain"
	for fields in profile["abilities"]:
		brain.abilities.append(BossAbility.make(fields))
	brain.phase_thresholds = [PHASE_TWO_AT]
	brain.phase_openers = {2: profile.get("opener", "")}
	add_child(brain)

## Completion fires at the moment of death; the base class then plays the
## death clip before freeing.
func _on_died() -> void:
	EventBus.figment_completed.emit(GameState.active_map)
	_spawn_currency_pickup(Pinnacle.roll_fragment())
	super._on_died()
