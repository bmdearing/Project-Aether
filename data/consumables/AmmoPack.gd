extends Item
class_name AmmoPack
## A pickup that adds `amount` rounds to AmmoInventory instead of going into
## the inventory (LootPickup checks for this, same as SkillTome). Never
## equippable and not part of Constants.CRAFTING_CONSUMABLE_IDS.

@export var ammo_type: Constants.AmmoType = Constants.AmmoType.PISTOL
@export var amount: int = 0
