extends CanvasLayer
class_name DamageMeterScreen
## The Damage tab (J / open_damage_meter): the full breakdown of the current
## map's damage (DamageMeter). A header of map totals (top hit, burst, total,
## DPS), a table of every source (total, biggest hit and crit, burst,
## average, hits, crit rate), then each enemy type with the sources it took
## the most damage from. DamageRecap on the HUD is the in-play summary.

const COLUMNS := ["Source", "Total", "Hit", "Crit", "Burst", "Avg", "Hits", "Crit %"]
const NAME_WIDTH := 300.0
const COLUMN_WIDTH := 110.0
const SOURCES_PER_ENEMY := 4
const ROW_HEIGHT := 28.0
const BAR_COLOR := Color(0.86, 0.71, 0.42, 0.28)
const ENEMY_BAR_COLOR := Color(0.78, 0.35, 0.3, 0.32)
const CRIT_COLOR := Color(1.0, 0.8, 0.35)
const HEAD_COLOR := Color(0.86, 0.71, 0.42)

var _is_open := false
var _title: Label
var _header: HBoxContainer
var _table: VBoxContainer
var _enemies: VBoxContainer

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("damage_meter_screen")
	add_to_group("blocking_menu")
	_build()
	AetherStyle.style_screen(self)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", AetherStyle.MENU_TOP + 8)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	_title = Label.new()
	_title.name = "TitleLabel"
	page.add_child(_title)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 48)
	page.add_child(_header)
	page.add_child(HSeparator.new())
	_table = VBoxContainer.new()
	_table.add_theme_constant_override("separation", 1)
	page.add_child(_table)
	page.add_child(_section_heading("By enemy type"))
	_enemies = VBoxContainer.new()
	_enemies.add_theme_constant_override("separation", 1)
	page.add_child(_enemies)

func _section_heading(text: String) -> Label:
	var head := Label.new()
	head.text = AetherStyle.spaced(text)
	head.add_theme_font_override("font", AetherStyle.title())
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", HEAD_COLOR)
	return head

func refresh() -> void:
	for box in [_header, _table, _enemies]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_title.text = "Damage - %s" % (DamageMeter.map_name if DamageMeter.map_name != "" else "No map yet")
	if DamageMeter.total <= 0.0:
		_header.add_child(_stat_block("Nothing hit yet on this map", "", ""))
		return
	_header.add_child(_stat_block("Top hit", num(DamageMeter.top_hit), DamageMeter.top_hit_source))
	_header.add_child(_stat_block("Burst", num(DamageMeter.burst), "best %ds" % int(DamageMeter.BURST_WINDOW)))
	_header.add_child(_stat_block("Total", num(DamageMeter.total), "%d hits" % DamageMeter.hits))
	_header.add_child(_stat_block("DPS", num(DamageMeter.dps()), "over %ss" % num(DamageMeter.elapsed())))
	_table.add_child(_row(COLUMNS, 0.0, Color(0, 0, 0, 0), true))
	var rows := DamageMeter.sorted(DamageMeter.by_source)
	var top: float = rows[0][1]
	for r in rows:
		var s: Dictionary = DamageMeter.source_stats.get(r[0], {})
		var hits: int = s.get("hits", 0)
		var crits: int = s.get("crits", 0)
		_table.add_child(_row([
			r[0], num(r[1]), _or_dash(s.get("max_hit", 0.0)), _or_dash(s.get("max_crit", 0.0)),
			num(s.get("burst", 0.0)), num(r[1] / maxi(hits, 1)), str(hits),
			"%d%%" % roundi(100.0 * crits / hits) if hits > 0 else "-",
		], r[1] / top, BAR_COLOR, false))
	var enemy_rows := DamageMeter.sorted(DamageMeter.enemy_totals)
	for e in enemy_rows:
		var kind: String = e[0]
		var amount: float = e[1]
		_enemies.add_child(_row([kind, num(amount), "%d%%" % roundi(amount / DamageMeter.total * 100.0)], amount / float(enemy_rows[0][1]), ENEMY_BAR_COLOR, false, 17))
		var sources := DamageMeter.sorted(DamageMeter.by_enemy.get(kind, {}))
		for r in sources.slice(0, SOURCES_PER_ENEMY):
			_enemies.add_child(_row(["      " + String(r[0]), num(r[1]), "%d%%" % roundi(r[1] / amount * 100.0)], r[1] / amount, BAR_COLOR, false, 14))
		if sources.size() > SOURCES_PER_ENEMY:
			_enemies.add_child(_row(["      ...and %d more" % (sources.size() - SOURCES_PER_ENEMY)], 0.0, BAR_COLOR, false, 13))

func _stat_block(caption: String, value: String, note: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.text = caption.to_upper()
	cap.add_theme_font_override("font", AetherStyle.title())
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", HEAD_COLOR)
	box.add_child(cap)
	if value != "":
		var v := Label.new()
		v.text = value
		v.add_theme_font_override("font", AetherStyle.numbers())
		v.add_theme_font_size_override("font_size", 30)
		box.add_child(v)
	if note != "":
		var n := Label.new()
		n.text = note
		n.add_theme_font_size_override("font_size", 14)
		n.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
		box.add_child(n)
	return box

## One table line: a share bar behind the name, then right-aligned columns.
func _row(cells: Array, fraction: float, bar: Color, is_head: bool, font_size: int = 16) -> Control:
	var row := RowBack.new()
	row.fraction = fraction
	row.color = bar
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT if font_size >= 16 else ROW_HEIGHT - 6.0)
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.add_theme_constant_override("separation", 0)
	row.add_child(line)
	for i in cells.size():
		var label := Label.new()
		label.text = String(cells[i])
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_FILL
		label.custom_minimum_size.x = NAME_WIDTH if i == 0 else COLUMN_WIDTH
		label.clip_text = true
		if i == 0:
			label.text = "  " + label.text
		else:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_font_override("font", AetherStyle.numbers())
		label.add_theme_font_size_override("font_size", 13 if is_head else font_size)
		if is_head:
			label.add_theme_color_override("font_color", HEAD_COLOR)
		elif i == 3 and label.text != "-":
			label.add_theme_color_override("font_color", CRIT_COLOR)
		line.add_child(label)
	return row

static func _or_dash(v: float) -> String:
	return num(v) if v > 0.0 else "-"

static func num(v: float) -> String:
	if v >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	if v >= 10000.0:
		return "%.1fK" % (v / 1000.0)
	if v >= 1000.0:
		return "%d,%03d" % [int(v) / 1000, int(v) % 1000]
	return "%.0f" % v

## The share bar sits behind the source name and its numbers.
class RowBack extends Control:
	var fraction: float = 0.0
	var color: Color = Color.WHITE

	func _draw() -> void:
		if fraction > 0.0:
			var w := DamageMeterScreen.NAME_WIDTH + DamageMeterScreen.COLUMN_WIDTH
			draw_rect(Rect2(0, 1, w * clampf(fraction, 0.0, 1.0), size.y - 2), color)
