extends RefCounted
class_name AetherStyle
## The "celestial instrument" UI style: smoked glass, thin aged-gold
## linework, cyan for anything holding Aether. Palette, fonts and the
## drawing helpers every HUD widget and screen shares, so they all draw the
## same diamonds, plates, dividers and dials.

const GOLD := Color(0.86, 0.71, 0.42)
const GOLD_BRIGHT := Color(1.0, 0.86, 0.55)
const GOLD_DIM := Color(0.55, 0.45, 0.28, 0.9)
const GOLD_FAINT := Color(0.55, 0.45, 0.28, 0.45)
const GLASS := Color(0.04, 0.05, 0.09, 0.82)
const GLASS_LIGHT := Color(0.09, 0.11, 0.17, 0.88)
const GLASS_SOLID := Color(0.035, 0.04, 0.065, 0.96)
const AETHER := Color(0.45, 0.86, 1.0)
const LIFE := Color(0.78, 0.12, 0.14)
const MANA := Color(0.16, 0.36, 0.86)
const TEXT := Color(0.93, 0.9, 0.84)
const TEXT_DIM := Color(0.77, 0.73, 0.65)
const MOD_BLUE := Color(0.55, 0.72, 1.0)
const DANGER := Color(0.95, 0.3, 0.28)
const SHADOW := Color(0, 0, 0, 0.75)
## Menu text sizes: body text, secondary labels and hints, buttons and tabs.
const MENU_FONT := 18
const MENU_FONT_SMALL := 16
const BUTTON_FONT := 17
## Tabbed menu screens start below the tab band (MenuTabStrip) and keep
## these margins, so they all share one frame.
const MENU_TOP := 62
const MENU_SIDE := 28
const MENU_BOTTOM := 24
## Full-screen menus draw above the HUD (CanvasLayer default 1).
const SCREEN_LAYER := 10

## Bundled fonts (assets/fonts, all SIL OFL): Cinzel for titles and labels,
## EB Garamond for body text, Rajdhani for numbers. Each falls back to a
## system font if its file is missing.
const TITLE_FILE := "res://assets/fonts/Cinzel-Variable.ttf"
const SERIF_FILE := "res://assets/fonts/EBGaramond-Variable.ttf"
const SERIF_ITALIC_FILE := "res://assets/fonts/EBGaramond-Italic-Variable.ttf"
const NUMBER_FILE := "res://assets/fonts/Rajdhani-SemiBold.ttf"
const SERIF_NAMES := ["EB Garamond", "Georgia", "Times New Roman", "DejaVu Serif"]
const NUMBER_NAMES := ["Rajdhani", "Bahnschrift", "Arial Narrow", "DejaVu Sans Condensed"]

static var _title: Font
static var _serif: Font
static var _serif_italic: Font
static var _numbers: Font

## Engraved capitals for titles, headings and spaced labels - not body text.
static func title() -> Font:
	if _title == null:
		_title = _font(TITLE_FILE, SERIF_NAMES, false)
	return _title

static func serif() -> Font:
	if _serif == null:
		_serif = _font(SERIF_FILE, SERIF_NAMES, false)
	return _serif

static func serif_italic() -> Font:
	if _serif_italic == null:
		_serif_italic = _font(SERIF_ITALIC_FILE, SERIF_NAMES, true)
	return _serif_italic

static func numbers() -> Font:
	if _numbers == null:
		_numbers = _font(NUMBER_FILE, NUMBER_NAMES, false)
	return _numbers

static func _font(path: String, fallback_names: Array, italic: bool) -> Font:
	if ResourceLoader.exists(path):
		var file := load(path) as FontFile
		if file:
			return file
	var f := SystemFont.new()
	f.font_names = PackedStringArray(fallback_names)
	f.font_italic = italic
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f

## "L I F E" - letter-spaced small caps labels.
static func spaced(text: String) -> String:
	return " ".join(text.to_upper().split(""))

