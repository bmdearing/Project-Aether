extends RefCounted
class_name SpecialCorruptionPool
## Patch v3.6 stub - mods only reachable through corruption, never normal
## crafting (Shard of Tharsis' AddSpecialAffix outcome). No such pool
## exists yet - needs real design before it can do anything, per the
## brief's own "stubs only" scope.

static func get_random(_item_level: int) -> ItemAffix:
	push_warning("SpecialCorruptionPool.get_random() is a stub - no special-corruption pool data exists yet.")
	return null
