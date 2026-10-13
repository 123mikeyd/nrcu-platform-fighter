class_name CostumeMaterials
extends RefCounted

# Imported Texture2D resources are immutable and shared by all fighters.  The
# callers duplicate only materials, so one player's overrides cannot bleed into
# another player's visual.
static var _texture_cache: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var loaded := load(path)
	if not loaded is Texture2D:
		push_error("Missing imported costume texture: " + path)
		return null
	_texture_cache[path] = loaded
	return loaded
