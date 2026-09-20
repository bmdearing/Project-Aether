extends Resource
class_name SoundLibrary
## Every SFX slot the game plays, as arrays (random variation) or single
## streams. All start empty - the game runs silently until audio assets are
## dropped into data/sound/sound_library.tres. Played through the
## AudioManager autoload via the SoundLib wrapper.

# Ranged - per ammo type
@export var pistol_fire: Array[AudioStream] = []
@export var revolver_fire: Array[AudioStream] = []
@export var shotgun_fire: Array[AudioStream] = []
@export var rifle_fire: Array[AudioStream] = []
@export var automatic_fire: Array[AudioStream] = []
@export var crossbow_fire: Array[AudioStream] = []
@export var bow_fire: Array[AudioStream] = []
@export var dry_click: AudioStream = null   # trigger pulled on an empty magazine (never the fire sound)

# Reload
@export var pistol_reload: AudioStream = null
@export var revolver_reload: AudioStream = null
@export var shotgun_reload_start: AudioStream = null
@export var shotgun_shell_insert: AudioStream = null
@export var shotgun_reload_finish: AudioStream = null
@export var rifle_reload: AudioStream = null
@export var bolt_cycle: AudioStream = null
@export var lever_cycle: AudioStream = null

# Bullet impacts
@export var impact_flesh: Array[AudioStream] = []
@export var impact_metal: Array[AudioStream] = []
@export var impact_stone: Array[AudioStream] = []
@export var impact_wood: Array[AudioStream] = []

# Bullet whizz (near miss past the player)
@export var bullet_whizz: Array[AudioStream] = []

# Melee
@export var swing_blade: Array[AudioStream] = []
@export var swing_blunt: Array[AudioStream] = []
@export var swing_pierce: Array[AudioStream] = []
@export var hit_flesh: Array[AudioStream] = []
@export var hit_armor: Array[AudioStream] = []
@export var parry: Array[AudioStream] = []
@export var riposte: AudioStream = null

# Player
@export var player_footstep_stone: Array[AudioStream] = []
@export var player_footstep_metal: Array[AudioStream] = []
@export var player_dash: AudioStream = null
@export var player_hurt: Array[AudioStream] = []
@export var player_death: AudioStream = null

# Enemy
@export var enemy_footstep: Array[AudioStream] = []
@export var enemy_attack_grunt: Array[AudioStream] = []
@export var enemy_hurt: Array[AudioStream] = []
@export var enemy_death: Array[AudioStream] = []

# UI/World
@export var item_pickup: AudioStream = null
@export var item_equip: AudioStream = null
@export var brand_use: AudioStream = null
@export var level_up: AudioStream = null

func pick_random(arr: Array[AudioStream]) -> AudioStream:
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]

func get_fire_sound(ammo_type: Constants.AmmoType) -> AudioStream:
	match ammo_type:
		Constants.AmmoType.PISTOL: return pick_random(pistol_fire)
		Constants.AmmoType.REVOLVER: return pick_random(revolver_fire)
		Constants.AmmoType.SHOTGUN: return pick_random(shotgun_fire)
		Constants.AmmoType.RIFLE: return pick_random(rifle_fire)
		Constants.AmmoType.AUTOMATIC: return pick_random(automatic_fire)
		Constants.AmmoType.CROSSBOW_BOLT: return pick_random(crossbow_fire)
		Constants.AmmoType.ARROW: return pick_random(bow_fire)
	return null

func get_reload_sound(ammo_type: Constants.AmmoType) -> AudioStream:
	match ammo_type:
		Constants.AmmoType.PISTOL: return pistol_reload
		Constants.AmmoType.REVOLVER: return revolver_reload
		Constants.AmmoType.SHOTGUN: return shotgun_reload_start
		Constants.AmmoType.RIFLE, Constants.AmmoType.AUTOMATIC: return rifle_reload
	return null

func get_impact_sound(surface: String) -> AudioStream:
	match surface:
		"flesh": return pick_random(impact_flesh)
		"metal": return pick_random(impact_metal)
		"wood": return pick_random(impact_wood)
		_: return pick_random(impact_stone)
