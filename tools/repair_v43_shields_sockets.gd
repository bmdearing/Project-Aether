extends Node
## Implementation Brief v4.3 repair pass over every base item .tres:
##  - shields: block_chance set from item_level (BLOCK_CHANCE_BY_ITEM_LEVEL),
##    block_threshold lines removed (the field no longer exists);
##  - every weapon/armor/shield/ring/belt/amulet base: max_sockets (and
##    sockets) capped at ItemRoller.get_socket_cap() - never raised.
## Plain text edits so the rest of each file is untouched. Idempotent.
## Run: Godot --headless --path . res://tools/repair_v43_shields_sockets.tscn --quit-after 5

const DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

func _ready() -> void:
	call_deferred("_run")

## Upper item_level bound -> block chance (fraction), per the brief.
func _block_chance_for(item_level: int) -> float:
	if item_level <= 15: return 0.15
	if item_level <= 30: return 0.17
	if item_level <= 45: return 0.19
	if item_level <= 60: return 0.21
	if item_level <= 75: return 0.24
	return 0.28

func _run() -> void:
	var socket_caps := 0
	var shields_fixed := 0
	var thresholds_removed := 0
	var files_changed := 0
	for dir_path in DIRS:
		for file_name in DirAccess.get_files_at(dir_path):
			if not file_name.ends_with(".tres"):
				continue
			var path: String = dir_path + file_name
			var item := load(path) as Item
			if item == null:
				continue
			var cap := ItemRoller.get_socket_cap(item)
			var is_shield := item is Shield
			var lines := FileAccess.get_file_as_string(path).split("\n")
			var out: Array[String] = []
			var changed := false
			var saw_block_chance := false
			for line in lines:
				if is_shield and line.begins_with("block_threshold = "):
					thresholds_removed += 1
					changed = true
					continue
				if is_shield and line.begins_with("block_chance = "):
					saw_block_chance = true
					var wanted := "block_chance = %s" % str(_block_chance_for(item.item_level))
					if line != wanted:
						line = wanted
						changed = true
						shields_fixed += 1
				elif cap > 0 and (line.begins_with("max_sockets = ") or line.begins_with("sockets = ")):
					var parts := line.split(" = ")
					if int(parts[1]) > cap:
						line = "%s = %d" % [parts[0], cap]
						changed = true
						socket_caps += 1
				out.append(line)
			if is_shield and not saw_block_chance:
				# No line means the base sat at the 0.0 default.
				while not out.is_empty() and out[-1].strip_edges() == "":
					out.pop_back()
				out.append("block_chance = %s" % str(_block_chance_for(item.item_level)))
				out.append("")
				changed = true
				shields_fixed += 1
			if changed:
				var f := FileAccess.open(path, FileAccess.WRITE)
				f.store_string("\n".join(out))
				f.close()
				files_changed += 1
	print("files changed: ", files_changed, " | sockets capped: ", socket_caps, " | shield block_chance set: ", shields_fixed, " | block_threshold lines removed: ", thresholds_removed)
	get_tree().quit()
