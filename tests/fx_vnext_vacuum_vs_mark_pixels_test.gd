extends SceneTree
# Windowed rendered-pixel proof: vacuum warps the nearby frame but never pixels
# belonging to the opaque portion of the live VS wordmark.
const Runtime = preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const Renderer = preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const Look = preload("res://scripts/fx_vnext/fx_look.gd")
const Evidence = preload("res://scripts/fx_vnext/fx_evidence.gd")

const W := 1280
const H := 720
const TIME := 0.65
const NOISE_FLOOR := 0.0005
var checks := 0
var failures := 0
var host: Control
var runtime
var renderer
var out_dir := ""
var mark_alpha: Image
var protected_alpha: Image

func _init() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "": out_dir = ProjectSettings.globalize_path("res://evidence/vacuum_vs_mark")
	DirAccess.make_dir_recursive_absolute(out_dir)
	host = Control.new()
	host.size = Vector2(W, H)
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(W, H)
	host.add_child(container)
	runtime = Runtime.new()
	container.add_child(runtime.subvp)
	await process_frame
	check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "windowed VS runtime mounts")
	await settle(35)
	runtime.screen.lab_preview_resume()
	runtime.seek(TIME)
	check(runtime.screen.lab_preview_is_paused(), "user seek leaves preview paused")
	runtime.screen.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 0.0
	renderer = Renderer.new(runtime.screen, runtime.registry)
	renderer.set_clocks(TIME, TIME)
	await settle(4)
	mark_alpha = await isolate_mark_alpha()
	check(mark_alpha != null, "live mark alpha matte readback exists")
	protected_alpha = await isolate_mark_shadow_alpha()
	check(protected_alpha != null, "live mark+shadow exclusion matte readback exists")
	var alpha_count := _opaque_count(mark_alpha)
	check(alpha_count > 100, "texture alpha >0.9 defines opaque VS mark pixels", "count=%d" % alpha_count)
	var pre_neutral := await capture()
	var active := vacuum_look()
	check(await apply(active), "active vacuum composition installs mark protection")
	await settle(4)
	var at_time := await capture()
	var metrics := compare(pre_neutral, at_time, mark_alpha)
	var protected_metrics := compare(pre_neutral, at_time, protected_alpha)
	check(metrics.mark_count > 100, "opaque mark ROI has sufficient samples", "count=%d" % metrics.mark_count)
	check(metrics.mark_mad <= NOISE_FLOOR, "active vacuum leaves opaque mark pixels at same noise floor", "mad=%.8f floor=%.8f" % [metrics.mark_mad, NOISE_FLOOR])
	check(protected_metrics.mark_count > metrics.mark_count, "mark+shadow ROI is larger than the mark alone", "count=%d" % protected_metrics.mark_count)
	# Ghost-proof by construction: the final pass is layered below VsMark, so
	# the captured frame never contains mark or shadow and cannot smear them.
	var final_node: Node = runtime.screen.get_node_or_null("Root/vnext_final_composite")
	var vs_node: Node = runtime.screen.get_node_or_null("Root/VsMark")
	check(final_node != null and vs_node != null and final_node.get_index() < vs_node.get_index(), "vacuum pass is layered below the VS mark and its shadow")
	check(protected_metrics.mark_mad <= NOISE_FLOOR, "mark and shadow pixels are untouched by the vacuum", "mad=%.8f floor=%.8f" % [protected_metrics.mark_mad, NOISE_FLOOR])
	check(metrics.nearby_mad > NOISE_FLOOR, "nearby background ROI is visibly distorted", "mad=%.8f" % metrics.nearby_mad)
	# Use neutral-before/after captures at the exact same frozen scene/time; active
	# must match the neutral image on the protected mark and repeat deterministically.
	check(await apply(neutral_look()), "neutral control installs")
	await settle(3)
	var neutral_after := await capture()
	check(await apply(active), "vacuum replay installs")
	await settle(3)
	var replay := await capture()
	var recovery := compare(pre_neutral, neutral_after, mark_alpha)
	var replay_diff := _image_mad(at_time, replay)
	check(recovery.full_mad <= NOISE_FLOOR, "before/after event neutral frame matches exactly within noise floor", "mad=%.8f" % recovery.full_mad)
	check(replay_diff <= NOISE_FLOOR, "active vacuum replay is stable", "mad=%.8f" % replay_diff)
	check(recovery.mark_mad <= NOISE_FLOOR, "neutral recovery preserves wordmark pixels", "mad=%.8f" % recovery.mark_mad)
	_check_artifacts(pre_neutral, at_time, neutral_after, replay, metrics, recovery, replay_diff)
	print("[FX-VACUUM-VS-MARK] done · checks=%d failures=%d" % [checks, failures])
	Engine.time_scale = 1.0
	quit(1 if failures else 0)

