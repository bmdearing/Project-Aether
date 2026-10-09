extends RefCounted
class_name SpellArt
## Code-drawn spell icons, one per ability_id, on a dark disc in the spell's
## colour. Spells without their own art fall back to their damage type's
## glyph. IconArt.draw() routes Abilities here.

## Spells whose damage type colour (mostly Kinetic grey) doesn't say what
## they are.
const ACCENTS := {
	"battle_cry": Color(0.95, 0.5, 0.25),
	"intimidating_shout": Color(0.85, 0.3, 0.3),
	"seismic_cry": Color(0.8, 0.62, 0.38),
	"blink": Color(0.55, 0.78, 1.0),
	"purge": Color(1.0, 0.92, 0.6),
	"tornado": Color(0.7, 0.88, 0.82),
	"caltrops": Color(0.78, 0.8, 0.86),
}
const FIRE_CORE := Color(1.0, 0.85, 0.35)
const ICE := Color(0.75, 0.93, 1.0)
const BOLT := Color(1.0, 0.97, 0.6)

static func colour_of(ability: Ability) -> Color:
	if ACCENTS.has(ability.ability_id):
		return ACCENTS[ability.ability_id]
	var c: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	return c.lightened(0.3) if c.get_luminance() < 0.3 else c

static func draw(ci: CanvasItem, ability: Ability, rect: Rect2) -> void:
	var pen := IconArt.Pen.new(ci, IconArt.fit(rect, 1.0, 0.04))
	var c := colour_of(ability)
	_backdrop(pen, c)
	match ability.ability_id:
		"battle_cry": _warcry(pen, c, "sword")
		"intimidating_shout": _warcry(pen, c, "skull")
		"seismic_cry": _seismic_cry(pen, c)
		"black_hole": _black_hole(pen, c)
		"blink": _blink(pen, c)
		"booming_blade": _booming_blade(pen, c)
		"caltrops": _caltrops(pen, c)
		"cinder_lance": _cinder_lance(pen, c)
		"comet": _comet(pen, c)
		"entropic_decay": _entropic_decay(pen, c)
		"flame_jets": _flame_jets(pen, c)
		"flame_wall": _flame_wall(pen, c)
		"frost_armor": _frost_armor(pen, c)
		"ice_pulse": _ice_pulse(pen, c)
		"inferno": _inferno(pen, c)
		"meteor": _meteor(pen, c)
		"purge": _purge(pen, c)
		"spark": _spark(pen, c)
		"static_discharge": _static_discharge(pen, c)
		"stormcall": _stormcall(pen, c)
		"thunder_javelin": _thunder_javelin(pen, c)
		"thunder_sweep": _thunder_sweep(pen, c)
		"tornado": _tornado(pen, c)
		"winters_eye": _winters_eye(pen, c)
		_:
			var tag := String(Constants.DAMAGE_TYPE_NAME.get(ability.damage_type, "")).to_lower()
			IconArt.glyph(pen, IconArt.DAMAGE_GLYPHS.get(tag, "star"), pen.v(0.5, 0.5), 0.6, c)

# --- helpers ------------------------------------------------------------------

static func _backdrop(pen: IconArt.Pen, c: Color) -> void:
	pen.circle(0.5, 0.5, 0.48, c.darkened(0.82))
	pen.ci.draw_circle(pen.v(0.5, 0.5), 0.36 * pen.unit(), pen.col(Color(c, 0.1)))
	pen.ci.draw_circle(pen.v(0.5, 0.5), 0.22 * pen.unit(), pen.col(Color(c, 0.1)))

static func _glow(pen: IconArt.Pen, x: float, y: float, r: float, c: Color, a: float = 0.25) -> void:
	pen.ci.draw_circle(pen.v(x, y), r * pen.unit(), pen.col(Color(c, a)))

static func _width(pen: IconArt.Pen, w: float) -> float:
	return maxf(1.0, w * pen.unit())

## Jagged line from a to b (normalised), the same zigzag every frame.
static func _zigzag(pen: IconArt.Pen, a: Vector2, b: Vector2, segments: int, amp: float, c: Color, w: float) -> void:
	var p := PackedVector2Array()
	var side := (b - a).orthogonal().normalized()
	for i in segments + 1:
		var t := float(i) / segments
		var offset := 0.0 if i == 0 or i == segments else amp * (1.0 if i % 2 == 0 else -1.0)
		var q := a.lerp(b, t) + side * offset
		p.append(pen.v(q.x, q.y))
	pen.stroke_px(p, Color(c, 0.35), _width(pen, w * 2.5))
	pen.stroke_px(p, c, _width(pen, w))

