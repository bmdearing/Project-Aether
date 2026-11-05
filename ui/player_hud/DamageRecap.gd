extends Control
class_name DamageRecap
## In-play damage summary under the minimap: live DPS (the last few seconds),
## the map's total, and the top sources with their share. The full table is
## the Damage tab (DamageMeterScreen). Hidden until something's been hit.

const WIDTH := Minimap.SIZE
const TOP_SOURCES := 3
const LINE := 17.0
const REDRAW_EVERY := 0.25

var _timer := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -WIDTH - Minimap.MARGIN
	offset_right = -Minimap.MARGIN
	offset_top = Minimap.MARGIN + Minimap.SIZE + 32.0
	offset_bottom = offset_top + 34.0 + TOP_SOURCES * LINE + 18.0

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REDRAW_EVERY
	visible = DamageMeter.total > 0.0
	if visible:
		queue_redraw()

func _draw() -> void:
	var rows := DamageMeter.sorted(DamageMeter.by_source).slice(0, TOP_SOURCES)
	var h := 34.0 + rows.size() * LINE + 18.0
	draw_rect(Rect2(0, 0, WIDTH, h), Color(0.03, 0.035, 0.06, 0.55))
	draw_rect(Rect2(0, 0, WIDTH, h), AetherStyle.GOLD_FAINT, false, 1.0)
	var numbers := AetherStyle.numbers()
	var serif := AetherStyle.serif_text()
	AetherStyle.text(self, numbers, Vector2(8, 22), "%s DPS" % DamageMeterScreen.num(DamageMeter.recent_dps()), 20, AetherStyle.GOLD_BRIGHT)
	AetherStyle.text(self, numbers, Vector2(0, 22), "%s total" % DamageMeterScreen.num(DamageMeter.total), 14, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 8.0)
	var y := 34.0
	for r in rows:
		var share: float = r[1] / DamageMeter.total
		draw_rect(Rect2(6, y + 2, (WIDTH - 12) * share, LINE - 3), Color(0.86, 0.71, 0.42, 0.22))
		var name := String(r[0])
		if name.length() > 22:
			name = name.left(21) + "…"
		AetherStyle.text(self, serif, Vector2(10, y + LINE - 4), name, 13, AetherStyle.TEXT)
		AetherStyle.text(self, numbers, Vector2(0, y + LINE - 4), "%d%%" % roundi(share * 100.0), 13, AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 10.0)
		y += LINE
	var hint := "%s: full meter" % _key_name()
	AetherStyle.text(self, serif, Vector2(0, y + 13), hint, 11, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, WIDTH)

func _key_name() -> String:
	for e in InputMap.action_get_events("open_damage_meter"):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return "J"