func vacuum_look() -> Dictionary:
	var layer: Dictionary = Look.new_layer("FX", "Vacuum proof")
	layer["plane"] = "COMPOSITION_FOREGROUND"
	layer["authority"] = "COMPOSITION"
	layer["lane"] = "FINAL_COMPOSITE"
	var fx: Dictionary = layer["fx"]
	fx["operator"] = "vacuum_burst"
	fx["operator_strength"] = 1.0
	fx["operator_event_start"] = 0.0
	fx["operator_duration"] = 2.0
	fx["operator_scale"] = 1.0
	fx["operator_center"] = [0.5, 0.5]
	var doc: Dictionary = Look.new_look("VACUUM_VS_PROOF", "Vacuum VS proof")
	doc["layers"].append(layer)
	return Look.materialize(doc)

func neutral_look() -> Dictionary:
	var layer: Dictionary = Look.new_layer("FX", "Vacuum proof")
	layer["plane"] = "COMPOSITION_FOREGROUND"
	layer["authority"] = "COMPOSITION"
	layer["lane"] = "FINAL_COMPOSITE"
	var doc: Dictionary = Look.new_look("VACUUM_VS_NEUTRAL", "Vacuum VS neutral")
	doc["layers"].append(layer)
	return Look.materialize(doc)

func apply(doc: Dictionary) -> bool:
	var r: Dictionary = renderer.apply_composition([{"key":"composition", "scope":"COMPOSITION", "look":doc}], {"anchor_target_key":""})
	if not bool(r.get("ok", false)):
		check(false, "composition renderer accepts document", str(r.get("errors", [])))
		return false
	renderer.set_clocks(TIME, TIME)
	return true

func isolate_mark_alpha() -> Image:
	var mark: CanvasItem = runtime.screen.get_node_or_null("Root/VsMark/Mark") as CanvasItem
	if mark == null: return null
	var white := Shader.new()
	white.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(1.0,1.0,1.0,COLOR.a); }"
	var hidden := Shader.new()
	hidden.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(0.0); }"
	var saved: Array = []
	_isolate(runtime.screen, mark, white, hidden, saved)
	var prior: bool = runtime.subvp.transparent_bg
	runtime.subvp.transparent_bg = true
	await settle(4)
	await RenderingServer.frame_post_draw
	var image: Image = runtime.subvp.get_texture().get_image()
	for state in saved:
		(state[0] as CanvasItem).material = state[1]
		(state[0] as CanvasItem).use_parent_material = state[2]
	runtime.subvp.transparent_bg = prior
	await settle(4)
	return image

func isolate_mark_shadow_alpha() -> Image:
	var mark := runtime.screen.get_node_or_null("Root/VsMark/Mark") as CanvasItem
	var shadow := runtime.screen.get_node_or_null("Root/VsMark/UnderShadow") as CanvasItem
	if mark == null or shadow == null: return null
	var white := Shader.new()
	white.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(1.0,1.0,1.0,COLOR.a); }"
	var hidden := Shader.new()
	hidden.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(0.0); }"
	var saved: Array = []
	_isolate_with_two(runtime.screen, mark, shadow, white, hidden, saved)
	var prior: bool = runtime.subvp.transparent_bg
	runtime.subvp.transparent_bg = true
	await settle(4)
	await RenderingServer.frame_post_draw
	var image: Image = runtime.subvp.get_texture().get_image()
	for state in saved:
		(state[0] as CanvasItem).material = state[1]
		(state[0] as CanvasItem).use_parent_material = state[2]
	runtime.subvp.transparent_bg = prior
	await settle(4)
	return image

func _isolate_with_two(node: Node, first: CanvasItem, second: CanvasItem, white: Shader, hidden: Shader, saved: Array) -> void:
	if node is SubViewport: return
	if node is CanvasItem:
		saved.append([node, node.material, node.use_parent_material])
		var material := ShaderMaterial.new()
		material.shader = white if node == first or node == second else hidden
		node.material = material
		node.use_parent_material = false
	for child in node.get_children(): _isolate_with_two(child, first, second, white, hidden, saved)

func _isolate(node: Node, selected: CanvasItem, white: Shader, hidden: Shader, saved: Array) -> void:
	if node is SubViewport: return
	if node is CanvasItem:
		saved.append([node, node.material, node.use_parent_material])
		var material := ShaderMaterial.new()
		material.shader = white if node == selected or bool(node.get_meta("fx_mask_shadow", false)) else hidden
		node.material = material
		node.use_parent_material = false
	for child in node.get_children(): _isolate(child, selected, white, hidden, saved)

