extends RefCounted
class_name BossAbility
## One boss ability, as data. BossBrain picks a ready one in range and runs
## it by kind; every kind telegraphs on the ground (BossTelegraph) first.
##   SLAM   - circle around the boss.
##   BLAST  - circle on the player's spot; `count` > 1 drops more around them.
##   HAZARD - circle on the player's spot that stays and burns for `duration`.
##   CHARGE - strip toward the player, then the boss rushes along it.
##   VOLLEY - a fan of `count` projectiles at the player.
##   SUMMON - `count` roster units (`unit_id`) around the boss.
##   PULL   - drags the player in, then slams around the boss (or the
##            boss's Enemy.get_pull_center()).
## Damage is the boss's own attack damage times `damage_mult`; damage_type -1
## asks the boss (Enemy.get_ability_damage_type(), e.g. the Lord's element).

enum Kind { SLAM, BLAST, HAZARD, CHARGE, VOLLEY, SUMMON, PULL }

var id: String = ""
var display_name: String = ""
var kind: Kind = Kind.SLAM
var cooldown: float = 8.0
var telegraph: float = 1.2
var radius: float = 4.0
var damage_mult: float = 1.5
var damage_type: int = -1
var count: int = 1
var spread_degrees: float = 40.0
var duration: float = 5.0
var min_range: float = 0.0
var max_range: float = 20.0
var min_phase: int = 1
## Status effect id applied to the player on a hit ("chill", "pallid"...).
var status: String = ""
var unit_id: String = ""
var weight: float = 1.0
## PULL: how far from the pull's centre the player stops.
var pull_stop: float = BossBrain.PULL_STOP_DISTANCE

static func make(fields: Dictionary) -> BossAbility:
	var a := BossAbility.new()
	for key in fields:
		a.set(key, fields[key])
	if a.display_name == "":
		a.display_name = a.id.capitalize()
	return a
