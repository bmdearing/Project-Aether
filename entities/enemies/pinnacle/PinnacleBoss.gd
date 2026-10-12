extends Enemy
class_name PinnacleBoss
## Base for the Pinnacle bosses (PinnacleArena): three phases at 66% and 33%
## health run by a BossBrain built from abilities(), a fixed baseline Life
## (pinnacle_life(), before Figment mods), the usual
## Boss loot rolls, and a chance at each of its own exclusive uniques
## (UniqueCatalog "boss" + "boss_chance").

const PHASE_THRESHOLDS: Array[float] = [0.66, 0.33]
## Ward refills over ~12.5s once the boss goes this long without being hit.
const WARD_REGEN_DELAY := 8.0
const WARD_REGEN_PERCENT_PER_SECOND := 0.08
## Spells leave from about chest height of the (tall, scaled) model.
const CAST_HEIGHT_SHARE := 0.62
## Pinnacle.BOSSES id, set by PinnacleArena; its own uniques join the reward pool.
var pinnacle_id: String = ""

func _ready() -> void:
	super._ready()
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

## Baseline Life, before Figment and boss mods; each boss sets its own.
func pinnacle_life() -> float:
	return 65_000_000.0

## Pinnacle Life is fixed, not level-scaled.
func _level_scaled_health(_at_level: int) -> float:
	return pinnacle_life()

func get_cast_origin() -> Vector3:
	return global_position + Vector3.UP * body_height * CAST_HEIGHT_SHARE

## Bolts gather at the hand and fly as glowing shots.
func on_ranged_windup(seconds: float) -> void:
	BossFx.charge(self, get_cast_origin(), get_ability_damage_type(), seconds, false)

func on_projectile_fired(projectile: Projectile) -> void:
	BossFx.dress_bolt(projectile, projectile.damage_type)
	BossFx.sound(BossFx.cast_sound(projectile.damage_type), get_cast_origin(), -10.0, 1.3)

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
