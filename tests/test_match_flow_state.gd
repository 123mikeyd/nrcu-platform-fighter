extends SceneTree
# WP-0 migration step 2 test — corrective package Doc 02 §2 (MatchFlowState),
# §3 (MatchLaunchConfig) and §10.2 ("Add typed MatchFlowState + adapters"),
# pinned to the locked product rules in Doc 01 §2 (fresh VS defaults, >= 2 active
# fighters, >= 1 Human, CPU-only behind an explicit debug flag), §3 (team mode
# needs both sides; 1v1 Team A vs Team B is valid) and §4 (combat device
# ownership: P1/P2 keyboard-or-pad, P3/P4 pad only, no duplicate pad, disconnected
# pad invalidates).
#
# What it proves:
#   * the fresh-default factories produce exactly the Doc 01 §2 layout and seed
#     P1 from the entry device;
#   * the slot helpers and the ONE validation authority reject every documented
#     invalid configuration and accept every documented valid one;
#   * the adapters round-trip the CURRENT production selection state losslessly
#     (and the fields with no legacy counterpart are pinned as one-way);
#   * MatchLaunchConfig freezes a validated state and cannot be changed by later
#     state mutation or by consumers mutating what they read.
#
# The suite runs headless with no pads connected, so every device case injects
# its own availability through set_connected_pads() and no assertion depends on
# the machine's real hardware list.

const State = preload("res://scripts/match_flow_state.gd")
const LaunchConfig = preload("res://scripts/match_launch_config.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")
const Config = preload("res://scripts/match_config.gd")
const StageCatalog = preload("res://scripts/catalogs/stage_catalog.gd")
const EncounterCatalog = preload("res://scripts/catalogs/story_encounter_catalog.gd")

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_fresh_defaults()
	_entry_device_mapping()
	_slot_helpers()
	_stage_select_rules()
	_launch_rules()
	_authority_consistency()
	_legacy_adapters()
	_launch_config()
	_legacy_pins()
	print("MatchFlowState checks run: %d" % checks)
	if failures == 0:
		print("PASS: MatchFlowState defaults, one validation authority, legacy adapters and the MatchLaunchConfig snapshot")
	quit(1 if failures else 0)

# --- shared fixtures -------------------------------------------------------

func _vs_state():
	# Baseline player-facing VS: P1 Human / Teknium / Keyboard 1, P2 CPU /
	# Doge Man / NORMAL, P3+P4 Empty. Valid, but no stage yet.
	var flow = State.fresh_vs()
	flow.slots[0].fighter_id = "teknium"
	flow.slots[1].fighter_id = "doge_man"
	return flow

func _same_state(a, b) -> bool:
	if int(a.mode) != int(b.mode) or str(a.stage_id) != str(b.stage_id):
		return false
	if str(a.story_encounter_id) != str(b.story_encounter_id) or str(a.origin) != str(b.origin):
		return false
	if bool(a.allow_cpu_only) != bool(b.allow_cpu_only):
		return false
	if a.slots.size() != b.slots.size():
		return false
	for i in a.slots.size():
		var left = a.slots[i]
		var right = b.slots[i]
		if int(left.kind) != int(right.kind) or str(left.fighter_id) != str(right.fighter_id):
			return false
		if str(left.difficulty) != str(right.difficulty) or int(left.team_id) != int(right.team_id):
			return false
		if int(left.palette_index) != int(right.palette_index) or left.input_source != right.input_source:
			return false
	return true

func _no_node_references(payload, label: String) -> void:
	var entries: Array = payload if payload is Array else [payload]
	for entry in entries:
		if not (entry is Dictionary):
			continue
		for key in entry.keys():
			check(not (entry[key] is Node), label + ": no node reference at \"" + str(key) + "\"")

# --- Doc 01 §2 fresh defaults ---------------------------------------------

