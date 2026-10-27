extends Control
class_name AilmentOverlay
## Makes ailments on the player obvious: each one tints and animates the
## screen edges its own way (player_ailments.gdshader), and a newly landed
## one flashes its name under the crosshair. The status row's icons still
## carry the timers.

const SHADER := preload("res://shaders/player_ailments.gdshader")
const FADE_SPEED := 4.0
## Shader channel -> the effects that drive it, with their strength.
const CHANNELS := {
	"ignite": {"ignite": 1.0, "scorch": 0.7, "forbidden_fire": 1.0},
	"chill": {"chill": 0.6, "freeze": 1.0},
	"shock": {"shock": 0.8, "electrocute": 1.0},
	"bleed": {"bleed": 1.0},
	"esoteric": {"unraveling": 1.0, "pallid": 0.8, "aetherburn": 1.0},
}
const CALLOUTS := {
	"ignite": "IGNITED", "scorch": "SCORCHED", "forbidden_fire": "FORBIDDEN FIRE",
	"chill": "CHILLED", "freeze": "FROZEN", "shock": "SHOCKED", "electrocute": "ELECTROCUTED",
	"bleed": "BLEEDING", "unraveling": "UNRAVELING", "pallid": "PALLID", "aetherburn": "AETHERBURN",
}
const CALLOUT_SECONDS := 1.4
const CALLOUT_Y := 0.62

var player: Player
var _mat: ShaderMaterial
var _levels: Dictionary = {}
var _shown: Dictionary = {}
var _callout: Label
var _callout_tween: Tween

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	rect.material = _mat
	add_child(rect)
	_callout = Label.new()
	_callout.set_anchors_preset(Control.PRESET_CENTER)
	_callout.anchor_top = CALLOUT_Y
	_callout.anchor_bottom = CALLOUT_Y
	_callout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.add_theme_font_size_override("font_size", 28)
	_callout.add_theme_constant_override("outline_size", 6)
	_callout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout.modulate.a = 0.0
	add_child(_callout)

func _process(delta: float) -> void:
	var effects := player.status_effects if is_instance_valid(player) else null
	var size_now := get_viewport_rect().size
	_mat.set_shader_parameter("aspect", size_now.x / maxf(size_now.y, 1.0))
	for channel in CHANNELS:
		var target := 0.0
		if effects:
			for id in CHANNELS[channel]:
				if effects.has_effect(id):
					target = maxf(target, CHANNELS[channel][id])
		var level := move_toward(float(_levels.get(channel, 0.0)), target, delta * FADE_SPEED)
		_levels[channel] = level
		_mat.set_shader_parameter(channel, level)
	if effects == null:
		return
	for id in CALLOUTS:
		var on := effects.has_effect(id)
		if on and not _shown.has(id):
			_show_callout(id)
		if on:
			_shown[id] = true
		else:
			_shown.erase(id)

func _show_callout(id: String) -> void:
	_callout.text = CALLOUTS[id]
	_callout.add_theme_color_override("font_color", StatusIcons.colour_of(id).lightened(0.15))
	if _callout_tween:
		_callout_tween.kill()
	_callout.modulate.a = 1.0
	_callout.scale = Vector2.ONE
	_callout_tween = create_tween()
	_callout_tween.tween_interval(CALLOUT_SECONDS * 0.6)
	_callout_tween.tween_property(_callout, "modulate:a", 0.0, CALLOUT_SECONDS * 0.4)
