extends SceneTree
# Capture-only acceptance. NumPy gates live in tools/analyze_fx_pixels.py.
# Every pair uses the SAME frozen real VS hierarchy and canonical composition.
const Oracle = preload("res://tests/fx_vnext_pixel_oracle.gd")
const Recipes = preload("res://scripts/fx_vnext/fx_recipes.gd")
var runtime
var renderer
var out_dir: String
var checks := 0
var failures := 0
var records: Array = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir.is_empty(): out_dir = ProjectSettings.globalize_path("res://evidence/astra_artist_pixels")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var container := SubViewportContainer.new()
	container.size = Vector2(1280, 720)
	root.add_child(container)
	runtime = load("res://scripts/fx_vnext/fx_screen_runtime.gd").new()
	container.add_child(runtime.subvp)
	await process_frame
	check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "real portraits mounted")
	Oracle.freeze(runtime)
	await settle()
	(await Oracle.role_alpha(self, runtime, ["primary"])).save_png(out_dir.path_join("primary_oracle.png"))
	(await Oracle.role_alpha(self, runtime, ["echo"])).save_png(out_dir.path_join("echo_oracle.png"))
	renderer = load("res://scripts/fx_vnext/fx_layer_renderer.gd").new(runtime.screen, runtime.registry)
	var clash := composition("CLASH_OVERDRIVE")
	var vacuum := pass_for(clash, "vacuum_burst")
	var speed := pass_for(clash, "speedlines_field")
	check(not vacuum.is_empty() and not speed.is_empty(), "one CLASH instance has both creative passes")
	var vs := float(vacuum.event_start)
	var ve := vs + float(vacuum.duration)
	var ss := float(speed.event_start)
	var se := ss + float(speed.duration)
	check(ss > vs, "vacuum-only interval exists")
	await pair("clash_pre", clash, maxf(0.0, vs - 0.05), "neutral")
	await pair("clash_vacuum", clash, (vs + minf(ve, ss)) * 0.5, "echo")
	await pair("clash_impact", clash, ss + float(speed.duration) * 0.5, "protected")
	await pair("clash_recovery", clash, maxf(ve, se) + 0.05, "neutral")
	for recipe in ["VACUUM_CLASH", "KINETIC_RUSH"]:
		var doc := composition(recipe)
		var p: Dictionary = doc.final_passes[0]
		await pair(recipe.to_lower(), doc, float(p.event_start) + float(p.duration) * 0.5, "echo" if recipe == "VACUUM_CLASH" else "protected")
	# Isolate exactly the signature speed pass. No lines can satisfy distortion.
	var isolated := clash.duplicate(true)
	isolated.final_passes = [speed.duplicate(true)]
	var t := ss + float(speed.duration) * 0.5
	isolated.final_passes[0].fx.operator_mix_mode = 1.0
	await pair("distortion_only", isolated, t, "protected")
	var zero := isolated.duplicate(true)
	zero.final_passes[0].fx.operator_distortion = 0.0
	await pair("distortion_zero", zero, t, "neutral")
	isolated.final_passes[0].fx.operator_mix_mode = 0.0
	await pair("lines_only", isolated, t, "protected")
	await render_capture("lines_static_later", isolated, ss + float(speed.duration) * 0.6)
	var pattern := composition("PATTERN_CUT")
	var pp: Dictionary = pattern.final_passes[0]
	for i in 5:
		await pair("pattern_event_%d" % i, pattern, float(pp.event_start) + float(pp.duration) * float(i) / 4.0, "neutral" if i == 0 or i == 4 else "active")
	# Static progress controls at constant envelope and clock, distinct from the
	# event's recovery envelope. This makes 0/.25/.5/.75/1 an honest control proof.
	var pt := float(pp.event_start) + float(pp.duration) * 0.5
	for i in 5:
		var doc := pattern.duplicate(true)
		doc.final_passes[0].fx.operator_progress_mode = "STATIC"
		doc.final_passes[0].fx.operator_progress = float(i) / 4.0
		await pair("pattern_progress_%d" % i, doc, pt, "neutral" if i == 0 else "active")
	var baseline := pattern.duplicate(true)
	baseline.final_passes[0].fx.operator_progress_mode = "STATIC"
	baseline.final_passes[0].fx.operator_progress = 0.5
	for spec in [["direction", "operator_axis_x", -1.0], ["shape", "operator_pattern_family", 2.0], ["scale", "operator_scale", 2.7], ["feather", "operator_softness", 0.35], ["motion", "operator_speed", 3.0]]:
		var variant := baseline.duplicate(true)
		variant.final_passes[0].fx[spec[1]] = spec[2]
		await pair("pattern_control_" + str(spec[0]), variant, pt, "active")
	var file := FileAccess.open(out_dir.path_join("artist_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records, "event_marks": runtime.event_marks(), "frozen_scene_time": 1.0, "clash": clash, "pattern": pattern}, "  "))
	file.close()
	renderer.clear_all()
	print("[ARTIST-CAPTURE] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func composition(id: String) -> Dictionary:
	var made: Dictionary = Recipes.instantiate_composition(id, "artist_single")
	check(made.get("ok", false), id + " canonical single instance")
	return made.get("doc", {})

func pass_for(doc: Dictionary, op: String) -> Dictionary:
	for p in doc.final_passes:
		if p.operator == op: return p
	return {}

func pair(label: String, doc: Dictionary, t: float, expected: String) -> void:
	var neutral := doc.duplicate(true)
	neutral.final_passes = []
	await render_capture(label + "_neutral", neutral, t)
	await render_capture(label + "_repeat", neutral, t)
	await render_capture(label + "_active", doc, t)
	records.append({"label": label, "time": t, "expected": expected, "clock": "PRESENTATION_TIME", "passes": doc.final_passes})

func render_capture(label: String, doc: Dictionary, t: float) -> void:
	check(renderer.apply_composition([], {"composition": doc}).get("ok", false), label + " apply")
	renderer.set_clocks(t, t)
	await settle()
	await RenderingServer.frame_post_draw
	check(runtime.subvp.get_texture().get_image().save_png(out_dir.path_join(label + ".png")) == OK, label + " saved")

func settle() -> void:
	for i in 6: await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[ARTIST-CAPTURE] %s %s" % ["PASS" if ok else "FAIL", label])