# --- drawing helpers (call from a CanvasItem's _draw) ------------------------

static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size_px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string(font, pos + Vector2(1, 1), s, align, width, size_px, Color(0, 0, 0, 0.75 * color.a))
	ci.draw_string(font, pos, s, align, width, size_px, color)

static func text_width(font: Font, s: String, size_px: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

static func diamond(ci: CanvasItem, c: Vector2, r: float, fill: Color, outline: Color = GOLD) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	ci.draw_colored_polygon(pts, fill)
	if outline.a > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, outline, 1.2, true)

static func ticks(ci: CanvasItem, c: Vector2, r: float, count: int, major_every: int, color: Color) -> void:
	for i in count:
		var a := TAU * i / count - PI / 2.0
		var d := Vector2(cos(a), sin(a))
		var major := i % major_every == 0
		ci.draw_line(c + d * r, c + d * (r + (7.0 if major else 3.5)), color, 1.2 if major else 1.0, true)

## Horizontal rule with a small diamond in the middle.
static func divider(ci: CanvasItem, x: float, y: float, width: float, inset := 14.0) -> void:
	var c := Vector2(x + width / 2.0, y)
	ci.draw_line(Vector2(x + inset, y), c - Vector2(9, 0), GOLD_FAINT, 1.0, true)
	ci.draw_line(c + Vector2(9, 0), Vector2(x + width - inset, y), GOLD_FAINT, 1.0, true)
	diamond(ci, c, 4.0, GLASS, GOLD_DIM)

## Glass panel with a double gold frame and diamonds on the corners.
static func plate(ci: CanvasItem, rect: Rect2, corner := 4.0, bg: Color = GLASS) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(2)
	ci.draw_style_box(box, rect)
	ci.draw_rect(rect, GOLD_DIM, false, 1.2)
	ci.draw_rect(rect.grow(-4), GOLD_FAINT, false, 1.0)
	for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		diamond(ci, p, corner, GLASS, GOLD)

## Clock sweep for the unrecovered fraction (from 12 o'clock), with a gold
## hand; clipped to rect so it works on square tiles and round dials alike.
static func dial(ci: CanvasItem, rect: Rect2, fraction: float, round_shape := false) -> void:
	if fraction <= 0.0:
		return
	var c := rect.get_center()
	var reach := rect.size.x / 2.0 if round_shape else rect.size.length()
	var start := -PI / 2.0 + TAU * (1.0 - fraction)
	var pts := PackedVector2Array([c])
	for i in 33:
		var a := start + TAU * fraction * i / 32.0
		pts.append(_clip(c + Vector2(cos(a), sin(a)) * reach, rect))
	ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	ci.draw_line(c, _clip(c + Vector2(cos(start), sin(start)) * reach, rect), GOLD, 2.0, true)

static func _clip(p: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))

## Square with clipped corners, like a cut gem.
static func facet(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([
		p + Vector2(cut, 0), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), p + Vector2(0, cut)])

static func outline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width := 1.6) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, color, width, true)

## A thin bar in a glass track with a gold frame and diamond end caps.
static func bar(ci: CanvasItem, rect: Rect2, fraction: float, fill: Color, trail := 0.0) -> void:
	ci.draw_rect(rect, GLASS)
	if trail > fraction:
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x * trail, rect.size.y)), fill.lightened(0.45))
	if fraction > 0.0:
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), fill)
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, 1.5)), fill.lightened(0.3))
	ci.draw_rect(rect, GOLD_DIM, false, 1.0)
	diamond(ci, rect.position + Vector2(0, rect.size.y / 2.0), 4.5, GLASS, GOLD)
	diamond(ci, rect.position + Vector2(rect.size.x, rect.size.y / 2.0), 4.5, GLASS, GOLD)

# --- StyleBoxes for ordinary Controls -----------------------------------------