## Tapered streak, wide at `head` and pointed at `tail`.
static func _streak(pen: IconArt.Pen, tail: Vector2, head: Vector2, half_width: float, c: Color) -> void:
	var side := (head - tail).orthogonal().normalized() * half_width
	var p := PackedVector2Array([pen.v(tail.x, tail.y), pen.v(head.x + side.x, head.y + side.y), pen.v(head.x - side.x, head.y - side.y)])
	pen.ci.draw_colored_polygon(p, pen.col(c))

static func _flame(pen: IconArt.Pen, x: float, y: float, s: float, c: Color) -> void:
	IconArt.glyph(pen, "flame", pen.v(x, y), s, c)

static func _shard(pen: IconArt.Pen, centre: Vector2, angle: float, length: float, c: Color) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var side := dir.orthogonal() * length * 0.28
	var base := centre - dir * length * 0.3
	var tip := centre + dir * length * 0.7
	pen.poly([base.x + side.x, base.y + side.y, tip.x, tip.y, base.x - side.x, base.y - side.y], c)

# --- warcries -----------------------------------------------------------------

static func _sound_waves(pen: IconArt.Pen, centre: Vector2, c: Color, up_only: bool = false) -> void:
	var o := pen.v(centre.x, centre.y)
	for i in 3:
		var r := (0.24 + i * 0.08) * pen.unit()
		var colour := pen.col(Color(c, 0.9 - i * 0.25))
		var w := _width(pen, 0.035)
		if up_only:
			pen.ci.draw_arc(o, r, PI * 1.15, PI * 1.85, 16, colour, w, true)
		else:
			pen.ci.draw_arc(o, r, PI * 0.78, PI * 1.22, 10, colour, w, true)
			pen.ci.draw_arc(o, r, -PI * 0.22, PI * 0.22, 10, colour, w, true)

static func _warcry(pen: IconArt.Pen, c: Color, glyph_name: String) -> void:
	_glow(pen, 0.5, 0.5, 0.22, c, 0.3)
	_sound_waves(pen, Vector2(0.5, 0.5), c)
	IconArt.glyph(pen, glyph_name, pen.v(0.5, 0.5), 0.42, c.lerp(Color.WHITE, 0.35))

static func _seismic_cry(pen: IconArt.Pen, c: Color) -> void:
	_sound_waves(pen, Vector2(0.5, 0.66), c, true)
	pen.poly([0.1, 0.68, 0.9, 0.68, 0.86, 0.84, 0.14, 0.84], c.darkened(0.55))
	pen.stroke_px(pen.pts([0.3, 0.68, 0.38, 0.76, 0.34, 0.84]), Color(1, 0.75, 0.4), _width(pen, 0.025))
	pen.stroke_px(pen.pts([0.62, 0.68, 0.56, 0.75, 0.64, 0.84]), Color(1, 0.75, 0.4), _width(pen, 0.025))
	pen.poly([0.22, 0.5, 0.28, 0.46, 0.3, 0.53, 0.24, 0.56], c.darkened(0.2))
	pen.poly([0.72, 0.44, 0.79, 0.42, 0.8, 0.5, 0.73, 0.51], c.darkened(0.2))
	pen.poly([0.47, 0.36, 0.53, 0.34, 0.55, 0.41, 0.48, 0.42], c.darkened(0.2))

# --- entropic -----------------------------------------------------------------

static func _black_hole(pen: IconArt.Pen, c: Color) -> void:
	var centre := pen.v(0.5, 0.5)
	for arm in 3:
		var p := PackedVector2Array()
		for i in 22:
			var t := i / 21.0
			var a := arm * TAU / 3.0 + t * PI * 1.6
			p.append(centre + Vector2(cos(a), sin(a)) * (0.42 - t * 0.28) * pen.unit())
		pen.stroke_px(p, Color(c.lightened(0.2), 0.85), _width(pen, 0.05))
	_glow(pen, 0.5, 0.5, 0.2, c, 0.5)
	pen.circle(0.5, 0.5, 0.12, Color(0.02, 0.0, 0.04))
	pen.ci.draw_arc(centre, 0.13 * pen.unit(), 0.0, TAU, 24, pen.col(c.lightened(0.4)), _width(pen, 0.02), true)

