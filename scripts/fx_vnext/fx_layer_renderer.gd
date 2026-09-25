class_name FxLayerRenderer
extends RefCounted

const DEFAULT_OPERATOR_COLOR_A := Color(0.25, 0.95, 1.0, 1.0)
const DEFAULT_OPERATOR_COLOR_B := Color(1.0, 0.35, 0.82, 1.0)
# NRCU FX Lab vNext — layer renderer (Stream C core).
#
# Renders a Look's layer stack for one target inside a mounted VS screen:
# every enabled layer becomes a full-frame presentation quad driven by the
# shared vNext layer shader (TRANSFORM -> DISPLACE -> FX -> MASK -> OPACITY).
# The canonical screen node is hidden while a stack is active; quads are
# inserted at plane-anchored positions around the canonical slot.
#
# Shared between Lab and game runtime: the same module renders in both.
# INPUT semantics: ORIGINAL_SOURCE / TRANSFORMED_SOURCE sample the canonical
# source texture; LAYER_BELOW / COMPOSITE_BELOW render the lower local layer(s)
# into a per-target offscreen stage that the consumer samples 1:1 in canvas
# space. v1 constraints (fail loudly, tracked): at most one offscreen consumer
# per target and no nested offscreen inputs. Non-NORMAL blends are reported as
# unsupported until the blend unit lands.

const SHADER_PATH := "res://shaders/nrcu_fx_vnext_layer.gdshader"
const FINAL_SHADER_PATH := "res://shaders/nrcu_fx_vnext_final_composite.gdshader"
const SPEEDLINES_NOISE_PATH := "res://assets/vs/fx/speedlines_noise.png"
const CANVAS := Vector2(1280.0, 720.0)
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")
const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")

const OFFSET_INPUTS := ["LAYER_BELOW", "COMPOSITE_BELOW"]
const SUPPORTED_INPUTS := ["ORIGINAL_SOURCE", "TRANSFORMED_SOURCE", "LAYER_BELOW", "COMPOSITE_BELOW"]
const SUPPORTED_BLENDS := ["NORMAL", "ADD", "SCREEN", "MULTIPLY"]
const BLEND_INDEX := {"NORMAL": 0, "ADD": 1, "SCREEN": 2, "MULTIPLY": 3}

var screen: Node
var registry
var _shader: Shader
var _final_shader: Shader
var _stacks: Dictionary = {}
var _final_composite: Dictionary = {}
var _last_time: float = 0.0
var _last_free: float = 0.0

func _init(screen_ref: Node, registry_ref) -> void:
	screen = screen_ref
	registry = registry_ref
	_shader = load(SHADER_PATH)
	_final_shader = load(FINAL_SHADER_PATH)

# ---------------------------------------------------------------- public API

func apply_look(target_key: String, look: Dictionary) -> Dictionary:
	# Keep the single-target API on the same deterministic composition path so a
	# final layer can never be mistaken for a target-local plane.
	return apply_composition([{"key": target_key, "look": look}], {"single_target": true})

func final_composite_supported() -> bool:
	# Explicit capability query: callers must not infer final-frame support from
	# COMPOSITION_BACKGROUND/FOREGROUND planes.
	return FxOperatorsScript.final_composite_supported() and _final_shader != null

func final_composite_status() -> Dictionary:
	var supported := final_composite_supported()
	return {
		"lane": "FINAL_COMPOSITE",
		"supported": supported,
		"ok": false,
		"errors": ["FINAL_COMPOSITE unsupported: dedicated full-canvas shader path is unavailable"] if not supported else ["FINAL_COMPOSITE requires an explicit layer"],
	}

func apply_final_composite(plan: Array, options := {}) -> Dictionary:
	# This public entry is intentionally strict: a final pass can never be
	# inferred from a target-local plane or installed without an explicit layer.
	var final_layers: Array = []
	for raw in plan:
		if raw is Dictionary:
			var layer: Dictionary = raw
			if str(layer.get("lane", "")) == "FINAL_COMPOSITE":
				final_layers.append(layer)
	if final_layers.is_empty():
		return final_composite_status()
	var built := _build_final_entry(final_layers, options)
	if not bool(built.get("ok", false)):
		return {"ok": false, "lane": "FINAL_COMPOSITE", "errors": built.get("errors", [])}
	clear_final_composite()
	var root := screen.get_node_or_null("Root") if screen != null else null
	if root == null or not _attach_final_entry(root, built["entry"], str(options.get("inject_failure", ""))):
		_cleanup_final_entry(built.get("entry", {}))
		return {"ok": false, "lane": "FINAL_COMPOSITE", "errors": ["FINAL_COMPOSITE setup failed"]}
	_final_composite = built["entry"]
	_push_final_time()
	return {"ok": true, "lane": "FINAL_COMPOSITE", "errors": [], "final_composite": final_layers.size(), "final_layers": final_layers.size()}

func apply_composition(plan: Array, options := {}) -> Dictionary:
	# ONE pass for the whole visible composition (Round-2 Finding 1). plan is a
	# list of {key, look}; the GLOBAL order is canonical regardless of the order
	# of entries in the plan or the order of apply calls:
	#   canonical base -> target-local planes in canonical target order -> ALL
	#   composition-background layers -> ALL composition-foreground layers ->
	#   cover/UI. Composition planes remain target-texture scoped; their global
	#   groups are resolved deterministically regardless of plan order.
	var errors: Array = []
	# RT-02: build EVERYTHING before touching the live tree. clear_all() used
	# to run first, so one invalid target committed a partial mixed frame.
	# Now a failed build cleans up detached nodes and tears down the live
	# composition before returning. A rejected apply must never leave a stale
	# stack mounted or hide the canonical target behind a half-built frame.
	var root := screen.get_node_or_null("Root")
	if root == null:
		return {"ok": false, "errors": ["screen Root missing"], "targets": 0}
	if registry == null:
		return {"ok": false, "errors": ["registry missing"], "targets": 0}

	var canonical_keys: Array = []
	if registry.has_method("ordered_keys"):
		canonical_keys = registry.ordered_keys()
	else:
		for key in registry.keys():
			canonical_keys.append(str(key))
	var by_key: Dictionary = {}
	var composition_looks: Array = []
	var explicit_composition: Dictionary = options.get("composition", {}) if options.get("composition", {}) is Dictionary else {}
	var inject_failure := str(options.get("inject_failure", ""))
	for entry_raw in plan:
		if entry_raw is Dictionary:
			var entry: Dictionary = entry_raw
			var key := str(entry.get("key", ""))
			var scope := str(entry.get("scope", ""))
			if scope == "COMPOSITION" or key in ["composition", "__composition__"]:
				composition_looks.append(entry.get("look", {}))
			else:
				by_key[key] = entry.get("look", {})

	var stacks: Array = []
	for key in canonical_keys:
		if not by_key.has(key):
			continue
		var stack := _construct_stack(key, by_key[key])
		if inject_failure == "target_stack_build" and stacks.is_empty():
			_cleanup_stack(stack.get("entry", {}))
			errors.append("injected failure: target stack build")
			break
		if not bool(stack.get("ok", false)):
			errors.append_array(stack.get("errors", []))
			_cleanup_stack(stack.get("entry", {}))
			continue
		stacks.append(stack)
	if not errors.is_empty():
		for stack in stacks:
			_cleanup_stack((stack as Dictionary).get("entry", {}))
		return {"ok": false, "targets": 0, "background": 0, "foreground": 0, "errors": errors, "rolled_back": true}
	var final_layers := _collect_final_layers(stacks)
	if not explicit_composition.is_empty():
		var composition_check := FxCompositionScript.validate(explicit_composition)
		if not bool(composition_check.get("ok", false)):
			errors.append_array(composition_check.get("errors", []))
		elif not final_layers.is_empty():
			errors.append("mixed FINAL_COMPOSITE ownership: explicit composition cannot coexist with target-owned final layers")
		else:
			final_layers = FxCompositionScript.to_layers(composition_check.get("doc", explicit_composition))
	for raw_look in composition_looks:
		var composition_look: Dictionary = FxLookScript.materialize(raw_look if raw_look is Dictionary else {})
		var look_validation := FxLookScript.validate_input(composition_look)
		if not bool(look_validation.get("ok", false)):
			errors.append_array(look_validation.get("errors", []))
			continue
		for raw_layer in composition_look.get("layers", []):
			if not (raw_layer is Dictionary) or not bool((raw_layer as Dictionary).get("enabled", true)):
				continue
			var layer: Dictionary = raw_layer
			var lane := FxOperatorsScript.lane_for_layer(layer)
			if str(layer.get("type", "")) == "SOURCE":
				continue
			if lane != "FINAL_COMPOSITE" or str(layer.get("authority", "")) != "COMPOSITION":
				errors.append("composition authority only accepts COMPOSITION-owned FINAL_COMPOSITE FX layers (%s)" % str(layer.get("layer_id", "")))
				continue
			final_layers.append(layer.duplicate(true))
	if not errors.is_empty():
		for stack in stacks:
			_cleanup_stack((stack as Dictionary).get("entry", {}))
		return {"ok": false, "targets": 0, "background": 0, "foreground": 0, "final_composite": 0, "errors": errors, "rolled_back": true}
	var final_entry: Dictionary = {}
	if not final_layers.is_empty():
		var final_build := _build_final_entry(final_layers, options)
		if not bool(final_build.get("ok", false)):
			for stack in stacks:
				_cleanup_stack((stack as Dictionary).get("entry", {}))
			return {"ok": false, "targets": 0, "background": 0, "foreground": 0, "final_composite": 0, "errors": final_build.get("errors", []), "rolled_back": true}
		final_entry = final_build["entry"]
	clear_all()

	# ---- pass 1: target-local planes in canonical target order --------------------
	# Composition planes are attached after the target-local surfaces below. A
	# composition background is still scoped by the target texture (rather than
	# being a full-frame colour), so placing it after its source surface is what
	# makes its authored treatment observable in the target rect on OpenGL.
	var bg_index := 0

	# ---- pass 2: per-target local planes in canonical target order ---------------
	for stack in stacks:
		var entry: Dictionary = stack["entry"]
		var canonical: TextureRect = entry["canonical"]
		var below_idx := canonical.get_index()
		var overlay_count := 0
		var plane_anchors: Dictionary = {}
		for quad_entry in entry.get("quads", []):
			var plane := str(quad_entry.get("plane", "TARGET_SOURCE"))
			if plane == "COMPOSITION_BACKGROUND" or plane == "COMPOSITION_FOREGROUND":
				continue
			var placement := _place_quad(root, canonical, plane, quad_entry["node"], below_idx, overlay_count, plane_anchors)
			below_idx = int(placement.get("below_idx", below_idx))
			overlay_count = int(placement.get("overlay_count", overlay_count))
			_pin_if_blend(entry, quad_entry)

	# ---- pass 3: all composition-background layers (deterministic order) --------
	# The anchor is resolved after target-local placement so the background group
	# sits above every local target surface but remains below the foreground group.
	var background_anchor := _background_anchor_index(root) if bool(options.get("single_target", false)) else _foreground_anchor_index(root)
	for stack in stacks:
		for quad_entry in stack["entry"].get("quads", []):
			if str(quad_entry.get("plane", "")) != "COMPOSITION_BACKGROUND":
				continue
			_place_quad_at(root, background_anchor + bg_index, quad_entry["node"])
			bg_index += 1
			_pin_if_blend(stack["entry"], quad_entry)

	# ---- pass 4: all composition-foreground layers (deterministic order) ---------
	var foreground_anchor := _foreground_anchor_index(root)
	var fg_index := 0
	for stack in stacks:
		for quad_entry in stack["entry"].get("quads", []):
			if str(quad_entry.get("plane", "")) != "COMPOSITION_FOREGROUND":
				continue
			_place_quad_at(root, foreground_anchor + fg_index, quad_entry["node"])
			fg_index += 1
			_pin_if_blend(stack["entry"], quad_entry)

	# ---- pass 5: one explicit full-canvas final pass before impact/cover ---------
	if not final_entry.is_empty():
		if not _attach_final_entry(root, final_entry, inject_failure):
			_cleanup_final_entry(final_entry)
			for stack in stacks:
				_cleanup_stack((stack as Dictionary).get("entry", {}))
			return {"ok": false, "targets": 0, "background": 0, "foreground": 0, "final_composite": 0, "errors": ["FINAL_COMPOSITE setup failed"], "rolled_back": true}

	# ---- commit ------------------------------------------------------------------
	for stack in stacks:
		var entry: Dictionary = stack["entry"]
		var canonical: TextureRect = entry["canonical"]
		entry["canonical_self_modulate"] = canonical.self_modulate
		canonical.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
		_stacks[str(stack["key"])] = entry
		_push_current_time(entry)
	if not final_entry.is_empty():
		_final_composite = final_entry
		_push_final_time()
	for key in _stacks.keys():
		_update_stack(str(key))
	return {"ok": errors.is_empty(), "targets": stacks.size(), "background": bg_index, "foreground": fg_index, "final_composite": final_layers.size() if not final_entry.is_empty() else 0, "final_layers": final_layers.size(), "errors": errors}