func capture() -> Image:
	renderer.set_clocks(TIME, TIME)
	await RenderingServer.frame_post_draw
	return host.get_viewport().get_texture().get_image()

func compare_outside_protected(a: Image, b: Image, protected: Image, mark: Image) -> Dictionary:
	var sum := 0.0
	var count := 0
	var mx0 := W; var my0 := H; var mx1 := 0; var my1 := 0
	for y in H:
		for x in W:
			if mark.get_pixel(x, y).a > 0.9:
				mx0 = mini(mx0, x); my0 = mini(my0, y); mx1 = maxi(mx1, x); my1 = maxi(my1, y)
	var rect := Rect2i(maxi(0, mx0 - 36), maxi(0, my0 - 36), mini(W, mx1 + 37) - maxi(0, mx0 - 36), mini(H, my1 + 37) - maxi(0, my0 - 36))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if protected.get_pixel(x, y).a > 0.05: continue
			sum += _pixel_diff(a.get_pixel(x, y), b.get_pixel(x, y))
			count += 1
	return {"outside_mark_mad": sum / float(maxi(count, 1)), "outside_mark_count": count}

func compare(a: Image, b: Image, alpha: Image) -> Dictionary:
	var mark_sum := 0.0
	var mark_n := 0
	var near_sum := 0.0
	var near_n := 0
	var full_sum := 0.0
	var full_n := 0
	var mx0 := W; var my0 := H; var mx1 := 0; var my1 := 0
	for y in H:
		for x in W:
			var d := _pixel_diff(a.get_pixel(x,y), b.get_pixel(x,y))
			full_sum += d; full_n += 1
			if alpha.get_pixel(x,y).a > 0.9:
				mark_sum += d; mark_n += 1
				mx0 = mini(mx0,x); my0 = mini(my0,y); mx1 = maxi(mx1,x); my1 = maxi(my1,y)
	var rect := Rect2i(maxi(0,mx0-36), maxi(0,my0-36), mini(W,mx1+37)-maxi(0,mx0-36), mini(H,my1+37)-maxi(0,my0-36))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if alpha.get_pixel(x,y).a > 0.9: continue
			var d := _pixel_diff(a.get_pixel(x,y), b.get_pixel(x,y))
			near_sum += d; near_n += 1
	return {"mark_mad":mark_sum/float(maxi(mark_n,1)), "mark_count":mark_n, "nearby_mad":near_sum/float(maxi(near_n,1)), "nearby_count":near_n, "full_mad":full_sum/float(maxi(full_n,1))}

func _pixel_diff(a: Color, b: Color) -> float:
	return (absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3.0

func _image_mad(a: Image, b: Image) -> float:
	var total := 0.0
	for y in H:
		for x in W:
			total += _pixel_diff(a.get_pixel(x,y), b.get_pixel(x,y))
	return total / float(W * H)

func _opaque_count(image: Image) -> int:
	var n := 0
	for y in H:
		for x in W:
			if image.get_pixel(x,y).a > 0.9: n += 1
	return n

func _check_artifacts(before: Image, active: Image, after: Image, replay: Image, metrics: Dictionary, recovery: Dictionary, replay_diff: float) -> void:
	Evidence.save_png(before, out_dir.path_join("vacuum_vs_neutral_before.png"))
	Evidence.save_png(active, out_dir.path_join("vacuum_vs_active_t065.png"))
	Evidence.save_png(after, out_dir.path_join("vacuum_vs_neutral_after.png"))
	Evidence.save_png(replay, out_dir.path_join("vacuum_vs_active_replay.png"))
	Evidence.save_png(mark_alpha, out_dir.path_join("vacuum_vs_mark_alpha.png"))
	Evidence.write_json(out_dir.path_join("vacuum_vs_mark_summary.json"), {"status":"PASS" if failures==0 else "FAIL", "checks":checks, "failures":failures, "windowed":DisplayServer.get_name(), "scene_clock":TIME, "noise_floor_threshold":NOISE_FLOOR, "opaque_alpha_threshold":0.9, "active_metrics":metrics, "neutral_recovery_metrics":recovery, "active_replay_mad":replay_diff, "artifacts":["vacuum_vs_neutral_before.png","vacuum_vs_active_t065.png","vacuum_vs_neutral_after.png","vacuum_vs_active_replay.png","vacuum_vs_mark_alpha.png"]})

func settle(n: int) -> void:
	for i in n: await process_frame

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ",label,"  ",detail)
	else: print("[CHECK] PASS  ",label)
