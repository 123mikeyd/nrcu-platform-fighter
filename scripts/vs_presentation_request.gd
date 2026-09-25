extends RefCounted
# VsPresentationRequest — the normalized multiplayer presentation input
# (v1.3 contract: "Consume a normalized ordered list of 2-4 active fighter
# records"; schema/match_presentation_contract.json owns routing and
# normalization, schema/multiplayer_layouts_1280x720.json the geometry,
# schema/roster_optical_facing_profiles.json the orientation,
# schema/multiplayer_motion_timing.json the motion).
#
# WHY THIS FILE EXISTS
#   The 1v1 screen contract is start(left_fighter_id, right_fighter_id, stage_id):
#   exactly two fighters, two hard-coded visual slots. The multiplayer follow-up
#   needs an ordered 2-4 record input with player identity preserved, a route
#   decision, a visual-slot assignment and a per-fighter orientation decision.
#   All of that is PURE DATA AND RULES here: no scene, no node, no screen. The
#   overlay (scripts/vs_screen.gd) renders the plan; the adapter owns the launch.
#
# WHAT THE RULES ARE (and where they came from)
#   routing      schema/match_presentation_contract.json "normalization": 2
#                no-team -> the unchanged DUEL_1V1 renderer, 3 -> FFA_3,
#                4 -> FFA_4, team splits -> TEAM_2V1/TEAM_2V2/TEAM_3V1 with
#                "mirror group sides as needed" (the mirrored 1V2/1V3 variants
#                are the same layout mirrored: x' = 1280 - x - w, side flipped).
#   assignment   schema/.../assignment_policy. The optimizer is a documented,
#                deterministic cost rule (no fighter id is ever named):
#                  FFA_3  the CENTER takes the fighter with the lowest
#                         center_suitability (the "lowest center penalty");
#                         the remaining two keep their player order (earlier
#                         player -> left).
#                  FFA_4  players are ranked by center_suitability: the two
#                         extremes take the outer slots, the two middle ones the
#                         inner slots; the higher-ranked middle goes left, and
#                         the outer pair keeps the player order (earlier player
#                         -> left outer).
#                  teams  team membership is fixed; inside a team the members
#                         are ordered by primary_aspect descending into the
#                         team's slots from the outermost inwards (the widest
#                         silhouette takes the most outer slot).
#                Every rule preserves P1-P4: the player label travels with the
#                fighter record, never with the visual slot.
#   orientation  schema/roster_optical_facing_profiles.json: a LEFT visual slot
#                uses the original bake only when canonical_inward_side=left,
#                a RIGHT slot only when it is right; anything else is mirrored
#                horizontally. The CENTER slot keeps the original bake. This is
#                the GGB hard regression: the current original GGB bake must
#                never appear unmirrored in a left slot.
#
# EXTERNAL CONTRACT
#   from_config(config, kind_human/cpu/empty constants) -> Array[record]
#   route(records, teams_enabled) -> route id ("" = unsupported/bypass)
#   family_of(route) -> the multiplayer_layouts family key ("" for the duel)
#   mirrored(route) -> true when the team layout is the mirrored variant
#   plan(records, stage_id, teams_enabled) -> the full render plan
#   layout_spec()/facing_spec()/timing_spec()/contract_spec()

const LAYOUT_JSON := "res://assets/vs/schema/multiplayer_layouts_1280x720.json"
const FACING_JSON := "res://assets/vs/schema/roster_optical_facing_profiles.json"
const TIMING_JSON := "res://assets/vs/schema/multiplayer_motion_timing.json"
const CONTRACT_JSON := "res://assets/vs/schema/match_presentation_contract.json"
const ORIENTATION_CASES_JSON := "res://assets/vs/schema/orientation_test_cases.json"

const StateScript = preload("res://scripts/match_flow_state.gd")

