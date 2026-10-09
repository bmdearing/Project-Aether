extends RefCounted
class_name IconArt
## Code-drawn inventory icons. Every Item type, Slate, Figment, Maw Fragment
## and currency id gets vector art, fitted to any rect at that thing's own
## footprint aspect, so it fits grid blocks, paper-doll slots and list rows
## alike. ItemIcon is the Control that calls draw().

const OUTLINE := Color(0.03, 0.03, 0.05, 0.95)
const STEEL := Color(0.74, 0.76, 0.8)
const DARK_STEEL := Color(0.42, 0.44, 0.5)
const IRON := Color(0.3, 0.31, 0.35)
const WOOD := Color(0.52, 0.34, 0.2)
const LEATHER := Color(0.42, 0.27, 0.16)
const GOLD := Color(0.88, 0.7, 0.3)
const BRONZE := Color(0.72, 0.5, 0.3)
const PARCHMENT := Color(0.9, 0.84, 0.66)
const SLATE_STONE := Color(0.2, 0.22, 0.25)
const SPELL_TAG_COLOR := Color(0.62, 0.45, 0.92)

## Orb id -> [colour, glyph].
const ORBS := {
	"absolution": [Color(0.92, 0.92, 0.86), "ring"],
	"anchoring": [Color(0.33, 0.5, 0.72), "anchor"],
	"ascendant": [Color(0.95, 0.74, 0.22), "arrow_up"],
	"elevation": [Color(0.28, 0.72, 0.68), "chevrons_up"],
	"forging": [Color(0.92, 0.45, 0.14), "hammer"],
	"grafting": [Color(0.4, 0.74, 0.3), "branch"],
	"opening": [Color(0.5, 0.5, 0.56), "socket"],
	"quickening": [Color(0.5, 0.8, 0.95), "chevron_up"],
	"recasting": [Color(0.6, 0.4, 0.86), "cycle"],
	"reckoning": [Color(0.84, 0.3, 0.3), "dice"],
	"severance": [Color(0.55, 0.1, 0.14), "slash"],
	"tempering": [Color(0.74, 0.52, 0.32), "diamond"],
}

## Brand suffix -> [colour, glyph] for the non-damage-type Brands.
const BRAND_KINDS := {
	"armor": [Color(0.55, 0.62, 0.72), "shield"],
	"evasion": [Color(0.45, 0.78, 0.45), "swoosh"],
	"ward": [Color(0.55, 0.75, 0.95), "ward"],
	"resistance": [Color(0.8, 0.6, 0.4), "shield_tri"],
	"resilience": [Color(0.85, 0.35, 0.4), "heart"],
	"life": [Color(0.9, 0.18, 0.22), "plus"],
	"critical": [Color(0.95, 0.8, 0.3), "diamond"],
	"attack": [Color(0.85, 0.35, 0.25), "sword"],
	"spell": [SPELL_TAG_COLOR, "star"],
	"mana": [Color(0.3, 0.5, 0.95), "drop"],
	"speed": [Color(0.55, 0.9, 0.5), "chevrons_right"],
	"preservation": [Color(0.9, 0.75, 0.35), "lock"],
	"prefix": [Color(0.92, 0.88, 0.75), "P"],
	"suffix": [Color(0.92, 0.88, 0.75), "S"],
}

const DAMAGE_GLYPHS := {
	"kinetic": "impact", "piercing": "arrowhead", "explosive": "burst",
	"fire": "flame", "cold": "snowflake", "lightning": "bolt",
	"aetheric": "spiral", "entropic": "void", "pale": "crescent",
}

## Maw Fragment id -> [quadrant start angle, colour, accent].
const FRAGMENTS := {
	"maw_fragment_ash": [PI, Color(0.55, 0.5, 0.47), Color(1.0, 0.5, 0.15)],
	"maw_fragment_tide": [PI * 1.5, Color(0.22, 0.45, 0.75), Color(0.6, 0.9, 1.0)],
	"maw_fragment_storm": [0.0, Color(0.78, 0.72, 0.25), Color(1.0, 1.0, 0.7)],
	"maw_fragment_hollow": [PI * 0.5, Color(0.42, 0.25, 0.62), Color(0.85, 0.6, 1.0)],
}

## Draw state: maps normalised (0..1) coords into the fitted box and gives
## every filled shape a dark outline. A ghost pen draws one flat colour and
## no outlines (empty paper-doll slots).
class Pen:
	var ci: CanvasItem
	var box: Rect2
	var ow: float
	var ghost: Color = Color(0, 0, 0, 0)

	func _init(p_ci: CanvasItem, p_box: Rect2) -> void:
		ci = p_ci
		box = p_box
		ow = clampf(minf(box.size.x, box.size.y) * 0.03, 1.0, 2.5)

	func v(x: float, y: float) -> Vector2:
		return box.position + Vector2(x * box.size.x, y * box.size.y)

	## Pixels per normalised unit of width; glyphs and circles use it so
	## they stay round in tall boxes.
	func unit() -> float:
		return box.size.x

	func pts(a: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in range(0, a.size(), 2):
			out.append(v(a[i], a[i + 1]))
		return out

	func col(c: Color) -> Color:
		return c if ghost.a == 0.0 else ghost

	func fill(p: PackedVector2Array, c: Color) -> void:
		if p.size() < 3 or Geometry2D.triangulate_polygon(p).is_empty():
			return
		ci.draw_colored_polygon(p, col(c))
		if ghost.a == 0.0:
			var closed := p.duplicate()
			closed.append(p[0])
			ci.draw_polyline(closed, OUTLINE, ow, true)

	func poly(a: Array, c: Color) -> void:
		fill(pts(a), c)

	func rect(x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
		poly([x0, y0, x1, y0, x1, y1, x0, y1], c)

	func circle(x: float, y: float, r: float, c: Color) -> void:
		circle_px(v(x, y), r * unit(), c)

	func circle_px(centre: Vector2, r: float, c: Color) -> void:
		if ghost.a == 0.0:
			ci.draw_circle(centre, r + ow * 0.8, OUTLINE)
		ci.draw_circle(centre, r, col(c))

	## Thick outlined stroke through normalised points; w is a fraction of width.
	func line(a: Array, c: Color, w: float) -> void:
		stroke_px(pts(a), c, w * unit(), true)

	func stroke_px(p: PackedVector2Array, c: Color, w: float, outlined: bool = false) -> void:
		if outlined and ghost.a == 0.0:
			ci.draw_polyline(p, OUTLINE, w + ow * 2.0, true)
		ci.draw_polyline(p, col(c), w, true)

	func shine(x: float, y: float, r: float) -> void:
		if ghost.a == 0.0:
			ci.draw_circle(v(x, y), r * unit(), Color(1, 1, 1, 0.55))

	func text(s: String, x: float, y: float, size_frac: float, c: Color) -> void:
		var font := AetherStyle.numbers()
		var px := maxi(8, int(size_frac * unit()))
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var pos := v(x, y) + Vector2(-w * 0.5, px * 0.36)
		if ghost.a == 0.0:
			ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, int(px / 6.0)), OUTLINE)
		ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col(c))

# --- entry points -------------------------------------------------------------

## Art key for an Item, Slate or currency id.
static func key_of(content) -> StringName:
	if content is Ability:
		return &"spell"
	if content is StringName:
		return content
	if content is Slate:
		return &"slate"
	if content is Item:
		var t: StringName = content.get_item_type()
		if t == &"currency" or t == &"":
			return StringName(content.item_id)
		return t
	return &""

## Width / height of the art, from the footprint table (1:1 off-table).
static func aspect_of(key: StringName) -> float:
	var fp := FootprintTable.footprint_for_type(key)
	return float(fp.x) / float(fp.y)

## Largest box of `aspect` centred in `rect`, inset by `pad` of its size.
static func fit(rect: Rect2, aspect: float, pad: float = 0.08) -> Rect2:
	var inner := rect.grow_individual(-rect.size.x * pad, -rect.size.y * pad, -rect.size.x * pad, -rect.size.y * pad)
	var s := inner.size
	if s.x / s.y > aspect:
		s.x = s.y * aspect
	else:
		s.y = s.x / aspect
	return Rect2(inner.position + (inner.size - s) * 0.5, s)

