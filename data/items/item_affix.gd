extends Resource
class_name ItemAffix
## A single rolled modifier line on an Item. Mirrors SlateModifier.gd's
## shape (data/slates/modifier.gd) for consistency - value is a fixed
## rolled number for hand-authored items; range fields are for future
## procedural rolling. is_prefix follows Section 18's prefix/suffix split.

@export var description: String            # player-facing text
@export var stat_key: String                # machine key, e.g. "flat_armor"
@export var value: float = 0.0
@export var value_min: float = 0.0          # reserved for procedural rolling
@export var value_max: float = 0.0
@export var is_prefix: bool = true
