extends SceneTree
# FINAL_COMPOSITE lane contract and runtime proof.
# The readback section is intentionally small: it only claims pixels after a
# real SubViewport render has produced two captures.

const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxEvidenceScript := preload("res://scripts/fx_vnext/fx_evidence.gd")

var checks := 0
var failures := 0
var host: Control
var runtime
var renderer
var evidence_dir: String = ""
var neutral_readback: Image
var active_readback: Image

func _init() -> void:
	var supplied: String = OS.get_environment("FXLAB_EVIDENCE_DIR")
	evidence_dir = ProjectSettings.globalize_path(supplied) if supplied != "" else ProjectSettings.globalize_path("user://fx_evidence/final_composite")
	_static_contract()
	await _runtime_contract()
	_write_evidence_summary()
	print("[FX-FINAL-COMPOSITE] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _static_contract() -> void:
	_check(FxOperatorsScript.final_composite_supported(), "FINAL_COMPOSITE is supported only with the dedicated shader path")
	var entry: Dictionary = FxOperatorsScript.operator_entry("final_composite")
	_check(bool(entry.get("authoring_reachable", false)), "final_composite authoring flag is truthful")
	_check(bool(entry.get("persistence_proven", false)), "final_composite persistence flag is truthful")
	_check(bool(entry.get("runtime_observable", false)), "final_composite runtime flag is truthful")
	_check(str(entry.get("status", "")) != "UNSUPPORTED", "final_composite registry status is not unsupported")
	var shader_text := _read_text("res://shaders/nrcu_fx_vnext_final_composite.gdshader")
	_check(shader_text.find("hint_screen_texture") >= 0, "final shader samples the BackBufferCopy screen texture")
	_check(shader_text.find("uniform float final_tint_amount") >= 0, "final shader exposes the neutral tint amount")
	_check(shader_text.find("uniform float presentation_time") >= 0, "final shader exposes supplied presentation time")
	_check(FileAccess.file_exists("res://assets/vs/fx/speedlines_noise.png"), "deterministic speedline noise asset is present")
	_check(shader_text.find("scope_mask") >= 0, "final shader exposes semantic role scope mask")
	_check(shader_text.find("scope_factor") >= 0, "final shader gates operator output by semantic scope")
	var raw_time := RegEx.new()
	raw_time.compile("(^|[^A-Z_])TIME([^A-Z_]|$)")
	_check(raw_time.search(shader_text) == null, "final shader never uses raw TIME")

	var final_layer: Dictionary = _final_layer(0.0)
	var accepted: Dictionary = FxOperatorsScript.validate_layer_lane(final_layer)
	_check(bool(accepted.get("ok", false)), "explicit FINAL_COMPOSITE lane is accepted")
	_check(bool(accepted.get("supported", false)), "explicit FINAL_COMPOSITE lane is supported")
	_check(FxOperatorsScript.operator_ids_for_layer(final_layer).has("final_composite"), "final lane reports the final_composite operator")
	for plane in ["COMPOSITION_BACKGROUND"]:
		var forged: Dictionary = final_layer.duplicate(true)
		forged["plane"] = plane
		var rejected: Dictionary = FxOperatorsScript.validate_layer_lane(forged)
		_check(not bool(rejected.get("ok", false)), "%s cannot masquerade as FINAL_COMPOSITE" % plane)
	var explicit_foreground: Dictionary = final_layer.duplicate(true)
	explicit_foreground["plane"] = "COMPOSITION_FOREGROUND"
	_check(bool(FxOperatorsScript.validate_layer_lane(explicit_foreground).get("ok", false)), "COMPOSITION_FOREGROUND is the explicit final ownership plane")

	var doc := FxLookScript.new_look("FINAL_SCHEMA", "Final schema")
	doc["layers"].append(final_layer)
	var materialized: Dictionary = FxLookScript.materialize(doc)
	_check((materialized["layers"][1]["fx"] as Dictionary).has("final_tint_amount"), "FxLook materializes final-composite metadata")
	_check(FxLookScript.field_meta_all().has("final_tint_amount") and FxLookScript.field_meta_all().has("final_tint_color"), "authoring metadata exposes final-composite fields")
	_check(bool(FxLookScript.validate(materialized).get("ok", false)), "schema-compatible explicit final Look validates")

func _runtime_contract() -> void:
	host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "runtime mounts for final-composite proof")
	var stage: Node = runtime.screen.get_node_or_null("Root/Stage")
	if stage is CanvasItem:
		(stage as CanvasItem).modulate.a = 0.0
	var readback_fixture := ColorRect.new()
	readback_fixture.name = "FinalCompositeReadbackFixture"
	readback_fixture.color = Color(0.42, 0.28, 0.18, 1.0)
	readback_fixture.position = Vector2.ZERO
	readback_fixture.size = Vector2(1280, 720)
	# Keep the deterministic fixture behind the product's final-composite anchor;
	# the old z=0 placement covered the final quad and measured a harness-only
	# zero-diff, not the renderer output.
	readback_fixture.z_index = -100
	runtime.screen.get_node("Root").add_child(readback_fixture)
	await _settle(35)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	var neutral: Dictionary = _look("FINAL_NEUTRAL", _final_layer(0.0))
	var neutral_result: Dictionary = renderer.apply_composition([{"key": "composition", "scope": "COMPOSITION", "look": neutral}])
	_check(bool(neutral_result.get("ok", false)), "neutral final composition commits", str(neutral_result.get("errors", [])))
	_check(int(neutral_result.get("final_composite", 0)) == 1, "one explicit final layer produces one final pass")
	var final_node: Node = runtime.screen.get_node_or_null("Root/vnext_final_composite")
	var final_bbc: Node = runtime.screen.get_node_or_null("Root/vnext_final_bbc")
	_check(final_node is ColorRect, "final pass uses a dedicated full-canvas quad")
	_check(final_bbc is BackBufferCopy, "final pass has a dedicated BackBufferCopy")
	if final_node is ColorRect:
		var neutral_mat := (final_node as ColorRect).material as ShaderMaterial
		_check(neutral_mat != null, "final quad has a shader material")
		if neutral_mat != null:
			_check(is_equal_approx(float(neutral_mat.get_shader_parameter("final_tint_amount")), 0.0), "neutral final uniform is zero")
		_check(final_node.get_index() < runtime.screen.get_node("Root/ImpactFlash").get_index(), "final quad is before ImpactFlash")
		_check(final_node.get_index() < runtime.screen.get_node("Root/TransitionCover").get_index(), "final quad is before TransitionCover")
	if final_bbc is BackBufferCopy and final_node is ColorRect:
		_check(final_bbc.get_index() + 1 == final_node.get_index(), "BackBufferCopy immediately precedes final quad")

	renderer.set_clocks(2.5, 9.0)
	if final_node is ColorRect:
		var clock_mat := (final_node as ColorRect).material as ShaderMaterial
		if clock_mat != null:
			_check(is_equal_approx(float(clock_mat.get_shader_parameter("presentation_time")), 2.5), "final quad receives presentation clock")
			_check(is_equal_approx(float(clock_mat.get_shader_parameter("free_run_time")), 9.0), "final quad receives free-run clock")

	var static_only := OS.get_environment("FX_FINAL_STATIC_ONLY") == "1"
	print("[FX-FINAL-COMPOSITE] pixel readback mode: ", "static-only" if static_only else "mandatory")
	# Compatibility's headless DisplayServer cannot complete a synchronous
	# BackBufferCopy texture readback reliably: fail with an actionable result
	# instead of hanging until the outer process timeout. The default acceptance
	# command is therefore windowed; headless is reserved for explicit static
	# contract checks.
	if not static_only and DisplayServer.get_name() == "headless":
		_check(false, "mandatory pixel readback requires a windowed renderer", "use run_godot_suite.py without --headless")
		return
	if not static_only:
		neutral_readback = await _capture()
	var active_fx: Dictionary = _final_layer(1.0)
	(active_fx["fx"] as Dictionary)["operator"] = "speedlines_field"
	(active_fx["fx"] as Dictionary)["operator_strength"] = 1.0
	(active_fx["fx"] as Dictionary)["operator_event_start"] = 0.0
	(active_fx["fx"] as Dictionary)["operator_duration"] = 10.0
	(active_fx["fx"] as Dictionary)["operator_distortion"] = 0.9
	(active_fx["fx"] as Dictionary)["operator_mix_mode"] = 2.0
	(active_fx["fx"] as Dictionary)["operator_color_a"] = [1.0, 0.0, 0.0, 1.0]
	(active_fx["fx"] as Dictionary)["operator_color_b"] = [1.0, 1.0, 0.0, 1.0]
	(active_fx["fx"] as Dictionary)["operator_scope"] = "EXCLUDE_PRIMARY"
	var active_result: Dictionary = renderer.apply_composition([{"key": "composition", "scope": "COMPOSITION", "look": _look("FINAL_ACTIVE", active_fx)}])
	_check(bool(active_result.get("ok", false)), "non-neutral final composition commits", str(active_result.get("errors", [])))
	await _settle(4)
	var active_node: Node = runtime.screen.get_node_or_null("Root/vnext_final_composite")
	if active_node is ColorRect:
		var active_mat := (active_node as ColorRect).material as ShaderMaterial
		if active_mat != null:
			_check(float(active_mat.get_shader_parameter("final_tint_amount")) > 0.0, "non-neutral final uniform is non-zero")
			_check(is_equal_approx(float(active_mat.get_shader_parameter("final_scope_mode")), 3.0), "EXCLUDE_PRIMARY scope reaches the final material")
			_check(active_mat.get_shader_parameter("scope_mask") != null, "EXCLUDE_PRIMARY binds a semantic scope texture")
	if not static_only:
		(active_fx["fx"] as Dictionary)["operator_scope"] = "ALL"
		(active_fx["fx"] as Dictionary)["operator_event_start"] = 0.0
		var active_a_result: Dictionary = renderer.apply_composition([{"key": "composition", "scope": "COMPOSITION", "look": _look("FINAL_SPEEDLINES_A", active_fx)}], {"anchor_target_key": ""})
		_check(bool(active_a_result.get("ok", false)), "speedlines temporal A commits")
		await _settle(3)
		var active_a := await _capture()
		(active_fx["fx"] as Dictionary)["operator_event_start"] = 0.0
		# Supplied clock is set explicitly; no engine TIME or wall-clock enters the comparison.
		renderer.set_clocks(2.0, 2.0)
		var active_a_mat := ((runtime.screen.get_node("Root/vnext_final_composite") as ColorRect).material as ShaderMaterial)
		active_a_mat.set_shader_parameter("presentation_time", 2.0)
		await _settle(3)
		active_a = await _capture()
		active_a_mat.set_shader_parameter("presentation_time", 2.4)
		await _settle(3)
		var active_b := await _capture()
		_check(_mean_abs_diff(active_a, active_b) > 0.00005, "speedline render changes across supplied-clock frames", "mean_abs_diff=%f" % _mean_abs_diff(active_a, active_b))
		var displacement_fx: Dictionary = (active_fx["fx"] as Dictionary).duplicate(true)
		(displacement_fx as Dictionary)["operator_mix_mode"] = 1.0
		var displacement_result: Dictionary = renderer.apply_composition([{"key": "composition", "scope": "COMPOSITION", "look": _look("FINAL_SPEEDLINES_DISPLACE", active_fx)}], {"anchor_target_key": ""})
		_check(bool(displacement_result.get("ok", false)), "lines-off displacement-only composition commits")
		await _settle(3)
		var displacement_mat := ((runtime.screen.get_node("Root/vnext_final_composite") as ColorRect).material as ShaderMaterial)
		displacement_mat.set_shader_parameter("final_operator_mix_mode", 1.0)
		displacement_mat.set_shader_parameter("presentation_time", 2.2)
		await _settle(3)
		var displaced := await _capture()
		displacement_mat.set_shader_parameter("final_operator_distortion", 0.0)
		await _settle(3)
		var lines_only := await _capture()
		var displacement_diff := _mean_abs_diff(displaced, lines_only)
		_check(displacement_diff > 0.00005, "displacement-only readback differs from lines-only control", "mean_abs_diff=%f" % displacement_diff)
		var recovery_mat := displacement_mat
		recovery_mat.set_shader_parameter("final_operator_strength", 0.0)
		recovery_mat.set_shader_parameter("final_operator_distortion", 0.0)
		recovery_mat.set_shader_parameter("final_tint_amount", 0.0)
		recovery_mat.set_shader_parameter("final_operator_mode", 0.0)
		await _settle(3)
		var recovered := await _capture()
		var neutral_control_fx: Dictionary = _final_layer(0.0)
		var neutral_control_result: Dictionary = renderer.apply_composition([{"key": "composition", "scope": "COMPOSITION", "look": _look("FINAL_NEUTRAL_CONTROL", neutral_control_fx)}], {"anchor_target_key": ""})
		_check(bool(neutral_control_result.get("ok", false)), "neutral control composition recommits")
		await _settle(3)
		var neutral_control := await _capture()
		_check(_mean_abs_diff(neutral_control, recovered) < 0.0005, "speedlines recover to neutral control readback floor", "mean_abs_diff=%f" % _mean_abs_diff(neutral_control, recovered))
		active_readback = active_b


	var local_only: Dictionary = _look("FINAL_REMOUNT", null)
	var local_result: Dictionary = renderer.apply_composition([{"key": "echo_left", "look": local_only}])
	_check(bool(local_result.get("ok", false)), "local-only remount still commits")
	_check(runtime.screen.get_node_or_null("Root/vnext_final_composite") == null, "local-only remount removes final quad")
	_check(runtime.screen.get_node_or_null("Root/vnext_final_bbc") == null, "local-only remount removes final BackBufferCopy")
	var no_final: Dictionary = renderer.apply_final_composite([])
	_check(not bool(no_final.get("ok", false)), "direct final pass fails closed without explicit layers")
	var forged_final: Dictionary = _final_layer(1.0)
	forged_final["plane"] = "COMPOSITION_BACKGROUND"
	var forged_result: Dictionary = renderer.apply_final_composite([forged_final])
	_check(not bool(forged_result.get("ok", false)), "direct final pass rejects composition-plane masquerading")

