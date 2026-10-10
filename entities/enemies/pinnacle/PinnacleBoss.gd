extends Enemy
class_name PinnacleBoss
## Base for the Pinnacle bosses (PinnacleArena): three phases at 66% and 33%
## health run by a BossBrain built from abilities(), extra health, and a
## guaranteed Unique on death on top of the usual Boss loot rolls.

const HEALTH_MULTIPLIER := 3.0
const PHASE_THRESHOLDS: Array[float] = [0.66, 0.33]
## Chance the guaranteed drop is a Mythic instead of a Unique.
const MYTHIC_CHANCE := 0.1
## Pinnacle.BOSSES id, set by PinnacleArena; its own uniques join the reward pool.
var pinnacle_id: String = ""

func _ready() -> void:
	super._ready()
	health.max_health *= HEALTH_MULTIPLIER
	health.current_health = health.max_health
	var brain := BossBrain.new()
	brain.name = "BossBrain"
	for fields in abilities():
		brain.abilities.append(BossAbility.make(fields))
	brain.phase_thresholds = PHASE_THRESHOLDS
	brain.phase_openers = phase_openers()
	add_child(brain)

## BossAbility field dictionaries; overridden per boss.
func abilities() -> Array:
	return []

## Phase number -> opening ability id; overridden per boss.
func phase_openers() -> Dictionary:
	return {}

func _on_died() -> void:
	if pinnacle_id != "":
		GameState.pinnacle_clears[pinnacle_id] = int(GameState.pinnacle_clears.get(pinnacle_id, 0)) + 1
	var rarity := Constants.ItemRarity.MYTHIC if randf() < MYTHIC_CHANCE else Constants.ItemRarity.UNIQUE
	var reward := UniqueRoller.roll(rarity, _compute_item_level(), pinnacle_id)
	if reward:
		_spawn_pickup(reward)
	super._on_died()
