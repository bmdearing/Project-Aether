extends RefCounted
class_name StatusIcons
## The standard look of every status effect, wherever it's shown (enemy and
## boss bars via StatusIconRow, the player's via PlayerStatusRow): a glyph in
## the effect's colour on a dark tile. Ailments sit on a square tile, curses
## on a diamond, buffs on an octagon, everything else (debuffs, roots, stuns)
## on a round one. StatusIconRow skips effects missing from DEFS;
## PlayerStatusRow draws them with PLACEHOLDER. "aura:<curse id>" (a Hex Aura
## the player keeps up) is that curse's icon as a buff.

enum Kind { AILMENT, CURSE, DEBUFF, BUFF }

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
	"forbidden_fire": ["flame", Color(0.62, 0.2, 0.85), Kind.AILMENT],
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
	"steadfast": ["shield", Color(0.7, 0.75, 0.85), Kind.DEBUFF],
	"drenched": ["drop", Color(0.35, 0.6, 1.0), Kind.DEBUFF],
	"stone_skin": ["shield", Color(0.7, 0.55, 0.35), Kind.BUFF],
	"punctured": ["drop", Color(0.85, 0.15, 0.15), Kind.DEBUFF],
	"arach_mark": ["eye", Color(0.65, 0.3, 0.85), Kind.DEBUFF],
	# Player buffs kept outside StatusEffectComponent (PlayerStatusRow).
	"frost_armor": ["shield_tri", Color(0.6, 0.88, 1.0), Kind.BUFF],
	"battle_cry": ["chevrons_up", Color(1.0, 0.72, 0.3), Kind.BUFF],
	"death_shroud": ["void", Color(0.82, 0.86, 0.76), Kind.BUFF],
	"thunderstorm": ["bolt", Color(0.95, 0.9, 0.35), Kind.BUFF],
	"inner_power": ["star", Color(0.45, 0.85, 0.9), Kind.BUFF],
	"charged_reflexes": ["chevrons_up", Color(0.95, 0.9, 0.35), Kind.BUFF],
	"debt": ["lock", Color(0.86, 0.71, 0.42), Kind.BUFF],
}

const PLACEHOLDER := ["diamond", Color(0.72, 0.72, 0.75), Kind.DEBUFF]

static func has(effect_id: String) -> bool:
	return DEFS.has(effect_id)

## [glyph, colour, Kind] for effect_id, PLACEHOLDER when it has no icon.
static func def_of(effect_id: String) -> Array:
	if effect_id.begins_with("aura:"):
		var base: Array = DEFS.get(effect_id.trim_prefix("aura:"), PLACEHOLDER)
		return [base[0], base[1], Kind.BUFF]
	return DEFS.get(effect_id, PLACEHOLDER)

static func is_buff(effect_id: String) -> bool:
	return def_of(effect_id)[2] == Kind.BUFF

static func colour_of(effect_id: String) -> Color:
	return def_of(effect_id)[1]

## Draws effect_id's icon filling `rect` (PLACEHOLDER when it has none).
static func draw(ci: CanvasItem, effect_id: String, rect: Rect2) -> void:
	var def: Array = def_of(effect_id)
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
		Kind.BUFF:
			var o := PackedVector2Array()
			for i in 8:
				o.append(centre + Vector2.from_angle(TAU * (i + 0.5) / 8.0) * r * 0.98)
			ci.draw_colored_polygon(o, back)
			o.append(o[0])
			ci.draw_polyline(o, Color(c, 0.85), maxf(1.0, r * 0.1), true)
		_:
			ci.draw_circle(centre, r * 0.96, back)
			ci.draw_arc(centre, r * 0.92, 0.0, TAU, 24, Color(c, 0.85), maxf(1.0, r * 0.1), true)
	var pen := IconArt.Pen.new(ci, rect)
	IconArt.glyph(pen, def[0], centre, 0.62 if def[2] != Kind.CURSE else 0.5, c.lightened(0.2))