func _write_evidence_summary() -> void:
	var captures: Array[String] = []
	if neutral_readback != null:
		var neutral_path := evidence_dir.path_join("final_composite_neutral.png")
		if FxEvidenceScript.save_png(neutral_readback, neutral_path):
			captures.append(neutral_path)
	if active_readback != null:
		var active_path := evidence_dir.path_join("final_composite_active.png")
		if FxEvidenceScript.save_png(active_readback, active_path):
			captures.append(active_path)
	FxEvidenceScript.write_json(evidence_dir.path_join("final_composite_summary.json"), {
		"status": "PASS" if failures == 0 else "FAIL",
		"checks": checks,
		"failures": failures,
		"presentation_time": 2.5,
		"free_run_time": 9.0,
		"captures": captures,
	})

func _final_layer(amount: float):
	var layer: Dictionary = FxLookScript.new_layer("FX", "Final")
	layer["plane"] = "COMPOSITION_FOREGROUND"
	layer["authority"] = "COMPOSITION"
	layer["lane"] = "FINAL_COMPOSITE"
	(layer["fx"] as Dictionary)["final_tint_amount"] = amount
	return layer

func _look(look_id: String, final_layer):
	var doc: Dictionary = FxLookScript.new_look(look_id, look_id)
	if final_layer != null:
		doc["layers"].append(final_layer)
	return FxLookScript.materialize(doc)

func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return host.get_viewport().get_texture().get_image()

func _max_abs_diff(a: Image, b: Image, rect: Rect2) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var max_diff := 0.0
	var x0 := maxi(int(floor(rect.position.x)), 0)
	var y0 := maxi(int(floor(rect.position.y)), 0)
	var x1 := mini(int(ceil(rect.end.x)), a.get_width())
	var y1 := mini(int(ceil(rect.end.y)), a.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			max_diff = maxf(max_diff, absf(pa.r - pb.r))
			max_diff = maxf(max_diff, absf(pa.g - pb.g))
			max_diff = maxf(max_diff, absf(pa.b - pb.b))
	return max_diff

func _mean_abs_diff_region(a: Image, b: Image, rect: Rect2) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var total := 0.0
	var count := 0
	var x0 := maxi(int(floor(rect.position.x)), 0)
	var y0 := maxi(int(floor(rect.position.y)), 0)
	var x1 := mini(int(ceil(rect.end.x)), a.get_width())
	var y1 := mini(int(ceil(rect.end.y)), a.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 1
	return total / float(maxi(count, 1)) / 3.0

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 1
	return total / float(maxi(count, 1)) / 3.0

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
	else:
		print("[CHECK] PASS  ", label)