static func draw(ci: CanvasItem, content, rect: Rect2) -> void:
	if content is Ability:
		SpellArt.draw(ci, content, rect)
		return
	var key := key_of(content)
	if key == &"":
		return
	var pen := Pen.new(ci, fit(rect, aspect_of(key)))
	var accent := GOLD
	if content is Item:
		accent = Constants.ITEM_RARITY_COLOR.get(content.rarity, GOLD)
	_draw_key(pen, key, content, accent)

## Faint silhouette of an item type, for an empty equipment slot.
static func draw_ghost(ci: CanvasItem, key: StringName, rect: Rect2, colour: Color) -> void:
	var pen := Pen.new(ci, fit(rect, aspect_of(key), 0.14))
	pen.ghost = colour
	_draw_key(pen, key, null, colour)

static func _draw_key(pen: Pen, key: StringName, content, accent: Color) -> void:
	var k := String(key)
	if content is Slate:
		_slate(pen, content)
		return
	if content is FigmentItem:
		_figment(pen, content.tier)
		return
	if content is Lens:
		_lens(pen, accent)
		return
	if content is Jewel:
		_jewel(pen, accent)
		return
	if content is SkillTome:
		_skill_tome(pen, content)
		return
	if ORBS.has(k):
		_orb(pen, ORBS[k][0], ORBS[k][1])
		return
	if FRAGMENTS.has(k):
		_fragment(pen, FRAGMENTS[k])
		return
	if k.begins_with("brand_"):
		_brand(pen, k.trim_prefix("brand_"))
		return
	if k.begins_with("edict_"):
		_edict(pen, k.trim_prefix("edict_"))
		return
	if k.begins_with("vestige"):
		_plate(pen, Color(0.7, 0.2, 0.25), "skull")
		return
	match k:
		"crystallized_aether": _aether_crystals(pen)
		"infusion_stone": _stone(pen, Color(0.38, 0.5, 0.6), Color(0.45, 0.95, 1.0), "plus")
		"shrivening_stone": _stone(pen, Color(0.42, 0.4, 0.38), Color(0.85, 0.75, 0.6), "minus")
		"shard_of_tharsis": _tharsis(pen)
		"figment": _figment(pen, 1)
		"jewel": _jewel(pen, accent)
		"lens": _lens(pen, accent)
		"skill_tome": _book(pen, Color(0.2, 0.32, 0.6), GOLD, "star")
		"slate": _slate_blank(pen)
		# Armour and jewellery
		"helmet": _helmet(pen, accent)
		"body_armour": _body_armour(pen, accent)
		"gloves": _glove(pen, LEATHER, accent)
		"boots": _boot(pen, accent)
		"belt": _belt(pen, accent)
		"ring": _ring(pen, accent)
		"amulet": _amulet(pen, accent)
		# Shields
		"buckler": _buckler(pen, accent)
		"tower_shield", "great_shield", "pavise": _tower_shield(pen, accent, k)
		"shield", "kite_shield", "spiked_shield", "rune_shield", "warded_barrier": _kite_shield(pen, accent, k)
		# Blades
		"shortsword": _sword(pen, accent, 0.08, 0.0, 0.62)
		"saber": _sword(pen, accent, 0.075, 0.12, 0.62)
		"cutlass": _sword(pen, accent, 0.095, 0.16, 0.62)
		"rapier": _rapier(pen, accent)
		"greatsword": _sword(pen, accent, 0.11, 0.0, 0.66)
		"claymore": _sword(pen, accent, 0.1, 0.0, 0.66, true)
		"dagger": _dagger(pen, accent, 0.0)
		"athame": _dagger(pen, accent, 0.12)
		# Hafted
		"greataxe": _axe(pen, accent)
		"mace": _mace(pen, accent)
		"war_pick": _war_pick(pen, accent)
		"spear": _polearm(pen, accent, "spear")
		"halberd": _polearm(pen, accent, "halberd")
		"shock_lance": _lance(pen, accent)
		"whip": _whip(pen, accent)
		# Bows
		"shortbow", "bow": _bow(pen, accent, false)
		"longbow": _bow(pen, accent, true)
		"crossbow": _crossbow(pen, accent)
		# Firearms
		"service_pistol", "revolver", "voltage_pistol", "thermal_pistol", "machine_pistol": _pistol(pen, accent, k)
		"battle_rifle", "lever_action_rifle", "bolt_action_rifle", "pressurized_rifle", "jet_rifle", "rail_carbine", "loaded_shotgun", "pump_action_shotgun", "submachine_gun", "machine_gun": _long_gun(pen, accent, k)
		# Fists
		"gauntlet", "pressure_fist": _glove(pen, STEEL, accent)
		"spell_gauntlet": _glove(pen, Color(0.45, 0.4, 0.6), SPELL_TAG_COLOR)
		# Casters
		"staff": _staff(pen, accent)
		"rod": _rod(pen, accent)
		"wand": _wand(pen, accent)
		"tome": _book(pen, Color(0.45, 0.27, 0.15), accent, "rune")
		"grimoire": _book(pen, Color(0.3, 0.14, 0.38), accent, "eye")
		"focus": _focus(pen, accent)
		"lantern": _lantern(pen, accent)
		"talisman": _talisman(pen, accent)
		"charm": _charm(pen, accent)
		"seal": _seal(pen, accent)
		"fetish": _fetish(pen, accent)
		_:
			_orb(pen, GOLD, "?" + k.substr(0, 1).to_upper())

# --- currency -----------------------------------------------------------------

static func _orb(pen: Pen, c: Color, glyph_name: String) -> void:
	pen.circle(0.5, 0.5, 0.4, c.darkened(0.45))
	pen.ci.draw_circle(pen.v(0.47, 0.47), 0.35 * pen.unit(), pen.col(c))
	pen.ci.draw_circle(pen.v(0.5, 0.5), 0.2 * pen.unit(), pen.col(Color(c.lightened(0.25), 0.35)))
	pen.shine(0.36, 0.33, 0.07)
	var gc := Color(1, 1, 1, 0.95) if c.get_luminance() < 0.6 else Color(0.15, 0.12, 0.1, 0.95)
	glyph(pen, glyph_name, pen.v(0.5, 0.52), 0.42, gc)

## Hexagonal plate with a glowing glyph: Brands and Vestiges.
static func _plate(pen: Pen, c: Color, glyph_name: String) -> void:
	var hex: Array = []
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		hex.append_array([0.5 + cos(a) * 0.42, 0.5 + sin(a) * 0.42])
	pen.poly(hex, IRON)
	var inner: Array = []
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		inner.append_array([0.5 + cos(a) * 0.33, 0.5 + sin(a) * 0.33])
	pen.poly(inner, c.darkened(0.7))
	var glow := c.lightened(0.3) if c.get_luminance() < 0.35 else c
	pen.ci.draw_circle(pen.v(0.5, 0.5), 0.26 * pen.unit(), pen.col(Color(glow, 0.22)))
	glyph(pen, glyph_name, pen.v(0.5, 0.5), 0.38, glow)
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		pen.ci.draw_circle(pen.v(0.5 + cos(a) * 0.375, 0.5 + sin(a) * 0.375), 0.025 * pen.unit(), pen.col(DARK_STEEL.lightened(0.3)))

static func _brand(pen: Pen, kind: String) -> void:
	if DAMAGE_GLYPHS.has(kind):
		var dt: int = Constants.DAMAGE_TYPE_TAGS[kind]
		_plate(pen, Constants.DAMAGE_TYPE_COLOR[dt], DAMAGE_GLYPHS[kind])
	elif BRAND_KINDS.has(kind):
		_plate(pen, BRAND_KINDS[kind][0], BRAND_KINDS[kind][1])
	else:
		_plate(pen, GOLD, "rune")

