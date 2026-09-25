extends SceneTree
# Static gate for the final-composite acceptance harness. Pixel readback is
# mandatory by default; only an explicitly named static-only mode may skip it.

var checks := 0
var failures := 0

func _init() -> void:
	var file := FileAccess.open("res://tests/fx_vnext_final_composite_test.gd", FileAccess.READ)
	var source := file.get_as_text() if file != null else ""
	_check(not source.is_empty(), "final-composite acceptance test is readable")
	_check(source.find("FX_FINAL_READBACK") < 0, "legacy opt-in readback flag is removed")
	_check(source.find("pixel readback is opt-in") < 0, "forced-green readback fallback is removed")
	_check(source.find("FX_FINAL_STATIC_ONLY") >= 0, "static-only mode is explicit")
	_check(source.find("if not static_only") >= 0, "default acceptance path performs readback")
	print("[FX-FINAL-RUNNER-CONTRACT] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL ", label)
	else:
		print("[CHECK] PASS ", label)
