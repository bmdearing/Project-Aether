extends SceneTree
## Writes AetherStyle.build_theme() to res://ui/theme/aether_theme.tres, the
## project-wide theme (project setting gui/theme/custom). Re-run after
## changing AetherStyle.build_theme():
##   Godot --headless --path . --script res://tools/build_ui_theme.gd

const OUT := "res://ui/theme/aether_theme.tres"

func _init() -> void:
	var style: GDScript = load("res://ui/theme/AetherStyle.gd")
	var theme: Theme = style.call("build_theme")
	var err := ResourceSaver.save(theme, OUT)
	print("saved %s (%s)" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)