static func _edict(pen: Pen, kind: String) -> void:
	var seal_colour := Color(0.75, 0.15, 0.15)
	var glyph_name := "rune"
	match kind:
		"attack": glyph_name = "sword"
		"spell":
			glyph_name = "star"
			seal_colour = Color(0.45, 0.25, 0.7)
		"prefix":
			glyph_name = "P"
			seal_colour = Color(0.2, 0.32, 0.65)
		"suffix":
			glyph_name = "S"
			seal_colour = Color(0.2, 0.32, 0.65)
	pen.rect(0.24, 0.18, 0.76, 0.82, PARCHMENT)
	for y in [0.32, 0.42]:
		pen.stroke_px(PackedVector2Array([pen.v(0.32, y), pen.v(0.68, y)]), Color(0.5, 0.42, 0.3, 0.8), 0.025 * pen.unit())
	pen.rect(0.18, 0.1, 0.82, 0.2, PARCHMENT.darkened(0.2))
	pen.rect(0.18, 0.8, 0.82, 0.9, PARCHMENT.darkened(0.2))
	pen.circle(0.5, 0.64, 0.17, seal_colour)
	glyph(pen, glyph_name, pen.v(0.5, 0.64), 0.2, Color(1, 0.9, 0.8))

static func _stone(pen: Pen, c: Color, glow: Color, glyph_name: String) -> void:
	pen.poly([0.28, 0.2, 0.62, 0.12, 0.84, 0.32, 0.86, 0.66, 0.66, 0.88, 0.3, 0.86, 0.14, 0.62, 0.14, 0.36], c)
	pen.poly([0.3, 0.24, 0.6, 0.17, 0.66, 0.26, 0.34, 0.34], c.lightened(0.2))
	pen.ci.draw_circle(pen.v(0.5, 0.54), 0.22 * pen.unit(), pen.col(Color(glow, 0.2)))
	glyph(pen, glyph_name, pen.v(0.5, 0.54), 0.32, glow)

static func _tharsis(pen: Pen) -> void:
	var c := Color(0.62, 0.08, 0.14)
	pen.ci.draw_circle(pen.v(0.5, 0.5), 0.36 * pen.unit(), pen.col(Color(1.0, 0.2, 0.2, 0.16)))
	pen.poly([0.52, 0.06, 0.7, 0.3, 0.64, 0.5, 0.76, 0.72, 0.5, 0.95, 0.3, 0.7, 0.38, 0.48, 0.28, 0.3], c)
	pen.poly([0.52, 0.06, 0.6, 0.3, 0.5, 0.52, 0.38, 0.48, 0.28, 0.3], c.lightened(0.25))
	pen.stroke_px(pen.pts([0.45, 0.62, 0.55, 0.7, 0.5, 0.82]), Color(1, 0.6, 0.5, 0.9), 0.025 * pen.unit())

static func _aether_crystals(pen: Pen) -> void:
	var c: Color = Constants.DAMAGE_TYPE_COLOR[Constants.DamageType.AETHERIC].lightened(0.2)
	pen.ci.draw_circle(pen.v(0.5, 0.55), 0.36 * pen.unit(), pen.col(Color(c, 0.18)))
	pen.poly([0.2, 0.86, 0.18, 0.5, 0.27, 0.38, 0.36, 0.5, 0.36, 0.86], c.darkened(0.15))
	pen.poly([0.64, 0.86, 0.64, 0.45, 0.74, 0.32, 0.84, 0.45, 0.82, 0.86], c.darkened(0.1))
	pen.poly([0.36, 0.88, 0.36, 0.3, 0.5, 0.08, 0.64, 0.3, 0.64, 0.88], c)
	pen.poly([0.5, 0.08, 0.64, 0.3, 0.64, 0.88, 0.5, 0.88], c.lightened(0.3))
	pen.rect(0.12, 0.86, 0.88, 0.92, IRON)

static func _fragment(pen: Pen, def: Array) -> void:
	var start: float = def[0]
	var c: Color = def[1]
	var accent: Color = def[2]
	var centre := pen.v(0.5, 0.5)
	var r_out := 0.46 * pen.unit()
	var r_in := 0.25 * pen.unit()
	# The whole Maw, faint, so four fragments read as one set.
	pen.ci.draw_arc(centre, (r_out + r_in) * 0.5, 0.0, TAU, 40, pen.col(Color(c, 0.18)), r_out - r_in, true)
	var p := PackedVector2Array()
	var gap := 0.06
	var steps := 10
	for i in steps + 1:
		var a := start + gap + (PI * 0.5 - gap * 2.0) * i / steps
		p.append(centre + Vector2(cos(a), sin(a)) * r_out)
	for i in range(steps * 2, -1, -1):
		var a := start + gap + (PI * 0.5 - gap * 2.0) * i / (steps * 2)
		var r := r_in if i % 4 != 2 else r_in * 0.6  # teeth
		p.append(centre + Vector2(cos(a), sin(a)) * r)
	pen.fill(p, c)
	var mid := start + PI * 0.25
	var ember := centre + Vector2(cos(mid), sin(mid)) * (r_out + r_in) * 0.5
	pen.ci.draw_circle(ember, 0.09 * pen.unit(), pen.col(Color(accent, 0.35)))
	pen.ci.draw_circle(ember, 0.045 * pen.unit(), pen.col(accent))

static func _figment(pen: Pen, tier: int) -> void:
	var t := clampf((tier - 1) / 9.0, 0.0, 1.0)
	var c := Color(0.3, 0.55, 0.95).lerp(Color(0.65, 0.3, 0.85), minf(t * 2.0, 1.0)).lerp(Color(0.95, 0.25, 0.25), maxf(t * 2.0 - 1.0, 0.0))
	pen.poly([0.5, 0.04, 0.94, 0.5, 0.5, 0.96, 0.06, 0.5], GOLD.darkened(0.15))
	pen.poly([0.5, 0.14, 0.84, 0.5, 0.5, 0.86, 0.16, 0.5], c.darkened(0.55))
	var centre := pen.v(0.5, 0.5)
	for i in 3:
		var a0 := i * TAU / 3.0
		pen.ci.draw_arc(centre, (0.1 + i * 0.05) * pen.unit(), a0, a0 + PI * 0.9, 12, pen.col(Color(c.lightened(0.3), 0.8)), 0.03 * pen.unit(), true)
	pen.text(str(tier), 0.5, 0.5, 0.4, Color(1, 1, 1))

static func _slate(pen: Pen, slate: Slate) -> void:
	_slate_blank(pen)
	var cells := slate.shape_cells
	if cells.is_empty():
		return
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var span := hi - lo + Vector2i.ONE
	var cell := 0.7 / maxf(span.x, span.y)
	var origin := Vector2(0.5, 0.5) - Vector2(span) * cell * 0.5
	var primary := _slate_colour(slate, false)
	var secondary := _slate_colour(slate, true) if slate.is_hybrid else primary
	for c in cells:
		var o := origin + Vector2(c - lo) * cell
		var colour := secondary if (c.x + c.y) % 2 == 1 else primary
		var inset := cell * 0.08
		pen.rect(o.x + inset, o.y + inset, o.x + cell - inset, o.y + cell - inset, colour)

static func _slate_colour(slate: Slate, secondary: bool) -> Color:
	if slate.category_tag_override != "" and not secondary:
		return SPELL_TAG_COLOR
	var c: Color = Constants.DAMAGE_TYPE_COLOR.get(slate.secondary_tag if secondary else slate.tag, Color.GRAY)
	return c.lightened(0.25) if c.get_luminance() < 0.3 else c

static func _slate_blank(pen: Pen) -> void:
	pen.poly([0.12, 0.08, 0.88, 0.08, 0.94, 0.14, 0.94, 0.86, 0.88, 0.92, 0.12, 0.92, 0.06, 0.86, 0.06, 0.14], SLATE_STONE)

## A book in its spell's colour with the spell's icon on the cover.
static func _skill_tome(pen: Pen, tome: SkillTome) -> void:
	var ability: Ability = load(tome.ability_path) as Ability if tome.ability_path != "" else null
	if ability == null:
		_book(pen, Color(0.2, 0.32, 0.6), GOLD, "star")
		return
	_book(pen, SpellArt.colour_of(ability).darkened(0.55), GOLD, "")
	var side := 0.44 * pen.unit()
	SpellArt.draw(pen.ci, ability, Rect2(pen.v(0.54, 0.48) - Vector2(side, side) * 0.5, Vector2(side, side)))

static func _jewel(pen: Pen, c: Color) -> void:
	pen.ci.draw_circle(pen.v(0.5, 0.5), 0.4 * pen.unit(), pen.col(Color(c, 0.14)))
	pen.poly([0.3, 0.2, 0.7, 0.2, 0.86, 0.42, 0.5, 0.88, 0.14, 0.42], c.darkened(0.35))
	pen.poly([0.3, 0.2, 0.7, 0.2, 0.62, 0.42, 0.38, 0.42], c.lightened(0.35))
	pen.poly([0.38, 0.42, 0.62, 0.42, 0.5, 0.88], c)
	pen.shine(0.4, 0.28, 0.04)

