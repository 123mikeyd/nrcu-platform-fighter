extends SceneTree
# Regression: the game adapter must not report a started presentation when
# Production data cannot be loaded by game_binding.gd.

const Setup = preload("res://tools/fx_review_setup.gd")
const Adapter = preload("res://scripts/vs_presentation_adapter.gd")

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var missing_dir := ProjectSettings.globalize_path("user://fx_adapter_missing_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(missing_dir)
	var broken := FileAccess.open(missing_dir.path_join("assignments.json"), FileAccess.WRITE)
	broken.store_string("{}")
	broken.close()
	OS.set_environment("NRCU_FX_DATA_DIR", missing_dir)
	var adapter := Adapter.new()
	root.add_child(adapter)
	var bypasses: Array = []
	adapter.bypassed.connect(func(reason): bypasses.append(reason))

	var began := adapter.begin(Setup.match_config())
	_check(not began, "adapter rejects a presentation when Production loading fails")
	_check(not adapter.has_started(), "failed Production bind is not reported as started")
	_check(adapter.screen() == null, "failed Production bind tears down the screen")
	_check(adapter.bypass_reason() == "fx_production_unavailable", "Production failure has a distinct bypass reason", adapter.bypass_reason())
	_check(bypasses == ["fx_production_unavailable"], "Production failure reaches the bypass signal", str(bypasses))
	_check(not adapter.production_errors().is_empty(), "Production load errors remain observable", str(adapter.production_errors()))

	adapter.queue_free()
	await process_frame

	var empty_dir := ProjectSettings.globalize_path("user://fx_adapter_empty_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(empty_dir)
	OS.set_environment("NRCU_FX_DATA_DIR", empty_dir)
	var empty_adapter := Adapter.new()
	root.add_child(empty_adapter)
	var empty_began := empty_adapter.begin(Setup.match_config())
	_check(not empty_began, "adapter rejects an absent Production store")
	_check(not empty_adapter.has_started(), "empty Production store is not reported as started")
	_check(empty_adapter.screen() == null, "empty Production store tears down the screen")
	_check(empty_adapter.bypass_reason() == "fx_production_unavailable", "empty Production store has a distinct bypass reason", empty_adapter.bypass_reason())
	empty_adapter.queue_free()
	await process_frame
	OS.set_environment("NRCU_FX_DATA_DIR", "")
	print("[FX-ADAPTER-FAILURE] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL ", label, " ", detail)
	else:
		print("[CHECK] PASS ", label)
