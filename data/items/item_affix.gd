extends Resource
class_name ItemAffix
## A single rolled modifier line on an Item. is_prefix follows Section
## 18's prefix/suffix split. value_min/max/tier are 0 for hand-authored
## implicits (no tier range); ItemRoller.gd fills them in for rolled
## affixes so the advanced tooltip can show the full tier range.

@export var description: String
@export var stat_key: String    # machine key, e.g. "flat_armor"
@export var value: float = 0.0
@export var value_min: float = 0.0
@export var value_max: float = 0.0
@export var tier: int = 0       # 1 = best; 0 = not tiered (hand-authored)
@export var is_prefix: bool = true
