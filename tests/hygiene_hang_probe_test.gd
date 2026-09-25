# Harness hygiene probe: deliberately outlives any sane runner timeout so
# tools/test_run_godot_suite.py can prove the kill fallback leaves no process.
# Permanent instrument (timeout path). Never referenced by product code.
extends SceneTree

func _init() -> void:
	for i in 36000:
		await process_frame
	print("[HYGIENE-PROBE] should never print (runner must kill first)")
	quit(0)