## A glass lens in a brass rim.
static func _lens(pen: Pen, c: Color) -> void:
	var centre := pen.v(0.5, 0.5)
	var r := 0.36 * pen.unit()
	pen.ci.draw_circle(centre, r * 1.18, pen.col(BRONZE.darkened(0.3)))
	pen.ci.draw_circle(centre, r, pen.col(Color(c.lightened(0.2), 0.55)))
	pen.ci.draw_arc(centre, r * 0.7, PI * 1.1, PI * 1.6, 12, pen.col(Color(1, 1, 1, 0.7)), maxf(1.0, r * 0.12), true)
	pen.ci.draw_arc(centre, r * 1.18, 0.0, TAU, 32, pen.col(OUTLINE), maxf(1.0, r * 0.08), true)

# --- armour & jewellery -------------------------------------------------------

static func _helmet(pen: Pen, accent: Color) -> void:
	pen.poly([0.18, 0.86, 0.16, 0.5, 0.24, 0.26, 0.38, 0.14, 0.5, 0.1, 0.62, 0.14, 0.76, 0.26, 0.84, 0.5, 0.82, 0.86, 0.6, 0.86, 0.6, 0.56, 0.4, 0.56, 0.4, 0.86], STEEL)
	pen.rect(0.47, 0.1, 0.53, 0.56, DARK_STEEL)
	pen.poly([0.28, 0.5, 0.72, 0.5, 0.72, 0.56, 0.28, 0.56], IRON)
	pen.circle(0.5, 0.16, 0.05, accent)
	pen.shine(0.32, 0.3, 0.035)

static func _body_armour(pen: Pen, accent: Color) -> void:
	pen.poly([0.3, 0.08, 0.42, 0.13, 0.58, 0.13, 0.7, 0.08, 0.82, 0.2, 0.78, 0.92, 0.22, 0.92, 0.18, 0.2], STEEL)
	pen.poly([0.04, 0.22, 0.18, 0.1, 0.32, 0.14, 0.26, 0.38, 0.08, 0.4], DARK_STEEL)
	pen.poly([0.96, 0.22, 0.82, 0.1, 0.68, 0.14, 0.74, 0.38, 0.92, 0.4], DARK_STEEL)
	pen.rect(0.24, 0.62, 0.76, 0.68, LEATHER)
	pen.rect(0.45, 0.6, 0.55, 0.7, accent)
	pen.poly([0.42, 0.13, 0.58, 0.13, 0.5, 0.24], IRON)
	pen.shine(0.32, 0.3, 0.03)

static func _glove(pen: Pen, c: Color, accent: Color) -> void:
	# Fingers, then hand, then cuff.
	for i in 4:
		var x := 0.3 + i * 0.11
		pen.poly([x, 0.36, x, 0.14 + absf(i - 1.5) * 0.05, x + 0.1, 0.14 + absf(i - 1.5) * 0.05, x + 0.1, 0.36], c)
	pen.poly([0.12, 0.48, 0.2, 0.36, 0.3, 0.42, 0.28, 0.58], c)
	pen.poly([0.28, 0.34, 0.74, 0.34, 0.76, 0.66, 0.3, 0.68], c)
	pen.poly([0.26, 0.66, 0.8, 0.64, 0.86, 0.9, 0.24, 0.92], c.darkened(0.3))
	pen.rect(0.24, 0.72, 0.84, 0.77, accent)

static func _boot(pen: Pen, accent: Color) -> void:
	pen.poly([0.3, 0.08, 0.66, 0.08, 0.66, 0.6, 0.9, 0.7, 0.92, 0.9, 0.24, 0.9, 0.28, 0.6], LEATHER)
	pen.rect(0.26, 0.08, 0.7, 0.2, LEATHER.darkened(0.3))
	pen.rect(0.22, 0.86, 0.94, 0.92, IRON)
	pen.poly([0.66, 0.6, 0.9, 0.7, 0.9, 0.76, 0.66, 0.68], STEEL)
	pen.circle(0.48, 0.14, 0.035, accent)

static func _belt(pen: Pen, accent: Color) -> void:
	pen.poly([0.02, 0.32, 0.98, 0.32, 0.98, 0.68, 0.02, 0.68], LEATHER)
	pen.stroke_px(pen.pts([0.04, 0.4, 0.96, 0.4]), LEATHER.lightened(0.2), 0.008 * pen.unit())
	pen.stroke_px(pen.pts([0.04, 0.6, 0.96, 0.6]), LEATHER.lightened(0.2), 0.008 * pen.unit())
	pen.rect(0.42, 0.18, 0.58, 0.82, GOLD)
	pen.rect(0.46, 0.3, 0.54, 0.7, LEATHER.darkened(0.4))
	pen.rect(0.2, 0.32, 0.24, 0.68, accent)
	pen.rect(0.76, 0.32, 0.8, 0.68, accent)

static func _ring(pen: Pen, accent: Color) -> void:
	var centre := pen.v(0.5, 0.58)
	var r := 0.27 * pen.unit()
	if pen.ghost.a == 0.0:
		pen.ci.draw_arc(centre, r, 0.0, TAU, 32, OUTLINE, 0.13 * pen.unit() + pen.ow * 2.0, true)
	pen.ci.draw_arc(centre, r, 0.0, TAU, 32, pen.col(GOLD), 0.13 * pen.unit(), true)
	pen.ci.draw_arc(centre, r, PI * 1.1, PI * 1.4, 8, pen.col(GOLD.lightened(0.4)), 0.04 * pen.unit(), true)
	pen.poly([0.36, 0.3, 0.42, 0.2, 0.58, 0.2, 0.64, 0.3, 0.5, 0.4], GOLD.darkened(0.2))
	pen.circle(0.5, 0.25, 0.1, accent)
	pen.shine(0.46, 0.22, 0.03)

static func _amulet(pen: Pen, accent: Color) -> void:
	pen.stroke_px(pen.pts([0.18, 0.06, 0.3, 0.38, 0.5, 0.52, 0.7, 0.38, 0.82, 0.06]), GOLD, 0.04 * pen.unit(), true)
	pen.poly([0.5, 0.46, 0.68, 0.64, 0.5, 0.94, 0.32, 0.64], GOLD)
	pen.poly([0.5, 0.55, 0.6, 0.65, 0.5, 0.84, 0.4, 0.65], accent)
	pen.shine(0.46, 0.62, 0.025)

# --- shields ------------------------------------------------------------------

static func _kite_shield(pen: Pen, accent: Color, kind: String) -> void:
	var face := STEEL if kind != "warded_barrier" else Color(0.35, 0.55, 0.75)
	if kind == "spiked_shield":
		pen.poly([0.06, 0.1, 0.0, 0.0, 0.16, 0.06], IRON)
		pen.poly([0.94, 0.1, 1.0, 0.0, 0.84, 0.06], IRON)
		pen.poly([0.42, 0.88, 0.5, 1.0, 0.58, 0.88], IRON)
	pen.poly([0.08, 0.06, 0.92, 0.06, 0.92, 0.42, 0.5, 0.96, 0.08, 0.42], face)
	pen.poly([0.16, 0.12, 0.84, 0.12, 0.84, 0.4, 0.5, 0.86, 0.16, 0.4], face.darkened(0.25))
	match kind:
		"rune_shield":
			glyph(pen, "rune", pen.v(0.5, 0.4), 0.5, Color(0.5, 0.95, 1.0))
		"warded_barrier":
			glyph(pen, "ward", pen.v(0.5, 0.4), 0.5, Color(0.75, 0.95, 1.0))
		_:
			pen.rect(0.45, 0.12, 0.55, 0.8, accent.darkened(0.2))
			pen.rect(0.16, 0.3, 0.84, 0.38, accent.darkened(0.2))
	pen.circle(0.5, 0.34, 0.07, GOLD)

