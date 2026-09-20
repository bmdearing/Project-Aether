extends Node
## Writes Implementation Brief v4.2's ammo/fire-mode table onto every ranged
## weapon .tres in data/weapons/instances/, matched on `weapon_type`.
## Plain text edit (append/replace property lines) rather than load-and-
## resave, so the rest of each file is untouched. Idempotent - re-running
## replaces the managed lines.
## Run: Godot --headless --path . res://tools/apply_ranged_weapon_stats.tscn --quit-after 5

const DIR := "res://data/weapons/instances/"
const TABLE := Weapon.RANGED_PROFILES
const MANAGED_KEYS := ["ammo_type", "magazine_size", "fire_mode", "pellet_count", "pellet_spread_degrees", "fire_rate", "cycle_time", "reload_time", "reload_per_shell"]

func _ready() -> void:
	call_deferred("_run")

func _fmt(v: float) -> String:
	var s := "%.2f" % v
	return s.rstrip("0").rstrip(".") if "." in s else s

func _run() -> void:
	var updated := 0
	var skipped: Array[String] = []
	var per_type := {}
	for file_name in DirAccess.get_files_at(DIR):
		if not file_name.ends_with(".tres"):
			continue
		var path := DIR + file_name
		var text := FileAccess.get_file_as_string(path)
		if not "is_ranged = true" in text:
			continue
		var weapon_type := ""
		for line in text.split("\n"):
			if line.begins_with("weapon_type = "):
				weapon_type = line.trim_prefix("weapon_type = ").strip_edges().trim_prefix("\"").trim_suffix("\"")
		if not TABLE.has(weapon_type):
			skipped.append("%s (%s)" % [file_name, weapon_type])
			continue
		var row: Array = TABLE[weapon_type]
		var kept: Array[String] = []
		for line in text.split("\n"):
			var is_managed := false
			for key in MANAGED_KEYS:
				if line.begins_with(key + " = "):
					is_managed = true
			if not is_managed:
				kept.append(line)
		while not kept.is_empty() and kept[-1].strip_edges() == "":
			kept.pop_back()
		kept.append("ammo_type = %d" % row[0])
		kept.append("magazine_size = %d" % row[1])
		kept.append("fire_mode = %d" % row[2])
		kept.append("pellet_count = %d" % row[3])
		kept.append("pellet_spread_degrees = %s" % _fmt(row[4]))
		kept.append("fire_rate = %s" % _fmt(row[5]))
		kept.append("cycle_time = %s" % _fmt(row[6]))
		kept.append("reload_time = %s" % _fmt(row[7]))
		kept.append("reload_per_shell = %s" % ("true" if row[8] else "false"))
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string("\n".join(kept) + "\n")
		out.close()
		updated += 1
		per_type[weapon_type] = per_type.get(weapon_type, 0) + 1
	print("updated ", updated, " ranged weapon files: ", per_type)
	print("skipped (ranged, weapon_type not in table): ", skipped)
	get_tree().quit()