func _collect_final_layers(stacks: Array) -> Array:
	var out: Array = []
	for stack_raw in stacks:
		var stack: Dictionary = stack_raw
		var entry: Dictionary = stack.get("entry", {})
		for layer in entry.get("final_layers", []):
			if layer is Dictionary:
				out.append((layer as Dictionary).duplicate(true))
	return out

func _build_final_entry(final_layers: Array, _options := {}) -> Dictionary:
	if not final_composite_supported():
		return {"ok": false, "errors": ["FINAL_COMPOSITE unsupported: dedicated shader path is unavailable"]}
	if final_layers.is_empty():
		return {"ok": false, "errors": ["FINAL_COMPOSITE requires an explicit layer"]}
	var passes: Array = []
	var errors: Array = []
	for raw_layer in final_layers:
		var layer: Dictionary = raw_layer if raw_layer is Dictionary else {}
		if layer.is_empty() or str(layer.get("lane", "")) != "FINAL_COMPOSITE":
			errors.append("FINAL_COMPOSITE setup received a non-explicit layer")
			continue
		var lane_result: Dictionary = FxOperatorsScript.validate_layer_lane(layer)
		if not bool(lane_result.get("ok", false)):
			errors.append_array(lane_result.get("errors", []))
			continue
		if str(layer.get("type", "")) != "FX" or str(layer.get("authority", "")) != "COMPOSITION":
			errors.append("FINAL_COMPOSITE requires a COMPOSITION-owned FX layer")
			continue
		var built_pass := _build_final_pass(layer, _options)
		if not bool(built_pass.get("ok", false)):
			errors.append_array(built_pass.get("errors", []))
		else:
			var final_pass: Dictionary = built_pass.get("pass", {})
			var fx_data: Dictionary = layer.get("fx", {}) if layer.get("fx", {}) is Dictionary else {}
			var scope := str(fx_data.get("operator_scope", "ALL"))
			final_pass["scope"] = scope
			# The VS mark, its shadow and the name plates are layered ABOVE every
			# final pass (see _final_anchor_index), so no pass can capture or
			# warp them. The former vacuum mark matte / source exclusion is gone.
			if scope != "ALL":
				var scope_mask: SubViewport = _build_scope_mask(scope)
				if scope_mask == null:
					errors.append("FINAL_COMPOSITE scope requires a live semantic role matte: " + scope)
					_cleanup_final_pass(final_pass)
					continue
				var scope_material := (final_pass.get("node", null) as ColorRect).material as ShaderMaterial
				scope_material.set_shader_parameter("final_scope_mode", _scope_mode(scope))
				scope_material.set_shader_parameter("scope_mask", scope_mask.get_texture())
				final_pass["scope_viewport"] = scope_mask
				if scope == "ECHO_ONLY":
					# Keep pre-occlusion alpha separate. Canvas SUB subtracts coverage;
					# it is not source-over visibility E * (1 - P).
					var primary_mask: SubViewport = _build_scope_mask("PRIMARY_ONLY")
					if primary_mask == null:
						errors.append("FINAL_COMPOSITE scope requires a live semantic role matte: PRIMARY_ONLY")
						_cleanup_final_pass(final_pass)
						continue
					final_pass["primary_scope_viewport"] = primary_mask
					scope_material.set_shader_parameter("primary_scope_mask", primary_mask.get_texture())
			passes.append(final_pass)
	if not errors.is_empty() or passes.is_empty():
		for final_pass in passes:
			_cleanup_final_pass(final_pass)
		return {"ok": false, "errors": errors if not errors.is_empty() else ["FINAL_COMPOSITE requires an explicit layer"]}
	return {"ok": true, "errors": [], "entry": {"passes": passes, "layer_ids": passes.map(func(final_pass): return str((final_pass as Dictionary).get("layer_id", "")))} }

func _scope_mode(scope: String) -> float:
	return {"ALL": 0.0, "ECHO_ONLY": 1.0, "PRIMARY_ONLY": 2.0, "EXCLUDE_PRIMARY": 3.0}.get(scope, -1.0)

func _build_scope_mask(scope: String) -> SubViewport:
	# Semantic scopes are only valid when the requested source can be bound.
	if registry == null or not registry.has_method("ordered_keys"):
		return null
	if screen == null or not is_instance_valid(screen):
		return null
	if _scope_mode(scope) < 0.0:
		return null
	var mask_viewport := SubViewport.new()
	mask_viewport.name = "FxSemanticScopeMask_%s" % scope
	mask_viewport.size = Vector2i(int(CANVAS.x), int(CANVAS.y))
	mask_viewport.transparent_bg = true
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.add_child(mask_viewport)
	var bindings: Array = []
	var bound_nodes := 0
	for key in registry.ordered_keys():
		if not registry.slot_nodes.has(key):
			continue
		var context: Dictionary = registry.context_for_key(key)
		var role := str(context.get("element_role", ""))
		var is_primary := role == "primary"
		var include := (scope == "ECHO_ONLY" and role == "echo") or (scope == "PRIMARY_ONLY" and is_primary) or (scope == "EXCLUDE_PRIMARY" and is_primary)
		if not include:
			continue
		var source = registry.slot_nodes[key]
		if not (source is TextureRect) or source.texture == null:
			continue
		bound_nodes += 1
		# Reproduce the local hierarchy, not a decomposed global Control transform.
		# Nonuniform ancestor scale + child rotation produces skew; flattening that
		# into position/rotation/scale loses the actual raster transform and clips.
		var chain: Array = []
		var ancestor: Node = source
		while ancestor != null and not (ancestor is Viewport):
			chain.push_front(ancestor)
			ancestor = ancestor.get_parent()
		var parent: Node = mask_viewport
		for original in chain:
			var mirror: Node
			if original == source:
				mirror = TextureRect.new()
			elif original is Control:
				mirror = Control.new()
			elif original is Node2D:
				mirror = Node2D.new()
			else:
				mirror = Node.new()
			parent.add_child(mirror)
			bindings.append({"source": original, "mirror": mirror})
			parent = mirror
	if bound_nodes == 0:
		mask_viewport.free()
		return null
	mask_viewport.set_meta("fx_scope_bindings", bindings)
	_sync_scope_mask(mask_viewport)
	return mask_viewport

func _sync_scope_mask(viewport: SubViewport) -> void:
	for binding in viewport.get_meta("fx_scope_bindings", []):
		var source = binding.source
		var mirror = binding.mirror
		if not is_instance_valid(source) or not is_instance_valid(mirror):
			if is_instance_valid(mirror) and mirror is CanvasItem: mirror.visible = false
			continue
		if source is CanvasItem and mirror is CanvasItem:
			mirror.visible = source.visible
			mirror.top_level = source.top_level
			mirror.modulate = Color(1, 1, 1, source.modulate.a)
			var self_alpha: float = source.self_modulate.a
			# Local stacks hide the canonical source via self_modulate only. That
			# implementation detail must not erase its semantic source silhouette.
			for entry in _stacks.values():
				if entry.get("canonical") == source:
					self_alpha = entry.get("canonical_self_modulate", Color.WHITE).a
			mirror.self_modulate = Color(1, 1, 1, self_alpha)
			mirror.texture_filter = source.texture_filter
			mirror.texture_repeat = source.texture_repeat
		if source is Control and mirror is Control:
			mirror.size = source.size
			mirror.pivot_offset = source.pivot_offset
			mirror.position = source.position
			mirror.rotation = source.rotation
			mirror.scale = source.scale
			mirror.clip_contents = source.clip_contents
		elif source is Node2D and mirror is Node2D:
			mirror.transform = source.transform
		if source is TextureRect and mirror is TextureRect:
			mirror.expand_mode = source.expand_mode
			mirror.stretch_mode = source.stretch_mode
			mirror.texture = source.texture
			mirror.size = source.size
			mirror.flip_h = source.flip_h
			mirror.flip_v = source.flip_v

