# Harness hygiene probe: exits cooperatively after a few frames.
# Permanent instrument for tools/test_run_godot_suite.py (pass path).
extends SceneTree

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame
	print("[HYGIENE-PROBE] clean exit")
	quit(0)
