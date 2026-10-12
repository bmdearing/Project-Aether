extends RefCounted
class_name StatusIcons
## The standard look of every status effect, wherever it's shown (enemy and
## boss bars via StatusIconRow): a glyph in the effect's colour on a dark
## tile. Ailments sit on a square tile, curses on a diamond, everything else
## (debuffs, roots, stuns) on a round one. Effects missing from DEFS aren't
## shown.

enum Kind { AILMENT, CURSE, DEBUFF }

## effect_id -> [glyph (IconArt.glyph name), colour, Kind]
const DEFS := {
	"ignite": ["flame", Color(1.0, 0.45, 0.12), Kind.AILMENT],
	"scorch": ["flame", Color(0.85, 0.3, 0.1), Kind.AILMENT],
	"chill": ["snowflake", Color(0.55, 0.85, 1.0), Kind.AILMENT],
	"freeze": ["snowflake", Color(0.85, 0.97, 1.0), Kind.AILMENT],
	"shock": ["bolt", Color(0.75, 0.8, 1.0), Kind.AILMENT],
	"electrocute": ["bolt", Color(1.0, 0.95, 0.55), Kind.AILMENT],
	"bleed": ["drop", Color(0.85, 0.12, 0.12), Kind.AILMENT],
	"unraveling": ["spiral", Color(0.7, 0.4, 1.0), Kind.AILMENT],
	"pallid": ["crescent", Color(0.9, 0.9, 0.82), Kind.AILMENT],
	"aetherburn": ["rune", Color(0.35, 0.9, 1.0), Kind.AILMENT],
	"forbidden_fire": ["flame", Color(0.45, 1.0, 0.3), Kind.AILMENT],
	"meager": ["minus", Color(0.88, 0.86, 0.75), Kind.CURSE],
	"fracturing": ["impact", Color(0.86, 0.7, 0.5), Kind.CURSE],
	"decompose": ["void", Color(0.7, 0.4, 1.0), Kind.CURSE],
	"elemental_fragility": ["burst", Color(0.95, 0.72, 0.4), Kind.CURSE],
	"linger": ["spiral", Color(0.92, 0.9, 0.8), Kind.DEBUFF],
	"slow": ["chevrons_right", Color(0.78, 0.8, 0.86), Kind.DEBUFF],
	"suppressed": ["minus", Color(0.75, 0.75, 0.8), Kind.DEBUFF],
	"armor_shred": ["shield", Color(0.86, 0.7, 0.5), Kind.DEBUFF],
	"intimidated": ["skull", Color(0.85, 0.3, 0.3), Kind.DEBUFF],
	"marked": ["eye", Color(1.0, 0.85, 0.4), Kind.DEBUFF],
	"entangle": ["branch", Color(0.45, 0.8, 0.3), Kind.DEBUFF],
	"stun": ["star", Color(1.0, 0.9, 0.5), Kind.DEBUFF],
	"guard_break": ["star", Color(1.0, 0.6, 0.3), Kind.DEBUFF],
}

static func has(effect_id: String) -> bool:
	return DEFS.has(effect_id)

static func colour_of(effect_id: String) -> Color:
	return DEFS[effect_id][1] if DEFS.has(effect_id) else Color.WHITE

## Draws effect_id's icon filling `rect`.
static func draw(ci: CanvasItem, effect_id: String, rect: Rect2) -> void:
	if not DEFS.has(effect_id):
		return
	var def: Array = DEFS[effect_id]
	var c: Color = def[1]
	var centre := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var back := Color(c.darkened(0.85), 0.92)
	match def[2]:
		Kind.AILMENT:
			var tile := rect.grow(-r * 0.04)
			ci.draw_rect(tile, back)
			ci.draw_rect(tile, Color(c, 0.85), false, maxf(1.0, r * 0.1))
		Kind.CURSE:
			var d := PackedVector2Array([centre + Vector2(0, -r), centre + Vector2(r, 0), centre + Vector2(0, r), centre + Vector2(-r, 0)])
			ci.draw_colored_polygon(d, back)
			d.append(d[0])
			ci.draw_polyline(d, Color(c, 0.85), maxf(1.0, r * 0.1), true)
		_:
			ci.draw_circle(centre, r * 0.96, back)
			ci.draw_arc(centre, r * 0.92, 0.0, TAU, 24, Color(c, 0.85), maxf(1.0, r * 0.1), true)
	var pen := IconArt.Pen.new(ci, rect)
	IconArt.glyph(pen, def[0], centre, 0.62 if def[2] != Kind.CURSE else 0.5, c.lightened(0.2))