func _build_final_pass(layer: Dictionary, options := {}) -> Dictionary:
	var fx: Dictionary = layer.get("fx", {}) if layer.get("fx", {}) is Dictionary else {}
	var amount := float(fx.get("final_tint_amount", 0.0))
	if not is_finite(amount):
		amount = 0.0
	var opacity := float(layer.get("opacity", 1.0))
	if not is_finite(opacity):
		opacity = 1.0
	var quad := ColorRect.new()
	quad.name = "vnext_final_composite"
	quad.color = Color.WHITE
	quad.position = Vector2.ZERO
	quad.size = CANVAS
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.z_index = 0
	var material := ShaderMaterial.new()
	material.shader = _final_shader
	material.set_shader_parameter("speedlines_noise", load(SPEEDLINES_NOISE_PATH))
	material.set_shader_parameter("final_tint_amount", clampf(amount, 0.0, 1.0) * clampf(opacity, 0.0, 1.0))
	material.set_shader_parameter("final_tint_color", _color(fx.get("final_tint_color", [1.0, 1.0, 1.0, 1.0])))
	var final_operator := str(fx.get("operator", "NONE"))
	var final_mode := _final_operator_index(final_operator)
	material.set_shader_parameter("final_operator_mode", final_mode)
	# Composition is now an ordered list of explicit passes. The old secondary
	# Secondary operators are legacy input only; ordered composition passes own
	# execution order and no hidden mode-4 shortcut remains in the runtime path.
	material.set_shader_parameter("final_operator_strength", clampf(float(fx.get("operator_strength", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("final_operator_scale", maxf(float(fx.get("operator_scale", 1.0)), 0.25))
	material.set_shader_parameter("final_operator_speed", maxf(float(fx.get("operator_speed", 1.0)), 0.0))
	material.set_shader_parameter("final_operator_softness", clampf(float(fx.get("operator_softness", 0.1)), 0.0, 1.0))
	material.set_shader_parameter("final_operator_pattern_mode", clampf(float(fx.get("operator_pattern_mode", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("final_operator_pattern_family", clampf(float(fx.get("operator_pattern_family", 0.0)), 0.0, 2.0))
	material.set_shader_parameter("final_operator_distortion", clampf(float(fx.get("operator_distortion", 0.0)), 0.0, 1.0))
	var resolved_center := Vector2(float(fx.get("operator_center_x", 0.5)), float(fx.get("operator_center_y", 0.5)))
	var anchor := str(fx.get("operator_anchor", "CUSTOM"))
	if anchor != "CUSTOM" and registry != null and registry.has_method("resolve_anchor"):
		resolved_center = registry.resolve_anchor(anchor, str(options.get("anchor_target_key", "")))
	material.set_shader_parameter("final_operator_center", resolved_center)
	material.set_shader_parameter("final_operator_axis", Vector2(float(fx.get("operator_axis_x", 1.0)), float(fx.get("operator_axis_y", 0.0))))
	material.set_shader_parameter("final_operator_progress", clampf(float(fx.get("operator_progress", 0.5)), 0.0, 1.0))
	material.set_shader_parameter("final_operator_progress_start", clampf(float(fx.get("operator_progress_start", fx.get("operator_progress", 0.5))), 0.0, 1.0))
	material.set_shader_parameter("final_operator_progress_end", clampf(float(fx.get("operator_progress_end", fx.get("operator_progress", 0.5))), 0.0, 1.0))
	material.set_shader_parameter("final_operator_progress_animated", 1.0 if str(fx.get("operator_progress_mode", "STATIC")) == "EVENT_LINEAR" else 0.0)
	material.set_shader_parameter("final_operator_polarity", clampf(float(fx.get("operator_polarity", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("final_operator_mix_mode", clampf(float(fx.get("operator_mix_mode", 0.0)), 0.0, 2.0))
	material.set_shader_parameter("final_scope_mode", 0.0)
	var color_a := _color(fx.get("operator_color_a", [0.25, 0.95, 1.0, 1.0]))
	var color_b := _color(fx.get("operator_color_b", [1.0, 0.35, 0.82, 1.0]))
	# A pass without authored colours follows the VS screen's side colours,
	# so two-sided operators (speedlines) light each half in its own colour.
	# The look defaults always fill operator_color_a/b with the canonical
	# cyan/pink, so that exact value counts as "not authored".
	var unauthored := (not fx.has("operator_color_a") or color_a.is_equal_approx(DEFAULT_OPERATOR_COLOR_A)) and (not fx.has("operator_color_b") or color_b.is_equal_approx(DEFAULT_OPERATOR_COLOR_B))
	if unauthored and screen != null and is_instance_valid(screen) and screen.has_method("side_colors") and screen.has_method("ink_look_enabled") and screen.ink_look_enabled():
		var sides: Array = screen.side_colors()
		color_a = sides[0]
		color_b = sides[1]
	material.set_shader_parameter("final_operator_color_a", color_a)
	material.set_shader_parameter("final_operator_color_b", color_b)
	material.set_shader_parameter("presentation_time", _last_time)
	material.set_shader_parameter("free_run_time", _last_free)
	material.set_shader_parameter("final_time_source", 1.0 if str(fx.get("operator_time_source", fx.get("time_source", "PRESENTATION_TIME"))) == "FREE_RUN" else 0.0)
	material.set_shader_parameter("final_operator_event_start", float(fx.get("operator_event_start", 0.0)))
	material.set_shader_parameter("final_operator_duration", maxf(float(fx.get("operator_duration", 0.5)), 0.0))
	quad.material = material
	var bbc := BackBufferCopy.new()
	bbc.name = "vnext_final_bbc"
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	return {"ok": true, "errors": [], "pass": {"node": quad, "backbuffer_copy": bbc, "layer_id": str(layer.get("layer_id", ""))}}

func _attach_final_entry(root: Node, entry: Dictionary, inject_failure := "") -> bool:
	if root == null or entry.is_empty():
		return false
	var anchor := _final_anchor_index(root)
	var passes: Array = entry.get("passes", [])
	if passes.is_empty():
		return false
	for index in range(passes.size()):
		var final_pass: Dictionary = passes[index]
		if inject_failure == "attach_pass_1" and index == 0:
			return false
		if inject_failure == "attach_after_pass_2" and index == 2:
			return false
		var bbc = final_pass.get("backbuffer_copy", null)
		var quad = final_pass.get("node", null)
		if not (bbc is BackBufferCopy) or not (quad is ColorRect) or not is_instance_valid(bbc) or not is_instance_valid(quad):
			return false
		root.add_child(bbc)
		# EXCLUDE_PRIMARY passes sit directly below the primaries: the captured
		# frame never contains a primary, so displacement cannot drag primary
		# pixels into the background (no ghost copy leaking out of the matte).
		var pass_anchor := anchor
		var below_primary := _primary_anchor_index(root) if str(final_pass.get("scope", "ALL")) == "EXCLUDE_PRIMARY" else -1
		if below_primary >= 0:
			pass_anchor = below_primary
		else:
			pass_anchor = _final_anchor_index(root)
		root.move_child(bbc, clampi(pass_anchor, 0, root.get_child_count() - 1))
		root.add_child(quad)
		_fit_quad_global(quad, root)
		root.move_child(quad, clampi(bbc.get_index() + 1, 0, root.get_child_count() - 1))
	return true

func _primary_anchor_index(root: Node) -> int:
	# 1v1 primaries are direct Root children; family layouts keep them in
	# FamilyBack/Primaries, which is drawn after FamilyBack/Echoes, so the
	# pass cannot be interleaved there and keeps its semantic matte instead.
	var primary := root.get_node_or_null("PrimaryLeft")
	if primary is CanvasItem and (primary as CanvasItem).visible:
		return primary.get_index()
	return -1

func _cleanup_final_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	for final_pass in entry.get("passes", []):
		_cleanup_final_pass(final_pass)

func _cleanup_final_pass(final_pass: Dictionary) -> void:
	for key in ["node", "backbuffer_copy", "scope_viewport", "primary_scope_viewport"]:
		var node = final_pass.get(key, null)
		if is_instance_valid(node):
			node.free()

func clear_final_composite() -> void:
	_cleanup_final_entry(_final_composite)
	_final_composite = {}

func _construct_stack(target_key: String, look: Dictionary) -> Dictionary:
	# Builds every quad + offscreen stage + material wiring for one target.
	# Placement is the job of the caller (single-target vs composition order).
	var errors: Array = []
	var node = registry.target_node(target_key)
	if not (node is TextureRect) or node.texture == null:
		return {"ok": false, "errors": ["target has no source texture: " + target_key], "entry": {}}
	var canonical: TextureRect = node
	var rect: Rect2 = FxTargetsScript.presentation_rect(canonical)
	var tint: Color = canonical.get_meta("fx_source_tint", Color.WHITE)
	var entry := {"quads": [], "input_quads": [], "input_viewports": [], "backbuffer_copies": [], "final_layers": [], "canonical": canonical}
	_quad_asset_errors.clear()

	var enabled_layers: Array = []
	for raw in look.get("layers", []):
		if raw is Dictionary and bool((raw as Dictionary).get("enabled", true)):
			var candidate: Dictionary = raw
			var candidate_lane := FxOperatorsScript.lane_for_layer(candidate)
			if candidate_lane == "FINAL_COMPOSITE":
				if str(candidate.get("authority", "")) != "COMPOSITION":
					errors.append("FINAL_COMPOSITE layer is not composition-owned (%s)" % str(candidate.get("layer_id", "")))
					continue
				# A target Look may contain a stale final layer from an older schema,
				# but global passes are only admitted through the explicit composition
				# plan entry. Never let a fighter-owned Look smuggle a screen effect in.
				errors.append("FINAL_COMPOSITE layer requires an explicit composition plan entry (%s)" % str(candidate.get("layer_id", "")))
				continue
			else:
				enabled_layers.append(candidate)
	var viewport_consumers := 0
	var has_transformed_consumer := false
	for layer in enabled_layers:
		var input_kind := str((layer as Dictionary).get("input", ""))
		if input_kind in OFFSET_INPUTS:
			viewport_consumers += 1
		if str((layer as Dictionary).get("type", "")) == "FX" and input_kind == "TRANSFORMED_SOURCE":
			has_transformed_consumer = true
	if viewport_consumers > 1:
		errors.append("only one offscreen-input consumer per target is supported yet")
	if has_transformed_consumer and viewport_consumers > 0:
		errors.append("mixing TRANSFORMED_SOURCE with LAYER_BELOW/COMPOSITE_BELOW in one Look needs nested stages (unsupported yet)")
	var transformed_stage: SubViewport = null
	if has_transformed_consumer and errors.is_empty():
		transformed_stage = _build_transformed_stage(entry, canonical, rect, tint, enabled_layers)

	for index in range(enabled_layers.size()):
		var layer: Dictionary = enabled_layers[index]
		var layer_type := str(layer.get("type", ""))
		var input := str(layer.get("input", "ORIGINAL_SOURCE"))
		var blend := str(layer.get("blend_mode", "NORMAL"))
		if layer_type == "FX" and input not in SUPPORTED_INPUTS:
			errors.append("input not yet implemented: %s (%s)" % [input, str(layer.get("layer_id", ""))])
		if blend not in SUPPORTED_BLENDS:
			errors.append("blend mode not yet implemented: %s (%s)" % [blend, str(layer.get("layer_id", ""))])
		if layer_type == "FX" and input in OFFSET_INPUTS and _uses_offscreen_input(enabled_layers, index):
			errors.append("nested offscreen inputs are not supported yet (%s)" % str(layer.get("layer_id", "")))
		var plane := str(layer.get("plane", "TARGET_SOURCE"))
		var lane_result: Dictionary = FxOperatorsScript.validate_layer_lane(layer)
		var lane := str(lane_result.get("lane", ""))
		if not bool(lane_result.get("ok", false)):
			errors.append_array(lane_result.get("errors", []))
		var quad := _make_quad(canonical, rect, tint, layer)
		if layer_type == "FX" and input == "TRANSFORMED_SOURCE" and transformed_stage != null:
			var t_material := quad.material as ShaderMaterial
			t_material.set_shader_parameter("input_tex", transformed_stage.get_texture())
			t_material.set_shader_parameter("input_is_viewport", 1.0)
			t_material.set_shader_parameter("input_empty", 0.0)
			t_material.set_shader_parameter("source_rect", [0.0, 0.0, CANVAS.x, CANVAS.y])
			t_material.set_shader_parameter("source_tex_size", CANVAS)
		if layer_type == "FX" and input in OFFSET_INPUTS:
			var input_layers: Array = []
			if input == "LAYER_BELOW":
				if index > 0:
					input_layers.append(enabled_layers[index - 1])
			else:
				for j in range(index):
					input_layers.append(enabled_layers[j])
			var viewport := _build_input_viewport(entry, canonical, rect, tint, input_layers)
			var material := quad.material as ShaderMaterial
			material.set_shader_parameter("input_tex", viewport.get_texture())
			material.set_shader_parameter("input_is_viewport", 1.0)
			material.set_shader_parameter("input_empty", 1.0 if input_layers.is_empty() else 0.0)
			material.set_shader_parameter("source_rect", [0.0, 0.0, CANVAS.x, CANVAS.y])
			material.set_shader_parameter("source_tex_size", CANVAS)
		var transform: Dictionary = layer.get("transform", {})
		entry["quads"].append({
			"node": quad,
			"layer_id": str(layer.get("layer_id", "")),
			"plane": plane,
			"lane": lane,
			"blend": blend,
			"layer_flip_x": bool(transform.get("flip_x", false)),
			"layer_flip_y": bool(transform.get("flip_y", false)),
		})
	errors.append_array(_quad_asset_errors)
	_quad_asset_errors.clear()
	return {"ok": errors.is_empty(), "errors": errors, "entry": entry, "key": target_key}

func _pin_if_blend(entry: Dictionary, quad_entry: Dictionary) -> void:
	if str(quad_entry.get("blend", "NORMAL")) == "NORMAL":
		return
	var quad = quad_entry["node"]
	if not is_instance_valid(quad) or quad.get_parent() == null:
		return
	var bbc := BackBufferCopy.new()
	bbc.name = "vnext_bbc"
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	var parent: Node = quad.get_parent()
	parent.add_child(bbc)
	parent.move_child(bbc, quad.get_index())
	entry["backbuffer_copies"].append(bbc)

func _place_quad_at(root: Node, index: int, quad: Control) -> void:
	if not is_instance_valid(quad):
		return
	root.add_child(quad)
	_fit_quad_global(quad, root)
	root.move_child(quad, clampi(index, 0, root.get_child_count() - 1))

# SP-04: quads sample GLOBAL source_rect, so under a transformed ancestor
# position ZERO is not the global origin. Fit the quad node so its global
# rect is exactly the canvas rect (translation-exact; scale by basis
# lengths; rotation skew stays best-effort for sampling surfaces).
func _fit_quad_global(quad: Control, parent: Node) -> void:
	if not (parent is CanvasItem):
		return
	var inv: Transform2D = (parent as CanvasItem).get_global_transform().affine_inverse()
	quad.position = inv * Vector2.ZERO
	quad.size = Vector2(CANVAS.x * inv.x.length(), CANVAS.y * inv.y.length())
	quad.rotation = 0.0
	quad.scale = Vector2.ONE

func _cleanup_stack(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	for quad_entry in entry.get("quads", []):
		var quad = quad_entry["node"]
		if is_instance_valid(quad):
			quad.free()
	for viewport in entry.get("input_viewports", []):
		if is_instance_valid(viewport):
			viewport.free()
	for bbc in entry.get("backbuffer_copies", []):
		if is_instance_valid(bbc):
			bbc.free()

func clear_target(target_key: String) -> void:
	if not _stacks.has(target_key):
		return
	var entry: Dictionary = _stacks[target_key]
	for quad_entry in entry.get("quads", []):
		var quad = quad_entry["node"]
		if is_instance_valid(quad):
			quad.free()
	for viewport in entry.get("input_viewports", []):
		if is_instance_valid(viewport):
			viewport.free()
	for bbc in entry.get("backbuffer_copies", []):
		if is_instance_valid(bbc):
			bbc.free()
	var canonical = entry.get("canonical")
	if is_instance_valid(canonical):
		canonical.self_modulate = entry.get("canonical_self_modulate", Color.WHITE)
	_stacks.erase(target_key)

func clear_all() -> void:
	for key in _stacks.keys():
		clear_target(str(key))
	clear_final_composite()

func has_stack(target_key: String) -> bool:
	return _stacks.has(target_key)

func stack_quads(target_key: String) -> Array:
	if not _stacks.has(target_key):
		return []
	return _stacks[target_key].get("quads", [])

func set_time(t: float) -> void:
	# PRESENTATION_TIME is supplied by the owning transport; never use an
	# implicit shader TIME source.
	_last_time = t
	for key in _stacks.keys():
		for quad_entry in _all_quad_entries(_stacks[key]):
			var quad = quad_entry["node"]
			if is_instance_valid(quad) and quad.material is ShaderMaterial:
				(quad.material as ShaderMaterial).set_shader_parameter("layer_time", t)
				(quad.material as ShaderMaterial).set_shader_parameter("fx_time", t)
				_refresh_envelope(quad)
		_update_stack(str(key))
	_push_final_time()
	_push_living_edges()

# Living side-field edge choreography (shaders/side_field_edge.gdshader).
# One beat, not constant noise: restless while the fields fly in, pulled
# toward the centre by the vacuum, a single snap-out at the clash impact,
# then a slow breath through HOLD so the fighters keep the attention.
func living_edge_state(t: float) -> Dictionary:
	var impact := float(_event_marks.get("clash_impact", 0.615))
	var pull_start := impact - 0.16
	var energy := 0.28 + 0.04 * sin(t * 2.1)
	# Entry: restless, settling as the fields lock.
	energy += 0.6 * (1.0 - smoothstep(0.1, 0.5, t))
	var pull := 0.0
	# press (0..1): how much of the seam around the VS the two fields close
	# onto their shared clash boundary. amp: how hard that boundary tears.
	var press := 0.0
	var contact := 0.0
	var amp := 18.0
	if t >= pull_start and t < impact:
		var p := (t - pull_start) / (impact - pull_start)
		pull = 22.0 * p * p
		# Fronts surge in, accelerating into the hit.
		press = smoothstep(0.55, 1.0, p)
		energy = maxf(energy, 0.45 + 0.25 * p)
		contact = 1.6 * smoothstep(0.75, 1.0, p)
	elif t >= impact:
		var k := t - impact
		# Snap past rest, then a damped settle. The energy crest lands a few
		# frames AFTER the impact so the VS mark owns the hit itself.
		pull = 22.0 * exp(-k * 14.0) * cos(k * 20.0)
		var crest := k / 0.09
		energy = maxf(energy, 0.28 + 0.95 * crest * exp(1.0 - crest))
		# The hit: the contact line flares and tears wide, then settles into
		# a held, crackling border between the two sides.
		press = 1.0
		contact = 1.0 + 0.9 * exp(-k * 8.0)
		amp = 30.0 + 30.0 * exp(-k * 6.0) * absf(cos(k * 14.0))
	return {"energy": energy, "pull_px": pull, "press": press, "contact": contact, "amp": amp}

func _push_living_edges() -> void:
	# The living edge is part of the screen's own choreography, not an FX
	# operator: it follows the VS timeline (elapsed/seek), never the FX
	# PRESENTATION_TIME / FREE_RUN transports that operators select from.
	if screen == null or not is_instance_valid(screen) or not screen.has_method("elapsed"):
		return
	var t: float = float(screen.elapsed())
	var fields := screen.get_node_or_null("Root/SideFields")
	var state := living_edge_state(t)
	var edge_nodes: Array = fields.get_children() if fields != null else []
	for child in edge_nodes:
		if child is CanvasItem and bool((child as CanvasItem).get_meta("fx_living_edge", false)):
			var material := (child as CanvasItem).material as ShaderMaterial
			if material != null:
				material.set_shader_parameter("edge_time", t)
				material.set_shader_parameter("edge_energy", float(state["energy"]))
				material.set_shader_parameter("edge_pull_px", float(state["pull_px"]))
				material.set_shader_parameter("press", float(state["press"]))
				material.set_shader_parameter("clash_amp_px", float(state["amp"]))
				material.set_shader_parameter("contact_strength", float(state["contact"]))

	# The collision light: the seam between the fields and the VS mark flash
	# follow the same beat as the edges.
	var seam := 0.25 + 0.55 * clampf(float(state["energy"]) - 0.28, 0.0, 1.0) + maxf(float(state["pull_px"]), 0.0) / 60.0
	var stage := screen.get_node_or_null("Root/Stage") as CanvasItem
	if stage != null and stage.material is ShaderMaterial:
		(stage.material as ShaderMaterial).set_shader_parameter("seam_energy", seam)
	var hit := clampf((float(state["energy"]) - 0.45) / 0.8, 0.0, 1.0)
	for path in ["Root/VsMark/Mark", "Root/VsMark/UnderShadow"]:
		var node := screen.get_node_or_null(path) as CanvasItem
		if node != null and node.material is ShaderMaterial and (node.material as ShaderMaterial).shader != null and (node.material as ShaderMaterial).shader.resource_path.ends_with("vs_mark_ink.gdshader"):
			(node.material as ShaderMaterial).set_shader_parameter("impact", hit)

func set_clocks(presentation_time: float, free_run_time: float) -> void:
	# Explicit clock bundle for integrations that own both transports.
	set_time(presentation_time)
	set_free_run(free_run_time)

func clock_state() -> Dictionary:
	return {"presentation_time": _last_time, "free_run_time": _last_free}

# UI-04: debug view actually switches renderer output. The shader has long
# implemented modes 0..6; the renderer never drove the uniform (silent no-op).
const DEBUG_VIEWS := ["COMPOSITE", "BASE", "EFFECT", "EDGE", "COVERAGE", "MASK", "DRIVER"]
var _debug_view := "COMPOSITE"

# MK asset errors collected by _make_quad during one _construct_stack run.
var _quad_asset_errors: Array = []

func set_debug_view(mode: String) -> void:
	# Unknown names fall back to COMPOSITE (fail-safe display, never an error).
	_debug_view = mode if mode in DEBUG_VIEWS else "COMPOSITE"
	var value := float(DEBUG_VIEWS.find(_debug_view))
	for key in _stacks.keys():
		for quad_entry in _all_quad_entries((_stacks[key] as Dictionary)):
			var quad = (quad_entry as Dictionary).get("node", null)
			if is_instance_valid(quad) and (quad as Control).material is ShaderMaterial:
				((quad as Control).material as ShaderMaterial).set_shader_parameter("debug_view_mode", value)

func debug_view() -> String:
	return _debug_view

# TM-04: explicit manual-trigger epochs per motion domain.
var _manual_epochs: Dictionary = {}

func trigger_manual(domain := "") -> void:
	# Restarts "manual"-anchored envelopes at the current clock. Empty
	# domain triggers all four motion domains.
	var domains: Array = ["dither", "fringe", "flow", "rgb"] if domain == "" else [domain]
	for dom in domains:
		_manual_epochs[str(dom)] = _last_time
	set_time(_last_time)

func _refresh_envelope(quad: Node) -> void:
	if not (quad is Control):
		return
	if not (quad as Control).has_meta("fx_amount_base"):
		return
	var base: Dictionary = (quad as Control).get_meta("fx_amount_base")
	var motion: Dictionary = (quad as Control).get_meta("fx_motion", {})
	var material := (quad as Control).material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("fx_dither", float(base.get("dither", 0.0)) * _motion_multiplier(motion, "dither"))
	material.set_shader_parameter("fx_fringe", float(base.get("fringe", 0.0)) * _motion_multiplier(motion, "fringe"))
	material.set_shader_parameter("fx_flow", float(base.get("flow", 0.0)) * _motion_multiplier(motion, "flow"))
	material.set_shader_parameter("fx_rgb", float(base.get("rgb", 0.0)) * _motion_multiplier(motion, "rgb"))

func set_free_run(t: float) -> void:
	# FREE_RUN displacement time-source: advances with wall clock even while the
	# presentation transport is parked (specs/04).
	_last_free = t
	for key in _stacks.keys():
		for quad_entry in _all_quad_entries(_stacks[key]):
			var quad = quad_entry["node"]
			if is_instance_valid(quad) and quad.material is ShaderMaterial:
				(quad.material as ShaderMaterial).set_shader_parameter("free_time", t)
	_push_final_time()

# ---------------------------------------------------------------- internals

func _push_current_time(entry: Dictionary) -> void:
	# Newly built quads must inherit the renderer's current transport state so a
	# runtime that seeks first and applies later (or vice versa) stays coherent.
	for quad_entry in _all_quad_entries(entry):
		var quad = quad_entry["node"]
		if is_instance_valid(quad) and quad.material is ShaderMaterial:
			var material: ShaderMaterial = quad.material
			material.set_shader_parameter("layer_time", _last_time)
			material.set_shader_parameter("fx_time", _last_time)
			material.set_shader_parameter("free_time", _last_free)

func _all_quad_entries(entry: Dictionary) -> Array:
	var out: Array = []
	out.append_array(entry.get("quads", []))
	out.append_array(entry.get("input_quads", []))
	return out

func _uses_offscreen_input(layers: Array, index: int) -> bool:
	for j in range(index):
		if str((layers[j] as Dictionary).get("input", "")) in OFFSET_INPUTS:
			return true
	return false

func _build_transformed_stage(entry: Dictionary, canonical: TextureRect, rect: Rect2, tint: Color, enabled_layers: Array) -> SubViewport:
	# ONE stage per target: the canonical SOURCE layer rendered with Transform +
	# Displacement only (stage_stop short-circuits FX/Mask/Opacity/Blend in the
	# shared shader). All TRANSFORMED_SOURCE consumers sample this stage.
	var viewport := SubViewport.new()
	viewport.name = "vnext_input"
	viewport.size = Vector2i(int(CANVAS.x), int(CANVAS.y))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.add_child(viewport)
	entry["input_viewports"].append(viewport)
	var source_layer: Dictionary = {}
	for layer in enabled_layers:
		if str((layer as Dictionary).get("type", "")) == "SOURCE":
			source_layer = layer
			break
	if source_layer.is_empty():
		return viewport
	var quad := _make_quad(canonical, rect, tint, source_layer)
	var material := quad.material as ShaderMaterial
	material.set_shader_parameter("stage_stop", 1.0)
	material.set_shader_parameter("mask_enabled", 0.0)
	material.set_shader_parameter("layer_opacity", 1.0)
	viewport.add_child(quad)
	var transform: Dictionary = source_layer.get("transform", {})
	entry["input_quads"].append({
		"node": quad,
		"layer_id": str(source_layer.get("layer_id", "")),
		"plane": "TRANSFORMED_STAGE",
		"layer_flip_x": bool(transform.get("flip_x", false)),
		"layer_flip_y": bool(transform.get("flip_y", false)),
	})
	return viewport

func _build_input_viewport(entry: Dictionary, canonical: TextureRect, rect: Rect2, tint: Color, layers: Array) -> SubViewport:
	# Per-consumer offscreen stage: the lower local layers render here and the
	# consumer samples the flattened result 1:1 in canvas space.
	var viewport := SubViewport.new()
	viewport.name = "vnext_input"
	viewport.size = Vector2i(int(CANVAS.x), int(CANVAS.y))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.add_child(viewport)
	entry["input_viewports"].append(viewport)
	for layer in layers:
		var quad := _make_quad(canonical, rect, tint, layer)
		viewport.add_child(quad)
		var transform: Dictionary = (layer as Dictionary).get("transform", {})
		entry["input_quads"].append({
			"node": quad,
			"layer_id": str((layer as Dictionary).get("layer_id", "")),
			"plane": "INPUT",
			"layer_flip_x": bool(transform.get("flip_x", false)),
			"layer_flip_y": bool(transform.get("flip_y", false)),
		})
	return viewport

func _make_quad(canonical: TextureRect, rect: Rect2, tint: Color, layer: Dictionary) -> Control:
	var quad := ColorRect.new()
	quad.name = "vnext_" + str(layer.get("layer_id", "layer")).to_lower()
	quad.color = Color.WHITE
	quad.position = Vector2.ZERO
	quad.size = CANVAS
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SP-06: mirror canonical z so future authored z stays authoritative.
	quad.z_index = canonical.z_index
	var material := ShaderMaterial.new()
	material.shader = _shader
	var transform: Dictionary = layer.get("transform", {})
	var displacement: Dictionary = layer.get("displacement", {})
	var mask: Dictionary = layer.get("mask", {})
	material.set_shader_parameter("source_tex", canonical.texture)
	material.set_shader_parameter("canvas_size", CANVAS)
	material.set_shader_parameter("source_rect", [rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	material.set_shader_parameter("source_tex_size", Vector2(canonical.texture.get_width(), canonical.texture.get_height()))
	material.set_shader_parameter("tex_size", Vector2(canonical.texture.get_width(), canonical.texture.get_height()))
	material.set_shader_parameter("viewport_size", CANVAS)
	material.set_shader_parameter("element_size", rect.size)
	material.set_shader_parameter("source_uv_scale", Vector2.ONE)
	material.set_shader_parameter("source_uv_offset", Vector2.ZERO)
	tint = tint
	material.set_shader_parameter("source_tint", tint)
	material.set_shader_parameter("position_px", _vec2(transform.get("position_px", [0.0, 0.0])))
	material.set_shader_parameter("layer_scale", _vec2(transform.get("scale", [1.0, 1.0])))
	material.set_shader_parameter("rotation_deg", float(transform.get("rotation_deg", 0.0)))
	material.set_shader_parameter("pivot", _vec2(transform.get("pivot", [0.5, 0.5])))
	material.set_shader_parameter("flip_x", 1.0 if bool(transform.get("flip_x", false)) else 0.0)
	material.set_shader_parameter("flip_y", 1.0 if bool(transform.get("flip_y", false)) else 0.0)
	material.set_shader_parameter("disp_enabled", 1.0 if bool(displacement.get("enabled", false)) else 0.0)
	material.set_shader_parameter("disp_driver", float(_driver_index(str(displacement.get("driver", "NOISE")))))
	material.set_shader_parameter("disp_amount_px", _vec2(displacement.get("amount_px", [0.0, 0.0])))
	material.set_shader_parameter("disp_scale", float(displacement.get("scale", 1.0)))
	material.set_shader_parameter("disp_speed", float(displacement.get("speed", 0.0)))
	material.set_shader_parameter("disp_phase", float(displacement.get("phase", 0.0)))
	material.set_shader_parameter("disp_seed", float(displacement.get("seed", 1)))
	material.set_shader_parameter("disp_angle_deg", float(displacement.get("angle_deg", 0.0)))
	material.set_shader_parameter("disp_edge_mode", float(_edge_mode_index(str(displacement.get("edge_mode", "TRANSPARENT")))))
	material.set_shader_parameter("disp_time_source", 1.0 if str(displacement.get("time_source", "PRESENTATION_TIME")) == "FREE_RUN" else 0.0)
	var disp_custom = displacement.get("custom_texture", null)
	if disp_custom != null and str(disp_custom) != "":
		var tex = FxAssetsScript.load_texture(str(disp_custom))
		if tex is Texture2D:
			material.set_shader_parameter("disp_custom_tex", tex)
			material.set_shader_parameter("disp_custom_loaded", 1.0)
		else:
			_quad_asset_errors.append("displacement.custom_texture: asset not loadable: %s (%s)" % [str(disp_custom), str(layer.get("layer_id", ""))])
	# MK-05: influence gate wiring — same source/region/space contract as
	# layer.mask, evaluated pre-displacement in the shader.
	var infl = displacement.get("influence_mask", null)
	var infl_dict: Dictionary = infl if infl is Dictionary else {}
	material.set_shader_parameter("disp_infl_enabled", 1.0 if bool(infl_dict.get("enabled", false)) else 0.0)
	material.set_shader_parameter("disp_infl_source", float(_mask_source_index(str(infl_dict.get("source", "NONE")))))
	material.set_shader_parameter("disp_infl_region", float(_mask_region_index(str(infl_dict.get("region", "FULL")))))
	material.set_shader_parameter("disp_infl_space", float(_mask_space_index(str(infl_dict.get("space", "LAYER_SPACE")))))
	material.set_shader_parameter("disp_infl_expand_contract_px", float(infl_dict.get("expand_contract_px", 0.0)))
	material.set_shader_parameter("disp_infl_width_px", float(infl_dict.get("width_px", 0.0)))
	material.set_shader_parameter("disp_infl_feather_px", float(infl_dict.get("feather_px", 0.0)))
	material.set_shader_parameter("disp_infl_invert", 1.0 if bool(infl_dict.get("invert", false)) else 0.0)
	var infl_custom = infl_dict.get("custom_mask", null)
	if infl_custom != null and str(infl_custom) != "":
		var infl_tex = FxAssetsScript.load_texture(str(infl_custom))
		if infl_tex is Texture2D:
			material.set_shader_parameter("disp_infl_custom_tex", infl_tex)
			material.set_shader_parameter("disp_infl_custom_loaded", 1.0)
		elif bool(infl_dict.get("enabled", false)) and str(infl_dict.get("source", "")) == "CUSTOM_MASK":
			_quad_asset_errors.append("displacement.influence_mask.custom_mask: asset not loadable: %s (%s)" % [str(infl_custom), str(layer.get("layer_id", ""))])
	material.set_shader_parameter("mask_enabled", 1.0 if bool(mask.get("enabled", false)) else 0.0)
	material.set_shader_parameter("mask_source", float(_mask_source_index(str(mask.get("source", "NONE")))))
	material.set_shader_parameter("mask_region", float(_mask_region_index(str(mask.get("region", "FULL")))))
	material.set_shader_parameter("mask_space", float(_mask_space_index(str(mask.get("space", "LAYER_SPACE")))))
	material.set_shader_parameter("mask_expand_contract_px", float(mask.get("expand_contract_px", 0.0)))
	material.set_shader_parameter("mask_width_px", float(mask.get("width_px", 0.0)))
	material.set_shader_parameter("mask_feather_px", float(mask.get("feather_px", 0.0)))
	material.set_shader_parameter("mask_invert", 1.0 if bool(mask.get("invert", false)) else 0.0)
	var mask_custom = mask.get("custom_mask", null)
	if mask_custom != null and str(mask_custom) != "":
		var mask_tex = FxAssetsScript.load_texture(str(mask_custom))
		if mask_tex is Texture2D:
			material.set_shader_parameter("mask_custom_tex", mask_tex)
			material.set_shader_parameter("mask_custom_loaded", 1.0)
		elif bool(mask.get("enabled", false)) and str(mask.get("source", "")) == "CUSTOM_MASK":
			_quad_asset_errors.append("mask.custom_mask: asset not loadable: %s (%s)" % [str(mask_custom), str(layer.get("layer_id", ""))])
	# R3 §12: renderer-side finite gate — a non-finite opacity must never reach
	# the shader (the validator rejects such docs at apply time; this is the
	# last line of defense for any render path that bypasses validation).
	var op := float(layer.get("opacity", 1.0))
	material.set_shader_parameter("layer_opacity", op if is_finite(op) else 1.0)
	material.set_shader_parameter("blend_mode", float(BLEND_INDEX.get(str(layer.get("blend_mode", "NORMAL")), 0)))
	material.set_shader_parameter("debug_view_mode", float(DEBUG_VIEWS.find(_debug_view)))
	_set_fx_uniforms(material, layer.get("fx", {}), layer.get("motion", {}), str(layer.get("layer_id", "")))
	quad.material = material
	# TM-03: envelope base amounts + motion ride on the quad so set_time can
	# recompute the live multiplier every frame.
	var quad_fx: Dictionary = layer.get("fx", {}) if layer.get("fx", {}) is Dictionary else {}
	quad.set_meta("fx_amount_base", {
		"dither": float(quad_fx.get("dither", 0.0)),
		"fringe": float(quad_fx.get("fringe", 0.0)),
		"flow": float(quad_fx.get("flow", quad_fx.get("fx_flow", 0.0))),
		"rgb": float(quad_fx.get("rgb", 0.0)),
	})
	quad.set_meta("fx_motion", (layer.get("motion", {}) as Dictionary).duplicate(true) if layer.get("motion", {}) is Dictionary else {})
	return quad

func _set_fx_uniforms(material: ShaderMaterial, fx, motion := {}, layer_id := "") -> void:
	var f_raw: Dictionary = fx if fx is Dictionary else {}
	# R3 §23 hardening: sanitize once. A hostile non-numeric value in ANY fx field
	# used to abort float() mid-way and silently drop every uniform after it.
	# Structured/bool/null/non-numeric-string values fall back to shader defaults.
	var f: Dictionary = {}
	for key in f_raw.keys():
		var v = f_raw[key]
		if v == null or v is Dictionary:
			continue
		if v is Array:
			# Only size-4 finite colour vectors (fringe_color_a/b, palette_source
			# _color) are legitimate fx arrays; anything else (wrong size, junk
			# elements) is hostile and falls back to the shader default.
			var arr: Array = v
			var ok_arr := arr.size() == 4
			if ok_arr:
				for item in arr:
					if not (item is float or item is int) or not is_finite(float(item)):
						ok_arr = false
						break
			if ok_arr:
				f[key] = v
			continue
		if v is String and not (v as String).strip_edges().is_valid_float():
			# UI-07/08: legitimate asset-path strings (treatment/edge mask)
			# must survive sanitizing — the texture loader below resolves
			# them. Gold operator/time enums are canonical authoring data;
			# preserve only the finite enum vocabulary rather than allowing
			# arbitrary strings through the numeric uniform surface.
			var string_key := str(key)
			var allowed_enum := string_key in ["operator", "operator_secondary", "operator_time_source", "time_source"]
			if not allowed_enum and string_key != "treatment_mask_path" and string_key != "edge_mask_path":
				continue
		if (v is float or v is int) and not is_finite(float(v)):
			continue
		# NOTE: bools are legitimate fx values (pure_continuous, effect_mask_*)
		# and are kept; only hostile containers/non-finite/non-numeric junk drops.
		f[key] = v
	var size: float = float(f.get("size", f.get("fx_size", 1.0)))
	var intensity: float = float(f.get("intensity", f.get("fx_intensity", 1.0)))
	var pattern: float = float(f.get("pattern_scale", 1.0))
	var dither_amount: float = float(f.get("dither", 0.0)) * _motion_multiplier(motion, "dither")
	var fringe_amount: float = float(f.get("fringe", 0.0)) * _motion_multiplier(motion, "fringe")
	var flow_amount: float = float(f.get("flow", f.get("fx_flow", 0.0))) * _motion_multiplier(motion, "flow")
	var rgb_amount: float = float(f.get("rgb", 0.0)) * _motion_multiplier(motion, "rgb")
	var edge_width: float = float(f.get("edge_width", f.get("fx_edge_width", 3.0)))
	var rgb_shift: float = float(f.get("rgb_shift_amount", f.get("rgb_shift", 6.0)))
	var colors_a = f.get("fringe_color_a", f.get("col_a", [0.25, 0.95, 1.0, 1.0]))
	var colors_b = f.get("fringe_color_b", f.get("col_b", [1.0, 0.4, 0.85, 1.0]))
	var values: Dictionary = {
		"fx_pure_continuous": 1.0 if bool(f.get("pure_continuous", false)) else 0.0,
		"pure_continuous": 1.0 if bool(f.get("pure_continuous", false)) else 0.0,
		"fx_size": size, "fx_intensity": intensity, "fx_pattern_scale": pattern,
		"fx_fringe": fringe_amount, "fx_rgb": rgb_amount, "fx_dither": dither_amount,
		"fx_edge_width": edge_width, "fx_edge_alpha_weight": float(f.get("edge_alpha_weight", 1.2)),
		"fx_edge_luma_weight": float(f.get("edge_luma_weight", 1.0)), "fx_edge_threshold": float(f.get("edge_threshold", 0.08)),
		"fx_edge_source_mode": float(f.get("edge_source_mode", 2.0)), "fx_wind_reach": float(f.get("wind_reach", 32.0)),
		"fx_wind_trail": float(f.get("wind_trail", 0.35)), "fx_wind_cutoff": float(f.get("wind_cutoff", 0.22)),
		"fx_split_separation": float(f.get("split_separation", 10.0)), "fx_signal_gain": float(f.get("signal_gain", 1.35)),
		"fx_color_blur": float(f.get("color_blur", 0.0)), "fx_signal_softness": float(f.get("signal_softness", 0.08)),
		"fx_signal_posterize": float(f.get("signal_posterize", 0.0)), "fx_coverage_mode": float(f.get("fringe_coverage_mode", 0.0)),
		"fx_coverage_threshold": float(f.get("fringe_coverage_threshold", 0.12)), "fx_coverage_gain": float(f.get("fringe_coverage_gain", 1.0)),
		"fx_coverage_bayer_level": float(f.get("fringe_bayer_level", 2.0)), "fx_coverage_pixel": float(f.get("fringe_pixel", 2.0)),
		"fx_fringe_color_a": _color(colors_a), "fx_fringe_color_b": _color(colors_b),
		"fx_fringe_bleed": float(f.get("fringe_bleed", 0.65)), "fx_fringe_blend": float(f.get("fringe_blend_mode", f.get("fringe_blend", 0.0))),
		"fx_rgb_shift_px": rgb_shift, "fx_rgb_angle": float(f.get("rgb_shift_angle", f.get("rgb_angle", 0.0))),
		"fx_rgb_alpha": float(f.get("rgb_shift_alpha", f.get("rgb_alpha", 0.0))),
		"fx_dither_black": float(f.get("dither_black_point", f.get("dither_black", 0.0))),
		"fx_dither_white": float(f.get("dither_white_point", f.get("dither_white", 1.0))), "fx_dither_gamma": float(f.get("dither_gamma", f.get("fx_dither_gamma", 1.35))),
		"fx_dither_contrast": float(f.get("dither_contrast", f.get("fx_dither_contrast", 1.6))), "fx_dither_brightness": float(f.get("dither_brightness", f.get("fx_dither_brightness", 0.0))),
		"fx_dither_mode": float(f.get("dither_mode", f.get("fx_dither_mode", 1.0))), "fx_dither_bayer_level": float(f.get("dither_bayer_level", 2.0)),
		"fx_dither_levels": float(f.get("dither_levels", 6.0)), "fx_dither_pixel": float(f.get("dither_pixel", 2.0)), "fx_dither_space": float(f.get("dither_space", 1.0)),
		# The certified legacy names are also written because the v0.3 helper math
		# intentionally retains its names and stage order.
		"pattern_scale": pattern,
		"fx_flow": flow_amount,
		"edge_width": edge_width, "edge_alpha_weight": float(f.get("edge_alpha_weight", 1.2)), "edge_luma_weight": float(f.get("edge_luma_weight", 1.0)), "edge_threshold": float(f.get("edge_threshold", 0.08)),
		"wind_reach": float(f.get("wind_reach", 32.0)), "wind_trail": float(f.get("wind_trail", 0.35)), "wind_cutoff": float(f.get("wind_cutoff", 0.22)), "split_separation": float(f.get("split_separation", 10.0)),
		"signal_gain": float(f.get("signal_gain", 1.35)), "color_blur": float(f.get("color_blur", 0.0)), "signal_softness": float(f.get("signal_softness", 0.08)), "signal_posterize": float(f.get("signal_posterize", 0.0)),
		"fringe_coverage_mode": float(f.get("fringe_coverage_mode", 0.0)), "fringe_coverage_threshold": float(f.get("fringe_coverage_threshold", 0.12)), "fringe_coverage_gain": float(f.get("fringe_coverage_gain", 1.0)), "fringe_bayer_level": float(f.get("fringe_bayer_level", 2.0)), "fringe_pixel": float(f.get("fringe_pixel", 2.0)), "fringe_space": float(f.get("fringe_space", 1.0)),
		"fringe_color_a": _color(colors_a), "fringe_color_b": _color(colors_b), "fringe_bleed": float(f.get("fringe_bleed", 0.65)), "fringe_blend_mode": float(f.get("fringe_blend_mode", 0.0)),
		"rgb_shift_amount": rgb_shift, "rgb_shift_angle": float(f.get("rgb_shift_angle", 0.0)), "rgb_shift_units": float(f.get("rgb_shift_units", 1.0)), "rgb_shift_alpha": float(f.get("rgb_shift_alpha", 0.0)),
		"dither_threshold": float(f.get("dither_threshold", 0.75)), "dither_black_point": float(f.get("dither_black_point", 0.0)), "dither_white_point": float(f.get("dither_white_point", 1.0)), "dither_gamma": float(f.get("dither_gamma", 1.35)), "dither_contrast": float(f.get("dither_contrast", 1.6)), "dither_brightness": float(f.get("dither_brightness", 0.0)), "dither_mode": float(f.get("dither_mode", 1.0)), "dither_bayer_level": float(f.get("dither_bayer_level", 2.0)), "dither_pixel": float(f.get("dither_pixel", 2.0)), "dither_levels": float(f.get("dither_levels", 6.0)), "dither_space": float(f.get("dither_space", 1.0)),
		"base_mode": float(f.get("base_mode", 0.0)), "base_opacity": float(f.get("base_opacity", 1.0)), "base_grade_amount": float(f.get("base_grade_amount", 0.0)), "grade_black_point": float(f.get("grade_black_point", 0.0)), "grade_white_point": float(f.get("grade_white_point", 1.0)), "grade_gamma": float(f.get("grade_gamma", 1.0)), "grade_contrast": float(f.get("grade_contrast", 1.0)), "grade_brightness": float(f.get("grade_brightness", 0.0)), "grade_saturation": float(f.get("grade_saturation", 1.0)),
		"source_pixel_size": float(f.get("source_pixel_size", 0.0)), "source_pixel_units": float(f.get("source_pixel_units", 1.0)), "mono_threshold": float(f.get("mono_threshold", 0.75)), "mono_mode": float(f.get("mono_mode", 1.0)), "mono_bayer_level": float(f.get("mono_bayer_level", 2.0)), "mono_pixel": float(f.get("mono_pixel", 2.0)), "mono_space": float(f.get("mono_space", 1.0)),
		"flow_strength": float(f.get("flow_strength", 12.0)), "flow_center_x": float(f.get("flow_center_x", 0.5)), "flow_center_y": float(f.get("flow_center_y", 0.5)), "wind_displace": float(f.get("wind_displace", 1.0)),
		"driver_mode": float(f.get("driver_mode", 0.0)), "driver_sampling_mode": float(f.get("driver_sampling_mode", 0.0)), "driver_pixel_size": float(f.get("driver_pixel_size", 2.0)),
		"FIELD_STRENGTH": float(f.get("FIELD_STRENGTH", 0.42)), "FIELD_SPEED": float(f.get("FIELD_SPEED", 0.55)), "OUTWARDNESS": float(f.get("OUTWARDNESS", 0.55)), "FIELD_BREAKUP": float(f.get("FIELD_BREAKUP", 0.85)), "COORD_NUDGE": float(f.get("COORD_NUDGE", 0.18)), "FIELD_SIZE": float(f.get("FIELD_SIZE", 1.0)), "FIELD_CENTER": Vector2(float(f.get("FIELD_CENTER_X", 1.25)), float(f.get("FIELD_CENTER_Y", 1.45))),
		"LEGACY_SCALE": float(f.get("LEGACY_SCALE", 5.0)), "LEGACY_SPEED": float(f.get("LEGACY_SPEED", 0.3)), "LEGACY_RADIAL": float(f.get("LEGACY_RADIAL", 0.45)), "DRIVER_CENTER": Vector2(float(f.get("DRIVER_CENTER_X", 1.5)), float(f.get("DRIVER_CENTER_Y", 1.5))), "DRIVER_SCALE": float(f.get("DRIVER_SCALE", 1.0)), "DRIVER_STRETCH": float(f.get("DRIVER_STRETCH", 0.0)), "DRIVER_ANGLE": float(f.get("DRIVER_ANGLE", 0.0)), "DRIVER_SPEED": float(f.get("DRIVER_SPEED", 1.0)), "DRIVER_DETAIL": float(f.get("DRIVER_DETAIL", 0.5)), "DRIVER_FLOW": float(f.get("DRIVER_FLOW", 0.5)),
		"rgb_gradient": float(f.get("rgb_gradient", 0.0)), "rgb_gradient_balance": float(f.get("rgb_gradient_balance", 0.0)), "rgb_gradient_contrast": float(f.get("rgb_gradient_contrast", 1.0)), "geometry_units": float(f.get("geometry_units", 1.0)), "temporal_hold": float(f.get("temporal_hold", 0.0)),
		"effect_mask_enabled": 1.0 if bool(f.get("effect_mask_enabled", false)) else 0.0, "effect_mask_invert": 1.0 if bool(f.get("effect_mask_invert", false)) else 0.0, "effect_mask_base": 1.0 if bool(f.get("effect_mask_base", false)) else 0.0, "effect_mask_threshold": float(f.get("effect_mask_threshold", 0.5)), "effect_mask_softness": float(f.get("effect_mask_softness", 0.10)),
		"fx_time_source": 1.0 if str(f.get("time_source", "PRESENTATION_TIME")) == "FREE_RUN" else 0.0,
		"gold_operator_mode": float(_local_operator_index(str(f.get("operator", "NONE")))),
		"gold_operator_strength": clampf(float(f.get("operator_strength", 0.0)), 0.0, 1.0),
		"gold_operator_scale": maxf(float(f.get("operator_scale", 1.0)), 0.25),
		"gold_operator_speed": maxf(float(f.get("operator_speed", 1.0)), 0.0),
		"gold_operator_threshold": clampf(float(f.get("operator_threshold", 0.5)), 0.0, 1.0),
		"gold_operator_softness": clampf(float(f.get("operator_softness", 0.1)), 0.001, 1.0),
		"gold_operator_axis_x": float(f.get("operator_axis_x", 1.0)),
		"gold_operator_axis_y": float(f.get("operator_axis_y", 0.0)),
		"gold_operator_pattern_mode": clampf(float(f.get("operator_pattern_mode", 0.0)), 0.0, 1.0),
		"gold_operator_pattern_family": clampf(float(f.get("operator_pattern_family", 0.0)), 0.0, 2.0),
		"gold_operator_distortion": clampf(float(f.get("operator_distortion", 0.0)), 0.0, 1.0),
		"gold_operator_time_source": 1.0 if str(f.get("operator_time_source", f.get("time_source", "PRESENTATION_TIME"))) == "FREE_RUN" else 0.0,
		"gold_operator_color_a": _color(f.get("operator_color_a", [0.25, 0.95, 1.0, 1.0])),
		"gold_operator_color_b": _color(f.get("operator_color_b", [1.0, 0.35, 0.82, 1.0])),
		"palette_strategy": float(f.get("palette_strategy", 0.0)), "palette_hue_offset": float(f.get("palette_hue_offset", 0.0)), "palette_saturation": float(f.get("palette_saturation", 1.0)), "palette_value": float(f.get("palette_value", 1.0)),
		"palette_lock_a": 1.0 if bool(f.get("palette_lock_a", false)) else 0.0, "palette_lock_b": 1.0 if bool(f.get("palette_lock_b", false)) else 0.0,
		"palette_swap": 1.0 if bool(f.get("palette_swap", false)) else 0.0, "palette_source_color": _vec3_color(f.get("palette_source_color", [0.5, 0.5, 0.5])),
	}
	for key in values.keys():
		material.set_shader_parameter(str(key), values[key])
	var edge_path: String = str(f.get("edge_mask_path", ""))
	var treatment_path: String = str(f.get("treatment_mask_path", ""))
	if edge_path != "":
		# MK-02: the custom edge source is not wired to any live shader path.
		var edge_tex = load(edge_path)
		if edge_tex is Texture2D:
			material.set_shader_parameter("custom_edge_mask_tex", edge_tex)
			material.set_shader_parameter("custom_edge_mask_loaded", 1.0)
		_quad_asset_errors.append("fx.edge_mask_path: unsupported — custom edge source is not wired (%s)" % layer_id)
	if treatment_path != "":
		var treatment_tex = FxAssetsScript.load_texture(treatment_path)
		if treatment_tex is Texture2D:
			material.set_shader_parameter("treatment_mask_tex", treatment_tex)
			material.set_shader_parameter("treatment_mask_loaded", 1.0)
		elif bool(f.get("effect_mask_enabled", false)):
			_quad_asset_errors.append("fx.treatment_mask_path: asset not loadable: %s (%s)" % [treatment_path, layer_id])

# UI-03 quality (event authority): named flow events with deterministic
# presentation times. Set by whoever owns the presentation (the lab shell
# passes its event marks; game integration supplies its own). Unknown
# non-manual anchors fall back to fixed anchor_time (documented, same as the
# historical behavior for every non-manual anchor).
var _event_marks: Dictionary = {}

func set_event_marks(marks: Dictionary) -> void:
	_event_marks = marks.duplicate()

func event_marks() -> Dictionary:
	return _event_marks.duplicate()

func _motion_multiplier(motion, domain: String) -> float:
	if not (motion is Dictionary) or (motion as Dictionary).is_empty():
		return 1.0
	var m: Dictionary = motion
	var enabled: Dictionary = m.get("enabled", {}) if m.get("enabled") is Dictionary else {}
	if not bool(enabled.get(domain, false)):
		return 1.0
	var tracks: Dictionary = m.get("tracks", {}) if m.get("tracks") is Dictionary else {}
	var track: Dictionary = tracks.get(domain, {}) if tracks.get(domain, {}) is Dictionary else {}
	# Researcher B: no unknown -> fixed footgun. manual runs from a trigger
	# epoch, fixed means anchor_time, known events mean mark + offset, and
	# anything else is INVALID and never fires (typos must not silently work).
	var anchor := str(track.get("anchor", "manual"))
	var start := float(track.get("anchor_time", 0.0))
	if anchor == "manual":
		start = float(_manual_epochs.get(domain, 0.0))
	elif anchor == "fixed":
		pass
	elif _event_marks.has(anchor):
		start = float(_event_marks[anchor]) + float(track.get("anchor_time", 0.0))
	else:
		return 0.0
	var elapsed: float = _last_time - start - float(track.get("delay", 0.0))
	if elapsed < 0.0:
		return 0.0
	var attack: float = maxf(float(track.get("attack", 0.1)), 0.001)
	var hold: float = maxf(float(track.get("hold", 0.0)), 0.0)
	var release: float = maxf(float(track.get("release", 0.25)), 0.001)
	if elapsed < attack:
		return _ease_motion(elapsed / attack, str(track.get("attack_curve", "cubic_out")))
	if elapsed < attack + hold:
		return 1.0
	if elapsed < attack + hold + release:
		var p: float = _ease_motion((elapsed - attack - hold) / release, str(track.get("release_curve", "sine_in_out")))
		return lerpf(1.0, clampf(float(track.get("sustain", 0.0)), 0.0, 1.0), p)
	return clampf(float(track.get("sustain", 0.0)), 0.0, 1.0)

func _ease_motion(p: float, curve: String) -> float:
	var t: float = clampf(p, 0.0, 1.0)
	match curve:
		"linear": return t
		"cubic_in": return t * t * t
		"back_out":
			var c1: float = 1.70158
			var c3: float = c1 + 1.0
			return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
		"sine_in_out": return 0.5 - 0.5 * cos(PI * t)
		_: return 1.0 - pow(1.0 - t, 3.0)


func _color(value) -> Color:
	if value is Color:
		return value
	if value is Array and (value as Array).size() >= 3:
		var arr: Array = value
		var alpha := float(arr[3]) if arr.size() > 3 else 1.0
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), alpha)
	return Color.WHITE

func _vec3_color(value) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var arr: Array = value
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3(0.5, 0.5, 0.5)

func _place_quad(root: Node, canonical: TextureRect, plane: String, quad: Control, below_idx: int, overlay_count: int, plane_anchors: Dictionary) -> Dictionary:
	var parent: Node = canonical.get_parent()
	var index := 0
	match plane:
		"TARGET_UNDERLAY", "TARGET_SOURCE":
			index = below_idx
			below_idx += 1
		"TARGET_OVERLAY":
			index = canonical.get_index() + 1 + overlay_count
			overlay_count += 1
		"COMPOSITION_BACKGROUND":
			parent = root
			if not plane_anchors.has(plane):
				plane_anchors[plane] = _background_anchor_index(root)
			index = int(plane_anchors[plane])
			plane_anchors[plane] = index + 1
		"COMPOSITION_FOREGROUND":
			parent = root
			if not plane_anchors.has(plane):
				plane_anchors[plane] = _foreground_anchor_index(root)
			index = int(plane_anchors[plane])
			plane_anchors[plane] = index + 1
		_:
			index = below_idx
			below_idx += 1
	parent.add_child(quad)
	_fit_quad_global(quad, parent)
	parent.move_child(quad, clampi(index, 0, parent.get_child_count() - 1))
	return {"below_idx": below_idx, "overlay_count": overlay_count}

func _background_anchor_index(root: Node) -> int:
	var side_fields := root.get_node_or_null("SideFields")
	if side_fields != null:
		return side_fields.get_index() + 1
	var stage := root.get_node_or_null("Stage")
	if stage != null:
		return stage.get_index() + 1
	return 0

func _final_anchor_index(root: Node) -> int:
	# Scene-wide passes act on the scene (stage, side fields, fighters) and sit
	# BELOW the presentation graphics: the VS mark, its shadow, the name plates
	# and names draw after the pass, so the captured frame never contains them
	# and no warp can distort or smear them. Layering, not masking.
	var mark := root.get_node_or_null("VsMark")
	if mark != null:
		return mark.get_index()
	return _foreground_anchor_index(root)

func _foreground_anchor_index(root: Node) -> int:
	for anchor in ["ImpactFlash", "TransitionCover"]:
		var node := root.get_node_or_null(anchor)
		if node != null:
			return node.get_index()
	return root.get_child_count()

func _update_stack(target_key: String) -> void:
	# Mirror per-frame state (entry animations, screen visibility, screen-side
	# mirroring) from the canonical node onto its quads so the stack renders
	# exactly like the canonical node would.
	if not _stacks.has(target_key):
		return
	var entry: Dictionary = _stacks[target_key]
	var canonical = entry.get("canonical")
	if not is_instance_valid(canonical):
		return
	for quad_entry in _all_quad_entries(entry):
		var quad = quad_entry["node"]
		if not is_instance_valid(quad):
			continue
		quad.visible = canonical.visible
		quad.modulate = canonical.modulate
		if quad.material is ShaderMaterial:
			# Canonical flip (screen-side mirroring) XOR layer flip.
			var canonical_flip_x := canonical is TextureRect and (canonical as TextureRect).flip_h
			var canonical_flip_y := canonical is TextureRect and (canonical as TextureRect).flip_v
			var layer_flip_x := bool(quad_entry.get("layer_flip_x", false))
			var layer_flip_y := bool(quad_entry.get("layer_flip_y", false))
			var material := quad.material as ShaderMaterial
			material.set_shader_parameter("flip_x", 1.0 if canonical_flip_x != layer_flip_x else 0.0)
			material.set_shader_parameter("flip_y", 1.0 if canonical_flip_y != layer_flip_y else 0.0)
			# SP-05: the sampled source rect is LIVE canonical geometry, not
			# the placement-time snapshot — styled quads follow position /
			# scale / rotation animation every frame.
			if canonical is TextureRect:
				var live: Rect2 = FxTargetsScript.presentation_rect(canonical)
				material.set_shader_parameter("source_rect", [live.position.x, live.position.y, live.size.x, live.size.y])

# ---------------------------------------------------------------- enum helpers

func _driver_index(driver: String) -> int:
	return ["NOISE", "DIRECTIONAL", "WAVE", "CELLULAR", "FRINGE_DRIVER", "CUSTOM_TEXTURE"].find(driver)

func _edge_mode_index(mode: String) -> int:
	return ["TRANSPARENT", "CLAMP", "MIRROR", "REPEAT"].find(mode)

func _mask_source_index(source: String) -> int:
	return ["NONE", "ORIGINAL_SOURCE_ALPHA", "POST_DISPLACEMENT_ALPHA", "CUSTOM_MASK"].find(source)

func _mask_region_index(region: String) -> int:
	return ["FULL", "EDGE_BAND", "OUTER_BAND", "INNER_BAND"].find(region)

func _mask_space_index(space: String) -> int:
	return ["SOURCE_SPACE", "LAYER_SPACE", "PRESENTATION_SPACE"].find(space)

func _local_operator_index(operator_id: String) -> int:
	return ["NONE", "noise_erosion_border", "pixel_sort_smear"].find(operator_id)

func _final_operator_index(operator_id: String) -> int:
	return ["NONE", "speedlines_field", "pattern_transition", "vacuum_burst"].find(operator_id)

func _vec2(value) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO

func _push_final_time() -> void:
	for final_pass in _final_composite.get("passes", []):
		for mask_key in ["scope_viewport", "primary_scope_viewport"]:
			var scope_viewport = (final_pass as Dictionary).get(mask_key, null)
			if is_instance_valid(scope_viewport):
				_sync_scope_mask(scope_viewport)
		var node = (final_pass as Dictionary).get("node", null)
		if is_instance_valid(node) and node.material is ShaderMaterial:
			var material: ShaderMaterial = node.material
			material.set_shader_parameter("presentation_time", _last_time)
			material.set_shader_parameter("free_run_time", _last_free)