# Route ids. The duel keeps the 1v1 renderer and is named after the 1v1
# integration contract's match class.
const ROUTE_DUEL := "DUEL_1V1"
const ROUTE_FFA_3 := "FFA_3"
const ROUTE_FFA_4 := "FFA_4"
const ROUTE_TEAM_2V2 := "TEAM_2V2"
const ROUTE_TEAM_2V1 := "TEAM_2V1"
const ROUTE_TEAM_1V2 := "TEAM_1V2"
const ROUTE_TEAM_3V1 := "TEAM_3V1"
const ROUTE_TEAM_1V3 := "TEAM_1V3"

const TEAM_MIRROR := {
	ROUTE_TEAM_2V1: ROUTE_TEAM_1V2,
	ROUTE_TEAM_1V2: ROUTE_TEAM_2V1,
	ROUTE_TEAM_3V1: ROUTE_TEAM_1V3,
	ROUTE_TEAM_1V3: ROUTE_TEAM_3V1,
}

# Player station vocabulary ("P1".."P4") — the label that must survive the
# visual permutation.
const SLOT_LABELS := ["P1", "P2", "P3", "P4"]

# Slot sides used by roster_optical_facing_profiles.json.
const SIDE_LEFT := "left"
const SIDE_RIGHT := "right"
const SIDE_CENTER := "center"

const TEAM_A := 0
const TEAM_B := 1

# The schema's stagger_rule states the hard ceiling in words
# (multiplayer_motion_timing.json: "maximum added span <= 0.06s"); it is the
# one number the rule cannot be read out of a field for, so it is named here.
const MAX_STAGGER_SPAN := 0.06

# --- spec reads -------------------------------------------------------------

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []


static func layout_spec() -> Dictionary:
	return read_json(LAYOUT_JSON)


static func facing_spec() -> Dictionary:
	return read_json(FACING_JSON)


static func timing_spec() -> Dictionary:
	return read_json(TIMING_JSON)


static func contract_spec() -> Dictionary:
	return read_json(CONTRACT_JSON)


static func orientation_cases() -> Array:
	return read_json_array(ORIENTATION_CASES_JSON)


static func families() -> Dictionary:
	var families_value = layout_spec().get("families", {})
	return families_value if families_value is Dictionary else {}


static func has_family(family: String) -> bool:
	return families().has(family)


static func supports_fighter(fighter_id: String) -> bool:
	return facing_spec().has(fighter_id)


static func center_suitability(fighter_id: String) -> float:
	return float((facing_spec().get(fighter_id, {}) as Dictionary).get("center_suitability", 0.0))


static func primary_aspect(fighter_id: String) -> float:
	# The authored optical aspect of the fighter's PRIMARY bake. The reference
	# boards carry the same numbers in original_dimensions; primary_aspect is
	# the pre-divided value, kept here so the ordering rule reads one number.
	var entry: Dictionary = facing_spec().get(fighter_id, {})
	if entry.has("primary_aspect"):
		return float(entry["primary_aspect"])
	var dims: Array = entry.get("original_dimensions", [])
	if dims.size() == 2 and float(dims[1]) != 0.0:
		return float(dims[0]) / float(dims[1])
	return 1.0


static func canonical_inward_side(fighter_id: String) -> String:
	return str((facing_spec().get(fighter_id, {}) as Dictionary).get("canonical_inward_side", SIDE_LEFT))


# --- records ----------------------------------------------------------------

static func record(slot_index: int, fighter_id: String, team_id: int, kind: int, palette_index: int = 0) -> Dictionary:
	return {
		"slot_id": SLOT_LABELS[slot_index] if slot_index >= 0 and slot_index < SLOT_LABELS.size() else "P%d" % (slot_index + 1),
		"index": slot_index,
		"fighter_id": str(fighter_id),
		"team_id": int(team_id),
		"kind": int(kind),
		"palette_index": int(palette_index),
	}