static func glass_box(border: Color = GOLD_DIM, bg: Color = GLASS, border_width := 1, margin := 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(2)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.6
	box.content_margin_bottom = margin * 0.6
	return box

## Buttons and tabs: roomier padding than a panel, and an optional outer
## glow for hover. Thicker borders give back the padding so text never shifts.
static func button_box(border: Color, bg: Color, border_width := 1, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := glass_box(border, bg, border_width, 16.0)
	var shift := float(border_width - 1)
	box.content_margin_left = 16.0 - shift
	box.content_margin_right = 16.0 - shift
	box.content_margin_top = 6.0 - shift
	box.content_margin_bottom = 6.0 - shift
	box.shadow_color = glow
	box.shadow_size = 5 if glow.a > 0.0 else 0
	return box

## A row of control hints that wraps: a gold key badge, then what it does.
## `pairs` is [[key, action], ...]; a key can be "LMB", "RMB", "Alt", "Esc".
static func key_hints(pairs: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "KeyHints"
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 8)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in pairs:
		flow.add_child(key_hint(String(pair[0]), String(pair[1])))
	return flow

static func key_hint(key: String, action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in key.split("+"):
		row.add_child(key_badge(part))
	var label := Label.new()
	label.text = action
	label.add_theme_font_size_override("font_size", MENU_FONT_SMALL)
	label.add_theme_color_override("font_color", TEXT)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return row

## A key cap: bright numerals in a small framed plate.
static func key_badge(key: String) -> PanelContainer:
	var badge := PanelContainer.new()
	var box := glass_box(GOLD, Color(0.16, 0.13, 0.08, 0.95), 1, 7.0)
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	box.border_width_bottom = 2
	badge.add_theme_stylebox_override("panel", box)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = key
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 14
	label.add_theme_font_override("font", numbers())
	label.add_theme_font_size_override("font_size", MENU_FONT_SMALL)
	label.add_theme_color_override("font_color", GOLD_BRIGHT)
	badge.add_child(label)
	return badge

## Item/slot buttons: dark glass with the rarity (or damage type) as border
## and a faint inner tint, instead of a flat colour fill.
static func slot_box(accent: Color, hovered := false) -> StyleBoxFlat:
	var box := glass_box(accent.lightened(0.2) if hovered else accent, GLASS_LIGHT.lerp(accent, 0.16 if hovered else 0.1), 2, 4.0)
	box.shadow_color = Color(accent, 0.35) if hovered else Color(0, 0, 0, 0)
	box.shadow_size = 6 if hovered else 0
	return box

static func style_slot_button(button: Button, accent: Color) -> void:
	button.add_theme_stylebox_override("normal", slot_box(accent))
	button.add_theme_stylebox_override("hover", slot_box(accent, true))
	button.add_theme_stylebox_override("pressed", slot_box(accent, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", slot_box(accent.darkened(0.4)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, TEXT)

## The project-wide Theme: every stock Control (buttons, panels, labels,
## scrollbars, tooltips, inputs, tabs, sliders) in the instrument style.
## Screens only need overrides for things the theme can't know, like
## rarity colours.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = serif()
	t.default_font_size = MENU_FONT

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	# Normal: dim frame. Hover: lit frame with a soft glow. Pressed or toggled
	# on: heavier bright frame on warm gold-tinted glass.
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, button_box(GOLD_DIM, GLASS_LIGHT))
		t.set_stylebox("hover", type, button_box(GOLD, Color(0.15, 0.15, 0.2, 0.94), 1, Color(GOLD, 0.22)))
		t.set_stylebox("pressed", type, button_box(GOLD_BRIGHT, Color(0.24, 0.19, 0.1, 0.96), 2))
		t.set_stylebox("hover_pressed", type, button_box(GOLD_BRIGHT, Color(0.28, 0.22, 0.12, 0.96), 2, Color(GOLD, 0.28)))
		t.set_stylebox("disabled", type, button_box(GOLD_FAINT, GLASS))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_font_size("font_size", type, BUTTON_FONT)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD_BRIGHT)
		t.set_color("font_pressed_color", type, GOLD_BRIGHT)
		t.set_color("font_hover_pressed_color", type, GOLD_BRIGHT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.6))

	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, StyleBoxEmpty.new())
		t.set_stylebox("hover", type, StyleBoxEmpty.new())
		t.set_stylebox("pressed", type, StyleBoxEmpty.new())
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD_BRIGHT)
		t.set_color("font_pressed_color", type, GOLD)

	var panel := glass_box(GOLD_DIM, GLASS_SOLID, 1, 14.0)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupPanel", glass_box(GOLD, GLASS_SOLID, 1, 10.0))
	t.set_stylebox("panel", "TooltipPanel", glass_box(GOLD, GLASS_SOLID, 1, 10.0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", serif())
	t.set_font_size("font_size", "TooltipLabel", MENU_FONT_SMALL)

	for type in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", type, glass_box(GOLD_DIM, Color(0.02, 0.025, 0.04, 0.9), 1, 8.0))
		t.set_stylebox("focus", type, glass_box(GOLD, Color(0.02, 0.025, 0.04, 0.9), 1, 8.0))
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, GOLD_BRIGHT)
		t.set_color("selection_color", type, Color(GOLD, 0.35))

	var rule := StyleBoxLine.new()
	rule.color = GOLD_FAINT
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	var vrule := StyleBoxLine.new()
	vrule.color = GOLD_FAINT
	vrule.thickness = 1
	vrule.vertical = true
	t.set_stylebox("separator", "VSeparator", vrule)

	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.35)
		track.set_corner_radius_all(3)
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grab := StyleBoxFlat.new()
			grab.bg_color = GOLD_DIM if state == "grabber" else GOLD
			grab.set_corner_radius_all(3)
			t.set_stylebox(state, type, grab)

	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.02, 0.025, 0.04, 0.9)
	slider.border_color = GOLD_DIM
	slider.set_border_width_all(1)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = GOLD.darkened(0.2)
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	var tab_on := button_box(GOLD_BRIGHT, Color(0.24, 0.19, 0.1, 0.96), 2)
	var tab_off := button_box(GOLD_FAINT, GLASS)
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_on)
		t.set_stylebox("tab_unselected", type, tab_off)
		t.set_stylebox("tab_hovered", type, button_box(GOLD, Color(0.15, 0.15, 0.2, 0.94)))
		t.set_font_size("font_size", type, BUTTON_FONT)
		t.set_color("font_selected_color", type, GOLD_BRIGHT)
		t.set_color("font_unselected_color", type, TEXT_DIM)
		t.set_color("font_hovered_color", type, TEXT)
	t.set_stylebox("panel", "TabContainer", panel)

	t.set_stylebox("panel", "ItemList", glass_box(GOLD_DIM, GLASS, 1, 6.0))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", GOLD_BRIGHT)
	t.set_stylebox("selected", "ItemList", glass_box(GOLD, Color(0.18, 0.15, 0.09, 0.9), 1, 4.0))
	t.set_stylebox("selected_focus", "ItemList", glass_box(GOLD, Color(0.18, 0.15, 0.09, 0.9), 1, 4.0))

	t.set_color("default_color", "RichTextLabel", TEXT)
	return t