static func _entropic_decay(pen: IconArt.Pen, c: Color) -> void:
	var centre := pen.v(0.5, 0.5)
	for i in 3:
		var r := (0.18 + i * 0.11) * pen.unit()
		for k in 6:
			var a0 := k * TAU / 6.0 + i * 0.4
			pen.ci.draw_arc(centre, r, a0, a0 + TAU / 6.0 * 0.6, 6, pen.col(Color(c.lightened(0.15), 0.9 - i * 0.22)), _width(pen, 0.035), true)
	for k in 7:
		var a := k * 2.4
		var q := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * (0.24 + (k % 3) * 0.07)
		pen.ci.draw_rect(Rect2(pen.v(q.x, q.y), Vector2.ONE * 0.035 * pen.unit()), pen.col(c.lightened(0.3)))
	pen.circle(0.5, 0.5, 0.08, c.lightened(0.2))

# --- utility ------------------------------------------------------------------

static func _blink(pen: IconArt.Pen, c: Color) -> void:
	for i in 3:
		var x := 0.2 + i * 0.16
		var colour := Color(c, 0.3 + i * 0.25)
		pen.stroke_px(pen.pts([x, 0.3, x + 0.14, 0.5, x, 0.7]), colour, _width(pen, 0.07))
	IconArt.glyph(pen, "star", pen.v(0.78, 0.5), 0.32, c.lerp(Color.WHITE, 0.4))

static func _purge(pen: IconArt.Pen, c: Color) -> void:
	_glow(pen, 0.5, 0.5, 0.34, c, 0.2)
	IconArt.glyph(pen, "burst", pen.v(0.5, 0.5), 0.72, c)
	pen.circle(0.5, 0.5, 0.12, Color(1, 1, 0.92))
	for q in [Vector2(0.2, 0.24), Vector2(0.8, 0.3), Vector2(0.74, 0.8), Vector2(0.24, 0.76)]:
		IconArt.glyph(pen, "star", pen.v(q.x, q.y), 0.14, Color(1, 1, 0.9))

static func _tornado(pen: IconArt.Pen, c: Color) -> void:
	for i in 7:
		var t := i / 6.0
		var y := 0.82 - t * 0.62
		var rx := 0.05 + t * 0.3
		var cx := 0.5 + sin(t * 4.0) * 0.05
		var p := PackedVector2Array()
		for k in 17:
			var a := k * TAU / 16.0
			p.append(pen.v(cx + cos(a) * rx, y + sin(a) * rx * 0.25))
		pen.stroke_px(p, Color(c, 0.45 + t * 0.5), _width(pen, 0.03))
	for q in [Vector2(0.24, 0.62), Vector2(0.78, 0.5), Vector2(0.3, 0.3)]:
		pen.ci.draw_rect(Rect2(pen.v(q.x, q.y), Vector2.ONE * 0.04 * pen.unit()), pen.col(c.darkened(0.3)))

# --- piercing -----------------------------------------------------------------

static func _caltrops(pen: IconArt.Pen, c: Color) -> void:
	var ground := PackedVector2Array()
	for k in 25:
		var a := k * TAU / 24.0
		ground.append(pen.v(0.5 + cos(a) * 0.4, 0.66 + sin(a) * 0.14))
	pen.ci.draw_colored_polygon(ground, pen.col(Color(c, 0.12)))
	for q in [Vector2(0.3, 0.62), Vector2(0.55, 0.56), Vector2(0.72, 0.68), Vector2(0.44, 0.74), Vector2(0.5, 0.36)]:
		var s := 0.24 if q.y > 0.4 else 0.36
		var star := PackedVector2Array()
		for i in 8:
			var a := i * TAU / 8.0 + 0.3
			star.append(pen.v(q.x, q.y) + Vector2(cos(a), sin(a)) * s * pen.unit() * (0.5 if i % 2 == 0 else 0.14))
		pen.fill(star, c)

# --- fire ---------------------------------------------------------------------

static func _cinder_lance(pen: IconArt.Pen, c: Color) -> void:
	_streak(pen, Vector2(0.1, 0.9), Vector2(0.72, 0.28), 0.1, Color(c, 0.6))
	_streak(pen, Vector2(0.2, 0.8), Vector2(0.78, 0.22), 0.05, FIRE_CORE)
	pen.poly([0.7, 0.22, 0.9, 0.1, 0.78, 0.3], Color(1, 0.95, 0.75))
	for q in [Vector2(0.32, 0.5), Vector2(0.5, 0.74), Vector2(0.22, 0.62), Vector2(0.62, 0.56)]:
		pen.ci.draw_circle(pen.v(q.x, q.y), 0.025 * pen.unit(), pen.col(FIRE_CORE))