static func from_config(config) -> Array:
	# The launch config's slots() are frozen dictionaries
	# ({index, kind, fighter_id, difficulty, team_id, input_source,
	#   palette_index}); EMPTY stations are removed ONLY for presentation
	# routing, the original slot identity stays attached (contract: "remove
	# Empty slots", "preserve slot_id/player identity").
	var out: Array = []
	if config == null or not config.is_valid():
		return out
	for entry in config.slots():
		var kind := int(entry.get("kind", StateScript.Kind.EMPTY))
		if kind == StateScript.Kind.EMPTY:
			continue
		var fighter_id := str(entry.get("fighter_id", ""))
		if fighter_id == "":
			continue
		out.append(record(int(entry.get("index", out.size())), fighter_id,
			int(entry.get("team_id", StateScript.NO_TEAM)), kind,
			int(entry.get("palette_index", 0))))
	return out


static func teams_enabled(config, records: Array) -> bool:
	# The contract's `teams_enabled` input: the match is in Team mode AND every
	# active fighter carries a real team id. A Team-mode launch with an unset
	# side is not representable as a team layout, so it is not treated as one.
	if config == null or not config.has_method("mode"):
		return false
	if int(config.mode()) != int(StateScript.Mode.TEAMS):
		return false
	for r in records:
		if int(r["team_id"]) != TEAM_A and int(r["team_id"]) != TEAM_B:
			return false
	return true


static func team_members(records: Array, team_id: int) -> Array:
	var out: Array = []
	for r in records:
		if int(r["team_id"]) == team_id:
			out.append(r)
	return out


# --- routing ----------------------------------------------------------------

static func route(records: Array, teams: bool) -> String:
	# "" means "not a supported multiplayer presentation": the caller keeps the
	# existing immediate match-start path.
	var count := records.size()
	if count < 2 or count > 4:
		return ""
	for r in records:
		if not supports_fighter(str(r["fighter_id"])):
			return ""
	if count == 2:
		# "route 2 no-team to existing DUEL_1V1 renderer unchanged": the
		# two-fighter match IS the duel renderer. (The approved baseline treated
		# any two active fighters as the duel case, teams mode included; the 1v1
		# renderer has no team surface, so team ids do not change it.)
		return ROUTE_DUEL
	if not teams:
		if count == 3:
			return ROUTE_FFA_3
		if count == 4:
			return ROUTE_FFA_4
		return ""
	var a := team_members(records, TEAM_A).size()
	var b := team_members(records, TEAM_B).size()
	if count == 3:
		if (a == 2 and b == 1) or (a == 1 and b == 2):
			# "route 3 team to TEAM_2V1; mirror group sides as needed": T0/Team A
			# owns the authored side (left); when Team A is the solo the layout
			# is the mirrored 1V2 variant (solo left, pair right).
			return ROUTE_TEAM_2V1 if a > b else ROUTE_TEAM_1V2
		return ""
	if count == 4:
		if a == 2 and b == 2:
			return ROUTE_TEAM_2V2
		if a == 3 and b == 1:
			return ROUTE_TEAM_3V1
		if a == 1 and b == 3:
			return ROUTE_TEAM_1V3
		return ""
	return ""


static func family_of(route_id: String) -> String:
	# The multiplayer_layouts_1280x720.json family key. The mirrored team
	# variants are the base family rendered mirrored.
	match route_id:
		ROUTE_FFA_3:
			return "FFA_3"
		ROUTE_FFA_4:
			return "FFA_4"
		ROUTE_TEAM_2V2:
			return "TEAM_2V2"
		ROUTE_TEAM_2V1, ROUTE_TEAM_1V2:
			return "TEAM_2V1"
		ROUTE_TEAM_3V1, ROUTE_TEAM_1V3:
			return "TEAM_3V1"
	return ""


static func is_duel(route_id: String) -> bool:
	return route_id == ROUTE_DUEL


static func is_mirrored_route(route_id: String) -> bool:
	return route_id == ROUTE_TEAM_1V2 or route_id == ROUTE_TEAM_1V3


