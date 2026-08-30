extends Item
class_name Brand
## Section 20 - Crafting System's primary currency: "dropped as loot only
## ... consumed on every attempt" (see BrandRoller.gd for drops,
## CraftingSystem.gd for what a craft actually does with one). Max 2 of
## the same Brand per Cube craft is enforced by CraftingScreen at
## placement time, not here.
##
## `equip_slot` (inherited from Item) is meaningless here, same as
## MapItem - a Brand is never equipped via EquipmentComponent.
##
## Scope: the doc's Damage Type (9), Defensive Type (5), Umbrella (4), and
## Crafting Utility (6) Brands are all modeled, plus 2 of the 5 Special/
## Rare Brands (Binder, Rectify) - Facsimile/Amalgam/Imbue are cut for
## this pass (item duplication, mod-pool merging, and a new "powerful
## implicit" pool are each their own separate can of worms; README flags
## this).

enum BrandFunction {
	DAMAGE_TYPE,     # biases a new affix toward this damage type's category (Constants.DamageType, via category_tag)
	DEFENSIVE_TYPE,  # biases toward a defensive stat category (armor/evasion/ward/resistance/resilience)
	UMBRELLA,        # biases toward a broad category (resource/skills/movement)
	RENDER,          # reroll every explicit affix - new stat_keys too, same count
	REFINE,          # boost every existing affix's value
	CLEAVE,          # lock one affix, reroll the rest - 2nd use ever risks destroying the item
	EXCISE,          # remove one chosen affix
	BORE,            # set max_sockets to this item type's Section 15 cap - one-time
	SEVER,           # combined with a category Brand in the same craft, permanently seals that tag
	BINDER,          # exempts every other Brand in the craft from consumption; protects a failed 2nd Sever
	RECTIFY,         # reroll existing affix VALUES only (same stat_keys) - no risk, unlike Cleave
}

@export var brand_function: BrandFunction = BrandFunction.DAMAGE_TYPE
## Only meaningful for DAMAGE_TYPE/DEFENSIVE_TYPE/UMBRELLA (and as SEVER's
## paired tag) - see ItemRoller.AFFIX_POOL's own brand_tags for the pool
## each value can draw from.
@export var category_tag: String = ""
