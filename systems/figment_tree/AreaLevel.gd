extends RefCounted
class_name AreaLevel
## Area Level: the one number a Figment's monsters, drops and XP follow.
## Player level never feeds monster stats; it only gates equipping gear (and
## sets the XP gap below), so a strong build can push content above its level.
##
## Fragmented Reality levels through Depths 1-23 (Area Level 1-67, 3 per
## Depth) before the endgame; the Campaign (when it exists) replaces that
## stage. Both then share the endgame: Tier N is Area Level 68 + N (T1 = 69,
## T21 = 89), and Pinnacle bosses are 90.

const DEPTHS := 23
const LEVELS_PER_DEPTH := 3
const ENDGAME_BASE := 68
const PINNACLE := 90

## Monster stats compound per level above 1 (from tests/balance/probe_power_curve:
## typical gear DPS grows ~20x from level 1 to 89, so health grows a little
## faster, 24.6x, to keep time-to-kill steady). XP and Gold compound too.
## Damage grows steeply (21x by 89) so fighting far above your level is
## deadly, not just slow; the player's Life and Ward grow with level
## (PLAYER_POOL_GROWTH) so an on-level hit stays where the old 1.021 damage
## curve had it (about 7.7% of typical Life after Armour at 89). That's a
## little more than DAMAGE_GROWTH / 1.021, since Armour stops less of a big
## hit. Fitted with probe_power_curve; a level 14 at Area Level 74 takes about
## 34% of their Life per standard hit (12% on the old curve).
const HEALTH_GROWTH := 1.037
const DAMAGE_GROWTH := 1.035
const PLAYER_POOL_GROWTH := 1.0185
const XP_GROWTH := 1.165
const GOLD_GROWTH := 1.02

## XP gap: the zone is 7 + 10% of the player's level. Monsters below the
## player taper from 100% to 0% across the zone; above, XP rises to +20% at
## the zone's edge and no further.
const XP_ZONE_BASE := 7
const XP_ZONE_PER_LEVEL := 0.1
const XP_ABOVE_BONUS := 0.2

static func of_figment(figment: FigmentItem) -> int:
	if figment == null:
		return 0
	if figment.depth > 0:
		return clampi(figment.depth, 1, DEPTHS) * LEVELS_PER_DEPTH - (LEVELS_PER_DEPTH - 1)
	return ENDGAME_BASE + clampi(figment.tier, 1, FigmentMods.MAX_TIER)

## The current area's level: the active Figment, a Pinnacle arena, or 0
## (Hub, test scenes: monsters keep their definition's own level).
static func current() -> int:
	if GameState.active_map:
		return of_figment(GameState.active_map)
	if GameState.in_pinnacle:
		return PINNACLE
	return 0

static func health_scale(level: int) -> float:
	return pow(HEALTH_GROWTH, maxi(level, 1) - 1)

static func damage_scale(level: int) -> float:
	return pow(DAMAGE_GROWTH, maxi(level, 1) - 1)

## Monsters further above you than your XP zone hit harder still: x1.04 per
## level past it. A level 14 takes ~12% of their Life from a standard hit 20
## levels up, ~63% at 40 and is one-shot from about 50 (289% at 60).
const GAP_DAMAGE_GROWTH := 1.04

static func gap_damage_multiplier(monster_level: int, player_level: int) -> float:
	var over := monster_level - player_level - xp_zone(player_level)
	return pow(GAP_DAMAGE_GROWTH, over) if over > 0 else 1.0

## How much the player's maximum Life and Ward grow at a character level.
static func player_pool_scale(level: int) -> float:
	return pow(PLAYER_POOL_GROWTH, maxi(level, 1) - 1)

static func xp_scale(level: int) -> float:
	return pow(XP_GROWTH, maxi(level, 1) - 1)

static func gold_scale(level: int) -> float:
	return pow(GOLD_GROWTH, maxi(level, 1) - 1)

static func xp_zone(player_level: int) -> int:
	return XP_ZONE_BASE + floori(player_level * XP_ZONE_PER_LEVEL)

## XP multiplier for killing a monster of `monster_level` at `player_level`.
static func xp_multiplier(monster_level: int, player_level: int) -> float:
	var zone := float(xp_zone(player_level))
	var gap := monster_level - player_level
	if gap >= 0:
		return 1.0 + XP_ABOVE_BONUS * minf(gap / zone, 1.0)
	return maxf(1.0 + gap / zone, 0.0)
