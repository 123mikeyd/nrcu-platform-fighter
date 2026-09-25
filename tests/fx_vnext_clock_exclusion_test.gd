extends SceneTree
# Clock-exclusion acceptance: the selected operator clock may affect the
# frame, while the other supplied clock must be observationally irrelevant.

const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const Oracle := preload("res://tests/fx_vnext_pixel_oracle.gd")

var host_root: Node
var runtime
var renderer
var checks := 0
var failures := 0

func _init() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	host_root = Node.new()
	host_root.name = "ClockExclusionHost"
	root.add_child(host_root)
	host_root.add_child(host)
	var container := SubViewportContainer.new()
	container.size = Vector2(1280, 720)
	container.stretch = false
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "clock harness mounts")
	# Freeze the real source, including shader TIME, with the shared independent
	# oracle. Keep the actual primary/echo hierarchy: hiding it makes ECHO_ONLY
	# empty, and a uniform rectangle cannot reveal spatial distortion.
	Oracle.freeze(runtime)
	await settle(6)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	await _probe_final(FxRecipesScript.KINETIC_RUSH, "speedlines_field")
	await _probe_final(FxRecipesScript.PATTERN_CUT, "pattern_transition")
	await _probe_final(FxRecipesScript.VACUUM_CLASH, "vacuum_burst")
	await _probe_local(FxRecipesScript.LIVING_CONTOUR, "primary_left", "noise_erosion_border")
	await _probe_local(FxRecipesScript.SIGNAL_MELT, "echo_left", "pixel_sort_smear")
	renderer.clear_all()
	runtime.free_screen()
	if host_root != null and is_instance_valid(host_root):
		host_root.free()
	print("[FX-CLOCK-EXCLUSION] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _probe_final(recipe_id: String, operator_id: String) -> void:
	var source: Dictionary = FxRecipesScript.instantiate_composition(recipe_id, "clock-exclusion").get("doc", {})
	# Derive probes from the canonical event interval. Historical .2/1.2 are
	# both neutral for the current vacuum and speedline defaults.
	var active := 0.0
	var inactive := 0.0
	for p in source.final_passes:
		if p.operator == operator_id:
			active = float(p.event_start) + float(p.duration) * 0.5
			inactive = float(p.event_start) + float(p.duration) + 0.2
	var presentation_doc := source.duplicate(true)
	_set_composition_clock(presentation_doc, operator_id, "PRESENTATION_TIME")
	var applied: Dictionary = renderer.apply_composition([], {"composition": presentation_doc})
	_check(bool(applied.get("ok", false)), "%s PRESENTATION_TIME applies" % operator_id, str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var p_base: Image = await _frame_at(inactive, inactive)
	var p_unused: Image = await _frame_at(inactive, active)
	var p_active: Image = await _frame_at(active, inactive)
	_check(p_base.get_data() == p_unused.get_data(), "%s ignores FREE_RUN in PRESENTATION_TIME" % operator_id)
	_check(p_base.get_data() != p_active.get_data(), "%s responds to PRESENTATION_TIME" % operator_id)
	var free_doc := source.duplicate(true)
	_set_composition_clock(free_doc, operator_id, "FREE_RUN")
	applied = renderer.apply_composition([], {"composition": free_doc})
	_check(bool(applied.get("ok", false)), "%s FREE_RUN applies" % operator_id, str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var final_material: ShaderMaterial = ((renderer._final_composite.get("passes", [])[0] as Dictionary).get("node") as Control).material
	print("[CLOCK-DEBUG] final operator=%s source=%s time_source=%s" % [operator_id, str(final_material.get_shader_parameter("final_time_source")), str(final_material.get_shader_parameter("presentation_time"))])
	var f_base: Image = await _frame_at(inactive, inactive)
	var f_unused: Image = await _frame_at(active, inactive)
	var f_active: Image = await _frame_at(inactive, active)
	_check(f_base.get_data() == f_unused.get_data(), "%s ignores PRESENTATION_TIME in FREE_RUN" % operator_id)
	_check(f_base.get_data() != f_active.get_data(), "%s responds to FREE_RUN" % operator_id)

func _probe_local(recipe_id: String, target_key: String, operator_id: String) -> void:
	var source: Dictionary = FxRecipesScript.instantiate_look(recipe_id, "clock-exclusion", "Clock Exclusion", "clock-exclusion").get("look", {})
	var presentation_doc := source.duplicate(true)
	_set_local_clock(presentation_doc, operator_id, "PRESENTATION_TIME")
	var applied: Dictionary = renderer.apply_composition([{"key": target_key, "look": presentation_doc}])
	_check(bool(applied.get("ok", false)), "%s local PRESENTATION_TIME applies" % operator_id, str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var local_quad: Dictionary = renderer.stack_quads(target_key)[0]
	var local_material: ShaderMaterial = (local_quad.get("node") as Control).material
	print("[CLOCK-DEBUG] local operator=%s mode=%s time_source=%s gold_source=%s" % [operator_id, str(local_material.get_shader_parameter("gold_operator_mode")), str(local_material.get_shader_parameter("fx_time_source")), str(local_material.get_shader_parameter("gold_operator_time_source"))])
	var p_base: Image = await _frame_at(0.2, 0.2)
	var p_unused: Image = await _frame_at(0.2, 1.2)
	var p_active: Image = await _frame_at(1.2, 0.2)
	_check(p_base.get_data() == p_unused.get_data(), "%s local ignores FREE_RUN in PRESENTATION_TIME" % operator_id)
	_check(p_base.get_data() != p_active.get_data(), "%s local responds to PRESENTATION_TIME" % operator_id)
	var free_doc := source.duplicate(true)
	_set_local_clock(free_doc, operator_id, "FREE_RUN")
	applied = renderer.apply_composition([{"key": target_key, "look": free_doc}])
	_check(bool(applied.get("ok", false)), "%s local FREE_RUN applies" % operator_id, str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var f_base: Image = await _frame_at(0.2, 0.2)
	var f_unused: Image = await _frame_at(1.2, 0.2)
	var f_active: Image = await _frame_at(0.2, 1.2)
	_check(f_base.get_data() == f_unused.get_data(), "%s local ignores PRESENTATION_TIME in FREE_RUN" % operator_id)
	_check(f_base.get_data() != f_active.get_data(), "%s local responds to FREE_RUN" % operator_id)


func _set_composition_clock(doc: Dictionary, operator_id: String, source: String) -> void:
	for raw_pass in doc.get("final_passes", []):
		var pass_doc: Dictionary = raw_pass
		if str(pass_doc.get("operator", "")) == operator_id:
			(pass_doc.get("fx", {}) as Dictionary)["operator_time_source"] = source
			(pass_doc.get("fx", {}) as Dictionary)["time_source"] = source

func _set_local_clock(doc: Dictionary, operator_id: String, source: String) -> void:
	for raw_layer in doc.get("layers", []):
		var layer: Dictionary = raw_layer
		var fx: Dictionary = layer.get("fx", {})
		if str(fx.get("operator", "")) == operator_id:
			fx["operator_time_source"] = source
			fx["time_source"] = source
			layer["fx"] = fx

func _frame_at(presentation: float, free_run: float) -> Image:
	renderer.set_clocks(presentation, free_run)
	await settle(3)
	await RenderingServer.frame_post_draw
	return runtime.subvp.get_texture().get_image()

func settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