func _fresh_defaults() -> void:
	var flow = State.fresh_vs()
	check(int(flow.mode) == State.Mode.FFA, "fresh VS is free-for-all")
	check(flow.slots.size() == State.SLOT_COUNT, "fresh VS owns exactly four slots")
	check(int(flow.slots[0].kind) == State.Kind.HUMAN, "fresh P1 is Human")
	check(str(flow.slots[0].fighter_id) == "", "fresh P1 has no preselected fighter")
	check(int(flow.slots[1].kind) == State.Kind.CPU, "fresh P2 is CPU")
	check(str(flow.slots[1].fighter_id) == "", "fresh P2 has no preselected fighter")
	check(str(flow.slots[1].difficulty) == "normal", "fresh P2 is NORMAL")
	check(int(flow.slots[2].kind) == State.Kind.EMPTY, "fresh P3 is Empty")
	check(int(flow.slots[3].kind) == State.Kind.EMPTY, "fresh P4 is Empty")
	check(str(flow.stage_id) == "", "no stage is preselected")
	check(str(flow.story_encounter_id) == "", "a fresh VS state is not a Story state")
	check(str(flow.origin) == "" and flow.return_stack.is_empty(), "a fresh VS state has no route origin yet")
	check(not bool(flow.allow_cpu_only), "CPU-only starts OFF (debug/spectate is explicit)")
	check(flow.slots[0].input_source == State.keyboard_source(1), "mouse/keyboard entry seeds P1 as Keyboard 1")
	check(int(flow.slots[0].palette_index) == 0 and int(flow.slots[3].palette_index) == 3, "palette_index resolves from the slot index")
	check(int(flow.active_count()) == 2, "fresh VS has two participating slots")
	check(int(flow.human_count()) == 1, "fresh VS has one Human")
	check(flow.validate_for_stage_select() == State.MESSAGE_FIGHTER, "fresh VS cannot ready before fighters are picked")
	# The seeding rule for a controller entry (Doc 01 §2): that pad when it is
	# available, Keyboard 1 when availability prevents it. The expectation is
	# derived from the state's own device list so the test stays hardware-neutral.
	var pad_flow = State.fresh_vs("controller:0")
	var expected_input: Dictionary = State.pad_source(0) if 0 in pad_flow.connected_pads else State.keyboard_source(1)
	check(pad_flow.slots[0].input_source == expected_input, "controller entry seeds P1 to that pad, or falls back to Keyboard 1")

# --- entry device mapping (pure) ------------------------------------------

func _entry_device_mapping() -> void:
	check(State.input_source_for_entry_device("controller:2", [0, 2]) == State.pad_source(2), "a connected controller enters as that pad")
	check(State.input_source_for_entry_device("controller:2", [0]) == State.keyboard_source(1), "an unavailable controller falls back to Keyboard 1")
	check(State.input_source_for_entry_device("controller:7", []) == State.keyboard_source(1), "no connected pad means the Keyboard 1 fallback")
	check(State.input_source_for_entry_device("controller:abc", [0]) == State.keyboard_source(1), "an unresolvable controller entry also falls back")
	check(State.input_source_for_entry_device("mouse_keyboard", [3]) == State.keyboard_source(1), "mouse/keyboard enters as Keyboard 1")
	check(State.input_source_for_entry_device("keyboard", []) == State.no_input_source(), "an unknown entry device stays unassigned")
	check(State.input_source_kind(State.pad_source(1)) == State.INPUT_KIND_PAD, "pad sources report their kind")
	check(int(State.input_source_index(State.keyboard_source(2))) == 2, "sources report their index")
	check(State.input_source_kind({}) == "" and int(State.input_source_index({})) == -1, "an unassigned source has no kind/index")
	check(int(State.keyboard_index_for_slot(0)) == 1 and int(State.keyboard_index_for_slot(1)) == 2, "P1/P2 own Keyboard 1/2")
	check(int(State.keyboard_index_for_slot(2)) == -1 and int(State.keyboard_index_for_slot(3)) == -1, "P3/P4 own no keyboard")

# --- slot helpers ----------------------------------------------------------