## Per-screen touches the theme can't infer from type alone: labels named
## "...Title"/"TitleLabel" become gold serif headings, a "DimBackground"
## ColorRect becomes a deep blue-black veil.
static func style_screen(root: Node) -> void:
	for node in root.find_children("*", "Label", true, false):
		var n := String(node.name)
		if n == "TitleLabel" or n.ends_with("Title"):
			title_label(node, 26 if n == "TitleLabel" else 20)
	for node in root.find_children("DimBackground", "ColorRect", true, false):
		(node as ColorRect).color = Color(0.01, 0.015, 0.03, 0.84)

## Moves `node` into a glass PanelContainer (gold frame, corner diamonds)
## in its place, for screens whose content floats on the veil.
static func wrap_in_plate(node: Control, margin := 20) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Plate"
	panel.add_theme_stylebox_override("panel", glass_box(GOLD_DIM, GLASS_SOLID, 1, margin))
	var parent := node.get_parent()
	var index := node.get_index()
	panel.size_flags_horizontal = node.size_flags_horizontal
	panel.size_flags_vertical = node.size_flags_vertical
	parent.remove_child(node)
	parent.add_child(panel)
	parent.move_child(panel, index)
	panel.add_child(node)
	var corners := PlateCorners.new()
	corners.margin = margin
	corners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(corners)
	return panel

