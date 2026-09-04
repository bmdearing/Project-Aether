extends ItemAffix
class_name SlateAffix
## Patch v3.6 Section 1: a rollable Slate modifier, entirely separate
## from the gear affix pool (ItemRoller.AFFIX_POOL) - Slates and gear
## don't share a pool. The only crossover is the Shard of Tharsis'
## Veiltouch outcome pulling a SlateAffix onto gear as a real ItemAffix
## (see CorruptionOutcome.gd) - extending ItemAffix rather than a fresh
## Resource makes that a plain duplicate() + clear is_implicit, no field
## translation needed.
##
## Not used by hand-authored Slate.gd instances yet - those still carry
## their own fixed SlateModifier list (data/slates/modifier.gd). This is
## scaffolding for a future procedural Slate-affix roll, same footing as
## SlateAffixPool.gd itself.

@export var tag: String = ""                    # damage type tag ("cold", "entropic"...) or "spell"/"attack"/"generic" - see Constants.DAMAGE_TYPE_TAGS
@export var is_conditional: bool = false         # requires a condition to activate
@export var condition_description: String = ""   # human readable condition
@export var is_behavior_modifier: bool = false   # changes how a skill behaves, not just numbers