static func _tower_shield(pen: Pen, accent: Color, kind: String) -> void:
	var face := WOOD if kind == "pavise" else STEEL
	pen.poly([0.08, 0.1, 0.5, 0.03, 0.92, 0.1, 0.92, 0.94, 0.08, 0.94], face)
	pen.rect(0.16, 0.14, 0.84, 0.88, face.darkened(0.25))
	pen.rect(0.08, 0.46, 0.92, 0.52, IRON)
	for y in [0.12, 0.9]:
		for x in [0.14, 0.86]:
			pen.circle(x, y, 0.035, GOLD)
	pen.circle(0.5, 0.49, 0.12, accent.darkened(0.15))
	if kind == "pavise":
		pen.poly([0.3, 0.94, 0.36, 1.0, 0.42, 0.94], IRON)
		pen.poly([0.58, 0.94, 0.64, 1.0, 0.7, 0.94], IRON)

static func _buckler(pen: Pen, accent: Color) -> void:
	pen.circle(0.5, 0.5, 0.4, STEEL)
	pen.circle(0.5, 0.5, 0.3, DARK_STEEL)
	pen.circle(0.5, 0.5, 0.12, accent)
	pen.shine(0.36, 0.3, 0.04)

# --- melee --------------------------------------------------------------------

## Vertical blade, tip up. curve bends it like a saber; guard_y is where the
## blade meets the crossguard.
static func _sword(pen: Pen, accent: Color, half_width: float, curve: float, guard_y: float, two_handed_guard: bool = false) -> void:
	var tip := 0.03
	var steps := 8
	var left: Array = []
	var right: Array = []
	for i in steps + 1:
		var t := float(i) / steps  # 0 at guard, 1 at tip
		var y := guard_y - (guard_y - tip) * t
		var cx := 0.5 + curve * t * t
		var hw := half_width * (1.0 - pow(t, 6.0)) if curve == 0.0 else half_width * (1.0 - t * t)
		left.append_array([cx - hw, y])
		right.push_front(y)
		right.push_front(cx + hw)
	var blade: Array = left
	blade.append_array(right)
	pen.poly(blade, STEEL)
	pen.line([0.5, guard_y - 0.02, 0.5 + curve * 0.3, guard_y - (guard_y - tip) * 0.55], DARK_STEEL, 0.02)
	var gw := 0.36 if two_handed_guard else 0.28
	if two_handed_guard:
		pen.poly([0.5 - gw, guard_y - 0.05, 0.5 + gw, guard_y - 0.05, 0.5 + gw * 0.7, guard_y + 0.03, 0.5 - gw * 0.7, guard_y + 0.03], GOLD.darkened(0.2))
	else:
		pen.rect(0.5 - gw, guard_y, 0.5 + gw, guard_y + 0.045, GOLD.darkened(0.2))
	var grip_end := 0.9 if guard_y > 0.64 else 0.86
	pen.rect(0.45, guard_y + 0.045, 0.55, grip_end, LEATHER)
	pen.circle(0.5, grip_end + 0.03, 0.08, accent)

static func _rapier(pen: Pen, accent: Color) -> void:
	pen.poly([0.48, 0.6, 0.5, 0.02, 0.52, 0.6], STEEL)
	var centre := pen.v(0.5, 0.64)
	pen.circle_px(centre, 0.2 * pen.unit(), GOLD.darkened(0.25))
	pen.ci.draw_circle(centre, 0.12 * pen.unit(), pen.col(GOLD.darkened(0.5)))
	pen.stroke_px(pen.pts([0.68, 0.64, 0.76, 0.76, 0.6, 0.9, 0.55, 0.88]), GOLD.darkened(0.2), 0.035 * pen.unit(), true)
	pen.rect(0.46, 0.68, 0.54, 0.88, LEATHER)
	pen.circle(0.5, 0.91, 0.07, accent)

static func _dagger(pen: Pen, accent: Color, curve: float) -> void:
	_sword(pen, accent, 0.09, curve, 0.58)

static func _haft(pen: Pen, y0: float, y1: float) -> void:
	pen.rect(0.46, y0, 0.54, y1, WOOD)
	pen.rect(0.45, y1 - 0.12, 0.55, y1 - 0.03, LEATHER)

static func _axe(pen: Pen, accent: Color) -> void:
	_haft(pen, 0.06, 0.97)
	pen.poly([0.54, 0.1, 0.72, 0.04, 0.92, 0.1, 0.98, 0.24, 0.92, 0.38, 0.72, 0.44, 0.54, 0.38], STEEL)
	pen.poly([0.46, 0.14, 0.3, 0.1, 0.16, 0.16, 0.12, 0.24, 0.16, 0.32, 0.3, 0.38, 0.46, 0.34], STEEL.darkened(0.12))
	pen.rect(0.44, 0.12, 0.56, 0.4, IRON)
	pen.circle(0.5, 0.26, 0.05, accent)

static func _mace(pen: Pen, accent: Color) -> void:
	_haft(pen, 0.3, 0.96)
	pen.poly([0.5, 0.02, 0.56, 0.12, 0.44, 0.12], DARK_STEEL)
	for side in [-1.0, 1.0]:
		pen.poly([0.5 + side * 0.18, 0.16, 0.5 + side * 0.4, 0.22, 0.5 + side * 0.18, 0.3], DARK_STEEL)
	pen.circle(0.5, 0.23, 0.22, STEEL)
	pen.rect(0.43, 0.33, 0.57, 0.38, IRON)
	pen.circle(0.5, 0.23, 0.07, accent)

static func _war_pick(pen: Pen, accent: Color) -> void:
	_haft(pen, 0.1, 0.96)
	pen.poly([0.56, 0.12, 0.8, 0.18, 0.98, 0.36, 0.74, 0.25, 0.56, 0.24], STEEL)
	pen.rect(0.16, 0.12, 0.44, 0.24, STEEL.darkened(0.15))
	pen.rect(0.42, 0.08, 0.58, 0.28, IRON)
	pen.circle(0.5, 0.18, 0.045, accent)

static func _polearm(pen: Pen, accent: Color, kind: String) -> void:
	pen.rect(0.47, 0.18, 0.53, 0.98, WOOD)
	if kind == "halberd":
		pen.poly([0.53, 0.14, 0.76, 0.1, 0.92, 0.2, 0.9, 0.32, 0.76, 0.36, 0.53, 0.3], STEEL)
		pen.poly([0.47, 0.18, 0.24, 0.24, 0.47, 0.28], STEEL.darkened(0.15))
	pen.poly([0.5, 0.01, 0.62, 0.11, 0.54, 0.22, 0.46, 0.22, 0.38, 0.11], STEEL)
	pen.rect(0.45, 0.2, 0.55, 0.24, accent)
	pen.rect(0.46, 0.84, 0.54, 0.9, IRON)

static func _lance(pen: Pen, accent: Color) -> void:
	var bolt: Color = Constants.DAMAGE_TYPE_COLOR[Constants.DamageType.LIGHTNING]
	pen.poly([0.5, 0.02, 0.64, 0.62, 0.36, 0.62], STEEL)
	pen.stroke_px(pen.pts([0.5, 0.1, 0.46, 0.3, 0.54, 0.36, 0.48, 0.56]), bolt, 0.03 * pen.unit())
	pen.poly([0.2, 0.62, 0.8, 0.62, 0.66, 0.7, 0.34, 0.7], DARK_STEEL)
	pen.rect(0.45, 0.7, 0.55, 0.92, LEATHER)
	pen.circle(0.5, 0.94, 0.06, accent)

static func _whip(pen: Pen, accent: Color) -> void:
	var p := PackedVector2Array()
	var centre := pen.v(0.56, 0.42)
	for i in 40:
		var a := -PI * 0.5 + i * 0.25
		var r := (0.34 - i * 0.0065) * pen.unit()
		p.append(centre + Vector2(cos(a), sin(a)) * r)
	pen.stroke_px(p, LEATHER.lightened(0.15), 0.035 * pen.unit(), true)
	pen.line([0.12, 0.92, 0.32, 0.66], LEATHER.darkened(0.2), 0.09)
	pen.circle(0.12, 0.92, 0.05, accent)

