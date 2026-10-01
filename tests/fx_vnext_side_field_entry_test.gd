extends SceneTree
# Side fields must enter from the edges in BOTH the Lab proxy and game polygon.
const Runtime = preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var rt = Runtime.new()
	root.add_child(rt.subvp)
	for i in 5: await process_frame
	check(rt.mount("1v1", "debug", "ice_mage", "doge_man"), "Lab runtime mounts")
	for i in 5: await process_frame
	var scr = rt.screen
	var plates: Node = scr.get_node_or_null("Root/NamePlates")
	for child in plates.get_children():
		print("[FX-SIDE-ENTRY] plate-node ", child.name, " visible=", child.visible, " modulate=", child.modulate, " z=", child.z_index)
	scr.lab_preview_pause()
	var left = scr.get_node_or_null("Root/SideFields/FieldLeft_FXProxy")
	var right = scr.get_node_or_null("Root/SideFields/FieldRight_FXProxy")
	check(left != null and right != null, "Lab fields have live proxies")
	if left != null and right != null:
		rt.seek(0.0)
		await process_frame
		check(left.position.x < -300.0 and right.position.x > 300.0 and left.modulate.a < 0.01 and right.modulate.a < 0.01, "entry starts outside frame and invisible")
		rt.seek(0.25)
		await process_frame
		check(left.position.x > -300.0 and left.position.x < 0.0 and right.position.x < 300.0 and right.position.x > 0.0, "both fields travel toward their canonical positions")
		rt.seek(0.6)
		await process_frame
		check(absf(left.position.x) < 0.01 and absf(right.position.x) < 0.01 and left.modulate.a > 0.99 and right.modulate.a > 0.99, "fields settle at canonical geometry")
	rt.subvp.queue_free()
	for i in 3: await process_frame
	print("[FX-SIDE-ENTRY] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[FX-SIDE-ENTRY] %s %s" % ["PASS" if ok else "FAIL", label])
