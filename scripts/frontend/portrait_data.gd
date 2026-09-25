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

const BODY_DIR := "res://assets/portraits/body/"

static func body_path(id: String, palette_index := 0) -> String:
	# Full-body stills for surfaces that show the whole fighter (Character
	# Select bays, Story/How-to previews, Results). Pre-rendered offline, so the
	# menus stay free of live 3D. Palette-tinted fighters carry one still per
	# slot palette (<id>_p<n>.png); the rest share <id>.png.
	var p := posmod(palette_index, 4)
	if p > 0:
		var variant := BODY_DIR + "%s_p%d.png" % [id, p]
		if ResourceLoader.exists(variant):
			return variant
	return BODY_DIR + id + ".png"

static func body_texture(id: String, palette_index := 0) -> Texture2D:
	# Falls back to the bust portrait when no full-body still exists.
	if id == "":
		return null
	var path := body_path(id, palette_index)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return portrait_texture(id)

static func missing_ids(ids: Array) -> Array[String]:
	var missing: Array[String] = []
	for id in ids:
		if not has_portrait(str(id)):
			missing.append(str(id))
	return missing
