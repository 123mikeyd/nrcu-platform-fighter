extends Control
# NRCU FX Lab vNEXT — REFERENCE production-consumer scene (Round-2 Finding 1).
#
# Lifecycle label: PREVIEW / REFERENCE consumption path. This scene mounts
# its screen with fx_preview_no_teardown, so seeks past minimum_exposure
# freeze on deterministic frames instead of tearing the composition down.
# It is NOT evidence for game MatchFlow teardown: the game path leaves the
# flag unset and vs_screen frees itself on FINISHED (see _finish).
# Use fx_vnext_preview_lifetime_test for the explicit contract split.
#
# This is the reference consumption path: it mounts the canonical vs_screen,
# loads Production authority from disk (res://nrcu_fx_data or NRCU_FX_DATA_DIR),
# resolves EVERY visible target through the SHARED resolver and renders the
# whole composition through the SAME shared composition renderer as the Lab.
# No editor state, no session, no second renderer.
#
# Scene: res://scenes/nrcu_vs_runtime.tscn (main-free; used by the runtime check
# and as the reference for downstream game integration).

const ScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var runtime
var renderer
var production
var container: SubViewportContainer
var last_summary: Dictionary = {}
var _free_tick := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	production = FxProductionScript.new()
	var data_override := OS.get_environment("NRCU_FX_DATA_DIR")
	if data_override != "":
		production.data_dir = data_override
	production.recover_if_needed()  # R3 §8: strict last-known-good crash recovery at boot
	container = SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	runtime = ScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	var format := OS.get_environment("NRCU_VS_FORMAT")
	if format == "":
		format = "1v1"
	var stage := OS.get_environment("NRCU_VS_STAGE")
	if stage == "":
		stage = "debug"
	runtime.mount(format, stage, "ice_mage", "doge_man")
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	# P0: the reference runtime consumes the SAME event authority as the lab —
	# an anchor name means the same presentation time on every path.
	renderer.set_event_marks(runtime.event_marks())
	var seek_target := 1.5
	var seek_env := OS.get_environment("NRCU_VS_SEEK")
	if seek_env != "":
		seek_target = float(seek_env)
	seek(seek_target)
	reload_production()
	_free_tick = OS.get_environment("NRCU_VS_FREERUN") == "1"

func seek(t: float) -> void:
	runtime.seek(t)
	renderer.set_time(t)

func _process(_delta: float) -> void:
	# RT-03: the reference runtime proves live animation — presentation time
	# follows the canonical screen clock every frame while playing, exactly
	# like the lab shell. FREE_RUN stays separate and opt-in.
	if _free_tick and renderer != null:
		renderer.set_free_run(Time.get_ticks_msec() / 1000.0)
	if renderer != null and runtime != null and runtime.screen != null:
		var playing := true
		if runtime.screen.has_method("lab_preview_is_paused"):
			playing = not bool(runtime.screen.lab_preview_is_paused())
		if playing:
			renderer.set_time(maxf(runtime.elapsed(), 0.0))

func reload_production() -> Dictionary:
	# Resolve every registered target through the shared authority and render the
	# whole composition in ONE pass (canonical global order).
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		last_summary = {"ok": false, "errors": assignments.get("errors", [])}
		renderer.clear_all()
		return last_summary
	var doc: Dictionary = assignments["doc"]
	var plan: Array = []
	var skipped: Array = []
	var review_skipped: Array = []
	var plan_ids: Array = []
	# SP-06: iterate visual authority order, not lexicographic keys.
	var ordered: Array = runtime.registry.ordered_keys() if runtime.registry.has_method("ordered_keys") else runtime.registry.keys()
	for key in ordered:
		var key_str := str(key)
		var ctx: Dictionary = runtime.registry.context_for_key(key_str)
		var res: Dictionary = FxResolverScript.resolve(doc, ctx)
		if str(res.get("status", "")) not in ["ASSIGNED", "AMBIGUOUS"]:
			continue
		var look_id := str(res.get("look_id", ""))
		var loaded: Dictionary = production.load_look(look_id)
		if not bool(loaded.get("ok", false)):
			skipped.append(look_id)
			continue
		if str((loaded["doc"] as Dictionary).get("status", "")) != "PRODUCTION":
			review_skipped.append(look_id)
			continue
		plan.append({"key": key_str, "look": loaded["doc"]})
		plan_ids.append("%s:%s:r%d" % [key_str, look_id, int((loaded["doc"] as Dictionary).get("revision", 0))])
	var render_options: Dictionary = {}
	var active_composition: Dictionary = production.load_composition()
	if bool(active_composition.get("ok", false)) and not (active_composition.get("doc", {}) as Dictionary).is_empty():
		render_options["composition"] = active_composition["doc"]
		plan_ids.append("composition:%s:r%d" % [str((active_composition["doc"] as Dictionary).get("composition_id", "active")), int((active_composition["doc"] as Dictionary).get("revision", 0))])
	elif runtime.registry.has_method("composition_context"):
		var composition_result: Dictionary = FxResolverScript.resolve(doc, runtime.registry.composition_context())
		if str(composition_result.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
			var composition_look_id := str(composition_result.get("look_id", ""))
			var composition_loaded: Dictionary = production.load_look(composition_look_id)
			if bool(composition_loaded.get("ok", false)) and str((composition_loaded["doc"] as Dictionary).get("status", "")) == "PRODUCTION":
				plan.append({"key": "composition", "scope": "COMPOSITION", "look": composition_loaded["doc"]})
				plan_ids.append("composition:%s:r%d" % [composition_look_id, int((composition_loaded["doc"] as Dictionary).get("revision", 0))])
	var applied: Dictionary = renderer.apply_composition(plan, render_options)
	# P0: freshly committed stacks inherit the current canonical event table
	# (remount/reload can never silently drop back to fixed-anchor fallback).
	renderer.set_event_marks(runtime.event_marks())
	# RT-03 acceptance 8: a reload never rewinds the running clock — freshly
	# committed stacks inherit the current canonical time immediately.
	if bool(applied.get("ok", false)) and runtime != null and runtime.has_method("elapsed"):
		renderer.set_time(maxf(runtime.elapsed(), 0.0))
	# RT-01: a missing effective Look is a broken authority, never ok=true.
	# Review-withheld looks are intentionally excluded by design and stay
	# informational (review_skipped) rather than failing the composition.
	var missing: Array = skipped
	last_summary = {
		"plan_ids": plan_ids,
		"ok": bool(applied.get("ok", false)) and missing.is_empty(),
		"styled_targets": plan.size(),
		"missing_looks": skipped,
		"review_skipped": review_skipped,
		"errors": applied.get("errors", []),
	}
	return last_summary