func _slot_helpers() -> void:
	var empty = State.new_slot(2)
	check(not empty.participates(), "an Empty slot does not participate")
	check(empty.has_valid_fighter(), "an Empty slot has nothing to invalidate")
	check(empty.has_valid_input_assignment(), "an Empty slot needs no device")
	check(empty.has_valid_team(State.Mode.TEAMS), "an Empty slot needs no team")
	check(int(empty.index) == 2 and int(empty.palette_index) == 2, "a new slot knows its index")

	var p1 = State.new_slot(0)
	p1.kind = State.Kind.HUMAN
	check(p1.participates(), "a Human slot participates")
	check(not p1.has_valid_fighter(), "an active slot without a fighter is invalid")
	p1.fighter_id = "ggb"
	check(p1.has_valid_fighter(), "a roster fighter is valid")
	p1.fighter_id = "not_a_fighter"
	check(not p1.has_valid_fighter(), "an unknown fighter id is invalid")
	p1.fighter_id = "bobo"
	check(p1.has_valid_fighter(), "the encounter-owned fighter (Bobo) is a known fighter")
	p1.fighter_id = "ggb"

	p1.input_source = State.no_input_source()
	check(not p1.has_valid_input_assignment(), "P1 without an assignment is invalid")
	check(p1.input_assignment_error() == State.MESSAGE_P1_INPUT, "P1 reports its own message")
	p1.input_source = State.keyboard_source(1)
	check(p1.has_valid_input_assignment(), "P1 on Keyboard 1 is valid (Doc 01 §4)")
	p1.input_source = State.keyboard_source(2)
	check(not p1.has_valid_input_assignment(), "P1 cannot claim Keyboard 2")
	p1.input_source = State.pad_source(0)
	check(not p1.has_valid_input_assignment(), "an unconnected pad is invalid")
	check(p1.input_assignment_error() == State.MESSAGE_PAD_DISCONNECTED, "the disconnected pad message is the shipped one")
	p1.connected_pads = [0]
	check(p1.has_valid_input_assignment(), "a claimed connected pad is valid")

	var p2 = State.new_slot(1)
	p2.kind = State.Kind.HUMAN
	p2.input_source = State.keyboard_source(2)
	check(p2.has_valid_input_assignment(), "P2 on Keyboard 2 is valid")
	p2.input_source = State.keyboard_source(1)
	check(not p2.has_valid_input_assignment(), "P2 cannot claim Keyboard 1")
	check(p2.input_assignment_error() == State.MESSAGE_P2_INPUT, "P2 reports its own message")

	var p3 = State.new_slot(2)
	p3.kind = State.Kind.HUMAN
	p3.input_source = State.keyboard_source(1)
	check(not p3.has_valid_input_assignment(), "P3 has no keyboard assignment")
	check(p3.input_assignment_error() == State.MESSAGE_P3_P4_PAD, "P3 reports the shipped gamepad-required message")
	p3.input_source = State.pad_source(2)
	check(not p3.has_valid_input_assignment(), "P3 needs the pad connected")
	p3.connected_pads = [2]
	check(p3.has_valid_input_assignment(), "P3 with a connected pad is valid")

	var cpu = State.new_slot(0)
	cpu.kind = State.Kind.CPU
	cpu.input_source = State.no_input_source()
	check(cpu.has_valid_input_assignment(), "a CPU holds no device (device ownership is a Human concept)")

	var team_slot = State.new_slot(1)
	team_slot.kind = State.Kind.CPU
	team_slot.team_id = 5
	check(team_slot.has_valid_team(State.Mode.FFA), "FFA does not use team ids")
	check(not team_slot.has_valid_team(State.Mode.TEAMS), "an out-of-range team id is invalid in team mode")
	team_slot.team_id = State.TEAM_B
	check(team_slot.has_valid_team(State.Mode.TEAMS), "Team B is valid")

# --- Doc 01 §2/§3/§4 stage-select rules -----------------------------------

