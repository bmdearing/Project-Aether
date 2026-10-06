extends OmniLight3D
class_name FlickerLight
## Torch/brazier light with a soft, irregular flicker around its base energy.
## Stands in for the WC3 fire particles, which the MDX converter doesn't export.

const FLICKER_AMOUNT := 0.18
const FLICKER_SPEED := 9.0

var _base_energy: float
var _phase: float

func _ready() -> void:
	_base_energy = light_energy
	_phase = randf() * 100.0
	shadow_enabled = false

func _process(delta: float) -> void:
	_phase += delta * FLICKER_SPEED
	var wobble := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1) * 0.2
	light_energy = _base_energy * (1.0 + wobble * FLICKER_AMOUNT)
