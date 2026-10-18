extends RefCounted
class_name ShadowLight
## Light energies for shadow-casting lights are authored for Forward+. The
## Compatibility renderer (the OpenGL fallback on GPUs without Vulkan/D3D12)
## lights a surface roughly twice over when its light casts shadows, so its
## energy is divided back down there to keep the same look.

const DIRECTIONAL_COMPAT := 2.25
const OMNI_COMPAT := 2.5

static var _compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"

static func directional(energy: float) -> float:
	return energy / DIRECTIONAL_COMPAT if _compat else energy

static func omni(energy: float) -> float:
	return energy / OMNI_COMPAT if _compat else energy