static func _flame_jets(pen: IconArt.Pen, c: Color) -> void:
	pen.ci.draw_colored_polygon(pen.pts([0.12, 0.5, 0.92, 0.18, 0.92, 0.82]), pen.col(Color(c, 0.35)))
	pen.ci.draw_colored_polygon(pen.pts([0.12, 0.5, 0.86, 0.34, 0.86, 0.66]), pen.col(Color(FIRE_CORE, 0.55)))
	for i in 3:
		var x := 0.42 + i * 0.16
		_flame(pen, x, 0.5 + (0.12 if i == 1 else -0.1), 0.2 + i * 0.05, c)
	pen.circle(0.12, 0.5, 0.06, FIRE_CORE)

static func _flame_wall(pen: IconArt.Pen, c: Color) -> void:
	pen.rect(0.08, 0.74, 0.92, 0.8, c.darkened(0.5))
	for i in 4:
		var x := 0.2 + i * 0.2
		var tall := 0.5 if i % 2 == 0 else 0.4
		_flame(pen, x, 0.74 - tall * 0.5, tall, c)

static func _inferno(pen: IconArt.Pen, c: Color) -> void:
	var base := PackedVector2Array()
	for k in 25:
		var a := k * TAU / 24.0
		base.append(pen.v(0.5 + cos(a) * 0.34, 0.8 + sin(a) * 0.08))
	pen.ci.draw_colored_polygon(base, pen.col(Color(c, 0.45)))
	_flame(pen, 0.5, 0.48, 0.8, c)
	_flame(pen, 0.3, 0.66, 0.3, c)
	_flame(pen, 0.7, 0.64, 0.32, c)

static func _meteor(pen: IconArt.Pen, c: Color) -> void:
	_streak(pen, Vector2(0.06, 0.06), Vector2(0.58, 0.58), 0.2, Color(c, 0.45))
	_streak(pen, Vector2(0.18, 0.18), Vector2(0.58, 0.58), 0.1, Color(FIRE_CORE, 0.8))
	pen.poly([0.48, 0.48, 0.66, 0.42, 0.82, 0.56, 0.78, 0.78, 0.58, 0.84, 0.44, 0.68], Color(0.32, 0.12, 0.08))
	pen.stroke_px(pen.pts([0.56, 0.54, 0.64, 0.64, 0.6, 0.76]), FIRE_CORE, _width(pen, 0.025))
	pen.stroke_px(pen.pts([0.64, 0.64, 0.76, 0.62]), FIRE_CORE, _width(pen, 0.02))

# --- cold ---------------------------------------------------------------------

static func _comet(pen: IconArt.Pen, c: Color) -> void:
	_streak(pen, Vector2(0.94, 0.06), Vector2(0.44, 0.56), 0.17, Color(c, 0.35))
	_streak(pen, Vector2(0.86, 0.14), Vector2(0.44, 0.56), 0.09, Color(ICE, 0.7))
	pen.circle(0.4, 0.6, 0.17, c)
	pen.circle(0.4, 0.6, 0.11, ICE)
	pen.shine(0.35, 0.54, 0.04)
	for a in [PI * 0.6, PI * 0.85, PI * 0.35]:
		_shard(pen, Vector2(0.4, 0.6) + Vector2(cos(a), sin(a)) * 0.24, a, 0.1, ICE)

static func _frost_armor(pen: IconArt.Pen, c: Color) -> void:
	for i in 8:
		var a := i * TAU / 8.0
		_shard(pen, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.34, a, 0.14, ICE)
	pen.poly([0.3, 0.26, 0.7, 0.26, 0.7, 0.5, 0.5, 0.76, 0.3, 0.5], c)
	IconArt.glyph(pen, "snowflake", pen.v(0.5, 0.46), 0.3, Color(1, 1, 1))

static func _ice_pulse(pen: IconArt.Pen, c: Color) -> void:
	var centre := pen.v(0.5, 0.5)
	pen.ci.draw_arc(centre, 0.27 * pen.unit(), 0.0, TAU, 32, pen.col(Color(ICE, 0.5)), _width(pen, 0.08), true)
	for i in 10:
		var a := i * TAU / 10.0
		_shard(pen, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.36, a, 0.13, ICE)
	IconArt.glyph(pen, "snowflake", centre, 0.32, c.lerp(Color.WHITE, 0.4))

