extends Node
## Screenshots an outdoor map at a set time of day and weather. Run windowed:
## Godot --path . res://tests/ui_capture/capture_weather.tscn --resolution 1600x900 -- <out.png> <style_id> <time 0-1> <weather> [seed]
## Weather: clear, rain, storm, snow, blizzard, sandstorm.

const MapAtmosphere := preload("res://levels/generated_map/MapAtmosphere.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://weather.png"
	var style: String = args[1] if args.size() > 1 else "forest_plains"
	GameState.reset_to_defaults()
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = style
	GameState.active_map = figment
	GameState.portal_map_state = {"seed": int(args[4]) if args.size() > 4 else 3, "tileset_id": style}
	var map: GeneratedMap = load("res://levels/generated_map/GeneratedMap.tscn").instantiate()
	get_tree().root.add_child(map)
	var atmo := map.atmosphere
	atmo.time_of_day = float(args[2]) if args.size() > 2 else 0.5
	var weather: int = MapAtmosphere.WEATHER_NAMES.find(args[3] if args.size() > 3 else "clear")
	if weather != atmo.weather:
		atmo.weather = weather as MapAtmosphere.Weather
		if is_instance_valid(atmo._fall):
			atmo._fall.queue_free()
			atmo._fall = null
		atmo._build_fall()
	await get_tree().create_timer(2.5).timeout
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	if atmo.weather == MapAtmosphere.Weather.STORM:
		atmo.strike()
		await get_tree().create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
