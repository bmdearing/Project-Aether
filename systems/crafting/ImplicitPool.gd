extends RefCounted
class_name ImplicitPool
## Patch v3.6 stub - per-item-type implicit affix pool for Shard of
## Tharsis' AddImplicit/AddSecondImplicit outcomes. No such pool exists
## yet (every implicit in this project today is hand-authored directly
## on a base Item, not drawn from a shared pool) - this needs real data
## before it can do anything, per the brief's own "stubs only" scope.

static func get_random_for_type(_equip_slot: Constants.EquipmentSlot) -> ItemAffix:
	push_warning("ImplicitPool.get_random_for_type() is a stub - no implicit pool data exists yet.")
	return null
