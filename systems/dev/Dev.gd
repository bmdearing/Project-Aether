class_name Dev
## The one switch for testing conveniences: cut Pinnacle Life, free Pinnacle
## entry, the Spell Testing Shop, the Currency Exchange, the Gear Shop's
## Unique test stock and the Level 90 Test character.
## On in the editor and debug exports; off in release exports
## (--export-release) unless the preset lists the "dev" custom feature.
## Tests may flip it.

static var enabled: bool = OS.is_debug_build() or OS.has_feature("dev")