static func _bow(pen: Pen, accent: Color, long: bool) -> void:
	var p := PackedVector2Array()
	var bulge := 0.5 if long else 0.46
	for i in 21:
		var t := i / 20.0
		var y := 0.03 + t * 0.94
		var x := 0.74 - bulge * sin(t * PI) + 0.05 * sin(t * TAU * 2.0) * (0.0 if long else 1.0)
		p.append(pen.v(x, y))
	pen.stroke_px(PackedVector2Array([pen.v(0.74, 0.03), pen.v(0.74, 0.97)]), PARCHMENT, 0.012 * pen.unit())
	pen.stroke_px(p, WOOD, 0.07 * pen.unit(), true)
	pen.rect(0.2, 0.44, 0.34, 0.56, LEATHER)
	pen.circle(0.27, 0.5, 0.035, accent)

static func _crossbow(pen: Pen, accent: Color) -> void:
	pen.rect(0.44, 0.14, 0.56, 0.95, WOOD)
	var p := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		p.append(pen.v(0.04 + t * 0.92, 0.3 - 0.12 * sin(t * PI)))
	pen.stroke_px(PackedVector2Array([pen.v(0.04, 0.3), pen.v(0.5, 0.42), pen.v(0.96, 0.3)]), PARCHMENT, 0.012 * pen.unit())
	pen.stroke_px(p, DARK_STEEL, 0.06 * pen.unit(), true)
	pen.poly([0.4, 0.04, 0.6, 0.04, 0.56, 0.14, 0.44, 0.14], IRON)
	pen.rect(0.47, 0.42, 0.53, 0.6, STEEL)
	pen.circle(0.5, 0.72, 0.05, accent)

# --- firearms -----------------------------------------------------------------

static func _pistol(pen: Pen, accent: Color, kind: String) -> void:
	var trim := accent
	match kind:
		"voltage_pistol": trim = Constants.DAMAGE_TYPE_COLOR[Constants.DamageType.LIGHTNING]
		"thermal_pistol": trim = Constants.DAMAGE_TYPE_COLOR[Constants.DamageType.FIRE].lightened(0.2)
	pen.poly([0.6, 0.44, 0.84, 0.44, 0.78, 0.9, 0.56, 0.9], WOOD)
	if kind == "machine_pistol":
		pen.rect(0.62, 0.86, 0.76, 0.98, IRON)
	pen.stroke_px(pen.pts([0.62, 0.48, 0.5, 0.52, 0.52, 0.64, 0.6, 0.64]), IRON, 0.03 * pen.unit(), true)
	pen.rect(0.08, 0.26, 0.88, 0.46, DARK_STEEL)
	pen.rect(0.06, 0.28, 0.14, 0.38, IRON)
	if kind == "revolver":
		pen.circle(0.56, 0.38, 0.11, STEEL)
	else:
		pen.rect(0.2, 0.3, 0.84, 0.34, STEEL)
	pen.rect(0.3, 0.4, 0.5, 0.45, trim)

static func _long_gun(pen: Pen, accent: Color, kind: String) -> void:
	var shotgun := kind.ends_with("shotgun")
	var barrel_w := 0.07 if shotgun else 0.045
	var top := 0.12 if kind == "submachine_gun" else 0.02
	pen.rect(0.5 - barrel_w, top, 0.5 + barrel_w, 0.42, DARK_STEEL)
	if kind == "rail_carbine":
		pen.rect(0.4, top + 0.04, 0.44, 0.4, Color(0.4, 0.9, 1.0))
		pen.rect(0.56, top + 0.04, 0.6, 0.4, Color(0.4, 0.9, 1.0))
	pen.poly([0.38, 0.36, 0.62, 0.36, 0.62, 0.62, 0.38, 0.62], IRON)
	pen.poly([0.4, 0.62, 0.6, 0.62, 0.68, 0.96, 0.36, 0.96], WOOD)
	pen.rect(0.36, 0.92, 0.68, 0.97, LEATHER)
	match kind:
		"pump_action_shotgun":
			pen.rect(0.4, 0.2, 0.6, 0.3, WOOD)
		"lever_action_rifle":
			pen.stroke_px(pen.pts([0.62, 0.56, 0.74, 0.6, 0.74, 0.72, 0.62, 0.7]), IRON, 0.03 * pen.unit(), true)
		"bolt_action_rifle":
			pen.line([0.62, 0.44, 0.76, 0.5], STEEL, 0.03)
			pen.circle(0.78, 0.51, 0.04, STEEL)
		"pressurized_rifle", "jet_rifle":
			pen.rect(0.62, 0.28, 0.82, 0.58, BRONZE)
			pen.circle(0.72, 0.28, 0.05, BRONZE.darkened(0.2))
		"machine_gun":
			pen.circle(0.26, 0.48, 0.13, IRON)
			pen.stroke_px(pen.pts([0.5, 0.14, 0.3, 0.3]), IRON, 0.025 * pen.unit())
			pen.stroke_px(pen.pts([0.5, 0.14, 0.7, 0.3]), IRON, 0.025 * pen.unit())
		_:
			if not shotgun:
				pen.rect(0.24, 0.44, 0.38, 0.58, IRON)
	pen.rect(0.38, 0.5, 0.62, 0.53, accent)

# --- caster offhands & staves -------------------------------------------------

static func _staff(pen: Pen, accent: Color) -> void:
	pen.rect(0.46, 0.18, 0.54, 0.98, WOOD)
	pen.stroke_px(pen.pts([0.46, 0.22, 0.3, 0.14, 0.32, 0.04]), WOOD, 0.05 * pen.unit(), true)
	pen.stroke_px(pen.pts([0.54, 0.22, 0.7, 0.14, 0.68, 0.04]), WOOD, 0.05 * pen.unit(), true)
	pen.ci.draw_circle(pen.v(0.5, 0.12), 0.22 * pen.unit(), pen.col(Color(accent, 0.25)))
	pen.circle(0.5, 0.12, 0.12, accent)
	pen.shine(0.46, 0.1, 0.035)
	pen.rect(0.45, 0.5, 0.55, 0.62, LEATHER)

static func _rod(pen: Pen, accent: Color) -> void:
	pen.rect(0.46, 0.3, 0.54, 0.95, DARK_STEEL)
	pen.poly([0.5, 0.04, 0.72, 0.18, 0.64, 0.34, 0.36, 0.34, 0.28, 0.18], GOLD.darkened(0.15))
	pen.circle(0.5, 0.2, 0.1, accent)
	pen.rect(0.44, 0.78, 0.56, 0.84, GOLD.darkened(0.15))

static func _wand(pen: Pen, accent: Color) -> void:
	pen.line([0.2, 0.86, 0.68, 0.32], WOOD, 0.07)
	pen.line([0.2, 0.86, 0.32, 0.72], LEATHER, 0.09)
	glyph(pen, "star", pen.v(0.74, 0.25), 0.36, accent.lightened(0.3))

static func _book(pen: Pen, cover: Color, accent: Color, emblem: String) -> void:
	pen.rect(0.24, 0.14, 0.84, 0.9, PARCHMENT)
	pen.rect(0.18, 0.1, 0.8, 0.88, cover)
	pen.rect(0.18, 0.1, 0.28, 0.88, cover.darkened(0.35))
	pen.circle(0.54, 0.48, 0.17, cover.darkened(0.3))
	glyph(pen, emblem, pen.v(0.54, 0.48), 0.26, accent.lightened(0.2))
	for y in [0.18, 0.8]:
		pen.rect(0.66, y - 0.03, 0.78, y + 0.03, GOLD)

static func _focus(pen: Pen, accent: Color) -> void:
	pen.poly([0.3, 0.92, 0.7, 0.92, 0.6, 0.7, 0.4, 0.7], DARK_STEEL)
	pen.stroke_px(pen.pts([0.38, 0.72, 0.26, 0.5, 0.32, 0.3]), GOLD, 0.04 * pen.unit(), true)
	pen.stroke_px(pen.pts([0.62, 0.72, 0.74, 0.5, 0.68, 0.3]), GOLD, 0.04 * pen.unit(), true)
	pen.ci.draw_circle(pen.v(0.5, 0.42), 0.32 * pen.unit(), pen.col(Color(accent, 0.2)))
	pen.circle(0.5, 0.42, 0.2, accent.darkened(0.2))
	pen.shine(0.43, 0.34, 0.05)