static func mirror_route(route_id: String) -> String:
	return str(TEAM_MIRROR.get(route_id, route_id))


# --- orientation ------------------------------------------------------------

static func mirrored_for_side(fighter_id: String, side: String) -> bool:
	# Orientation authority. A visual slot that reads from the left uses the
	# original bake when the fighter is authored for the left; every other
	# combination is mirrored horizontally (contract: "use original if
	# canonical_inward_side=left; otherwise mirror horizontally"). The centre
	# slot keeps the original bake (the reference board's centre fighter reads
	# its authored direction).
	if side == SIDE_CENTER:
		return false
	return canonical_inward_side(fighter_id) != side


# --- assignment -------------------------------------------------------------

static func order_by_aspect(records: Array) -> Array:
	# Silhouette ordering: the widest primary reads best at the outermost slot.
	# Ties fall back to the player order, so the result is deterministic.
	var out := records.duplicate()
	out.sort_custom(func(x, y):
		var ax := primary_aspect(str(x["fighter_id"]))
		var ay := primary_aspect(str(y["fighter_id"]))
		if is_equal_approx(ax, ay):
			return int(x["index"]) < int(y["index"])
		return ax > ay)
	return out


static func order_by_center_rank(records: Array) -> Array:
	# Centre-penalty ranking, HIGHEST penalty first. center_suitability is the
	# authored penalty of standing in the CENTER (ggb 1.0 reads outward and
	# wants an outer slot; doge_man 0.1 reads fine in the middle) — the FFA
	# rules below are written against this one ordering. Ties fall back to the
	# player order, so the result is deterministic.
	var out := records.duplicate()
	out.sort_custom(func(x, y):
		var ax := center_suitability(str(x["fighter_id"]))
		var ay := center_suitability(str(y["fighter_id"]))
		if is_equal_approx(ax, ay):
			return int(x["index"]) < int(y["index"])
		return ax > ay)
	return out


static func order_by_player(records: Array) -> Array:
	var out := records.duplicate()
	out.sort_custom(func(x, y): return int(x["index"]) < int(y["index"]))
	return out


static func assign_ffa_3(records: Array) -> Dictionary:
	# Centre = the LOWEST centre penalty (the most centre-tolerant fighter;
	# reference board FFA_3 stress 1: ggb 1.0 left, teknium 0.4 center,
	# witcheer 0.7 right). The other two keep their player order (earlier
	# player -> left).
	var ranked := order_by_center_rank(records)
	var center = ranked[ranked.size() - 1]
	var rest := order_by_player(records.filter(func(r): return r != center))
	var out: Dictionary = {}
	out["center"] = center
	out["left"] = rest[0]
	out["right"] = rest[1]
	return out


static func assign_ffa_4(records: Array) -> Dictionary:
	# The two extremes of the centre ranking take the outer slots (where the
	# widest and the least centre-tolerant silhouettes read), the two middle
	# ones the inner slots; the higher-ranked middle goes to the left inner, and
	# the outer pair keeps the player order.
	var ranked := order_by_center_rank(records)
	var outer := order_by_player([ranked[0], ranked[3]])
	var out: Dictionary = {}
	out["left_outer"] = outer[0]
	out["right_outer"] = outer[1]
	out["left_inner"] = ranked[1]
	out["right_inner"] = ranked[2]
	return out


