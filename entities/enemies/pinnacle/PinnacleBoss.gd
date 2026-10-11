extends Enemy
class_name PinnacleBoss
## Base for the Pinnacle bosses (PinnacleArena): three phases at 66% and 33%
## health run by a BossBrain built from abilities(), extra health, the usual
## Boss loot rolls, and a chance at each of its own exclusive uniques
## (UniqueCatalog "boss" + "boss_chance").

const HEALTH_MULTIPLIER := 3.0
const PHASE_THRESHOLDS: Array[float] = [0.66, 0.33]
## Ward refills over ~4s once the boss goes this long without being hit.
const WARD_REGEN_DELAY := 4.0
const WARD_REGEN_PERCENT_PER_SECOND := 0.25
## Pinnacle.BOSSES id, set by PinnacleArena; its own uniques join the reward pool.
var pinnacle_id: String = ""

func _ready() -> void:
	super._ready()
	health.max_health *= HEALTH_MULTIPLIER
	health.current_health = health.max_health
	_reset_ward()
	var brain := BossBrain.new()
	brain.name = "BossBrain"
	for fields in abilities():
		brain.abilities.append(BossAbility.make(fields))
	brain.phase_thresholds = phase_thresholds()
	brain.phase_openers = phase_openers()
	add_child(brain)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if health.is_alive():
		regen_ward_if_idle(WARD_REGEN_DELAY, WARD_REGEN_PERCENT_PER_SECOND, delta)

## Health fractions that start each next phase; overridden per boss.
func phase_thresholds() -> Array[float]:
	return PHASE_THRESHOLDS

## BossAbility field dictionaries; overridden per boss.
func abilities() -> Array:
	return []

## Phase number -> opening ability id; overridden per boss.
func phase_openers() -> Dictionary:
	return {}

func _on_died() -> void:
	if pinnacle_id != "":
		GameState.pinnacle_clears[pinnacle_id] = int(GameState.pinnacle_clears.get(pinnacle_id, 0)) + 1
	for def in UniqueCatalog.DEFS:
		if pinnacle_id != "" and def.get("boss", "") == pinnacle_id and randf() < float(def.get("boss_chance", 0.0)):
			var reward := UniqueRoller.build(def, _compute_item_level())
			if reward:
				_spawn_pickup(reward)
	super._on_died()