func _stage_select_rules() -> void:
	check(_vs_state().validate_for_stage_select() == "", "the baseline VS state is ready")

	var all_empty = State.fresh_vs()
	all_empty.slots[0].kind = State.Kind.EMPTY
	all_empty.slots[1].kind = State.Kind.EMPTY
	check(int(all_empty.active_count()) == 0, "the empty fixture really has no active fighter")
	check(all_empty.validate_for_stage_select() == State.MESSAGE_TWO_ACTIVE, "no active fighter cannot ready")

	var solo = _vs_state()
	solo.slots[1].kind = State.Kind.EMPTY
	check(int(solo.active_count()) == 1, "the one-fighter fixture really has one fighter")
	check(solo.validate_for_stage_select() == State.MESSAGE_TWO_ACTIVE, "one active fighter cannot ready")

	var cpu_only = State.fresh_vs()
	cpu_only.slots[0].kind = State.Kind.CPU
	cpu_only.slots[0].fighter_id = "teknium"
	cpu_only.slots[1].fighter_id = "doge_man"
	check(int(cpu_only.human_count()) == 0, "the CPU-only fixture really has no Human")
	check(cpu_only.validate_for_stage_select() == State.MESSAGE_HUMAN_REQUIRED, "player-facing VS needs at least one Human")
	cpu_only.allow_cpu_only = true
	check(cpu_only.validate_for_stage_select() == "", "the explicit debug/spectate flag allows CPU-only")
	check(cpu_only.validate_for_launch("toy_room") == "", "a CPU-only debug match can launch")
	cpu_only.allow_cpu_only = false
	check(cpu_only.validate_for_stage_select() != "", "the CPU-only flag must be set explicitly")

	var same_side = _vs_state()
	same_side.mode = State.Mode.TEAMS
	same_side.slots[0].team_id = State.TEAM_A
	same_side.slots[1].team_id = State.TEAM_A
	check(same_side.validate_for_stage_select() == State.MESSAGE_TEAMS_BOTH_SIDES, "team mode needs both Team A and Team B")
	same_side.slots[1].team_id = State.TEAM_B
	check(same_side.validate_for_stage_select() == "", "a 1v1 Team A vs Team B match is valid (Doc 01 §3)")
	check(int(same_side.teams_present().size()) == 2, "both sides are represented")
	same_side.slots[1].kind = State.Kind.EMPTY
	check(same_side.validate_for_stage_select() == State.MESSAGE_TWO_ACTIVE, "team mode still needs two active fighters")
	same_side.slots[1].kind = State.Kind.CPU
	same_side.slots[1].team_id = State.NO_TEAM
	check(same_side.validate_for_stage_select() == State.MESSAGE_TEAM, "a participating slot must carry Team A or Team B")

	var duplicated = _vs_state()
	duplicated.set_connected_pads([4])
	duplicated.slots[0].input_source = State.pad_source(4)
	duplicated.slots[1].kind = State.Kind.HUMAN
	duplicated.slots[1].input_source = State.pad_source(4)
	check(duplicated.validate_for_stage_select() == State.MESSAGE_DUPLICATE_PAD, "no pad may be claimed by two humans")
	duplicated.slots[1].input_source = State.pad_source(5)
	check(duplicated.validate_for_stage_select() == State.MESSAGE_PAD_DISCONNECTED, "a claimed pad must be connected (P2)")
	duplicated.set_connected_pads([4, 5])
	check(duplicated.validate_for_stage_select() == "", "two humans with their own connected pads are valid")

	var p3_human = _vs_state()
	p3_human.slots[2].kind = State.Kind.HUMAN
	p3_human.slots[2].fighter_id = "ggb"
	check(p3_human.validate_for_stage_select() == State.MESSAGE_P3_P4_PAD, "P3 Human without a pad is rejected")
	p3_human.set_connected_pads([3])
	p3_human.slots[2].input_source = State.pad_source(3)
	check(p3_human.validate_for_stage_select() == "", "P3 Human with a connected pad is valid")
	p3_human.set_connected_pads([])
	check(p3_human.validate_for_stage_select() == State.MESSAGE_PAD_DISCONNECTED, "a disconnected pad invalidates P3")

	var p1_pad = _vs_state()
	p1_pad.set_connected_pads([1])
	p1_pad.slots[0].input_source = State.pad_source(1)
	check(p1_pad.validate_for_stage_select() == "", "P1 may claim a connected pad instead of Keyboard 1")
	p1_pad.set_connected_pads([])
	check(p1_pad.validate_for_stage_select() == State.MESSAGE_PAD_DISCONNECTED, "a disconnected pad invalidates P1")

	var bad_fighter = _vs_state()
	bad_fighter.slots[0].fighter_id = "ghost"
	check(bad_fighter.validate_for_stage_select() == State.MESSAGE_FIGHTER, "an unknown fighter is rejected")

	var bad_difficulty = _vs_state()
	bad_difficulty.slots[1].difficulty = "nightmare"
	check(bad_difficulty.validate_for_stage_select() == State.MESSAGE_DIFFICULTY, "an unknown bot difficulty is rejected")