static func assign_teams(records: Array, family: String, mirrored_layout: bool) -> Dictionary:
	# team membership cannot change; only the visual order inside a team is
	# optimized (widest silhouette outermost).
	var slots: Dictionary = (families().get(family, {}) as Dictionary).get("slots", {})
	var out: Dictionary = {}
	# Player order inside a team: the back/outer slot (whose nameplate sits
	# highest) goes to the lower player number, so tags read P1 above P2.
	var a := order_by_player(team_members(records, TEAM_A))
	var b := order_by_player(team_members(records, TEAM_B))
	if family == "TEAM_2V2":
		var a_order := ["A_back", "A_front"]
		var b_order := ["B_back", "B_front"]
		for i in a.size():
			out[a_order[i]] = a[i]
		for i in b.size():
			out[b_order[i]] = b[i]
	elif family == "TEAM_2V1":
		# The 2-member team takes the pair slots (A_back/A_front) and the solo
		# takes B_solo. The mirrored 1V2 variant mirrors the slot GEOMETRY
		# (group sides swap: pair right, solo left), never team identity — so
		# in the mirrored layout the pair is Team B and the solo Team A.
		var pair := b if mirrored_layout else a
		var solo := a if mirrored_layout else b
		out["A_back"] = pair[0] if pair.size() > 0 else null
		out["A_front"] = pair[1] if pair.size() > 1 else null
		out["B_solo"] = solo[0] if solo.size() > 0 else null
	elif family == "TEAM_3V1":
		# Same rule for the trio variant: the 3-member team takes the trio
		# slots (A_outer/A_mid/A_inner, outermost = widest silhouette), the
		# solo takes B_solo, and the mirrored 1V3 variant swaps the group sides.
		var trio := b if mirrored_layout else a
		var solo_member := a if mirrored_layout else b
		var trio_order := ["A_outer", "A_mid", "A_inner"]
		for i in trio.size():
			out[trio_order[i]] = trio[i]
		out["B_solo"] = solo_member[0] if solo_member.size() > 0 else null
	# Drop the null placeholders (a team with fewer members than authored slots
	# cannot happen for a routed family, but never render a null record).
	for key in out.keys():
		if out[key] == null:
			out.erase(key)
	return out


static func assign(records: Array, route_id: String) -> Dictionary:
	# slot name -> record
	if route_id == ROUTE_FFA_3:
		return assign_ffa_3(records)
	if route_id == ROUTE_FFA_4:
		return assign_ffa_4(records)
	var family := family_of(route_id)
	if family == "":
		return {}
	return assign_teams(records, family, is_mirrored_route(route_id))


# --- the render plan --------------------------------------------------------

static func mirror_rect(rect: Array) -> Array:
	if rect.size() != 4:
		return rect
	return [1280.0 - float(rect[0]) - float(rect[2]), float(rect[1]), float(rect[2]), float(rect[3])]


static func flip_side(side: String) -> String:
	if side == SIDE_LEFT:
		return SIDE_RIGHT
	if side == SIDE_RIGHT:
		return SIDE_LEFT
	return side


static func slot_geometry(family: String, slot_name: String, mirrored_layout: bool) -> Dictionary:
	# The family slot's rects (primary/echo/name), side, outer flag and z. The
	# mirrored team variants transform the authored rects, never re-author them.
	var slots: Dictionary = (families().get(family, {}) as Dictionary).get("slots", {})
	var spec = slots.get(slot_name, {})
	if not (spec is Dictionary) or spec.is_empty():
		return {}
	var out := (spec as Dictionary).duplicate(true)
	if mirrored_layout:
		for key in ["primary", "echo", "name"]:
			if out.has(key):
				out[key] = mirror_rect(out[key])
		out["side"] = flip_side(str(out.get("side", SIDE_LEFT)))
	return out


