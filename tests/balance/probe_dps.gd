extends Node
## Prints sustained single-target DPS for the strongest base of every
## weapon type, using the game's own damage and timing numbers.
## Run: Godot --headless --path . res://tests/balance/probe_dps.tscn --quit-after 600

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var sheet: StatSheet = (load("res://data/stats/instances/player_baseline.tres") as StatSheet).duplicate(true)
	var best := {}
	for f in DirAccess.get_files_at("res://data/weapons/instances/"):
		f = f.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var w := load("res://data/weapons/instances/" + f) as Weapon
		if w == null or w.is_conduit:
			continue
		var avg := (w.base_damage_min + w.base_damage_max) / 2.0
		var cur: Weapon = best.get(w.weapon_type)
		if cur == null or avg > (cur.base_damage_min + cur.base_damage_max) / 2.0:
			best[w.weapon_type] = w
	var rows := []
	for t in best:
		var w: Weapon = best[t]
		var dps := 0.0
		var note := ""
		if w.is_ranged:
			var interval := PlayerRangedAttack.BASE_FIRE_COOLDOWN
			if w.fire_mode == Constants.FireMode.FULL_AUTO and w.fire_rate > 0.0:
				interval = 1.0 / w.fire_rate
			interval = maxf(interval, maxf(w.cycle_time, w.get_draw_time()))
			var per_shot := w.predict_damage(1.0, sheet)
			var mag := w.magazine_size if w.magazine_size > 0 else 1000000
			var reload := w.reload_time * (mag if w.reload_per_shell else 1) if w.magazine_size > 0 else 0.0
			if w.reload_per_shell:
				reload = w.cycle_time * mag
			dps = per_shot * mag / (mag * interval + reload)
			note = "shot %.1f every %.2fs mag %d reload %.1f (aimed x%.1f)" % [per_shot, interval, w.magazine_size, reload, PlayerRangedAttack.AIMED_DAMAGE_MULTIPLIER]
		else:
			var mv: float = PlayerMeleeAttack.WEAPON_TYPE_MOTION_VALUE.get(t, 1.0)
			var swing := PlayerMeleeAttack.swing_seconds(t)
			var jab := w.predict_damage(mv * PlayerMeleeAttack.JAB_MOTION_VALUE_MULTIPLIER, sheet) / (swing * PlayerMeleeAttack.JAB_DURATION_MULTIPLIER)
			var thrust := w.predict_damage(mv, sheet) / swing
			dps = maxf(jab, thrust)
			note = "hit %.1f swing %.2fs" % [w.predict_damage(mv, sheet), swing]
		rows.append([dps, "%-22s %-8s DPS %7.1f  %s" % [t, "ranged" if w.is_ranged else "melee", dps, note]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		print(r[1])
	get_tree().quit()
