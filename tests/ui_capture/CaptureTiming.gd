extends RefCounted
## Frame-time sampling for the capture harnesses. Does nothing unless the
## CAPTURE_TIMING env var names an output file; then it uncaps the frame rate,
## samples frames after a warmup and appends one JSON line per shot:
## {label, renderer, avg_ms, p95_ms, p99_ms, fps, draw_calls, primitives}.

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 400

static func measure(node: Node, label: String) -> void:
	var path := OS.get_environment("CAPTURE_TIMING")
	if path == "":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var tree := node.get_tree()
	for i in WARMUP_FRAMES:
		await tree.process_frame
	var times: Array[float] = []
	var draw_calls := 0.0
	var primitives := 0.0
	var last := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var total := 0.0
	for t in times:
		total += t
	var sorted := times.duplicate()
	sorted.sort()
	var avg := total / times.size()
	var row := {
		"label": label,
		"renderer": RenderingServer.get_current_rendering_method(),
		"avg_ms": snappedf(avg, 0.01),
		"p95_ms": snappedf(sorted[int(sorted.size() * 0.95)], 0.01),
		"p99_ms": snappedf(sorted[int(sorted.size() * 0.99)], 0.01),
		"fps": snappedf(1000.0 / avg, 0.1),
		"draw_calls": roundi(draw_calls / SAMPLE_FRAMES),
		"primitives": roundi(primitives / SAMPLE_FRAMES),
	}
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(row))
	f.close()
