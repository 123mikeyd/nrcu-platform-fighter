extends SceneTree
# Public session -> disk -> fresh game adapter -> same pixels as Lab renderer.
const Setup = preload("res://tools/fx_review_setup.gd")
const Oracle = preload("res://tests/fx_vnext_pixel_oracle.gd")
const Adapter = preload("res://scripts/vs_presentation_adapter.gd")
var failures := 0
var checks := 0
var cover := 0
var finished := 0
var out_dir: String
var lifecycle: Array = []
const PHASES := [["pre", 0.29], ["vacuum", 0.45], ["impact", 0.81], ["recovery", 1.11]]

func _init() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "": out_dir = ProjectSettings.globalize_path("res://evidence/astra_game_smoke")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data := out_dir.path_join("production_%d" % OS.get_process_id())
	var drafts := out_dir.path_join("drafts_%d" % OS.get_process_id())
	OS.set_environment("NRCU_FX_DATA_DIR", data)
	OS.set_environment("NRCU_FX_DRAFT_DIR", drafts)
	var saved: Dictionary = Setup.seed("CLASH_OVERDRIVE", data, drafts)
	check(saved.get("ok", false), "public session add/apply/reload")
	var doc: Dictionary = saved.get("doc", {})
	check(doc.get("metadata", {}).get("recipe_instances", []).size() == 1, "exactly one persisted instance")
	var prod = Setup.Production.new()
	prod.data_dir = data
	check(prod.load_composition().get("doc", {}) == doc, "fresh Production reads canonical saved document")
	var session = Setup.Session.new(prod, Setup.Drafts.new())
	session.drafts.base_dir = drafts
	var ctx := {"target_key": "composition", "element_id": "composition", "element_role": "composition", "mode_family": "1v1", "stage_id": "debug"}
	session.open_target("composition", ctx, "composition||composition||||1v1|debug", "composition")
	check(session.composition == doc and not session.dirty, "fresh authoring session reopens clean")
	# The UI brackets a continuous gesture with one snapshot; the low-level
	# mutator intentionally does not create a history entry per slider tick.
	session.snapshot()
	var edited: Dictionary = session.edit_recipe_macro("CLASH_OVERDRIVE", "artist_single", "IMPACT", 0.8)
	check(edited.get("ok", false) and edited.get("changed", false), "artist macro mutates own canonical passes")
	var changed: Dictionary = session.composition.duplicate(true)
	check(session.undo() and session.composition == doc, "macro undo exact")
	check(session.redo() and session.composition == changed, "macro redo exact")
	check(session.save_draft().get("ok", false), "macro draft saved independently of Production")
	var reopened = Setup.Session.new(prod, session.drafts)
	reopened.open_target("composition", ctx, "composition||composition||||1v1|debug", "composition")
	# Stash deliberately changes the document status to DRAFT; all artist data
	# and revisions must remain exact (the diagnostic showed status-only drift).
	var draft_expected: Dictionary = changed.duplicate(true)
	draft_expected.status = "DRAFT"
	check(reopened.composition == draft_expected and reopened.dirty, "fresh session restores exact saved macro draft with DRAFT status")
	check(prod.load_composition().doc == doc, "draft save does not change game authority")
	check(session.apply().get("ok", false), "edited artist state saved")
	doc = prod.load_composition().doc
	var canonical = load("res://scripts/fx_vnext/fx_composition.gd")
	var expected: Dictionary = changed.duplicate(true)
	expected.status = "PRODUCTION"
	expected.revision = doc.revision
	check(canonical.materialize(expected) == doc, "saved canonical passes and macro metadata match artist state")
	# Game flow is the real adapter, not FxScreenRuntime.mount or reference scene.
	for cycle in 4:
		await game_cycle(data, doc, "game" if cycle == 0 else ("repeat" if cycle == 1 else ""))
	check(lifecycle[1] == lifecycle[2] and lifecycle[2] == lifecycle[3], "steady repeated entry/exit has no node/object/resource growth")
	var neutral_prod = Setup.Production.new()
	neutral_prod.data_dir = out_dir.path_join("neutral_%d" % OS.get_process_id())
	var neutral: Dictionary = canonical.new_document("neutral", "Neutral comparison")
	neutral.status = "PRODUCTION"
	check(neutral_prod.apply({"composition": neutral}).get("ok", false), "isolated canonical neutral written")
	await game_cycle(neutral_prod.data_dir, neutral_prod.load_composition().doc, "neutral")
	OS.set_environment("NRCU_FX_DATA_DIR", data)
	# Fresh independent Lab composition, no game screen remains to mask it.
	var runtime = load("res://scripts/fx_vnext/fx_screen_runtime.gd").new()
	root.add_child(runtime.subvp)
	check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "fresh Lab renderer mounts independently")
	Oracle.freeze(runtime)
	var renderer = load("res://scripts/fx_vnext/fx_layer_renderer.gd").new(runtime.screen, runtime.registry)
	check(renderer.apply_composition([], {"composition": doc}).get("ok", false), "Lab consumes exact same persisted document")
	for spec in PHASES:
		renderer.set_clocks(float(spec[1]), float(spec[1]))
		await capture(str(spec[0]) + "_lab", runtime.subvp)
	renderer.clear_all()
	runtime.subvp.queue_free()
	await process_frame
	var f := FileAccess.open(out_dir.path_join("game_manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "production": data, "doc": doc, "cover": cover, "finished": finished, "lifecycle": lifecycle, "phases": PHASES, "frozen_source_time": 1.0, "note": "candidate is artist-edited IMPACT=0.8, not artist approved; timeline_* frames use actual presentation times"}, "  "))
	f.close()
	print("[GAME-AUTHORING] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func game_cycle(data: String, doc: Dictionary, label: String) -> void:
	OS.set_environment("NRCU_FX_DATA_DIR", data)
	var before_cover := cover
	var before_finished := finished
	var adapter := Adapter.new()
	root.add_child(adapter)
	adapter.cover_reached.connect(func(): cover += 1)
	adapter.finished.connect(func(): finished += 1)
	check(adapter.begin(Setup.match_config()), "actual game adapter begins typed match")
	var screen = adapter.screen()
	check(not screen.has_meta("fx_preview_no_teardown"), "game screen has no preview lifetime flag")
	var binding = screen.get_node("ProductionFx")
	check(binding.last_summary.get("ok", false), "game loads Production through shared consumer")
	check(binding.runtime.subvp == null, "game does not mount a second screen viewport")
	check(binding.production.load_composition().doc == doc, "game consumes exact artist disk authority")
	Oracle.freeze(binding.runtime)
	if label != "":
		for spec in PHASES:
			binding.renderer.set_clocks(float(spec[1]), float(spec[1]))
			await capture(str(spec[0]) + "_" + label, root)
		for spec in PHASES:
			binding.runtime.seek(float(spec[1]))
			binding.renderer.set_clocks(float(spec[1]), float(spec[1]))
			await capture("timeline_" + str(spec[0]) + "_" + label, root)
	# Teardown through real readiness/cover/reveal, no private _finish call.
	Engine.time_scale = 1.0
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	screen.lab_preview_resume()
	adapter.signal_match_ready()
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(screen) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(screen) and not is_instance_valid(binding), "game screen and FX child teardown")
	check(cover == before_cover + 1 and finished == before_finished + 1, "game cover and exit signals exactly once")
	adapter.queue_free()
	for i in 8: await process_frame
	var sample := {"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}
	lifecycle.append(sample)
	print("[GAME-AUTHORING] lifecycle ", sample)

func capture(label: String, viewport: Viewport) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(out_dir.path_join(label + ".png")) == OK, label + " capture")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[GAME-AUTHORING] %s %s" % ["PASS" if ok else "FAIL", label])
