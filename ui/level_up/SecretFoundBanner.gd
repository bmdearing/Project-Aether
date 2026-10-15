extends CanvasLayer
class_name SecretFoundBanner
## "SECRET FOUND" across the upper screen, shown the first time the player
## steps into a Figment's secret room (SecretRoomBuilder).

const LAYER := 40
const FONT_SIZE := 54
const HOLD := 2.2
const FADE := 0.6

static func play(host: Node) -> SecretFoundBanner:
	var banner := SecretFoundBanner.new()
	host.add_child(banner)
	return banner

func _ready() -> void:
	layer = LAYER
	var label := Label.new()
	label.text = AetherStyle.spaced("SECRET FOUND")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_top = 0.22
	label.anchor_bottom = 0.32
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", AetherStyle.title())
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", AetherStyle.GOLD)
	label.add_theme_color_override("font_shadow_color", AetherStyle.SHADOW)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.modulate.a = 0.0
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.35)
	tween.tween_interval(HOLD)
	tween.tween_property(label, "modulate:a", 0.0, FADE)
	tween.tween_callback(queue_free)
