extends RefCounted
class_name UniquePool
## Corrupted Uniques for the Shard of Tharsis' Transcendent outcome: the
## UniqueCatalog entries marked corrupted_only, which never drop. Each is
## returned on a blank base; the outcome copies its name and modifiers onto
## the corrupted item.

static func get_corrupted_uniques_for_type(_equip_slot: Constants.EquipmentSlot) -> Array[Item]:
	var result: Array[Item] = []
	for def in UniqueCatalog.DEFS:
		if def.get("corrupted_only", false) and def["base_type"] == "any":
			result.append(UniqueRoller.build(def, 1, Item.new()))
	return result
