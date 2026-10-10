extends Node
## Counts the doodads a generated map places, by scene. Run:
## Godot --headless --path . res://tests/perf/probe_doodads.tscn -- <style_id> [seed]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var style: String = args[0] if args.size() > 0 else "forest_aspen"
	seed(int(args[1]) if args.size() > 1 else 7)
	GameState.reset_to_defaults()
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = style
	GameState.active_map = figment
	var map: GeneratedMap = load("res://levels/generated_map/GeneratedMap.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	var counts := {}
	for child in map.get_children():
		var path: String = child.scene_file_path
		if path.contains("doodads"):
			counts[path.get_file()] = int(counts.get(path.get_file(), 0)) + 1
	print("style %s (%s): %s" % [style, map.tileset.id if map.tileset else "?", counts])
	print("floor_props=%d clusters=%d scatter=%s" % [map.tileset.floor_props.size(), map.tileset.clusters.size(), map.layout.scatter_per_cell])
	var shown := 0
	for child in map.get_children():
		if child.scene_file_path.contains("Lordaerontree") and shown < 3:
			shown += 1
			var meshes := child.find_children("*", "MeshInstance3D", true, false)
			var vis := meshes.filter(func(m): return m.is_visible_in_tree()).size()
			var gi := meshes[0] as GeometryInstance3D if not meshes.is_empty() else null
			print("tree at %s scale %s meshes %d visible %d range %s" % [child.global_position, child.scale, meshes.size(), vis, [gi.visibility_range_begin, gi.visibility_range_end] if gi else []])
	get_tree().quit()
