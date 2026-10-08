extends Node
## Celestial-instrument UI mockup drawn over the live Hub. Nothing here is
## wired to gameplay - it's a static picture of the proposed style.
## Run windowed: Godot --path . res://tests/ui_mockup/ui_mockup.tscn --resolution 1920x1080 -- <out.png>

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	GameState.reset_to_defaults()
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	get_tree().root.add_child(hub)
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Player
	player.rotation.y = 0.0
	var weapon := Weapon.new()
	weapon.weapon_type = "Greatsword"
	weapon.is_two_handed = true
	player.equipment.primary_weapon = weapon
	player.equipment.equipment_changed.emit()
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 50
	get_tree().root.add_child(layer)
	var canvas := MockCanvas.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(canvas)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://ui_mockup.png")
	get_tree().quit()

class MockCanvas extends Control:
	const GOLD := Color(0.86, 0.71, 0.42)
	const GOLD_DIM := Color(0.55, 0.45, 0.28, 0.9)
	const GOLD_FAINT := Color(0.55, 0.45, 0.28, 0.45)
	const GLASS := Color(0.04, 0.05, 0.09, 0.78)
	const GLASS_LIGHT := Color(0.09, 0.11, 0.17, 0.85)
	const AETHER := Color(0.45, 0.86, 1.0)
	const LIFE := Color(0.78, 0.12, 0.14)
	const MANA := Color(0.16, 0.36, 0.86)
	const TEXT := Color(0.93, 0.9, 0.84)
	const TEXT_DIM := Color(0.66, 0.62, 0.55)
	const MOD_BLUE := Color(0.55, 0.72, 1.0)
	const RARE := Color(1.0, 0.86, 0.35)
	const FIRE := Color(1.0, 0.45, 0.15)
	const COLD := Color(0.5, 0.82, 1.0)
	const LIGHTNING := Color(1.0, 0.92, 0.35)
	const ENTROPIC := Color(0.7, 0.4, 1.0)

	var serif: SystemFont
	var serif_italic: SystemFont
	var numbers: SystemFont

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		serif = _font("Georgia")
		serif_italic = _font("Georgia", true)
		numbers = _font("Bahnschrift")

	func _font(name: String, italic: bool = false) -> SystemFont:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([name])
		f.font_italic = italic
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		return f

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var mid := w / 2.0
		_crosshair(Vector2(mid, h / 2.0))
		_enemy_bar(Vector2(mid - 150, h * 0.36), "Synod Warden Golem", Color(0.45, 0.65, 1.0), 0.62, 0.55)
		_bottom_shade(w, h)
		var base_y := h - 134.0
		_orb(Vector2(mid - 280, base_y), 68.0, 0.78, LIFE, "LIFE", "166", "/ 212", 0.32)
		_orb(Vector2(mid + 280, base_y), 68.0, 0.46, MANA, "MANA", "52", "/ 112", -1.0)
		var spells := [["Ci", FIRE, 0.0, "8"], ["Ic", COLD, 0.0, "8"], ["St", LIGHTNING, 0.35, "34"], ["Bh", ENTROPIC, 0.0, "30"]]
		_skill_bar(Vector2(mid, base_y + 4), spells)
		_xp_bar(Vector2(0, h - 7), w, 0.38, 14)
		_stance(Vector2(w - 330, h - 104), 42.0, "Execute", "Ex", "A", 0.4)
		_weapon_plate(Vector2(w - 262, h - 142))
		_item_card(Vector2(w - 470, 150), 400.0)

	## Soft dark band behind the bottom HUD so it reads over bright floors.
	func _bottom_shade(w: float, h: float) -> void:
		var top := h - 260.0
		draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6)]))

	# --- primitives ---------------------------------------------------------

	func _text(font: Font, pos: Vector2, text: String, size_px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
		draw_string(font, pos + Vector2(1, 1), text, align, width, size_px, Color(0, 0, 0, 0.75))
		draw_string(font, pos, text, align, width, size_px, color)

	func _spaced(text: String) -> String:
		return " ".join(text.split(""))

	func _diamond(c: Vector2, r: float, fill: Color, outline: Color = GOLD) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, outline, 1.2, true)

	func _ticks(c: Vector2, r: float, count: int, major_every: int, color: Color) -> void:
		for i in count:
			var a := TAU * i / count - PI / 2.0
			var d := Vector2(cos(a), sin(a))
			var length := 7.0 if i % major_every == 0 else 3.5
			draw_line(c + d * r, c + d * (r + length), color, 1.2 if i % major_every == 0 else 1.0, true)

	func _divider(x: float, y: float, width: float) -> void:
		var c := Vector2(x + width / 2.0, y)
		draw_line(Vector2(x + 14, y), c - Vector2(9, 0), GOLD_FAINT, 1.0, true)
		draw_line(c + Vector2(9, 0), Vector2(x + width - 14, y), GOLD_FAINT, 1.0, true)
		_diamond(c, 4.0, GLASS, GOLD_DIM)

	## Dark wedge for the unrecovered part, plus a gold hand at the sweep edge.
	func _dial(c: Vector2, r: float, fraction: float) -> void:
		var start := -PI / 2.0 + TAU * (1.0 - fraction)
		var pts := PackedVector2Array([c])
		for i in 33:
			var a := start + TAU * fraction * i / 32.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		draw_line(c, c + Vector2(cos(start), sin(start)) * r, GOLD, 2.0, true)

	# --- widgets --------------------------------------------------------------

	func _crosshair(c: Vector2) -> void:
		draw_arc(c, 9.0, 0, TAU, 32, Color(1, 1, 1, 0.55), 1.2, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 13.0, c + d * 18.0, Color(1, 1, 1, 0.7), 1.5, true)
		draw_circle(c, 1.6, Color(1, 1, 1, 0.9))

	## Glass sphere in a ticked gold ring; liquid level = fraction. ward >= 0
	## draws the Aether orbit around it.
	func _orb(c: Vector2, r: float, fraction: float, liquid: Color, label: String, value: String, max_text: String, ward: float) -> void:
		draw_circle(c, r + 18.0, Color(0, 0, 0, 0.35))
		draw_circle(c, r, GLASS)
		var level_y := c.y + r - 2.0 * r * fraction
		var t := acos(clampf((level_y - c.y) / r, -1.0, 1.0))
		var pts := PackedVector2Array()
		for i in 49:
			var a := -t + 2.0 * t * i / 48.0
			pts.append(c + Vector2(sin(a), cos(a)) * r)
		draw_colored_polygon(pts, liquid.darkened(0.35))
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(c + (p - c) * 0.8 + Vector2(0, r * 0.12))
		draw_colored_polygon(inner, liquid)
		draw_line(Vector2(c.x - sin(t) * r, level_y), Vector2(c.x + sin(t) * r, level_y), liquid.lightened(0.5), 1.5, true)
		draw_arc(c + Vector2(-r * 0.25, -r * 0.3), r * 0.55, PI * 1.05, PI * 1.55, 16, Color(1, 1, 1, 0.22), 4.0, true)
		draw_arc(c, r, 0, TAU, 64, GOLD, 2.5, true)
		draw_arc(c, r + 3.0, 0, TAU, 64, GOLD_FAINT, 1.0, true)
		_ticks(c, r + 4.0, 60, 5, GOLD_DIM)
		if ward > 0.0:
			_ward_lattice(c, r, ward)
			var edge_x := c.x + r - 2.0 * r * ward
			_text(numbers, Vector2(edge_x, c.y - r * 0.42), "48", 15, Color(0.85, 0.98, 1.0), HORIZONTAL_ALIGNMENT_CENTER, c.x + r - edge_x)
		_text(numbers, c + Vector2(-r, 8), value, 30, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		_text(numbers, c + Vector2(-r, 28), max_text, 15, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		_text(serif, c + Vector2(-r, r + 40), _spaced(label), 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)

	## Ward as a crystalline field over the right side of the Life globe,
	## reaching in by fraction of the width: a triangular lattice with a few
	## lit facets and a ruler-straight inner edge - deliberately not liquid.
	func _ward_lattice(c: Vector2, r: float, fraction: float) -> void:
		var edge_x := c.x + r - 2.0 * r * fraction
		var inside := func(p: Vector2) -> bool: return p.distance_to(c) <= r - 2.0 and p.x >= edge_x
		# Segment of the circle right of the edge, tinted.
		var t := acos(clampf((edge_x - c.x) / r, -1.0, 1.0))
		var cap := PackedVector2Array()
		for i in 49:
			var a := -t + 2.0 * t * i / 48.0
			cap.append(c + Vector2(cos(a), sin(a)) * (r - 1.0))
		draw_colored_polygon(cap, Color(0.25, 0.75, 1.0, 0.2))
		# Triangular lattice.
		var s := 11.0
		var row_h := s * 0.866
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var rows := int(2.0 * r / row_h) + 2
		var cols := int(2.0 * r / s) + 2
		var origin := c - Vector2(r, r)
		for j in rows:
			for i in cols:
				var p := origin + Vector2(i * s + (j % 2) * s * 0.5, j * row_h)
				var right := p + Vector2(s, 0)
				var down_l := p + Vector2(-s * 0.5, row_h)
				var down_r := p + Vector2(s * 0.5, row_h)
				if inside.call(p) and inside.call(down_l) and inside.call(down_r) and rng.randf() < 0.32:
					draw_colored_polygon(PackedVector2Array([p, down_l, down_r]), Color(0.55, 0.92, 1.0, rng.randf_range(0.12, 0.38)))
				for q in [right, down_l, down_r]:
					if inside.call(p) and inside.call(q):
						draw_line(p, q, Color(0.55, 0.9, 1.0, 0.42), 1.0, true)
		# Hard inner edge with nodes, plus a faint duplicate offset for a
		# slight "out of phase" shimmer.
		var half := sin(t) * r
		draw_line(Vector2(edge_x - 2, c.y - half + 2), Vector2(edge_x - 2, c.y + half - 2), Color(1.0, 0.3, 0.9, 0.25), 1.0, true)
		draw_line(Vector2(edge_x, c.y - half + 2), Vector2(edge_x, c.y + half - 2), Color(0.75, 0.97, 1.0, 0.95), 1.6, true)
		var ny := c.y - half + 8.0
		while ny < c.y + half - 6.0:
			_diamond(Vector2(edge_x, ny), 2.2, Color(0.8, 0.98, 1.0), Color(0, 0, 0, 0))
			ny += 14.0
		draw_arc(c, r - 2.0, -t, t, 40, Color(0.6, 0.95, 1.0, 0.6), 1.5, true)

	func _medallion(c: Vector2, r: float, glyph: String, element: Color, cooldown: float, key: String, cost: String, starved: bool) -> void:
		draw_circle(c, r + 6.0, Color(0, 0, 0, 0.35))
		draw_circle(c, r, GLASS_LIGHT)
		draw_circle(c, r * 0.72, Color(element, 0.12))
		draw_arc(c, r * 0.72, 0, TAU, 40, Color(element, 0.5), 1.0, true)
		_text(serif, c + Vector2(-r, 10), glyph, 26, element.lerp(Color.WHITE, 0.15) if not starved else element.darkened(0.5), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		if cooldown > 0.0:
			_dial(c, r - 1.0, cooldown)
		if starved:
			draw_circle(c, r - 1.0, Color(0.05, 0.1, 0.35, 0.45))
		draw_arc(c, r, 0, TAU, 48, GOLD, 2.0, true)
		draw_arc(c, r + 4.0, 0, TAU, 48, GOLD_FAINT, 1.0, true)
		_diamond(c + Vector2(0, r + 4.0), 9.0, GLASS, GOLD)
		_text(numbers, c + Vector2(-10, r + 9), key, 13, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 20)
		_text(numbers, c + Vector2(-r, -r - 6), cost, 12, MANA.lightened(0.45) if not starved else Color(1, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)

	## Edge-to-edge bar along the very bottom (Guild Wars 2 style): a glass
	## track with a gold fill, a notch every 5%, the level at the left end
	## and the XP count over the centre.
	func _xp_bar(pos: Vector2, width: float, fraction: float, level: int) -> void:
		var track := Rect2(pos - Vector2(0, 5), Vector2(width, 10))
		draw_rect(track, Color(0.02, 0.025, 0.04, 0.9))
		var fill := Rect2(track.position, Vector2(width * fraction, track.size.y))
		draw_rect(fill, GOLD.darkened(0.25))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), GOLD.lightened(0.25))
		draw_line(track.position, track.position + Vector2(width, 0), GOLD_DIM, 1.0)
		for i in range(1, 20):
			var x := width * i / 20.0
			draw_line(Vector2(x, track.position.y), Vector2(x, track.end.y), Color(0, 0, 0, 0.7) if i % 4 else Color(0, 0, 0, 0.9), 1.0 if i % 4 else 2.0)
		draw_circle(Vector2(width * fraction, pos.y), 2.5, Color(1, 0.95, 0.8))
		_diamond(Vector2(30, pos.y - 24), 16.0, GLASS, GOLD)
		_text(numbers, Vector2(18, pos.y - 18), str(level), 15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 24)
		_text(numbers, Vector2(width / 2.0 - 100, pos.y - 10), "1,140 / 3,000 XP", 12, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 200)

	## One engraved plate holding the four skills edge to edge.
	func _skill_bar(centre: Vector2, spells: Array) -> void:
		var tile := 70.0
		var gap := 6.0
		var pad := 10.0
		var width := spells.size() * tile + (spells.size() - 1) * gap + pad * 2.0
		var plate := Rect2(centre - Vector2(width / 2.0, tile / 2.0 + pad), Vector2(width, tile + pad * 2.0))
		_plate(plate)
		for i in spells.size():
			var s: Array = spells[i]
			var rect := Rect2(plate.position + Vector2(pad + i * (tile + gap), pad), Vector2(tile, tile))
			_facet_tile(rect, s[0], s[1], s[2], str(i + 1), s[3], i == 3)

	## Square with clipped corners, like a cut gem: element tint, glyph, cost,
	## key on a diamond at the bottom edge, and a dial sweep when recharging.
	func _facet_tile(rect: Rect2, glyph: String, element: Color, cooldown: float, key: String, cost: String, starved: bool) -> void:
		var cut := 10.0
		var p := rect.position
		var e := rect.end
		var shape := PackedVector2Array([
			p + Vector2(cut, 0), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
			Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), p + Vector2(0, cut)])
		draw_colored_polygon(shape, GLASS_LIGHT)
		var inner := PackedVector2Array()
		for v in shape:
			inner.append(rect.get_center() + (v - rect.get_center()) * 0.8)
		draw_colored_polygon(inner, Color(element, 0.14))
		var inner_loop := inner.duplicate()
		inner_loop.append(inner[0])
		draw_polyline(inner_loop, Color(element, 0.45), 1.0, true)
		var c := rect.get_center()
		_text(serif, c + Vector2(-rect.size.x / 2.0, 10), glyph, 26, element.lerp(Color.WHITE, 0.15) if not starved else element.darkened(0.55), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		if cooldown > 0.0:
			_square_dial(rect.grow(-2), cooldown)
		if starved:
			draw_colored_polygon(shape, Color(0.05, 0.1, 0.35, 0.45))
		var loop := shape.duplicate()
		loop.append(shape[0])
		draw_polyline(loop, GOLD, 1.8, true)
		_text(numbers, Vector2(e.x - 30, p.y + 15), cost, 12, MANA.lightened(0.45) if not starved else Color(1, 0.4, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 24)
		_diamond(Vector2(c.x, e.y), 9.0, GLASS, GOLD)
		_text(numbers, Vector2(c.x - 10, e.y + 5), key, 13, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 20)

	## Clock sweep clipped to a square, with the gold hand.
	func _square_dial(rect: Rect2, fraction: float) -> void:
		var c := rect.get_center()
		var reach := rect.size.length()
		var start := -PI / 2.0 + TAU * (1.0 - fraction)
		var pts := PackedVector2Array([c])
		for i in 33:
			var a := start + TAU * fraction * i / 32.0
			var q := c + Vector2(cos(a), sin(a)) * reach
			pts.append(Vector2(clampf(q.x, rect.position.x, rect.end.x), clampf(q.y, rect.position.y, rect.end.y)))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		var hand := c + Vector2(cos(start), sin(start)) * reach
		draw_line(c, Vector2(clampf(hand.x, rect.position.x, rect.end.x), clampf(hand.y, rect.position.y, rect.end.y)), GOLD, 2.0, true)

	func _stance(c: Vector2, r: float, title: String, glyph: String, page: String, cooldown: float) -> void:
		_text(serif, c + Vector2(-90, -r - 26), title, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 180)
		draw_circle(c, r + 10.0, Color(0, 0, 0, 0.35))
		draw_circle(c, r, GLASS_LIGHT)
		_dial(c, r - 1.0, cooldown)
		_text(numbers, c + Vector2(-r, 8), "3", 24, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		draw_arc(c, r, 0, TAU, 56, GOLD, 2.5, true)
		_ticks(c, r + 4.0, 48, 4, GOLD_DIM)
		var gem := c + Vector2(-r * 0.78, -r * 0.78)
		_diamond(gem, 10.0, Color(0.25, 0.18, 0.06), GOLD)
		_text(serif, gem + Vector2(-10, 5), page, 13, GOLD.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, 20)
		_text(serif, c + Vector2(-r, r + 22), _spaced("RMB"), 11, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)

	func _weapon_plate(pos: Vector2) -> void:
		var rect := Rect2(pos, Vector2(222, 74))
		_plate(rect)
		_text(serif, pos + Vector2(14, 28), "Gloom Cleaver", 17, RARE)
		_text(serif, pos + Vector2(14, 48), "Greatsword", 12, TEXT_DIM)
		_text(numbers, pos + Vector2(14, 66), "Set A", 12, GOLD_DIM)
		_text(numbers, pos + Vector2(100, 66), "Gold  12,480", 12, GOLD)

	func _plate(rect: Rect2) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = GLASS
		box.set_corner_radius_all(2)
		draw_style_box(box, rect)
		draw_rect(rect, GOLD_DIM, false, 1.2)
		draw_rect(rect.grow(-4), GOLD_FAINT, false, 1.0)
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			_diamond(corner, 4.0, GLASS, GOLD)

	func _enemy_bar(pos: Vector2, title: String, title_color: Color, health: float, ward: float) -> void:
		var width := 300.0
		_text(serif, pos + Vector2(0, -12), title, 15, title_color, HORIZONTAL_ALIGNMENT_CENTER, width)
		var ward_rect := Rect2(pos + Vector2(20, -2), Vector2(width - 40, 3))
		draw_rect(ward_rect, Color(AETHER, 0.18))
		draw_rect(Rect2(ward_rect.position, Vector2(ward_rect.size.x * ward, 3)), AETHER)
		var bar := Rect2(pos + Vector2(0, 5), Vector2(width, 8))
		draw_rect(bar, GLASS)
		draw_rect(Rect2(bar.position, Vector2(width * (health + 0.08), 8)), Color(0.95, 0.65, 0.55, 0.8))
		draw_rect(Rect2(bar.position, Vector2(width * health, 8)), LIFE.lightened(0.1))
		draw_rect(bar, GOLD_DIM, false, 1.0)
		_diamond(bar.position + Vector2(0, 4), 5.0, GLASS, GOLD)
		_diamond(bar.position + Vector2(width, 4), 5.0, GLASS, GOLD)

	func _item_card(pos: Vector2, width: float) -> void:
		var lines := 15
		var height := 120.0 + lines * 24.0
		var rect := Rect2(pos, Vector2(width, height))
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.04, 0.045, 0.07, 0.93)
		box.set_corner_radius_all(3)
		box.shadow_color = Color(0, 0, 0, 0.5)
		box.shadow_size = 12
		draw_style_box(box, rect)
		draw_rect(rect, GOLD, false, 1.5)
		draw_rect(rect.grow(-5), GOLD_FAINT, false, 1.0)
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			_diamond(corner, 6.0, GLASS, GOLD)
		var gem := Vector2(pos.x + width / 2.0, pos.y)
		draw_circle(gem, 15.0, Color(RARE, 0.18))
		_diamond(gem, 11.0, RARE.darkened(0.15), GOLD)
		_diamond(gem, 5.0, RARE.lightened(0.4), Color(0, 0, 0, 0))
		var x := pos.x
		var y := pos.y + 46.0
		_text(serif, Vector2(x, y), "Gloom Cleaver", 26, RARE, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 22
		_text(serif_italic, Vector2(x, y), "Greatsword  -  Two-Handed", 13, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 18
		_divider(x, y, width)
		y += 28
		var pad := 26.0
		_stat(x + pad, y, width - pad * 2, "Kinetic Damage", "42 - 61", Color(0.85, 0.82, 0.78), MOD_BLUE)
		y += 23
		_stat(x + pad, y, width - pad * 2, "Critical Chance", "5.5%", TEXT_DIM, TEXT)
		y += 23
		_stat(x + pad, y, width - pad * 2, "Attack Speed", "0.92", TEXT_DIM, TEXT)
		y += 16
		_divider(x, y, width)
		y += 26
		_text(serif, Vector2(x, y), "+12% increased Composure Damage", 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 14
		_divider(x, y, width)
		y += 26
		for mod in ["+23 Strength", "+18% increased Attack Speed", "Adds 6 - 11 Fire Damage to Attacks", "+31% chance to cause Bleed", "+14% increased Bleed Duration"]:
			_text(serif, Vector2(x, y), mod, 15, MOD_BLUE, HORIZONTAL_ALIGNMENT_CENTER, width)
			y += 23
		y -= 7
		_divider(x, y, width)
		y += 26
		_text(serif, Vector2(x, y), _spaced("STANCE") + "    Execute", 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 21
		_text(serif, Vector2(x, y), "A fully charged slam into a small area.", 13, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 16
		_divider(x, y, width)
		y += 26
		_text(serif_italic, Vector2(x, y), "\"It remembers every oath it broke.\"", 14, Color(0.78, 0.66, 0.46), HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 24
		_text(numbers, Vector2(x, y), "Item Level 34   -   Requires 40 Strength", 12, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, width)

	func _stat(x: float, y: float, width: float, label: String, value: String, label_color: Color, value_color: Color) -> void:
		_text(serif, Vector2(x, y), label, 15, label_color)
		_text(numbers, Vector2(x, y), value, 16, value_color, HORIZONTAL_ALIGNMENT_RIGHT, width)
		var lw := serif.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var vw := numbers.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var dots_from := x + lw + 8.0
		var dots_to := x + width - vw - 8.0
		var dx := dots_from
		while dx < dots_to:
			draw_circle(Vector2(dx, y - 4), 0.8, GOLD_FAINT)
			dx += 6.0