class PlateCorners extends Control:
	var margin: float = 20.0

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size).grow(margin)
		draw_rect(rect.grow(-5), GOLD_FAINT, false, 1.0)
		for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			AetherStyle.diamond(self, p, 5.0, GLASS_SOLID, GOLD)

## Gives a full-rect MarginContainer the shared tabbed-menu frame.
static func menu_margins(box: MarginContainer) -> void:
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("margin_left", MENU_SIDE)
	box.add_theme_constant_override("margin_right", MENU_SIDE)
	box.add_theme_constant_override("margin_top", MENU_TOP)
	box.add_theme_constant_override("margin_bottom", MENU_BOTTOM)

## True while a full-screen menu (inventory, character, pause, death...)
## is up - the combat HUD hides then rather than showing through the veil.
static func menu_open(tree: SceneTree) -> bool:
	for menu in tree.get_nodes_in_group("blocking_menu"):
		if menu.is_open():
			return true
	for menu in tree.get_nodes_in_group("full_screen_menu"):
		if menu.visible:
			return true
	return false

static func title_label(label: Label, size_px := 22) -> void:
	label.add_theme_font_override("font", title())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

## A gold section heading: a diamond, the title in spaced capitals, and a
## rule fading out to the right.
static func section_header(text_value: String, size_px := 17) -> Control:
	var header := SectionHeader.new()
	header.title = text_value
	header.size_px = size_px
	return header

class SectionHeader extends Control:
	var title := ""
	var size_px := 17

	func _ready() -> void:
		custom_minimum_size.y = size_px + 14.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mid := size.y * 0.5 + 2.0
		AetherStyle.diamond(self, Vector2(5, mid), 4.0, AetherStyle.GOLD_DIM, AetherStyle.GOLD)
		var font := AetherStyle.title()
		var label := AetherStyle.spaced(title.to_upper())
		AetherStyle.text(self, font, Vector2(16, mid + size_px * 0.36), label, size_px, AetherStyle.GOLD)
		var x := 16.0 + AetherStyle.text_width(font, label, size_px) + 10.0
		var steps := 24
		for i in steps:
			var t := float(i) / steps
			var w := (size.x - x) / steps
			draw_line(Vector2(x + w * i, mid), Vector2(x + w * (i + 1), mid), Color(AetherStyle.GOLD_DIM, 0.9 * (1.0 - t)), 1.0)

## A centred gold rule with a diamond (divider()) as a Control; `faint`
## draws it shorter and quieter, for gaps between button groups.
static func section_divider(faint := false) -> Control:
	var rule := Divider.new()
	rule.faint = faint
	rule.custom_minimum_size.y = 14.0 if faint else 20.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

class Divider extends Control:
	var faint := false

	func _draw() -> void:
		var inset := size.x * (0.22 if faint else 0.04)
		if faint:
			draw_line(Vector2(inset, size.y / 2.0), Vector2(size.x - inset, size.y / 2.0), AetherStyle.GOLD_FAINT, 1.0)
		else:
			AetherStyle.divider(self, 0.0, size.y / 2.0, size.x, inset)

## Background for a stat row; every other row is faintly lit.
static func row_box(lit: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(GOLD, 0.08) if lit else Color(0, 0, 0, 0)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	return box
