extends RefCounted
class_name HitCooldown
## Per-enemy hit cooldowns shared by every instance of an effect, so
## overlapping copies (several Spark crawlers, stacked Caltrops fields)
## can't hit the same enemy more often than the interval between them.

const PRUNE_SIZE := 512
const PRUNE_AGE_MSEC := 5000

static var _last_hit: Dictionary = {}  # Vector2i(effect hash, enemy id) -> msec

## True (and starts the cooldown) when `enemy` may take a hit from `effect` now.
static func try_hit(effect: StringName, enemy: Object, interval: float) -> bool:
	var now := Time.get_ticks_msec()
	var key := Vector2i(hash(effect), enemy.get_instance_id())
	if now - int(_last_hit.get(key, -1000000)) < int(interval * 1000.0):
		return false
	_last_hit[key] = now
	if _last_hit.size() > PRUNE_SIZE:
		for k in _last_hit.keys():
			if now - int(_last_hit[k]) > PRUNE_AGE_MSEC:
				_last_hit.erase(k)
	return true