static func _lantern(pen: Pen, accent: Color) -> void:
	pen.ci.draw_arc(pen.v(0.5, 0.12), 0.1 * pen.unit(), PI, TAU, 12, pen.col(IRON), 0.04 * pen.unit(), true)
	pen.poly([0.3, 0.2, 0.7, 0.2, 0.64, 0.28, 0.36, 0.28], IRON)
	pen.rect(0.34, 0.28, 0.66, 0.78, Color(1.0, 0.75, 0.3))
	pen.ci.draw_circle(pen.v(0.5, 0.55), 0.12 * pen.unit(), pen.col(Color(1.0, 0.95, 0.7)))
	for x in [0.34, 0.5, 0.66]:
		pen.stroke_px(pen.pts([x, 0.28, x, 0.78]), IRON, 0.03 * pen.unit())
	pen.poly([0.28, 0.78, 0.72, 0.78, 0.66, 0.88, 0.34, 0.88], IRON)
	pen.circle(0.5, 0.83, 0.03, accent)

static func _talisman(pen: Pen, accent: Color) -> void:
	pen.stroke_px(pen.pts([0.3, 0.04, 0.5, 0.2, 0.7, 0.04]), LEATHER.lightened(0.2), 0.03 * pen.unit(), true)
	pen.circle(0.5, 0.56, 0.36, BRONZE)
	pen.circle(0.5, 0.56, 0.26, BRONZE.darkened(0.35))
	glyph(pen, "rune", pen.v(0.5, 0.56), 0.36, accent.lightened(0.2))

static func _charm(pen: Pen, accent: Color) -> void:
	pen.stroke_px(pen.pts([0.5, 0.04, 0.5, 0.28]), LEATHER.lightened(0.2), 0.03 * pen.unit(), true)
	for i in 3:
		pen.circle(0.5, 0.1 + i * 0.08, 0.04, accent)
	pen.poly([0.5, 0.32, 0.8, 0.86, 0.2, 0.86], BRONZE)
	pen.poly([0.5, 0.48, 0.66, 0.78, 0.34, 0.78], BRONZE.darkened(0.35))
	pen.circle(0.5, 0.66, 0.05, accent)

static func _seal(pen: Pen, accent: Color) -> void:
	pen.rect(0.42, 0.06, 0.58, 0.46, WOOD)
	pen.circle(0.5, 0.1, 0.1, WOOD.lightened(0.1))
	pen.poly([0.26, 0.46, 0.74, 0.46, 0.78, 0.56, 0.22, 0.56], GOLD.darkened(0.2))
	pen.circle(0.5, 0.74, 0.22, Color(0.7, 0.12, 0.12))
	glyph(pen, "rune", pen.v(0.5, 0.74), 0.24, accent.lightened(0.3))

static func _fetish(pen: Pen, accent: Color) -> void:
	pen.rect(0.46, 0.4, 0.54, 0.96, WOOD)
	pen.stroke_px(pen.pts([0.54, 0.5, 0.7, 0.64]), PARCHMENT, 0.04 * pen.unit(), true)
	pen.stroke_px(pen.pts([0.46, 0.56, 0.3, 0.7]), PARCHMENT, 0.04 * pen.unit(), true)
	glyph(pen, "skull", pen.v(0.5, 0.26), 0.44, PARCHMENT)
	pen.circle(0.5, 0.74, 0.04, accent)

# --- glyphs -------------------------------------------------------------------