# --- Doc 02 §3 / launch rules ---------------------------------------------

func _launch_rules() -> void:
	var ready = _vs_state()
	check(ready.validate_for_launch() == State.MESSAGE_STAGE_REQUIRED, "launch needs a stage when none is recorded")
	check(ready.validate_for_launch("toy_room") == "", "a selectable stage launches")
	check(ready.validate_for_launch("debug") == "", "the debug arena is still a selectable stage")
	check(ready.validate_for_launch("nowhere") == State.MESSAGE_STAGE_UNAVAILABLE, "an unknown stage is rejected")

	ready.stage_id = "toy_room"
	check(ready.validate_for_launch("toy_room") == "", "the recorded stage may be launched")
	check(ready.validate_for_launch("") == "", "an empty launch id falls back to the recorded stage")
	check(ready.validate_for_launch("sky") == State.MESSAGE_STAGE_DESYNC, "a launch id that disagrees with the recorded selection is rejected")

	var story = State.fresh_story("story_01", "turbofit")
	check(story.is_story(), "the story factory produces a story state")
	check(str(story.story_encounter_id) == "story_01", "the encounter id is recorded")
	check(str(story.slots[1].fighter_id) == "bobo", "the encounter owns the opponent slot (StoryEncounterCatalog)" + ""
		+ " — consumed by gameplay only through the launch config's story payload")
	check(int(story.slots[1].team_id) == 1, "the encounter records the opponent side from the catalog")
	check(story.validate_for_stage_select() == "", "a complete story state passes the shared rules")
	check(story.validate_for_launch("") == State.MESSAGE_STAGE_REQUIRED, "a story launch still needs a stage")
	check(story.validate_for_launch("toy_room") == "", "a story state launches through the same authority")

	var unknown_encounter = State.fresh_story("story_99", "turbofit")
	check(unknown_encounter.validate_for_stage_select() == State.MESSAGE_ENCOUNTER_UNKNOWN, "an unknown encounter is rejected")
	var banned_fighter = State.fresh_story("story_01", "ice_mage")
	check(banned_fighter.validate_for_stage_select() == State.MESSAGE_ENCOUNTER_FIGHTER, "ice_mage is not an allowed encounter fighter")
	var unbriefed = State.fresh_story("story_01", "")
	check(unbriefed.validate_for_stage_select() == State.MESSAGE_FIGHTER, "the encounter player must have chosen a fighter (shared fighter rule)")
	var no_opponent = State.fresh_story("story_01", "turbofit")
	no_opponent.slots[1].kind = State.Kind.EMPTY
	check(no_opponent.validate_for_stage_select() == State.MESSAGE_ENCOUNTER_OPPONENT, "the encounter opponent must be in the slots")

# --- one validation authority ---------------------------------------------

