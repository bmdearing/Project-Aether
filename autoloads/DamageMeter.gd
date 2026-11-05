extends Node
## Damage done to enemies on the current map, by source (spell, weapon,
## ailment, minion) and by enemy type. Starts over when a map loads
## (GeneratedMap calls start_map()); shown on the Damage tab (DamageMeterScreen).
##
## Sources: an emit site sets `label` just before EventBus.damage_dealt so the
## hit is credited to the right spell or weapon. Hits without one fall back
## to the source node's kind.

## Credit for the next damage_dealt; consumed (cleared) by it.
var label: String = ""

var map_name: String = ""
var total: float = 0.0
var hits: int = 0
## label -> total damage
var by_source: Dictionary = {}
## label -> {"hits", "crits", "max_hit", "max_crit", "burst"}
var source_stats: Dictionary = {}
## The biggest single hit on the map, and what dealt it.
var top_hit: float = 0.0
var top_hit_source: String = ""
## Most damage dealt inside any BURST_WINDOW seconds.
var burst: float = 0.0
const BURST_WINDOW := 3.0
var _window: Array = []  # [[msec, amount, label], ...] inside the last BURST_WINDOW
var _source_window: Dictionary = {}  # label -> running total inside _window
## enemy type -> {label -> total damage}
var by_enemy: Dictionary = {}
## enemy type -> total damage
var enemy_totals: Dictionary = {}
var _started_msec: int = 0
var _last_hit_msec: int = 0

func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)

func start_map(display_name: String) -> void:
	map_name = display_name
	total = 0.0
	hits = 0
	by_source.clear()
	source_stats.clear()
	top_hit = 0.0
	top_hit_source = ""
	burst = 0.0
	_window.clear()
	_source_window.clear()
	by_enemy.clear()
	enemy_totals.clear()
	_started_msec = Time.get_ticks_msec()
	_last_hit_msec = _started_msec

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, _more: bool, is_critical: bool) -> void:
	var credit := label
	label = ""
	if not (target is Enemy) or amount <= 0.0:
		return
	if credit == "":
		credit = _fallback_label(source, damage_type)
	var enemy := target as Enemy
	var kind := enemy.definition.display_name if enemy.definition and enemy.definition.display_name != "" else enemy.display_name
	if kind == "":
		kind = "Unknown"
	total += amount
	hits += 1
	by_source[credit] = float(by_source.get(credit, 0.0)) + amount
	if not by_enemy.has(kind):
		by_enemy[kind] = {}
	by_enemy[kind][credit] = float(by_enemy[kind].get(credit, 0.0)) + amount
	enemy_totals[kind] = float(enemy_totals.get(kind, 0.0)) + amount
	_record_hit(credit, amount, is_critical, StatusEffectComponent.emitting_dot)
	_last_hit_msec = Time.get_ticks_msec()

func _fallback_label(source: Node, damage_type: int) -> String:
	if source is Player:
		var weapon := (source as Player).get_active_weapon()
		return weapon.display_name if weapon else "Unarmed"
	if source != null and source.is_in_group("minion"):
		return "Minions"
	return "%s damage" % Constants.DAMAGE_TYPE_NAME.get(damage_type, "Other")

## Seconds from the map's start to the last hit (the meter stops counting
## while nothing is being hit after that).
func elapsed() -> float:
	return maxf((_last_hit_msec - _started_msec) / 1000.0, 1.0)

func dps() -> float:
	return total / elapsed()

## [[label, amount], ...] highest first.
static func sorted(totals: Dictionary) -> Array:
	var rows := []
	for k in totals:
		rows.append([k, float(totals[k])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows

## Per-source hit stats and the burst windows. Ailment ticks are batched
## reports, not hits, so they add to Total and Burst but not Hit/Crit.
func _record_hit(credit: String, amount: float, is_critical: bool, is_tick: bool) -> void:
	if not source_stats.has(credit):
		source_stats[credit] = {"hits": 0, "crits": 0, "max_hit": 0.0, "max_crit": 0.0, "burst": 0.0}
	var s: Dictionary = source_stats[credit]
	s["hits"] += 1
	if not is_tick:
		if is_critical:
			s["crits"] += 1
			s["max_crit"] = maxf(s["max_crit"], amount)
		else:
			s["max_hit"] = maxf(s["max_hit"], amount)
		if amount > top_hit:
			top_hit = amount
			top_hit_source = credit
	var now := Time.get_ticks_msec()
	_window.append([now, amount, credit])
	_source_window[credit] = float(_source_window.get(credit, 0.0)) + amount
	while not _window.is_empty() and now - int(_window[0][0]) > BURST_WINDOW * 1000.0:
		var old: Array = _window.pop_front()
		_source_window[old[2]] = float(_source_window[old[2]]) - float(old[1])
	var in_window := 0.0
	for k in _source_window:
		in_window += float(_source_window[k])
	burst = maxf(burst, in_window)
	s["burst"] = maxf(s["burst"], float(_source_window[credit]))

## Damage over the last few seconds, for the HUD recap's live number.
func recent_dps() -> float:
	var now := Time.get_ticks_msec()
	var sum := 0.0
	for e in _window:
		if now - int(e[0]) <= BURST_WINDOW * 1000.0:
			sum += float(e[1])
	return sum / BURST_WINDOW
