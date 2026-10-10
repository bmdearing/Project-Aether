extends Node
## Prints each roster unit's move speed against its walk/run clip speeds and
## the playback rate that gives. Run: Godot --headless --path . res://tests/perf/probe_anim_rates.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for file_name in DirAccess.get_files_at("res://data/enemies/definitions/"):
		file_name = file_name.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var id := file_name.get_basename()
		var unit := EnemyRoster.create_unit(id)
		add_child(unit)
		await get_tree().process_frame
		var ctrl := unit._anim_controller as EnemyAnimationController
		var walk: float = ctrl._clip_speeds.get("Walk", 0.0) if ctrl else -1.0
		var run: float = ctrl._clip_speeds.get("Run", 0.0) if ctrl else -1.0
		var speed := unit.move_speed
		var state := "Run" if speed > EnemyAnimationController.RUN_SPEED_THRESHOLD else "Walk"
		var authored := run if state == "Run" else walk
		print("%-28s move %.2f  walk %.2f  run %.2f  -> %s rate %s" % [id, speed, walk, run, state, ("%.2f" % (speed / authored)) if authored > 0.0 else "n/a (1.0)"])
		unit.queue_free()
	get_tree().quit()
