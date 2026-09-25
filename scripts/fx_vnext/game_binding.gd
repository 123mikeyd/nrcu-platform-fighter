extends "res://scripts/fx_vnext/vs_runtime.gd"
# Thin game consumer: inherits the reference consumer's canonical resolver,
# production loading and clock propagation, not its preview mount/lifetime.
# Added only by VsPresentationAdapter after the actual screen has started.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func bind_started_screen(screen: CanvasLayer, format: String, stage: String) -> Dictionary:
	production = FxProductionScript.new()
	var override := OS.get_environment("NRCU_FX_DATA_DIR")
	if override != "": production.data_dir = override
	elif not _has_local_production(production.data_dir):
		# A fresh checkout or an export has no locally authored Production
		# (nrcu_fx_data is authoring state and git-ignored). Play the shipped,
		# read-only default instead of silently dropping the VS screen.
		production.data_dir = DEFAULT_PRODUCTION_DIR
	# Game consumption is read-only. Recovery/writes belong to the authoring
	# process; packaged res:// production may be read-only.
	runtime = ScreenRuntimeScript.new(false)
	runtime.screen = screen
	runtime.mode_format = format
	runtime.stage_id = stage
	runtime.install_vector_proxies()
	runtime.registry.bind_screen(screen, format, stage)
	renderer = FxLayerRendererScript.new(screen, runtime.registry)
	renderer.set_event_marks(runtime.event_marks())
	var result: Dictionary = reload_production()
	# An absent production store is a valid empty V2 document for the authoring
	# resolver, but it is not a valid live-game presentation. Do not silently
	# claim a started FX consumer when no approved production plan was bound.
	var plan_ids: Array = result.get("plan_ids", [])
	if bool(result.get("ok", false)) and plan_ids.is_empty():
		var errors: Array = result.get("errors", [])
		errors.append({
			"code": "fx_production_unavailable",
			"message": "No approved production FX plan is available for the live VS screen.",
		})
		result["ok"] = false
		result["errors"] = errors
		last_summary = result
		renderer.clear_all()
	set_process(true)
	return result

const DEFAULT_PRODUCTION_DIR := "res://assets/vs/fx/default_production"

static func _has_local_production(dir: String) -> bool:
	for name in ["composition.json", "assignments.json"]:
		if FileAccess.file_exists(dir.path_join(name)) or FileAccess.file_exists(dir.path_join(name + ".prev")):
			return true
	return false

func _exit_tree() -> void:
	# All render nodes are screen descendants and die with it. Freeing siblings
	# inside this child's exit notification mutates a busy parent (engine crash).
	# Drop RefCounted owners only; the SceneTree owns native node teardown.
	renderer = null
	if runtime != null:
		runtime.screen = null
		runtime = null