static func plan(records: Array, stage_id: String, teams: bool) -> Dictionary:
	# The complete, render-ready presentation plan. `ok == false` (with a
	# reason) means the caller must keep the existing immediate path.
	var route_id := route(records, teams)
	if route_id == "":
		return {"ok": false, "reason": "unsupported_presentation_config"}
	var ordered := order_by_player(records)
	if route_id == ROUTE_DUEL:
		# The 1v1/duel case is the approved renderer: left = the earlier player.
		return {
			"ok": true,
			"route": ROUTE_DUEL,
			"family": "",
			"mirrored": false,
			"stage_id": str(stage_id),
			"teams_enabled": false,
			"fighters": ordered,
			"placements": [
				{"slot": "duel_left", "side": SIDE_LEFT, "record": ordered[0]},
				{"slot": "duel_right", "side": SIDE_RIGHT, "record": ordered[1]},
			],
		}
	var family := family_of(route_id)
	var mirrored_layout := is_mirrored_route(route_id)
	var assignment := assign(records, route_id)
	# Visual order: outermost -> innermost (the stagger and the planner both
	# read the placements in this order).
	var placements: Array = []
	for slot_name in family_slot_order(family, mirrored_layout):
		if not assignment.has(slot_name):
			continue
		var geometry := slot_geometry(family, slot_name, mirrored_layout)
		if geometry.is_empty():
			continue
		var rec: Dictionary = assignment[slot_name]
		placements.append({
			"slot": slot_name,
			"side": str(geometry.get("side", SIDE_LEFT)),
			"outer": bool(geometry.get("outer", false)),
			"z": int(geometry.get("z", 0)),
			"geometry": geometry,
			"record": rec,
			"mirror_asset": mirrored_for_side(str(rec["fighter_id"]), str(geometry.get("side", SIDE_LEFT))),
			"label": str(rec["slot_id"]),
		})
	return {
		"ok": true,
		"route": route_id,
		"family": family,
		"mirrored": mirrored_layout,
		"stage_id": str(stage_id),
		"teams_enabled": true if family.begins_with("TEAM") else false,
		"fighters": ordered,
		"placements": placements,
	}


static func family_slot_order(family: String, mirrored_layout: bool) -> Array:
	# The authored slot order of the family: outermost/back slot first, so the
	# micro-stagger reads left-to-right and z stacking follows it.
	var slots: Dictionary = (families().get(family, {}) as Dictionary).get("slots", {})
	var names: Array = slots.keys()
	names.sort_custom(func(x, y):
		var sx: Dictionary = slots[x]
		var sy: Dictionary = slots[y]
		var zx := int(sx.get("z", 0))
		var zy := int(sy.get("z", 0))
		if zx != zy:
			return zx < zy
		var side_x := str(sx.get("side", SIDE_LEFT))
		var side_y := str(sy.get("side", SIDE_LEFT))
		var cx := float((sx.get("primary", [0, 0, 0, 0]) as Array)[0])
		var cy := float((sy.get("primary", [0, 0, 0, 0]) as Array)[0])
		if side_x != side_y:
			return side_x == SIDE_LEFT
		return cx < cy)
	return names


# --- motion -----------------------------------------------------------------

static func stagger_for(family: String) -> float:
	var micro = timing_spec().get("micro_stagger", {})
	if micro is Dictionary and (micro as Dictionary).has(family):
		return float((micro as Dictionary)[family])
	return 0.0


static func stagger_offsets(count: int, step: float) -> Array:
	# "symmetrical around base start; maximum added span <= 0.06s; never
	# serialize all fighters": n fighters are placed symmetrically around the
	# authored band start, and the authored step is clamped so the ADDED SPAN
	# can never exceed the schema's hard 0.06 s ceiling (the authored 0.025 s
	# step with four slots would otherwise span 0.075 s).
	var out: Array = []
	if count <= 1 or step <= 0.0:
		for i in count:
			out.append(0.0)
		return out
	var effective := minf(step, MAX_STAGGER_SPAN / float(count - 1))
	var middle := float(count - 1) * 0.5
	for i in count:
		out.append(round((float(i) - middle) * effective * 1000.0) / 1000.0)
	return out


static func shared_bands() -> Dictionary:
	return timing_spec().get("shared", {})


static func hold_start() -> float:
	return float(shared_bands().get("hold_start", 0.88))


static func band(name: String) -> Array:
	var band_value = shared_bands().get(name, [0.0, 0.0])
	return band_value if band_value is Array and band_value.size() == 2 else [0.0, 0.0]
