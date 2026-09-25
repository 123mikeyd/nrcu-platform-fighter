extends SceneTree

const Recipes = preload("res://scripts/fx_vnext/fx_recipes.gd")
const Runtime = preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const Renderer = preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const Oracle = preload("res://tests/fx_vnext_pixel_oracle.gd")

const HISTORICAL_THRESHOLD := 0.0005
const W := 1280
const H := 720

var out_dir := ""
var host: Control
var runtime
var renderer
var failures := 0
var captures: Dictionary = {}
var records: Array = []
var current_envelope: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "": out_dir = ProjectSettings.globalize_path("res://evidence/runtime_visual_20260921")
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
	if not runtime.mount("1v1", "debug", "ice_mage", "doge_man"): fail("runtime mount")
	await settle(40)
	# Freeze the VS timeline: neutral and active captures are taken at different
	# wall-clock moments, and the screen itself animates (living side-field
	# edges breathe through HOLD). This test measures FX passes only.
	Oracle.freeze(runtime)
	await settle(6)
	renderer = Renderer.new(runtime.screen, runtime.registry)
	renderer.set_clocks(0.0, 0.0)

	await run_recipe("CLASH_OVERDRIVE", "clash")
	await run_recipe("PATTERN_CUT", "pattern")
	await run_isolated("VACUUM_CLASH", "vacuum", "vacuum_burst")
	await run_isolated("KINETIC_RUSH", "speedline", "speedlines_field")
	await write_contact_sheet()
	var floor_a: Image = await capture("neutral_floor_a")
	await settle(2)
	var floor_b: Image = await capture("neutral_floor_b")
	var floor_mad := image_mad(floor_a, floor_b)
	if floor_mad > HISTORICAL_THRESHOLD: fail("identical-neutral noise floor %.8f exceeds %.4f" % [floor_mad, HISTORICAL_THRESHOLD])

	var summary := {
		"status": "PASS" if failures == 0 else "FAIL",
		"failures": failures,
		"threshold_historical": HISTORICAL_THRESHOLD,
		"clock": "PRESENTATION_TIME",
		"records": records,
		"neutral_floor_mad": floor_mad,
		"contact_sheet": "contact_sheet.png"
	}
	var f := FileAccess.open(out_dir.path_join("runtime_visual_summary.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("[FX-RUNTIME-VISUAL] phase-aware done · checks=%d failures=%d" % [records.size(), failures])
	quit(1 if failures else 0)

func run_recipe(recipe_id: String, label: String) -> void:
	var made: Dictionary = Recipes.instantiate_look(recipe_id, "EVIDENCE_" + recipe_id, recipe_id, "evidence")
	if not made.get("ok", false): fail("instantiate %s" % recipe_id); return
	var comp: Dictionary = made.get("composition", {}).get("doc", {})
	if comp.is_empty(): fail("empty composition %s" % recipe_id); return
	comp["status"] = "PRODUCTION"
	var passes: Array = comp.get("final_passes", [])
	var envelope := pass_envelope(passes)
	if envelope.is_empty(): fail("no canonical pass envelope %s" % recipe_id); return
	current_envelope = envelope
	var active := await apply_comp(comp)
	if not active: return
	var neutral := comp.duplicate(true)
	neutral["final_passes"] = []
	var neutral_ok := await apply_comp(neutral)
	if not neutral_ok: return
	# Restore the exact same active composition after preparing the neutral frame.
	if not await apply_comp(comp): return
	if recipe_id == "CLASH_OVERDRIVE":
		await capture_pair(label, "pre", envelope["pre"], comp, neutral)
		await capture_pair(label, "vacuum_peak", envelope["vacuum_peak"], comp, neutral)
		await capture_pair(label, "impact_peak", envelope["impact_peak"], comp, neutral)
		await capture_pair(label, "recovery", envelope["recovery"], comp, neutral)
	else:
		for i in 5:
			var p := float(i) / 4.0
			await capture_pair(label, "progress_%02d" % i, envelope["start"] + envelope["duration"] * p, comp, neutral)
		var progression_hits := 0
		for rec in records:
			if rec.get("label") == label and str(rec.get("phase", "")).begins_with("progress_") and float(rec.get("mad", 0.0)) > HISTORICAL_THRESHOLD: progression_hits += 1
		if progression_hits < 3: fail("pattern progression has only %d non-neutral samples" % progression_hits)

func run_isolated(recipe_id: String, label: String, operator: String) -> void:
	var made: Dictionary = Recipes.instantiate_look(recipe_id, "EVIDENCE_" + recipe_id, recipe_id, "evidence")
	if not made.get("ok", false): fail("instantiate %s" % recipe_id); return
	var comp: Dictionary = made.get("composition", {}).get("doc", {})
	var passes: Array = comp.get("final_passes", [])
	var kept: Array = []
	for p in passes:
		if str(p.get("operator", p.get("fx", {}).get("operator", ""))) == operator: kept.append(p)
	if kept.is_empty(): fail("isolated %s pass missing" % operator); return
	comp["final_passes"] = kept
	var envelope := pass_envelope(kept)
	if envelope.is_empty(): fail("isolated %s envelope missing" % operator); return
	current_envelope = envelope
	if not await apply_comp(comp): return
	var neutral := comp.duplicate(true); neutral["final_passes"] = []
	if not await apply_comp(neutral): return
	if not await apply_comp(comp): return
	await capture_pair(label, "active", envelope["peak"], comp, neutral)

func capture_pair(label: String, phase: String, t: float, active_comp: Dictionary, neutral_comp: Dictionary) -> void:
	renderer.set_clocks(t, t)
	await settle(3)
	var neutral_img: Image = await capture_neutral(label + "_" + phase + "_neutral", neutral_comp, t)
	if not await apply_comp(active_comp): return
	renderer.set_clocks(t, t)
	await settle(3)
	var active_img: Image = await capture(label + "_" + phase + "_active")
	var mad := image_mad(active_img, neutral_img)
	var changed := changed_pixels(active_img, neutral_img, 0.01)
	var rec := {"label": label, "phase": phase, "time": t, "clock": "PRESENTATION_TIME", "progress": clampf((t - float(current_envelope.get("start", 0.0))) / maxf(float(current_envelope.get("duration", 0.5)), 0.001), 0.0, 1.0), "pass_envelope": current_envelope.duplicate(true), "mad": mad, "changed_pixels_gt_1pct": changed, "alpha_active": alpha_stats(active_img)}
	records.append(rec)
	if phase != "pre" and phase != "recovery" and phase != "progress_00" and phase != "progress_04" and mad <= HISTORICAL_THRESHOLD:
		fail("neutral output at active phase %s/%s time=%.4f mad=%.8f" % [label, phase, t, mad])
	if phase == "recovery" and mad > HISTORICAL_THRESHOLD:
		fail("recovery not neutral %s mad=%.8f" % [label, mad])
	if active_img == null or neutral_img == null: fail("missing paired image %s/%s" % [label, phase])

func capture_neutral(name: String, comp: Dictionary, t: float) -> Image:
	if not await apply_comp(comp): return null
	renderer.set_clocks(t, t)
	await settle(3)
	return await capture(name)

func apply_comp(comp: Dictionary) -> bool:
	var r: Dictionary = renderer.apply_composition([], {"composition": comp, "anchor_target_key": "primary_left", "single_target": false})
	if not r.get("ok", false): fail("apply composition: %s" % str(r.get("errors", []))); return false
	await settle(2)
	return true

func pass_envelope(passes: Array) -> Dictionary:
	var start := INF
	var finish := -INF
	var peak_start := INF
	var peak_end := -INF
	var vacuum := {}
	var speed := {}
	for raw in passes:
		var p: Dictionary = raw
		var s := float(p.get("event_start", 0.0))
		var d := maxf(float(p.get("duration", 0.0)), 0.0)
		var e := s + d
		if d <= 0.0: continue
		start = minf(start, s); finish = maxf(finish, e)
		var op := str(p.get("operator", p.get("fx", {}).get("operator", "")))
		if op == "vacuum_burst": vacuum = {"start": s, "end": e}
		if op == "speedlines_field": speed = {"start": s, "end": e}
	if start == INF: return {}
	# The impact sample belongs inside the speedline burst, not at the
	# zero-progress boundary where anticipation ends. Keep the vacuum midpoint
	# as its own sample and use the speed envelope for the impact midpoint.
	if not speed.is_empty():
		peak_start = float(speed.start); peak_end = float(speed.end)
	elif not vacuum.is_empty():
		peak_start = float(vacuum.start); peak_end = float(vacuum.end)
	if peak_start == INF: peak_start = start; peak_end = finish
	var peak := (peak_start + peak_end) * 0.5
	return {"start": start, "duration": finish - start, "pre": maxf(0.0, start - 0.05), "vacuum_peak": (float(vacuum.start) + float(vacuum.end)) * 0.5 if not vacuum.is_empty() else peak, "impact_peak": peak, "peak": peak, "recovery": finish + 0.05}

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = host.get_viewport().get_texture().get_image()
	if img == null: return null
	img.save_png(out_dir.path_join(name + ".png"))
	captures[name] = img
	return img

func image_mad(a: Image, b: Image) -> float:
	if a == null or b == null: return 1.0
	var total := 0.0
	for y in H:
		for x in W:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(W * H * 3)

func changed_pixels(a: Image, b: Image, threshold: float) -> int:
	if a == null or b == null: return 0
	var n := 0
	for y in H:
		for x in W:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > threshold or absf(ca.g - cb.g) > threshold or absf(ca.b - cb.b) > threshold: n += 1
	return n

func alpha_stats(img: Image) -> Dictionary:
	if img == null: return {"nonzero": 0, "mean": 0.0}
	var n := 0; var total := 0.0
	for y in H:
		for x in W:
			var a := img.get_pixel(x, y).a; total += a; n += 1 if a > 0.001 else 0
	return {"nonzero": n, "mean": total / float(W * H)}

func write_contact_sheet() -> void:
	var names: Array = captures.keys()
	if names.is_empty(): return
	var sheet := Image.create(640, 360 * int(ceil(float(names.size()) / 2.0)) / 2, false, Image.FORMAT_RGBA8)
	var i := 0
	for name in names:
		var img: Image = captures[name]
		img.resize(640, 360)
		sheet.blit_rect(img, Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
		i += 1
	sheet.save_png(out_dir.path_join("contact_sheet.png"))

func settle(n: int) -> void:
	for i in n: await process_frame

func fail(message: String) -> void:
	failures += 1
	push_error("[FX-RUNTIME-VISUAL] " + message)
