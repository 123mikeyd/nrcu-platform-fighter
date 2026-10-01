extends SceneTree
# Regression: semantic scope masks must fail closed when their role has no
# bound source nodes. In particular, EXCLUDE_PRIMARY must never become ALL.

const Runtime = preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const Renderer = preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var runtime
var renderer
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var container := SubViewportContainer.new()
	container.size = Vector2(1280, 720)
	container.stretch = false
	root.add_child(container)
	runtime = Runtime.new()
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "scope contract mounts the real screen")
	renderer = Renderer.new(runtime.screen, runtime.registry)

	var echo_keys := _keys_for_role("echo")
	_check(not echo_keys.is_empty(), "scope fixture has echo bindings")
	for key in echo_keys:
		runtime.registry.slot_nodes.erase(key)
	var echo_result: Dictionary = renderer.apply_final_composite([_layer("ECHO_ONLY")])
	_check(not bool(echo_result.get("ok", false)), "ECHO_ONLY fails closed without echo bindings", str(echo_result.get("errors", [])))

	var primary_keys := _keys_for_role("primary")
	_check(not primary_keys.is_empty(), "scope fixture has primary bindings")
	for key in primary_keys:
		runtime.registry.slot_nodes.erase(key)
	var primary_result: Dictionary = renderer.apply_final_composite([_layer("PRIMARY_ONLY")])
	_check(not bool(primary_result.get("ok", false)), "PRIMARY_ONLY fails closed without primary bindings", str(primary_result.get("errors", [])))
	var exclude_result: Dictionary = renderer.apply_final_composite([_layer("EXCLUDE_PRIMARY")])
	_check(not bool(exclude_result.get("ok", false)), "EXCLUDE_PRIMARY fails closed without primary bindings", str(exclude_result.get("errors", [])))

	renderer.clear_all()
	runtime.free_screen()
	container.queue_free()
	await process_frame
	print("[FX-SCOPE-MASK-CONTRACT] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _keys_for_role(role: String) -> Array:
	var keys: Array = []
	for key in runtime.registry.ordered_keys():
		if str(runtime.registry.context_for_key(key).get("element_role", "")) == role:
			keys.append(key)
	return keys

func _layer(scope: String) -> Dictionary:
	return {
		"layer_id": "scope_contract",
		"type": "FX",
		"plane": "COMPOSITION_FOREGROUND",
		"authority": "COMPOSITION",
		"lane": "FINAL_COMPOSITE",
		"fx": {
			"operator": "NONE",
			"final_tint_amount": 0.0,
			"final_tint_color": [1.0, 0.05, 0.02, 1.0],
			"operator_scope": scope,
		},
	}

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL ", label, " ", detail)
	else:
		print("[CHECK] PASS ", label)
