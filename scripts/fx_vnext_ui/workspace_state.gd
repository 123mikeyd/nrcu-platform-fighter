extends RefCounted
# NRCU FX Lab vNext — workspace persistence (specs/01 §7).
# Persisted per user/editor in user:// only — never in Production Look data.

const PATH := "user://nrcu_fx_vnext_workspace.json"
const PRESET_AUTHORING := "AUTHORING"
const PRESET_FOCUS := "FOCUS"
# Compatibility for existing workspace files and callers. The product label is
# FOCUS; PREVIEW remains an accepted input while old persisted state migrates.
const PRESET_PREVIEW := PRESET_FOCUS
const INTENT_AUTO := "AUTO"
const INTENT_USER_OPEN := "USER_OPEN"
const INTENT_USER_CLOSED := "USER_CLOSED"

const BROWSER_MIN := 220.0
const BROWSER_MAX := 360.0
const DOCK_MIN := 320.0
const TIMELINE_MIN := 120.0
const TIMELINE_MAX := 240.0

const DEFAULTS := {
	"browser_w": 280.0,
	"dock_w": 390.0,
	"dock_hidden": false,
	"layers_split": 0.38,
	"timeline_h": 200.0,
	"timeline_expanded": false,
	"browser_collapsed": false,
	"browser_intent": INTENT_AUTO,
	"timeline_intent": INTENT_AUTO,
	"preview_focus": "NORMAL",
	"preset": "AUTHORING",
	"workspace_role": "AUTHORING",
}

var data: Dictionary = {}

func _init() -> void:
	data = DEFAULTS.duplicate(true)

func load_state() -> bool:
	var f := FileAccess.open(state_path(), FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	for key in DEFAULTS.keys():
		if parsed.has(key):
			data[key] = parsed[key]
	# Migrate pre-tristate workspace files. The old booleans represented the
	# last rendered state; only an old explicit collapse/expand carries intent.
	if not parsed.has("browser_intent") and bool(parsed.get("browser_collapsed", false)):
		data["browser_intent"] = INTENT_USER_CLOSED
	if not parsed.has("timeline_intent") and bool(parsed.get("timeline_expanded", false)):
		data["timeline_intent"] = INTENT_USER_OPEN
	_clamp()
	return true

func save_state() -> void:
	_clamp()
	var path := state_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func state_path() -> String:
	var override := OS.get_environment("NRCU_FX_WORKSPACE_PATH")
	return override if override != "" else PATH

func reset() -> void:
	data = DEFAULTS.duplicate(true)

func apply_preset(name: String) -> void:
	var role := PRESET_FOCUS if name in [PRESET_FOCUS, "PREVIEW"] else PRESET_AUTHORING
	data["preset"] = role
	data["workspace_role"] = role
	match role:
		PRESET_FOCUS:
			# Focus is a presentation-review role: the preview is soloed, the
			# browser yields space, and the inspector remains available through
			# the right-dock Properties tab.
			data["browser_w"] = BROWSER_MIN
			data["dock_w"] = 420.0
			data["layers_split"] = 0.28
			data["preview_focus"] = "SOLO"
			data["timeline_expanded"] = false
			data["browser_collapsed"] = true
			data["browser_intent"] = INTENT_USER_CLOSED
			data["timeline_intent"] = INTENT_AUTO
		_:
			# Authoring is the default DCC role: keep target discovery open,
			# show the full layer stack, and restore a neutral preview.
			data["browser_w"] = DEFAULTS["browser_w"]
			data["dock_w"] = DEFAULTS["dock_w"]
			data["layers_split"] = 0.38
			data["preview_focus"] = "NORMAL"
			data["timeline_expanded"] = false
			data["browser_collapsed"] = false
			data["browser_intent"] = INTENT_USER_OPEN
			data["timeline_intent"] = INTENT_AUTO

func _clamp() -> void:
	data["browser_w"] = clampf(float(data.get("browser_w", 280.0)), BROWSER_MIN, BROWSER_MAX)
	data["dock_w"] = maxf(float(data.get("dock_w", 390.0)), DOCK_MIN)
	data["timeline_h"] = clampf(float(data.get("timeline_h", 200.0)), TIMELINE_MIN, TIMELINE_MAX)
	data["layers_split"] = clampf(float(data.get("layers_split", 0.42)), 0.15, 0.85)
	data["browser_intent"] = _normalize_intent(data.get("browser_intent", INTENT_AUTO))
	data["timeline_intent"] = _normalize_intent(data.get("timeline_intent", INTENT_AUTO))
	var focus := str(data.get("preview_focus", "NORMAL"))
	data["preview_focus"] = focus if focus in ["NORMAL", "DIM OTHERS", "SOLO"] else "NORMAL"

func _normalize_intent(raw: Variant) -> String:
	var intent := str(raw)
	return intent if intent in [INTENT_AUTO, INTENT_USER_OPEN, INTENT_USER_CLOSED] else INTENT_AUTO
