extends Enemy
class_name FigmentBoss
## User request: "figure out how to add bosses to each Figment to
## 'complete' a figment." No boss design exists anywhere in this project
## (Section 24 lists "Boss design philosophy" as explicitly not designed
## in the doc either) - this is a from-scratch, invented first pass: a
## much larger/tankier/harder-hitting HeavyHitter, spawned in the Vault's
## platform slot (see GeneratedMap.gd - the Vault is already the one
## guaranteed "real risk/reward set-piece" room per Map, so it's the
## natural, zero-extra-plumbing home for the one guaranteed Boss too),
## whose death fires EventBus.figment_completed - the signal
## GameState._on_figment_completed() listens to for Figment Tree points
## (see systems/figment_tree/ - scaffolding only, not a full system yet).
##
## Not a 4th Trinity Rule archetype (Fast/Lethal/Tanky combination) -
## bosses are explicitly exempt from that rule in most ARPGs this project
## draws from, and Section 21 doesn't weigh in on bosses at all.

const HEALTH_MULTIPLIER := 8.0    # relative to a HeavyHitter's 220
const DAMAGE_MULTIPLIER := 2.2    # relative to a HeavyHitter's MeleeAttack damage_amount
const REWARD_MULTIPLIER := 10.0   # relative to a HeavyHitter's xp/gold_reward

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.HEAVY_HITTER  # closest fit - Lethal + Tanky, taken to an extreme
	move_speed = 1.4
	stop_distance = 2.6
	health.max_health = 220.0 * HEALTH_MULTIPLIER
	xp_reward = 25.0 * REWARD_MULTIPLIER
	gold_reward = int(12 * REWARD_MULTIPLIER)
	_set_placeholder_color(Color(0.25, 0.04, 0.35))  # deep violet-black - reads as "not a normal enemy" at a glance

	var melee: EnemyMeleeAttack = get_node_or_null("MeleeAttack")
	if melee:
		melee.damage_amount *= DAMAGE_MULTIPLIER

## Figment "completion" - fires before the base class's own cleanup
## (xp/gold/loot drop, queue_free()) so the event lands while
## GameState.active_map (the completed Figment) is still whatever it was
## during this fight.
func _on_died() -> void:
	EventBus.figment_completed.emit(GameState.active_map)
	super._on_died()