static func _winters_eye(pen: IconArt.Pen, c: Color) -> void:
	for i in 9:
		var t := i / 8.0
		var a := t * PI * 2.2
		var q := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * (0.2 + t * 0.2)
		_shard(pen, q, a + PI * 0.5, 0.08 + t * 0.05, ICE)
	_glow(pen, 0.5, 0.5, 0.2, c, 0.4)
	pen.circle(0.5, 0.5, 0.13, c)
	pen.circle(0.5, 0.5, 0.06, Color(1, 1, 1))

# --- lightning ----------------------------------------------------------------

static func _booming_blade(pen: IconArt.Pen, c: Color) -> void:
	_glow(pen, 0.5, 0.42, 0.26, c, 0.25)
	pen.poly([0.5, 0.08, 0.56, 0.18, 0.56, 0.66, 0.44, 0.66, 0.44, 0.18], IconArt.STEEL)
	pen.rect(0.32, 0.66, 0.68, 0.71, IconArt.GOLD)
	pen.rect(0.46, 0.71, 0.54, 0.88, IconArt.LEATHER)
	_zigzag(pen, Vector2(0.62, 0.12), Vector2(0.64, 0.62), 6, 0.05, BOLT, 0.025)
	_zigzag(pen, Vector2(0.38, 0.2), Vector2(0.36, 0.58), 5, 0.04, BOLT, 0.02)

static func _spark(pen: IconArt.Pen, c: Color) -> void:
	pen.rect(0.1, 0.78, 0.9, 0.8, Color(c, 0.4))
	for i in 3:
		var x := 0.18 + i * 0.26
		var head := Vector2(x + 0.18, 0.62 - i * 0.12)
		_zigzag(pen, Vector2(x, 0.76), head, 4, 0.04, c, 0.025)
		_glow(pen, head.x, head.y, 0.08, c, 0.4)
		pen.circle(head.x, head.y, 0.04, BOLT)

static func _static_discharge(pen: IconArt.Pen, c: Color) -> void:
	for q in [Vector2(0.16, 0.22), Vector2(0.86, 0.3), Vector2(0.8, 0.84), Vector2(0.2, 0.78)]:
		_zigzag(pen, Vector2(0.5, 0.5), q, 5, 0.035, c, 0.025)
		pen.circle(q.x, q.y, 0.04, BOLT)
	_glow(pen, 0.5, 0.5, 0.2, c, 0.4)
	pen.circle(0.5, 0.5, 0.11, BOLT)

static func _stormcall(pen: IconArt.Pen, c: Color) -> void:
	_zigzag(pen, Vector2(0.5, 0.36), Vector2(0.48, 0.7), 4, 0.05, BOLT, 0.035)
	_zigzag(pen, Vector2(0.48, 0.7), Vector2(0.28, 0.88), 3, 0.03, BOLT, 0.025)
	_zigzag(pen, Vector2(0.48, 0.7), Vector2(0.7, 0.88), 3, 0.03, BOLT, 0.025)
	var cloud := Color(0.42, 0.44, 0.52)
	for q in [Vector2(0.3, 0.3), Vector2(0.5, 0.22), Vector2(0.7, 0.3), Vector2(0.42, 0.34), Vector2(0.6, 0.35)]:
		pen.ci.draw_circle(pen.v(q.x, q.y), 0.14 * pen.unit(), pen.col(cloud))
	pen.ci.draw_circle(pen.v(0.48, 0.2), 0.08 * pen.unit(), pen.col(cloud.lightened(0.2)))

static func _thunder_javelin(pen: IconArt.Pen, c: Color) -> void:
	pen.line([0.14, 0.86, 0.74, 0.26], IconArt.WOOD, 0.045)
	pen.poly([0.7, 0.22, 0.9, 0.1, 0.78, 0.3], IconArt.STEEL)
	_zigzag(pen, Vector2(0.18, 0.74), Vector2(0.8, 0.12), 9, 0.05, BOLT, 0.022)
	_glow(pen, 0.84, 0.16, 0.1, c, 0.4)

static func _thunder_sweep(pen: IconArt.Pen, c: Color) -> void:
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		var q := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.42
		_zigzag(pen, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.1, q, 4, 0.03, c, 0.022)
	pen.circle(0.5, 0.5, 0.08, BOLT)