## Small symbols, drawn around a pixel centre at size s (fraction of the box
## width) so they stay square in any box. A one- or two-letter name that
## isn't a known glyph prints as text ("P", "S", "?X").
static func glyph(pen: Pen, name: String, centre: Vector2, s: float, c: Color) -> void:
	var u := s * pen.unit()
	var w := maxf(1.5, u * 0.14)
	var g := func(a: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in range(0, a.size(), 2):
			out.append(centre + Vector2(a[i], a[i + 1]) * u)
		return out
	var col := pen.col(c)
	var ci := pen.ci
	match name:
		"ring":
			ci.draw_arc(centre, u * 0.32, 0.0, TAU, 24, col, w, true)
		"socket":
			ci.draw_arc(centre, u * 0.32, 0.0, TAU, 24, col, w, true)
			ci.draw_circle(centre, u * 0.12, col)
		"anchor":
			ci.draw_polyline(g.call([0, -0.36, 0, 0.4]), col, w, true)
			ci.draw_polyline(g.call([-0.2, -0.18, 0.2, -0.18]), col, w, true)
			ci.draw_arc(centre + Vector2(0, -0.42) * u, u * 0.08, 0.0, TAU, 12, col, w * 0.7, true)
			ci.draw_arc(centre + Vector2(0, 0.08) * u, u * 0.32, 0.25, PI - 0.25, 12, col, w, true)
		"arrow_up":
			ci.draw_colored_polygon(g.call([0, -0.42, 0.3, -0.06, 0.1, -0.06, 0.1, 0.4, -0.1, 0.4, -0.1, -0.06, -0.3, -0.06]), col)
		"chevron_up":
			ci.draw_polyline(g.call([-0.28, 0.14, 0, -0.16, 0.28, 0.14]), col, w * 1.3, true)
		"chevrons_up":
			ci.draw_polyline(g.call([-0.28, 0.02, 0, -0.28, 0.28, 0.02]), col, w * 1.2, true)
			ci.draw_polyline(g.call([-0.28, 0.32, 0, 0.02, 0.28, 0.32]), col, w * 1.2, true)
		"chevrons_right":
			ci.draw_polyline(g.call([-0.3, -0.28, 0, 0, -0.3, 0.28]), col, w * 1.2, true)
			ci.draw_polyline(g.call([0.02, -0.28, 0.32, 0, 0.02, 0.28]), col, w * 1.2, true)
		"hammer":
			ci.draw_colored_polygon(g.call([-0.32, -0.36, 0.32, -0.36, 0.32, -0.1, -0.32, -0.1]), col)
			ci.draw_polyline(g.call([0, -0.1, 0, 0.42]), col, w * 1.2, true)
		"branch":
			ci.draw_polyline(g.call([0, 0.42, 0, -0.02, -0.26, -0.3]), col, w, true)
			ci.draw_polyline(g.call([0, 0.12, 0.26, -0.18]), col, w, true)
			ci.draw_circle(centre + Vector2(-0.28, -0.34) * u, u * 0.08, col)
			ci.draw_circle(centre + Vector2(0.28, -0.22) * u, u * 0.08, col)
			ci.draw_circle(centre + Vector2(0, -0.08) * u, u * 0.06, col)
		"cycle":
			ci.draw_arc(centre, u * 0.3, -PI * 0.1, PI * 0.75, 12, col, w, true)
			ci.draw_arc(centre, u * 0.3, PI * 0.9, PI * 1.75, 12, col, w, true)
			ci.draw_colored_polygon(g.call([-0.42, 0.06, -0.18, 0.06, -0.3, 0.26]), col)
			ci.draw_colored_polygon(g.call([0.42, -0.06, 0.18, -0.06, 0.3, -0.26]), col)
		"dice":
			ci.draw_polyline(g.call([-0.3, -0.3, 0.3, -0.3, 0.3, 0.3, -0.3, 0.3, -0.3, -0.3]), col, w, true)
			for d in [Vector2(-0.14, -0.14), Vector2.ZERO, Vector2(0.14, 0.14)]:
				ci.draw_circle(centre + d * u, u * 0.06, col)
		"slash":
			ci.draw_colored_polygon(g.call([0.36, -0.4, 0.42, -0.34, -0.36, 0.4, -0.42, 0.34]), col)
			ci.draw_circle(centre + Vector2(0.22, 0.18) * u, u * 0.05, col)
			ci.draw_circle(centre + Vector2(-0.2, -0.2) * u, u * 0.05, col)
		"diamond":
			ci.draw_polyline(g.call([0, -0.38, 0.3, 0, 0, 0.38, -0.3, 0, 0, -0.38]), col, w, true)
			ci.draw_colored_polygon(g.call([0, -0.16, 0.12, 0, 0, 0.16, -0.12, 0]), col)
		"plus":
			ci.draw_polyline(g.call([0, -0.32, 0, 0.32]), col, w * 1.4, true)
			ci.draw_polyline(g.call([-0.32, 0, 0.32, 0]), col, w * 1.4, true)
		"minus":
			ci.draw_polyline(g.call([-0.32, 0, 0.32, 0]), col, w * 1.4, true)
		"impact":
			ci.draw_circle(centre, u * 0.16, col)
			for i in 8:
				var a := i * TAU / 8.0
				ci.draw_line(centre + Vector2(cos(a), sin(a)) * u * 0.26, centre + Vector2(cos(a), sin(a)) * u * 0.42, col, w, true)
		"arrowhead":
			ci.draw_colored_polygon(g.call([0, -0.46, 0.3, 0.02, 0.09, -0.04, 0.09, 0.44, -0.09, 0.44, -0.09, -0.04, -0.3, 0.02]), col)
		"burst":
			var star := PackedVector2Array()
			for i in 16:
				var a := i * TAU / 16.0 - PI * 0.5
				star.append(centre + Vector2(cos(a), sin(a)) * u * (0.46 if i % 2 == 0 else 0.2))
			ci.draw_colored_polygon(star, col)
		"flame":
			ci.draw_colored_polygon(g.call([0, -0.48, 0.16, -0.2, 0.3, 0.04, 0.28, 0.3, 0.12, 0.46, -0.12, 0.46, -0.28, 0.3, -0.3, 0.06, -0.18, -0.12, -0.1, 0.02, -0.05, -0.22]), col)
			ci.draw_colored_polygon(g.call([0, 0.0, 0.12, 0.2, 0.08, 0.4, -0.08, 0.4, -0.12, 0.2]), Color(1, 0.95, 0.7, col.a))
		"snowflake":
			for i in 3:
				var a := i * PI / 3.0 + PI * 0.5
				var d := Vector2(cos(a), sin(a)) * u * 0.42
				ci.draw_line(centre - d, centre + d, col, w, true)
				for sgn in [-1.0, 1.0]:
					var tip: Vector2 = centre + d * sgn * 0.62
					var side := d.orthogonal().normalized() * u * 0.12
					ci.draw_line(tip, tip + d * sgn * 0.3 + side, col, w * 0.7, true)
					ci.draw_line(tip, tip + d * sgn * 0.3 - side, col, w * 0.7, true)
		"bolt":
			ci.draw_colored_polygon(g.call([0.1, -0.5, -0.25, 0.05, 0.0, 0.05, -0.1, 0.5, 0.25, -0.1, 0.0, -0.1]), col)
		"spiral":
			var p := PackedVector2Array()
			for i in 30:
				var a := i * 0.4
				p.append(centre + Vector2(cos(a), sin(a)) * u * (0.04 + i * 0.013))
			ci.draw_polyline(p, col, w, true)
		"void":
			ci.draw_arc(centre, u * 0.36, 0.0, TAU, 24, col, w, true)
			ci.draw_circle(centre, u * 0.16, col)
			for i in 3:
				var a := i * TAU / 3.0
				ci.draw_circle(centre + Vector2(cos(a), sin(a)) * u * 0.36, u * 0.07, col)
		"crescent":
			var p := PackedVector2Array()
			for i in 13:
				var a := deg_to_rad(50.0 + i * 260.0 / 12.0)
				p.append(centre + Vector2(cos(a), sin(a)) * u * 0.42)
			for i in 13:
				var a := deg_to_rad(310.0 - i * 260.0 / 12.0)
				p.append(centre + (Vector2(0.17, 0) + Vector2(cos(a), sin(a)) * 0.33) * u)
			if not Geometry2D.triangulate_polygon(p).is_empty():
				ci.draw_colored_polygon(p, col)
		"shield", "shield_tri":
			var sp: PackedVector2Array = g.call([-0.34, -0.4, 0.34, -0.4, 0.34, 0.0, 0, 0.44, -0.34, 0.0])
			if name == "shield":
				ci.draw_colored_polygon(sp, col)
			else:
				sp.append(sp[0])
				ci.draw_polyline(sp, col, w, true)
				var dots := [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING]
				for i in 3:
					ci.draw_circle(centre + Vector2(-0.14 + i * 0.14, -0.08 + (0.14 if i == 1 else 0.0)) * u, u * 0.07, pen.col(Constants.DAMAGE_TYPE_COLOR[dots[i]].lightened(0.2)))
		"swoosh":
			ci.draw_arc(centre + Vector2(0.2, 0.3) * u, u * 0.5, PI, PI * 1.45, 12, col, w * 1.2, true)
			ci.draw_arc(centre + Vector2(0.3, 0.3) * u, u * 0.34, PI, PI * 1.45, 12, col, w, true)
		"sword":
			ci.draw_colored_polygon(g.call([0, -0.46, 0.07, -0.36, 0.07, 0.16, -0.07, 0.16, -0.07, -0.36]), col)
			ci.draw_line(centre + Vector2(-0.22, 0.18) * u, centre + Vector2(0.22, 0.18) * u, col, w, true)
			ci.draw_line(centre + Vector2(0, 0.18) * u, centre + Vector2(0, 0.42) * u, col, w, true)
		"star":
			var star := PackedVector2Array()
			for i in 8:
				var a := i * TAU / 8.0 - PI * 0.5
				star.append(centre + Vector2(cos(a), sin(a)) * u * (0.46 if i % 2 == 0 else 0.13))
			ci.draw_colored_polygon(star, col)
		"drop":
			var p := PackedVector2Array([centre + Vector2(0, -0.46) * u])
			for i in 15:
				var a := deg_to_rad(-30.0 + i * 240.0 / 14.0)
				p.append(centre + (Vector2(0, 0.12) + Vector2(cos(a), sin(a)) * 0.28) * u)
			ci.draw_colored_polygon(p, col)
		"lock":
			ci.draw_arc(centre + Vector2(0, -0.1) * u, u * 0.18, PI, TAU, 12, col, w, true)
			ci.draw_line(centre + Vector2(-0.18, -0.1) * u, centre + Vector2(-0.18, 0.0) * u, col, w, true)
			ci.draw_line(centre + Vector2(0.18, -0.1) * u, centre + Vector2(0.18, 0.0) * u, col, w, true)
			ci.draw_colored_polygon(g.call([-0.3, 0.0, 0.3, 0.0, 0.3, 0.4, -0.3, 0.4]), col)
		"heart":
			var p := PackedVector2Array()
			for i in 24:
				var t := i * TAU / 24.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
				p.append(centre + Vector2(x, y) * u * 0.024)
			ci.draw_colored_polygon(p, col)
		"ward":
			ci.draw_arc(centre, u * 0.34, 0.0, TAU, 24, col, w, true)
			for i in 4:
				var a := i * TAU / 4.0 + PI * 0.25
				ci.draw_circle(centre + Vector2(cos(a), sin(a)) * u * 0.34, u * 0.08, col)
			ci.draw_colored_polygon(g.call([0, -0.18, 0.12, 0, 0, 0.18, -0.12, 0]), col)
		"rune":
			ci.draw_line(centre + Vector2(-0.08, -0.4) * u, centre + Vector2(-0.08, 0.4) * u, col, w, true)
			ci.draw_polyline(g.call([-0.08, -0.4, 0.22, -0.2, -0.08, 0.0, 0.24, 0.4]), col, w, true)
		"eye":
			var p := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				p.append(centre + Vector2(-0.42 + t * 0.84, -sin(t * PI) * 0.26) * u)
			for i in range(7, 0, -1):
				var t := i / 8.0
				p.append(centre + Vector2(-0.42 + t * 0.84, sin(t * PI) * 0.26) * u)
			ci.draw_colored_polygon(p, col)
			ci.draw_circle(centre, u * 0.12, Color(0.05, 0.02, 0.08, col.a))
		"skull":
			ci.draw_circle(centre + Vector2(0, -0.08) * u, u * 0.32, col)
			ci.draw_colored_polygon(g.call([-0.18, 0.12, 0.18, 0.12, 0.16, 0.4, -0.16, 0.4]), col)
			var hole := Color(0.05, 0.03, 0.05, col.a)
			ci.draw_circle(centre + Vector2(-0.12, -0.06) * u, u * 0.08, hole)
			ci.draw_circle(centre + Vector2(0.12, -0.06) * u, u * 0.08, hole)
		_:
			var label := name.trim_prefix("?")
			var font := AetherStyle.numbers()
			var px := maxi(8, int(u * 0.75))
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			ci.draw_string(font, centre + Vector2(-tw * 0.5, px * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
