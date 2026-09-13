extends RefCounted
# Portrait asset pipeline (Doc 04 §7) — fighter_id -> 2D portrait texture.
#
# The roster displays pre-generated PNG portraits (produced offline by
# tools/portrait_gen.gd from the shared FighterRenderView PORTRAIT profile), so
# the roster itself never owns a live 3D viewport. Final character art drops in
# by replacing the PNG at the same path — no UI change required.

const DIR := "res://assets/portraits/"

static func portrait_path(id: String) -> String:
	return DIR + id + ".png"

static func has_portrait(id: String) -> bool:
	return id != "" and ResourceLoader.exists(portrait_path(id))

static func portrait_texture(id: String) -> Texture2D:
	if not has_portrait(id):
		return null
	return load(portrait_path(id)) as Texture2D

static func missing_ids(ids: Array) -> Array[String]:
	var missing: Array[String] = []
	for id in ids:
		if not has_portrait(str(id)):
			missing.append(str(id))
	return missing
