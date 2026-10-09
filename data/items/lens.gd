extends Jewel
class_name Lens
## Socketed into a Slate's socket (Slate.lenses), never into gear, and
## freely removable. Its radius modifier changes the Slates within `radius`
## tiles of its host on the Fate Board (FateBoard.lens_effects_at()); its
## jewel modifiers count as the character's while the host Slate is placed.

const LENS_NAME := "Lens"
## Radius in tiles -> size word in the name.
const SIZE_NAMES := {2: "Small", 3: "Medium", 4: "Large"}

@export var radius: int = 2
## LensRoller.RADIUS_MODS id.
@export var radius_mod: String = ""
@export var radius_value: float = 0.0
## Damage type for tag-specific radius modifiers, -1 otherwise.
@export var radius_tag: int = -1

## The radius modifier as card text: "Fire Slates in radius have 30% stronger modifiers".
func radius_text() -> String:
	var def: Dictionary = LensRoller.RADIUS_MODS.get(radius_mod, {})
	if def.is_empty():
		return ""
	var tag_name: String = Constants.DAMAGE_TYPE_NAME.get(radius_tag, "")
	return String(def["text"]).replace("{tag}", tag_name).replace("{v}", str(roundi(radius_value)))
