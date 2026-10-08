extends RefCounted
class_name ImplicitPool
## Stub: per-item-type implicit pool for corruption's AddImplicit outcomes.
## Needs data; implicits are currently hand-authored on bases.

static func get_random_for_type(_equip_slot: Constants.EquipmentSlot) -> ItemAffix:
	push_warning("ImplicitPool.get_random_for_type() is a stub - no implicit pool data exists yet.")
	return null