func _authority_consistency() -> void:
	# Same rule set, one entry point for ready and one for launch: with a valid
	# launch stage and no recorded stage, both must report the SAME message for
	# every fixture; the stage rule is the only difference (checked above).
	var fixtures: Array = []
	fixtures.append(_vs_state())

	var one_fighter = _vs_state()
	one_fighter.slots[1].kind = State.Kind.EMPTY
	fixtures.append(one_fighter)

	var cpu_only = State.fresh_vs()
	cpu_only.slots[0].kind = State.Kind.CPU
	cpu_only.slots[0].fighter_id = "teknium"
	cpu_only.slots[1].fighter_id = "doge_man"
	fixtures.append(cpu_only)

	var same_side = _vs_state()
	same_side.mode = State.Mode.TEAMS
	same_side.slots[0].team_id = State.TEAM_A
	same_side.slots[1].team_id = State.TEAM_A
	fixtures.append(same_side)

	var duplicated = _vs_state()
	duplicated.set_connected_pads([4])
	duplicated.slots[0].input_source = State.pad_source(4)
	duplicated.slots[1].kind = State.Kind.HUMAN
	duplicated.slots[1].input_source = State.pad_source(4)
	fixtures.append(duplicated)

	var p3_human = _vs_state()
	p3_human.slots[2].kind = State.Kind.HUMAN
	p3_human.slots[2].fighter_id = "ggb"
	fixtures.append(p3_human)

	var bad_fighter = _vs_state()
	bad_fighter.slots[0].fighter_id = "ghost"
	fixtures.append(bad_fighter)

	for index in fixtures.size():
		var flow = fixtures[index]
		var ready_error: String = flow.validate_for_stage_select()
		var launch_error: String = flow.validate_for_launch("toy_room")
		check(ready_error == launch_error, "fixture %d: ready and launch share the rule set" % index)
		if ready_error == "":
			check(flow.validate_for_launch("") == State.MESSAGE_STAGE_REQUIRED, "fixture %d: only the stage rule is missing at launch" % index)

# --- adapters to the current production state -----------------------------

func _legacy_adapters() -> void:
	var legacy = SelectionState.new()
	check(legacy.slots.size() == 4 and int(legacy.mode) == 0 and str(legacy.stage) == "debug", "the legacy state boots the shape the adapter assumes")
	for raw in legacy.slots:
		var entry: Dictionary = raw
		check(entry.size() == 5, "the legacy slot carries five keys")
		for key in ["kind", "character", "team", "difficulty", "device"]:
			check(entry.has(key), "the legacy slot carries \"" + key + "\"")

	legacy.mode = 1
	legacy.stage = "toy_room"
	legacy.slots[0] = {"kind": "human", "character": "teknium", "team": 0, "difficulty": "hard", "device": -1}
	legacy.slots[1] = {"kind": "bot", "character": "doge_man", "team": 1, "difficulty": "easy", "device": -1}
	legacy.slots[2] = {"kind": "human", "character": "ggb", "team": 0, "difficulty": "normal", "device": 5}
	legacy.slots[3] = {"kind": "empty", "character": "turbofit", "team": 1, "difficulty": "normal", "device": -1}

	var flow = State.from_selection_state(legacy)
	check(int(flow.mode) == State.Mode.TEAMS, "legacy mode 1 maps to TEAMS")
	check(str(flow.stage_id) == "toy_room", "the legacy stage is preserved")
	check(int(flow.slots[0].kind) == State.Kind.HUMAN and str(flow.slots[0].fighter_id) == "teknium", "P1 human/Teknium is preserved")
	check(int(flow.slots[0].team_id) == 0 and str(flow.slots[0].difficulty) == "hard", "P1 team and difficulty are preserved")
	check(flow.slots[0].input_source == State.keyboard_source(1), "P1 device -1 is Keyboard 1")
	check(int(flow.slots[1].kind) == State.Kind.CPU, "the legacy \"bot\" kind maps to CPU")
	check(flow.slots[1].input_source == State.keyboard_source(2), "a recorded device is preserved for every kind (P2 device -1 is Keyboard 2)")
	check(flow.slots[2].input_source == State.pad_source(5), "a pad device becomes a pad source")
	check(int(flow.slots[3].kind) == State.Kind.EMPTY, "the legacy \"empty\" kind maps to EMPTY")
	check(str(flow.slots[3].fighter_id) == "turbofit", "a committed fighter survives on an Empty slot")
	check(flow.slots[3].input_source.is_empty(), "P4 device -1 is unassigned (gamepad required)")
	check(int(flow.slots[0].palette_index) == 0 and int(flow.slots[3].palette_index) == 3, "palette variants resolve from the slot index")

	var back = flow.to_selection_state()
	check(int(back.mode) == 1 and str(back.stage) == "toy_room", "mode and stage round-trip")
	check(back.slots == legacy.slots, "every legacy slot value round-trips exactly")
	var again = State.from_selection_state(back)
	check(_same_state(flow, again), "state -> legacy -> state is the identity")
	check(int(back.active_count()) == 3, "the converted legacy state still counts three active slots")
	check(not bool(again.allow_cpu_only), "the debug flag is not invented by the adapter")

	# Documented one-way fields: they have no legacy counterpart.
	var one_way = State.fresh_vs()
	one_way.story_encounter_id = "story_01"
	one_way.origin = "MAIN"
	one_way.allow_cpu_only = true
	one_way.push_return("RESULTS")
	check(str(one_way.return_target()) == "RESULTS", "the return stack reports its top label")
	check(str(one_way.pop_return()) == "RESULTS", "the return stack pops")
	check(str(one_way.return_target()) == "MAIN", "the return target falls back to the origin")
	var stripped = State.from_selection_state(one_way.to_selection_state())
	check(str(stripped.story_encounter_id) == "", "story_encounter_id cannot round-trip the legacy object (one-way)")
	check(str(stripped.origin) == "" and stripped.return_stack.is_empty(), "origin/return cannot round-trip the legacy object (one-way)")
	check(not bool(stripped.allow_cpu_only), "allow_cpu_only cannot round-trip the legacy object (one-way)")
	var null_flow = State.from_selection_state(null)
	check(null_flow != null and str(null_flow.stage_id) == "", "adapting nothing yields a fresh state, not a crash")

