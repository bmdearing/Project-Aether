extends RefCounted
class_name GlowTexture
## Soft round particle sprites baked into an ImageTexture straight away.
## Used instead of GradientTexture2D, which fills itself in later through a
## deferred update: when that update didn't land, particles lost their round
## falloff and drew as hard squares (Hub motes). Cached per gradient key.

const SIZE := 64

static var _cache: Dictionary = {}

## White-to-clear radial falloff; `mid` adds a stop (offset, alpha) for a
## brighter core. Same look as the old GradientTexture2D FILL_RADIAL setups.
static func radial(mid: Vector2 = Vector2(-1.0, 0.0)) -> ImageTexture:
	var key := "%s" % mid
	if _cache.has(key):
		return _cache[key]
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	if mid.x >= 0.0:
		grad.add_point(mid.x, Color(1, 1, 1, mid.y))
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			img.set_pixel(x, y, grad.sample(clampf(d, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
