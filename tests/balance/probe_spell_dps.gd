extends Node
## Prints each damaging spell's hit, casting rhythm, single-target DPS and
## Mana per second at levels 1, 10 and 20 for the baseline character (no
## gear, no web points), to compare with tests/balance/probe_dps.tscn.
## Fields and pools that tick (Black Hole, Flame Wall...) are shown per hit,
## so their DPS here is a floor. Area spells hit everything in range.
## Run: Godot --headless --path . res://tests/balance/probe_spell_dps.tscn --quit-after 600

const DIR := "res://data/abilities/instances/"
const LEVELS := [1, 10, 20]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var sheet: StatSheet = (load("res://data/stats/instances/player_baseline.tres") as StatSheet).duplicate(true)
	var rows := []
	for f in DirAccess.get_files_at(DIR):
		f = f.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var a := (load(DIR + f) as Ability).duplicate() as Ability
		if not a.deals_damage():
			continue
		var line := "%-20s" % a.display_name
		var top := 0.0
		for level in LEVELS:
			a.level = level
			var r := a.predict_damage_range(sheet)
			var hit := (r.x + r.y) * 0.5
			var interval := maxf(a.get_cast_time(sheet) + a.base_recovery_time, a.cooldown_seconds)
			var dps := hit / maxf(interval, 0.05)
			var mana := a.get_mana_cost(sheet) / maxf(interval, 0.05)
			line += "  L%-2d hit %6.0f  dps %6.0f  mana/s %5.1f" % [level, hit, dps, mana]
			top = dps
		line += "  %s" % ("area" if a.has_tag(Ability.TAG_AREA) else "")
		rows.append([top, line])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	for r in rows:
		print(r[1])
	get_tree().quit()