# --- Doc 02 §3 MatchLaunchConfig ------------------------------------------

func _launch_config() -> void:
	var flow = _vs_state()
	flow.stage_id = "sky"
	var config = LaunchConfig.build(flow)
	check(config != null, "build never returns null")
	check(config.is_valid(), "a validated state produces a launch config")
	check(str(config.validation_error()) == "", "a valid config carries no error")
	check(int(config.mode()) == State.Mode.FFA, "the config carries the mode")
	check(str(config.stage_id()) == "sky", "the config carries the stage")
	check(int(config.slot_count()) == 4, "the config carries four resolved slots")
	check(str(config.story_encounter_id()) == "" and not bool(config.has_story()), "a VS config is not a story config")
	check(config.story_payload().is_empty(), "a VS config carries no story payload")
	var snapshot: Array = config.slots()
	check(int(snapshot[0]["kind"]) == State.Kind.HUMAN and str(snapshot[0]["fighter_id"]) == "teknium", "resolved slot 0 travels with the config")
	check(int(snapshot[1]["kind"]) == State.Kind.CPU and str(snapshot[1]["difficulty"]) == "normal", "resolved slot 1 travels with the config")
	check(snapshot[0]["input_source"] == State.keyboard_source(1), "the input assignment travels with the config")
	check(int(snapshot[0]["palette_index"]) == 0 and int(snapshot[3]["palette_index"]) == 3, "resolved palette variants travel with the config")
	check(snapshot.size() == config.slot_count() and config.slot(0) == snapshot[0], "slot(i) matches the snapshot")
	check(config.slot(-1).is_empty() and config.slot(4).is_empty(), "out-of-range slot reads are empty")
	_no_node_references(config.slots(), "launch config")

	# Immutability against the state it came from.
	flow.mode = State.Mode.TEAMS
	flow.stage_id = "toy_room"
	flow.story_encounter_id = "story_01"
	flow.slots[0].fighter_id = "ggb"
	flow.slots[0].palette_index = 3
	flow.slots[1].team_id = State.TEAM_A
	flow.slots[0].input_source["index"] = 2
	flow.set_connected_pads([2, 3])
	check(config.slots() == snapshot, "mutating the state after build does not change the snapshot")
	check(int(config.mode()) == State.Mode.FFA and str(config.stage_id()) == "sky", "mode and stage stay frozen")
	check(not bool(config.has_story()) and config.story_payload().is_empty(), "a VS config never gains a story payload")

	# Immutability against consumers reading copies.
	var copy: Array = config.slots()
	copy[0]["fighter_id"] = "__probe__"
	var nested: Dictionary = copy[0]["input_source"]
	nested["index"] = 99
	copy[0]["input_source"] = nested
	check(str(config.slots()[0]["fighter_id"]) == "teknium", "mutating a returned slot copy does not reach the config")
	check(config.slots()[0]["input_source"] == State.keyboard_source(1), "nested input sources are copies too")

	# Only a validated state builds; an invalid state never yields a payload.
	var unready = State.fresh_vs()
	var blocked = LaunchConfig.build(unready)
	check(blocked != null and not blocked.is_valid(), "an unready state produces an invalid config")
	check(str(blocked.validation_error()) == unready.validate_for_launch(""), "the config reports the authority's message")
	check(blocked.slots().is_empty() and str(blocked.stage_id()) == "", "an invalid config carries no payload")
	var unsatisfied = LaunchConfig.build(_vs_state())
	check(not unsatisfied.is_valid(), "a ready state still cannot build without a stage")
	check(str(unsatisfied.validation_error()) == State.MESSAGE_STAGE_REQUIRED, "the stage rule is why it cannot build")
	var missing = LaunchConfig.build(null)
	check(not missing.is_valid() and str(missing.validation_error()) != "", "a missing state is reported, not crashed on")

	# Story launch payload.
	var story = State.fresh_story("story_01", "turbofit")
	story.stage_id = "debug"
	var story_config = LaunchConfig.build(story)
	check(story_config.is_valid() and bool(story_config.has_story()), "a story state builds a story launch config")
	check(str(story_config.story_encounter_id()) == "story_01", "the encounter id travels with the config")
	var payload: Dictionary = story_config.story_payload()
	check(str(payload["enemy_id"]) == "bobo" and int(payload["enemy_hp"]) == 400, "the encounter payload resolves through the catalog")
	check(payload == EncounterCatalog.by_id("story_01"), "the payload is the catalog entry")
	check(str(story_config.slots()[1]["fighter_id"]) == "bobo", "the resolved opponent slot travels with the config")
	_no_node_references(payload, "story payload")
	payload["enemy_hp"] = 1
	check(int(story_config.story_payload()["enemy_hp"]) == 400, "story payload reads are frozen")

# --- legacy pins (what the adapter depends on) ----------------------------

func _legacy_pins() -> void:
	check(State.DIFFICULTIES == Config.DIFFICULTIES, "the difficulty vocabulary mirrors match_config.DIFFICULTIES")
	var one_v_one: Array = [
		{"kind": "human", "character": "teknium", "team": 0, "difficulty": "normal", "device": -1},
		{"kind": "bot", "character": "doge_man", "team": 1, "difficulty": "normal", "device": -1},
		{"kind": "empty", "character": "", "team": 0, "difficulty": "normal", "device": -1},
		{"kind": "empty", "character": "", "team": 1, "difficulty": "normal", "device": -1},
	]
	check(Config.validate(one_v_one, true) != "", "the legacy validator still demands three fighters in team mode (unchanged)")
	var legacy = SelectionState.new()
	legacy.mode = 1
	legacy.slots = one_v_one
	check(not legacy.can_ready(), "the legacy selection state still refuses a 1v1 team ready (unchanged)")
	check(State.is_known_fighter("bobo") and not State.is_known_fighter(""), "the known-fighter set is the roster plus the encounter fighters")
	check(State.encounter_enemy_ids() == ["bobo"], "the encounter catalog owns the Bobo fighter id")
