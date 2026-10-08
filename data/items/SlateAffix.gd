extends ItemAffix
class_name SlateAffix
## A rollable Slate modifier, separate from the gear affix pool. Extends
## ItemAffix so corruption's Veiltouch can copy one onto gear directly.
## Hand-authored Slates still use SlateModifier.

@export var tag: String = ""                    # damage type tag ("cold", "entropic"...) or "spell"/"attack"/"generic" - see Constants.DAMAGE_TYPE_TAGS
@export var is_conditional: bool = false         # requires a condition to activate
@export var condition_description: String = ""   # human readable condition
@export var is_behavior_modifier: bool = false   # changes how a skill behaves, not just numbers
