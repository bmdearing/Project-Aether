extends Enemy
class_name FigmentBoss
## Invented first-pass Figment boss (no boss design exists in the docs),
## spawned on the Vault's platform by GeneratedMap. Its death fires
## EventBus.figment_completed, which GameState._on_figment_completed() turns
## into Figment Tree points.
##
## Uses the Unchartered Chieftain's model, animations and facing, scaled up.
## Stats are set directly rather than from a definition: a definition's level
## curve would replace this health on every Map (see _apply_map_modifiers()).

const MODEL_SOURCE := preload("res://data/enemies/definitions/unchartered_chieftain.tres")
const BOSS_MODEL_SCALE := 1.5

const BOSS_HEALTH := 1760.0
const BOSS_XP_REWARD := 250.0
const BOSS_GOLD_REWARD := 120

func _ready() -> void:
	super._ready()
	display_name = "Figment Chieftain"
	move_speed = 1.4
	stop_distance = 2.6
	health.max_health = BOSS_HEALTH
	xp_reward = BOSS_XP_REWARD
	gold_reward = BOSS_GOLD_REWARD
	_install_model(MODEL_SOURCE.model_scene, MODEL_SOURCE.animation_set, MODEL_SOURCE.scale_modifier * BOSS_MODEL_SCALE, MODEL_SOURCE.model_yaw_offset)

## Completion fires at the moment of death; the base class then plays the
## death clip before freeing.
func _on_died() -> void:
	EventBus.figment_completed.emit(GameState.active_map)
	super._on_died()
