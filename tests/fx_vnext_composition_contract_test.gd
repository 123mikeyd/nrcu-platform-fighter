extends SceneTree
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxCostScript := preload("res://scripts/fx_vnext/fx_cost.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_test_recipe_documents()
	_test_unknown_fx_key_is_removed_before_persistence()
	_test_fx_validation_matches_look()
	_test_fail_closed_ownership()
	_test_order_is_authored()
	_test_cost_boundary()
	print("[FX-COMPOSITION-CONTRACT] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label + (" · " + detail if detail != "" else ""))

func _test_recipe_documents() -> void:
	for recipe_id in [FxRecipesScript.KINETIC_RUSH, FxRecipesScript.PATTERN_CUT, FxRecipesScript.VACUUM_CLASH, FxRecipesScript.CLASH_OVERDRIVE]:
		var result: Dictionary = FxRecipesScript.instantiate_composition(recipe_id, "contract")
		_check(bool(result.get("ok", false)), "%s instantiates composition" % recipe_id)
		var doc: Dictionary = result.get("doc", {})
		var validation: Dictionary = FxCompositionScript.validate(doc)
		_check(bool(validation.get("ok", false)), "%s validates" % recipe_id)
		_check(not (doc.get("final_passes", []) as Array).is_empty(), "%s has ordered passes" % recipe_id)
	_check((FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {}).get("final_passes", []) as Array).size() == 3, "clash has vacuum, speedlines, and terminal identity only")
	var clash: Array = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {}).get("final_passes", [])
	_check(str(clash[0].get("operator", "")) == "vacuum_burst", "clash stage 0 vacuum")
	_check(str(clash[1].get("operator", "")) == "speedlines_field", "clash stage 1 speedlines")
	_check(str(clash[2].get("operator", "")) == "NONE", "clash stage 2 identity")
	var pattern: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.PATTERN_CUT, "contract").get("doc", {})
	_check((pattern.get("final_passes", []) as Array).size() == 2, "pattern cut retains its dedicated pattern and identity passes")
	_check(str((pattern.get("final_passes", []) as Array)[0].get("operator", "")) == "pattern_transition", "pattern cut owns pattern transition")

func _test_unknown_fx_key_is_removed_before_persistence() -> void:
	var valid: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.KINETIC_RUSH, "unknown-fx").get("doc", {})
	var forged: Dictionary = valid.duplicate(true)
	var forged_pass: Dictionary = (forged["final_passes"] as Array)[0]
	(forged_pass["fx"] as Dictionary)["unknown_fx_field"] = {"must_not": "persist"}
	var canonical: Dictionary = FxCompositionScript.materialize(forged)
	var canonical_pass: Dictionary = (canonical["final_passes"] as Array)[0]
	var canonical_fx: Dictionary = canonical_pass["fx"]
	_check(not canonical_fx.has("unknown_fx_field"), "unknown composition fx field is removed by canonical materialization")
	var validation: Dictionary = FxCompositionScript.validate(canonical)
	_check(bool(validation.get("ok", false)), "canonical composition remains valid after unknown field removal", str(validation.get("errors", [])))
	var serialized := FxCompositionScript.save_text(forged)
	_check(not serialized.contains("unknown_fx_field"), "unknown composition fx field is absent before save")
	var persisted_raw = JSON.parse_string(serialized)
	_check(persisted_raw is Dictionary, "canonical composition save is readable JSON")
	var reread: Dictionary = FxCompositionScript.materialize(persisted_raw as Dictionary)
	_check(FxLookScript.equivalent(canonical, reread), "composition canonical semantics survive save and reread")
	var runtime_layers: Array = FxCompositionScript.to_layers(reread)
	_check(runtime_layers.size() == 1, "reread composition exposes one runtime layer")
	if runtime_layers.size() == 1:
		var runtime_fx: Dictionary = (runtime_layers[0] as Dictionary).get("fx", {})
		_check(not runtime_fx.has("unknown_fx_field"), "runtime materialization rejects unknown composition fx field")
		_check(FxLookScript.equivalent(canonical_fx, runtime_fx), "runtime fx semantics match persisted canonical fx")

func _test_fx_validation_matches_look() -> void:
	var valid: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.KINETIC_RUSH, "validator").get("doc", {})
	var forged: Dictionary = valid.duplicate(true)
	((forged["final_passes"] as Array)[0]["fx"] as Dictionary)["operator_anchor"] = "UNSUPPORTED_ANCHOR"
	var composition_check: Dictionary = FxCompositionScript.validate(forged)
	var layer: Dictionary = FxCompositionScript.to_layers(forged)[0]
	var look := FxLookScript.new_look("COMPOSITION_VALIDATOR", "Composition Validator")
	(look["layers"] as Array).append(layer)
	var look_check: Dictionary = FxLookScript.validate_input(FxLookScript.materialize(look))
	_check(not bool(look_check.get("ok", false)), "FxLook rejects unsupported composition FX field", str(look_check.get("errors", [])))
	_check(not bool(composition_check.get("ok", false)), "composition uses the same FX validator", str(composition_check.get("errors", [])))

func _test_fail_closed_ownership() -> void:
	var valid: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {})
	var forged: Dictionary = valid.duplicate(true)
	(forged["final_passes"] as Array)[0]["authority"] = "PRIMARY"
	var bad_authority: Dictionary = FxCompositionScript.validate(forged)
	_check(not bool(bad_authority.get("ok", false)), "wrong authority rejected")
	forged = valid.duplicate(true)
	(forged["final_passes"] as Array)[0]["lane"] = "TARGET_LOCAL"
	var bad_lane: Dictionary = FxCompositionScript.validate(forged)
	_check(not bool(bad_lane.get("ok", false)), "wrong lane rejected")
	forged = valid.duplicate(true)
	(forged["final_passes"] as Array)[1]["pass_id"] = str((forged["final_passes"] as Array)[0].get("pass_id", ""))
	var duplicate_id: Dictionary = FxCompositionScript.validate(forged)
	_check(not bool(duplicate_id.get("ok", false)), "duplicate pass id rejected")

func _test_order_is_authored() -> void:
	var source: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {})
	var reversed: Dictionary = source.duplicate(true)
	(reversed["final_passes"] as Array).reverse()
	var original_validation: Dictionary = FxCompositionScript.validate(source)
	var reversed_validation: Dictionary = FxCompositionScript.validate(reversed)
	_check(bool(original_validation.get("ok", false)) and bool(reversed_validation.get("ok", false)), "both authored orders validate")
	_check(str((reversed["final_passes"] as Array)[0].get("operator", "")) == "NONE", "reverse preserves explicit first entry")
	_check(str((source["final_passes"] as Array)[0].get("operator", "")) == "vacuum_burst", "source preserves authored first entry")

func _test_cost_boundary() -> void:
	var doc: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {})
	var cost: Dictionary = FxCostScript.composition_cost(doc)
	_check(cost.get("errors", []).is_empty(), "composition cost validates")
	_check(int((cost.get("passes", []) as Array).size()) == 2, "only vacuum and speedlines are charged; identity is not")
	_check(float(cost.get("total", 0.0)) > 0.0, "full-frame composition cost is visible")
