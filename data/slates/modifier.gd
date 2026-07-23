extends Resource
class_name SlateModifier
## A single passive modifier line on a Slate. Value is a fixed rolled number
## for hand-authored Slates; range fields are for future procedural rolling.

@export var description: String            # player-facing text, e.g. "Entropic damage deals X% increased damage per Wound"
@export var stat_key: String                # machine key consumed by DamageCalculator / StatSheet, e.g. "entropic_dmg_per_wound"
@export var value: float = 0.0
@export var value_min: float = 0.0          # reserved for procedural rolling
@export var value_max: float = 0.0
@export var is_more_multiplier: bool = false # true = multiplicative "More", false = additive "Increased"
