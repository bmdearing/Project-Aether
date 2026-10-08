extends Control
class_name StanceIndicator
## Bottom-right stance icon: what holding RMB does with the current weapon,
## which page (A/B) is selected, and a radial cooldown sweep when the
## stance's special is recharging. The name sits above the icon. Lights up
## while the stance is held; flashes red when a special is pressed early.

const ICON_SIZE := 64.0
const NAME_HEIGHT := 18.0
const BG_COLOR := Color(0.07, 0.07, 0.09, 0.85)
const READY_BORDER := Color(0.85, 0.68, 0.32)
const ACTIVE_BORDER := Color(1.0, 0.9, 0.55)
const COOLDOWN_BORDER := Color(0.4, 0.4, 0.42)
const DENIED_BORDER := Color(0.95, 0.2, 0.2)
const SWEEP_COLOR := Color(0, 0, 0, 0.62)
const GLYPH_COLOR := Color(0.95, 0.9, 0.8)
const DENIED_FLASH := 0.35

var _player: Player
var _name: String = ""
var _glyph: String = ""
var _page: String = ""
var _cooldown: float = 0.0
var _cooldown_total: float = 0.0
var _denied: float = 0.0
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE + NAME_HEIGHT)
	_font = get_theme_default_font()
	_player = get_tree().get_first_node_in_group("player") as Player
	EventBus.stance_on_cooldown.connect(func(_p, _r): _denied = DENIED_FLASH)

func _process(delta: float) -> void:
	_denied = maxf(_denied - delta, 0.0)
	_refresh()
	queue_redraw()

func _refresh() -> void:
	visible = false
	if not is_instance_valid(_player):
		return
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return
	var info := {}
	_page = ""
	if _player.shield_block and _player.shield_block.overrides_stance():
		info = {"name": "Raise Shield"}
	elif _player.caster_stance and _player.caster_stance.get_source():
		info = StanceInfo.for_conduit(_player.caster_stance.get_source())
		_page = _page_letter()
	elif weapon.is_ranged:
		var dual := StanceInfo.RANGED_B.has(weapon.weapon_type)
		info = StanceInfo.for_weapon(weapon, int(_player.weapon_stance.active_page) if dual else 0)
		_page = _page_letter() if dual else ""
	else:
		info = StanceInfo.for_weapon(weapon, int(_player.weapon_stance.active_page))
		_page = _page_letter()
	if info.is_empty():
		return
	visible = true
	_name = info.get("name", "")
	if _player.stance_attack and _player.stance_attack.is_stealthed():
		_name += " (hidden)"
	_glyph = _initials(info.get("name", ""))
	var behavior := _player.weapon_stance.get_ready_behavior()
	_cooldown = _player.weapon_stance.get_cooldown_remaining(behavior)
	_cooldown_total = behavior.cooldown_seconds if behavior else 0.0

func _page_letter() -> String:
	return "A" if _player.weapon_stance.active_page == WeaponStance.StancePage.A else "B"

static func _initials(text: String) -> String:
	var letters := ""
	for word in text.split(" ", false):
		if word[0] == word[0].to_upper():
			letters += word[0]
	return letters.left(2) if letters != "" else text.left(2)

func _draw() -> void:
	if not visible:
		return
	var name_size := _font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(_font, Vector2(ICON_SIZE - name_size.x, 12), _name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GLYPH_COLOR)
	var rect := Rect2(0, NAME_HEIGHT, ICON_SIZE, ICON_SIZE)
	var box := StyleBoxFlat.new()
	box.bg_color = BG_COLOR
	box.set_corner_radius_all(6)
	box.set_border_width_all(2)
	var on_cooldown := _cooldown > 0.0
	if _denied > 0.0:
		box.border_color = DENIED_BORDER
	elif on_cooldown:
		box.border_color = COOLDOWN_BORDER
	elif _player.weapon_stance.is_active:
		box.border_color = ACTIVE_BORDER
		box.set_border_width_all(3)
	else:
		box.border_color = READY_BORDER
	draw_style_box(box, rect)
	var glyph_size := _font.get_string_size(_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	var glyph_pos := rect.get_center() + Vector2(-glyph_size.x / 2.0, glyph_size.y / 3.0)
	draw_string(_font, glyph_pos, _glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GLYPH_COLOR.darkened(0.45) if on_cooldown else GLYPH_COLOR)
	if on_cooldown and _cooldown_total > 0.0:
		_draw_sweep(rect.grow(-2), _cooldown / _cooldown_total)
		var secs := str(ceili(_cooldown))
		var secs_size := _font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(_font, rect.get_center() + Vector2(-secs_size.x / 2.0, secs_size.y / 3.0), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if _page != "":
		draw_string(_font, rect.position + Vector2(5, 15), _page, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, READY_BORDER)
	draw_string(_font, rect.position + Vector2(ICON_SIZE - 30, ICON_SIZE - 5), "RMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.72))

## Clockwise dark wedge covering the unrecovered fraction, from 12 o'clock.
func _draw_sweep(rect: Rect2, fraction: float) -> void:
	var centre := rect.get_center()
	var reach := rect.size.length()
	var points := PackedVector2Array([centre])
	var steps := 24
	for i in steps + 1:
		var angle := -PI / 2.0 + TAU * (1.0 - fraction) + TAU * fraction * i / steps
		var p := centre + Vector2(cos(angle), sin(angle)) * reach
		points.append(Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y)))
	draw_colored_polygon(points, SWEEP_COLOR)
