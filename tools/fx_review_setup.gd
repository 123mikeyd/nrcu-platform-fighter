extends RefCounted
# Isolated review seeding through the public authoring authority, not JSON edits.
const Production = preload("res://scripts/fx_vnext/fx_production.gd")
const Drafts = preload("res://scripts/fx_vnext/fx_drafts.gd")
const Session = preload("res://scripts/fx_vnext/fx_session.gd")
const State = preload("res://scripts/match_flow_state.gd")
const Config = preload("res://scripts/match_launch_config.gd")
const SideShapes = preload("res://scripts/fx_vnext/fx_side_shapes.gd")
const SETUPS := ["CLASH_OVERDRIVE", "VACUUM_CLASH", "KINETIC_RUSH", "DISTORTION_ONLY", "PATTERN_CUT"]

static func seed(setup: String, data_dir: String, draft_dir: String) -> Dictionary:
	if not SETUPS.has(setup) or data_dir == "" or draft_dir == "":
		return {"ok": false, "errors": ["explicit isolated directories and known setup required"]}
	# Review selection is explicit and isolated: every scenario reviews the
	# canonical diagonal fields (the game layout polygons).
	var selected_shape := "CLASH_DIAGONAL_FIELDS"
	if not SideShapes.write_selection(data_dir, {"left": selected_shape, "right": selected_shape}):
		return {"ok": false, "errors": ["could not write isolated side-shape selection"]}
	var production := Production.new()
	production.data_dir = data_dir
	# Never replace artist edits on reopening a workspace.
	if FileAccess.file_exists(production.composition_path()): return production.load_composition()
	var drafts := Drafts.new()
	drafts.base_dir = draft_dir
	var session := Session.new(production, drafts)
	var context := {"target_key": "composition", "element_id": "composition", "element_role": "composition", "mode_family": "1v1", "stage_id": "debug"}
	session.open_target("composition", context, "composition||composition||||1v1|debug", "composition")
	var recipe := "KINETIC_RUSH" if setup == "DISTORTION_ONLY" else setup
	var added: Dictionary = session.add_recipe_instance(recipe, context, "artist_single")
	if not added.get("ok", false): return added
	if setup == "DISTORTION_ONLY":
		var edited: Dictionary = session.edit_recipe_macro(recipe, "artist_single", "DISTORTION", "DISTORTION")
		if not edited.get("ok", false): return edited
	var applied: Dictionary = session.apply()
	if not applied.get("ok", false): return applied
	return production.load_composition()

static func match_config(left := "ice_mage", right := "doge_man", stage := "debug"):
	var flow = State.fresh_vs()
	flow.slots[0].fighter_id = left
	flow.slots[1].fighter_id = right
	flow.stage_id = stage
	return Config.build(flow)
