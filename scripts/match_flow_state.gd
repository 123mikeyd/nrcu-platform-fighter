class_name MatchFlowState
extends RefCounted
# MatchFlowState — typed frontend/session setup state (corrective package Doc 02 §2).
#
# ADDITIVE WP-0 migration step 2 (Doc 02 §10.2 "Add typed MatchFlowState +
# adapters"). Nothing existing references this file yet: the MatchFlow router and
# the CSS/SSS/Story route migration steps come later and may then go through this
# module instead of reaching into screens or the Debug Setup model.
#
# It carries setup/session state across the frontend surfaces and is the SINGLE
# validation authority for it (Doc 02 §2: "Ready and actual launch must call the
# same validation authority"):
#   validate_for_stage_select()  ready gating on Character Select
#   validate_for_launch(id)      the stage-confirm / launch gate
# Both run the same rule set; the launch gate only adds the stage rule, which
# Stage Select owns. Each returns "" when the state may proceed, otherwise ONE
# player-facing message.
#
# Rule authority:
#   Doc 01 §2  fresh VS defaults; player-facing VS needs >= 2 active fighters and
#              >= 1 Human; CPU-only is a debug/spectate mode (allow_cpu_only,
#              default off).
#   Doc 01 §3  team mode needs >= 2 active fighters and BOTH Team A and Team B
#              represented; a 1v1 Team A vs Team B match is valid. This is the
#              locked rule — the legacy MatchConfig.validate still demands three.
#   Doc 01 §4  combat device ownership: P1 = Keyboard 1 or claimed pad,
#              P2 = Keyboard 2 or claimed pad, P3/P4 = connected pad only, no pad
#              claimed by two Human slots, a disconnected pad invalidates.
#
# Field provenance (what the adapters preserve from the CURRENT production state
# object res://scripts/match_selection_state.gd):
#   mode                  FFA / TEAMS; numeric encoding matches the legacy one
#                         (0 = free-for-all, 1 = teams).
#   slots[i].kind         legacy slot["kind"] spelled "human" / "bot" / "empty"
#                         in MatchConfig.default_slots() and CharSelect; the
#                         typed model calls the middle one CPU.
#   slots[i].fighter_id   legacy slot["character"], "" = no fighter.
#   slots[i].team_id      legacy slot["team"] (0 = Team A, 1 = Team B); the
#                         model adds NO_TEAM (-1) for "unset".
#   slots[i].input_source legacy slot["device"] (-1 = "no pad": Keyboard 1/2 on
#                         P1/P2 and "Gamepad required" on P3/P4; >= 0 = pad id).
#   slots[i].palette_index  resolved presentation variant; the current runtime
#                         resolves it from the slot index (roster.palette(id,
#                         slot_index)), so a fresh slot records its own index.
#   stage_id              legacy stage (Stage Select writes it on confirm).
#   story_encounter_id / origin / return_stack: no legacy counterpart — the VS
#                         selection state carries none of them (see the adapter
#                         notes in from_selection_state()/to_selection_state()).
#
# Contract: pure data + rules. No scene, node, screen or autoload access, and no
# side effect other than writing this object. Device availability
# (Input.get_connected_joypads) is runtime data: it is read once at construction
# and can be re-injected with set_connected_pads()/refresh_connected_pads() so
# headless tests and later routes drive it deterministically.

const SELF_PATH := "res://scripts/match_flow_state.gd"

const FighterCatalog = preload("res://scripts/catalogs/fighter_catalog.gd")
const StageCatalog = preload("res://scripts/catalogs/stage_catalog.gd")
const EncounterCatalog = preload("res://scripts/catalogs/story_encounter_catalog.gd")
const SelectionStateScript = preload("res://scripts/match_selection_state.gd")

const SLOT_COUNT := 4
const KEYBOARD_SLOT_COUNT := 2

enum Mode { FFA, TEAMS }
enum Kind { HUMAN, CPU, EMPTY }

const TEAM_A := 0
const TEAM_B := 1
const NO_TEAM := -1

const DEFAULT_DIFFICULTY := "normal"
# Mirrors match_config.gd DIFFICULTIES (the shipped difficulty vocabulary); the
# test pins the two lists together so the copy cannot drift unnoticed.
const DIFFICULTIES := ["easy", "normal", "hard"]

# Legacy (MatchConfig / MatchSelectionState / CharSelect) kind vocabulary.
const LEGACY_KIND_HUMAN := "human"
const LEGACY_KIND_CPU := "bot"
const LEGACY_KIND_EMPTY := "empty"
const LEGACY_NO_DEVICE := -1

# input_source vocabulary (Doc 01 §4 combat device ownership).
const INPUT_KIND_KEYBOARD := "keyboard"
const INPUT_KIND_PAD := "pad"
const ENTRY_MOUSE_KEYBOARD := "mouse_keyboard"
const ENTRY_CONTROLLER_PREFIX := "controller:"

# --- validation copy -------------------------------------------------------
# Reused verbatim from MatchConfig.validate where the shipped setup screen
# already owns the same rule; the rest is new copy introduced by the LOCKED
# Doc 01 §2/§3 rules. These are validation strings, not authored visuals.
const MESSAGE_SLOT_COUNT := "MatchFlowState owns exactly four slots."
const MESSAGE_FIGHTER := "Choose a valid fighter for every active player."
const MESSAGE_DIFFICULTY := "Choose Easy, Normal, or Hard bot difficulty."
const MESSAGE_TEAM := "Choose team A or B."
const MESSAGE_TWO_ACTIVE := "Choose at least two active fighters."
const MESSAGE_HUMAN_REQUIRED := "Player matches need at least one Human player."
const MESSAGE_TEAMS_BOTH_SIDES := "Teams need both Team A and Team B represented."
const MESSAGE_DUPLICATE_PAD := "Each human needs a different gamepad."
const MESSAGE_PAD_DISCONNECTED := "Selected gamepad is disconnected."
const MESSAGE_P3_P4_PAD := "P3/P4 humans need a connected gamepad; or choose Bot/Empty."
const MESSAGE_P1_INPUT := "P1 needs Keyboard 1 or a connected controller."
const MESSAGE_P2_INPUT := "P2 needs Keyboard 2 or a connected controller."
const MESSAGE_INPUT_UNAVAILABLE := "That input assignment is not available."
const MESSAGE_STAGE_REQUIRED := "Choose a stage."
const MESSAGE_STAGE_UNAVAILABLE := "That stage is not available."
const MESSAGE_STAGE_DESYNC := "The stage selection is out of sync with the match flow state."
const MESSAGE_ENCOUNTER_UNKNOWN := "That Story encounter is not available."
const MESSAGE_ENCOUNTER_ONE_HUMAN := "Story encounters are played by exactly one Human player."
const MESSAGE_ENCOUNTER_FIGHTER := "Choose an allowed fighter for this encounter."
const MESSAGE_ENCOUNTER_OPPONENT := "The encounter opponent is missing from the slots."

# ---------------------------------------------------------------------------
# Slot — one player station (Doc 02 §2 "slots[4]") and the ONLY place the slot
# level rules live. participates()/has_valid_fighter()/
# has_valid_input_assignment()/has_valid_team(mode) are the documented helpers;
# input_assignment_error() is the same input rule set, returning the message the
# state reports (one implementation, two views).
# ---------------------------------------------------------------------------
class Slot extends RefCounted:
	var index := 0                      # 0..3 = P1..P4
	var kind := Kind.EMPTY              # HUMAN / CPU / EMPTY
	var fighter_id := ""                # "" = no fighter selected
	var difficulty := DEFAULT_DIFFICULTY  # CPU vocabulary; ignored for humans
	var team_id := NO_TEAM              # TEAM_A / TEAM_B, NO_TEAM = unset
	var input_source: Dictionary = {}   # {} = unassigned; keyboard/pad source
	var palette_index := 0              # resolved presentation variant
	var connected_pads: Array = []      # injected device availability

	func participates() -> bool:
		return kind != Kind.EMPTY

	func has_valid_fighter() -> bool:
		if not participates():
			return true
		return fighter_id != "" and Slot.is_known_fighter(fighter_id)

	func has_valid_team(mode: int) -> bool:
		if not participates():
			return true
		if mode != Mode.TEAMS:
			return true                 # FFA does not use team ids (Doc 01 §3)
		return team_id == TEAM_A or team_id == TEAM_B

	func has_valid_input_assignment() -> bool:
		return input_assignment_error() == ""

	func input_assignment_error() -> String:
		# Doc 01 §4: combat device ownership is explicit and per Human slot.
		# CPUs and empty slots hold no device (any recorded value is ignored).
		if kind != Kind.HUMAN:
			return ""
		var source := input_source
		if source.is_empty():
			return slot_input_message()
		var source_kind := str(source.get("kind", ""))
		var source_index := int(source.get("index", -1))
		if source_kind == INPUT_KIND_KEYBOARD:
			var expected: int = Slot.keyboard_index_for_slot(index)
			if expected > 0 and source_index == expected:
				return ""
			return slot_input_message()
		if source_kind == INPUT_KIND_PAD:
			if source_index < 0:
				return MESSAGE_INPUT_UNAVAILABLE
			if not (source_index in connected_pads):
				return MESSAGE_PAD_DISCONNECTED
			return ""
		return MESSAGE_INPUT_UNAVAILABLE

	func slot_input_message() -> String:
		match index:
			0:
				return MESSAGE_P1_INPUT
			1:
				return MESSAGE_P2_INPUT
			_:
				return MESSAGE_P3_P4_PAD

	# Shared lookups live on the slot record because an inner class cannot call
	# the outer script's static functions; MatchFlowState re-exposes them so
	# callers still have one entry point.
	static func is_known_fighter(fighter_id: String) -> bool:
		# Roster fighters, plus the encounter-owned fighters (Bobo) from the
		# Story catalog: a story state must be representable here too.
		if fighter_id == "":
			return false
		if FighterCatalog.has(fighter_id):
			return true
		return fighter_id in encounter_enemy_ids()

	static func encounter_enemy_ids() -> Array[String]:
		var out: Array[String] = []
		for entry in EncounterCatalog.all():
			var enemy := str(entry.get("enemy_id", ""))
			if enemy != "" and not out.has(enemy):
				out.append(enemy)
		return out

	static func keyboard_index_for_slot(slot_index: int) -> int:
		# Doc 01 §4: P1 owns Keyboard 1, P2 owns Keyboard 2; P3/P4 have no
		# keyboard assignment.
		if slot_index >= 0 and slot_index < KEYBOARD_SLOT_COUNT:
			return slot_index + 1
		return -1

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var mode := Mode.FFA
var slots: Array = []                   # 4 x Slot, index 0..3 = P1..P4
var stage_id := ""                      # "" = Stage Select has not confirmed yet
var story_encounter_id := ""            # "" = VS; else a StoryEncounterCatalog id
var origin := ""                        # surface the flow was entered from
var return_stack: Array = []            # route return labels (Doc 02 §5 owns the verbs)
var allow_cpu_only := false             # debug/spectate only; default OFF (Doc 01 §2)
var connected_pads: Array = []          # device availability injected once

func _init() -> void:
	connected_pads = live_connected_pads()
	for i in SLOT_COUNT:
		slots.append(new_slot(i))
	_apply_connected_pads()

# --- construction ----------------------------------------------------------

static func _blank() -> RefCounted:
	# Own path: factories construct through the resource path so this script
	# never depends on its own class_name being registered in the global class
	# cache before it can build a state (headless test runs do not re-scan the
	# project).
	return (load(SELF_PATH) as GDScript).new()

static func new_slot(index: int) -> Slot:
	var slot := Slot.new()
	slot.index = index
	slot.palette_index = index           # current runtime resolves it from the index
	return slot

static func live_connected_pads() -> Array:
	return Input.get_connected_joypads()

static func fresh_vs(entry_device: String = ENTRY_MOUSE_KEYBOARD) -> RefCounted:
	# Doc 01 §2 fresh VS defaults: P1 HUMAN / no fighter / input seeded from the
	# entry device, P2 CPU / no fighter / NORMAL, P3 EMPTY, P4 EMPTY. Nothing is
	# preselected; returning from SSS/Results restores a state instead.
	var flow = _blank()
	flow.mode = Mode.FFA
	var p1 = flow.slots[0]
	p1.kind = Kind.HUMAN
	p1.fighter_id = ""
	p1.difficulty = DEFAULT_DIFFICULTY
	p1.team_id = NO_TEAM
	p1.input_source = input_source_for_entry_device(entry_device, flow.connected_pads)
	var p2 = flow.slots[1]
	p2.kind = Kind.CPU
	p2.fighter_id = ""
	p2.difficulty = DEFAULT_DIFFICULTY
	p2.team_id = NO_TEAM
	p2.input_source = no_input_source()
	return flow

static func fresh_story(encounter_id: String, fighter_id: String = "", entry_device: String = ENTRY_MOUSE_KEYBOARD) -> RefCounted:
	# Story entry: same player station, but the encounter owns the opponent
	# slot. Mirrors the CURRENT story launch (main.gd start_story(): P1 human,
	# slot 1 Bobo, slots 2/3 empty); the encounter metadata comes from
	# StoryEncounterCatalog, never from a screen.
	var flow = _blank()
	flow.mode = Mode.FFA
	flow.story_encounter_id = str(encounter_id)
	flow.slots[0].kind = Kind.HUMAN
	flow.slots[0].fighter_id = str(fighter_id)
	flow.slots[0].input_source = input_source_for_entry_device(entry_device, flow.connected_pads)
	var encounter: Dictionary = EncounterCatalog.by_id(flow.story_encounter_id)
	if not encounter.is_empty():
		var enemy: Dictionary = encounter.get("enemy_slot", {})
		flow.slots[1].kind = Kind.CPU
		flow.slots[1].fighter_id = str(encounter.get("enemy_id", ""))
		flow.slots[1].difficulty = str(enemy.get("difficulty", DEFAULT_DIFFICULTY))
		flow.slots[1].team_id = int(enemy.get("team", NO_TEAM))
	return flow

# --- input source vocabulary ----------------------------------------------

static func no_input_source() -> Dictionary:
	return {}

static func keyboard_source(index: int) -> Dictionary:
	return {"kind": INPUT_KIND_KEYBOARD, "index": index}

static func pad_source(index: int) -> Dictionary:
	return {"kind": INPUT_KIND_PAD, "index": index}

static func input_source_kind(source) -> String:
	if source is Dictionary:
		return str(source.get("kind", ""))
	return ""

static func input_source_index(source) -> int:
	if source is Dictionary:
		return int(source.get("index", -1))
	return -1

static func keyboard_index_for_slot(slot_index: int) -> int:
	return Slot.keyboard_index_for_slot(slot_index)

static func input_source_for_entry_device(entry_device: String, connected_pads: Array) -> Dictionary:
	# Doc 01 §2: Play entered with mouse/keyboard -> P1 = Keyboard 1; entered
	# with a controller -> P1 = that controller "unless product/device
	# availability prevents it", i.e. an unconnected pad falls back to
	# Keyboard 1. An unrecognized entry device stays unassigned so the caller
	# sees the state it actually produced instead of a silent default.
	if entry_device == ENTRY_MOUSE_KEYBOARD:
		return keyboard_source(1)
	if entry_device.begins_with(ENTRY_CONTROLLER_PREFIX):
		var suffix := entry_device.substr(ENTRY_CONTROLLER_PREFIX.length())
		if suffix.is_valid_int():
			var pad_index := int(suffix)
			if pad_index >= 0 and pad_index in connected_pads:
				return pad_source(pad_index)
		return keyboard_source(1)
	return no_input_source()

# --- device availability --------------------------------------------------

func set_connected_pads(pads: Array) -> void:
	connected_pads = pads.duplicate()
	_apply_connected_pads()

func refresh_connected_pads() -> void:
	set_connected_pads(live_connected_pads())

func _apply_connected_pads() -> void:
	for entry in slots:
		if entry is Slot:
			entry.connected_pads = connected_pads.duplicate()

# --- reads ----------------------------------------------------------------

func slot(index: int) -> Slot:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]

func participating_slots() -> Array:
	var out: Array = []
	for entry in slots:
		if entry is Slot and entry.participates():
			out.append(entry)
	return out

func human_slots() -> Array:
	var out: Array = []
	for entry in slots:
		if entry is Slot and entry.kind == Kind.HUMAN:
			out.append(entry)
	return out

func active_count() -> int:
	return participating_slots().size()

func human_count() -> int:
	return human_slots().size()

func teams_present() -> Array:
	var out: Array = []
	for entry in participating_slots():
		if not (entry.team_id in out):
			out.append(entry.team_id)
	return out

func is_teams() -> bool:
	return mode == Mode.TEAMS

func is_story() -> bool:
	return story_encounter_id != ""

static func is_known_fighter(fighter_id: String) -> bool:
	return Slot.is_known_fighter(fighter_id)

static func encounter_enemy_ids() -> Array[String]:
	return Slot.encounter_enemy_ids()

# --- route origin support (Doc 02 §5 owns the verbs) -----------------------

func push_return(label: String) -> void:
	return_stack.append(str(label))

func pop_return() -> String:
	if return_stack.is_empty():
		return ""
	return str(return_stack.pop_back())

func return_target() -> String:
	if not return_stack.is_empty():
		return str(return_stack[return_stack.size() - 1])
	return origin

# --- THE validation authority ---------------------------------------------
# Ready and launch run the same rule set; only the stage rule is added for the
# launch gate. Deterministic order, so the surfaced message is reproducible:
# slot structure -> per participating slot (fighter, difficulty, team, input)
# -> duplicate pad across humans -> VS counts/teams or the Story encounter
# shape -> the stage (launch only).

func validate_for_stage_select() -> String:
	return _validation_error(false, "")

func validate_for_launch(for_stage_id: String = "") -> String:
	# Doc 02 §2 validate_for_launch(stage_id): `for_stage_id` is the Stage Select
	# selection being launched with; empty falls back to this state's stage_id.
	return _validation_error(true, str(for_stage_id))

func _validation_error(require_stage: bool, for_stage_id: String) -> String:
	if slots.size() != SLOT_COUNT:
		return MESSAGE_SLOT_COUNT
	for entry in slots:
		var station: Slot = entry
		if not station.participates():
			continue
		if not station.has_valid_fighter():
			return MESSAGE_FIGHTER
		if station.kind == Kind.CPU and not (station.difficulty in DIFFICULTIES):
			return MESSAGE_DIFFICULTY
		if not station.has_valid_team(mode):
			return MESSAGE_TEAM
		var input_error := station.input_assignment_error()
		if input_error != "":
			return input_error
	var duplicate_error := _duplicate_pad_error()
	if duplicate_error != "":
		return duplicate_error
	if is_story():
		var story_error := _story_error()
		if story_error != "":
			return story_error
	else:
		var vs_error := _vs_error()
		if vs_error != "":
			return vs_error
	if require_stage:
		return _stage_error(for_stage_id)
	return ""

func _vs_error() -> String:
	var active := active_count()
	if active < 2:
		return MESSAGE_TWO_ACTIVE
	if human_count() < 1 and not allow_cpu_only:
		return MESSAGE_HUMAN_REQUIRED
	if is_teams() and teams_present().size() < 2:
		return MESSAGE_TEAMS_BOTH_SIDES
	return ""

func _story_error() -> String:
	# Encounter shape derived from the CURRENT story launch (main.gd
	# start_story() + StoryEncounterCatalog); the package does not lock Story
	# validation rules yet.
	var encounter: Dictionary = EncounterCatalog.by_id(story_encounter_id)
	if encounter.is_empty():
		return MESSAGE_ENCOUNTER_UNKNOWN
	var humans := human_slots()
	if humans.size() != 1:
		return MESSAGE_ENCOUNTER_ONE_HUMAN
	var player: Slot = humans[0]
	if player.fighter_id == "" or not (player.fighter_id in EncounterCatalog.allowed_fighter_ids(story_encounter_id)):
		return MESSAGE_ENCOUNTER_FIGHTER
	var enemy_id := str(encounter.get("enemy_id", ""))
	for entry in participating_slots():
		if entry.fighter_id == enemy_id:
			return ""
	return MESSAGE_ENCOUNTER_OPPONENT

func _duplicate_pad_error() -> String:
	var claimed: Array = []
	for entry in human_slots():
		var station: Slot = entry
		if input_source_kind(station.input_source) != INPUT_KIND_PAD:
			continue
		var pad_index := input_source_index(station.input_source)
		if pad_index in claimed:
			return MESSAGE_DUPLICATE_PAD
		claimed.append(pad_index)
	return ""

func _stage_error(for_stage_id: String) -> String:
	var launch_id := for_stage_id if for_stage_id != "" else stage_id
	if launch_id == "":
		return MESSAGE_STAGE_REQUIRED
	if not StageCatalog.is_selectable(launch_id):
		return MESSAGE_STAGE_UNAVAILABLE
	if stage_id != "" and launch_id != stage_id:
		# Divergence guard: the launch id and the recorded SSS selection must
		# agree, otherwise the state would silently launch something else.
		return MESSAGE_STAGE_DESYNC
	return ""

# --- adapters to the CURRENT production selection state --------------------

static func from_selection_state(state) -> RefCounted:
	# Adapter for the CURRENT res://scripts/match_selection_state.gd object.
	# Every value the legacy object holds is preserved:
	#   mode -> mode, stage -> stage_id, kind strings -> Kind, character ->
	#   fighter_id, team -> team_id, difficulty -> difficulty, device ->
	#   input_source (see input_source_from_legacy_device).
	# Fields with NO legacy counterpart stay at their fresh value and are
	# documented one-way: story_encounter_id, origin, return_stack,
	# allow_cpu_only (the legacy VS state cannot express them) and
	# palette_index (the legacy model resolves the variant from the slot index
	# at render time, never stores it).
	var flow = _blank()
	if state == null:
		return flow
	flow.mode = Mode.TEAMS if int(state.mode) == 1 else Mode.FFA
	flow.stage_id = str(state.stage)
	var raw_slots: Array = state.slots if state.slots is Array else []
	for i in mini(raw_slots.size(), SLOT_COUNT):
		var raw = raw_slots[i]
		if not (raw is Dictionary):
			continue
		var station: Slot = flow.slots[i]
		station.kind = kind_from_legacy(str(raw.get("kind", LEGACY_KIND_EMPTY)))
		station.fighter_id = str(raw.get("character", ""))
		station.difficulty = str(raw.get("difficulty", DEFAULT_DIFFICULTY))
		station.team_id = int(raw.get("team", NO_TEAM))
		station.input_source = input_source_from_legacy_device(i, int(raw.get("device", LEGACY_NO_DEVICE)))
	flow._apply_connected_pads()
	return flow

func to_selection_state() -> RefCounted:
	# Conversion back to the CURRENT state object shape, so later migration steps
	# can keep the existing screens running while they move over one at a time.
	# One-way fields (story_encounter_id, origin, return_stack, allow_cpu_only,
	# palette_index) cannot survive this trip: the legacy object has no slot for
	# them.
	var legacy = SelectionStateScript.new()
	legacy.mode = int(mode)
	legacy.stage = str(stage_id)
	var legacy_slots: Array = []
	for entry in slots:
		var station: Slot = entry
		legacy_slots.append({
			"kind": kind_to_legacy(station.kind),
			"character": station.fighter_id,
			"team": int(station.team_id),
			"difficulty": station.difficulty,
			"device": input_source_to_legacy_device(station.input_source),
		})
	legacy.slots = legacy_slots
	return legacy

static func kind_to_legacy(kind: int) -> String:
	if kind == Kind.HUMAN:
		return LEGACY_KIND_HUMAN
	if kind == Kind.CPU:
		return LEGACY_KIND_CPU
	return LEGACY_KIND_EMPTY

static func kind_from_legacy(name: String) -> int:
	if name == LEGACY_KIND_HUMAN:
		return Kind.HUMAN
	if name == LEGACY_KIND_CPU:
		return Kind.CPU
	return Kind.EMPTY

static func input_source_from_legacy_device(slot_index: int, device: int) -> Dictionary:
	# Legacy slot["device"]: >= 0 is a pad id; -1 is the "no pad" marker, which
	# means the physical Keyboard 1/2 on P1/P2 ("Keyboard %d" in the setup UI)
	# and "Gamepad required" on P3/P4 (no allowed assignment).
	if device >= 0:
		return pad_source(device)
	var keyboard_index := keyboard_index_for_slot(slot_index)
	if keyboard_index > 0:
		return keyboard_source(keyboard_index)
	return no_input_source()

static func input_source_to_legacy_device(source) -> int:
	# Keyboard 1/2 and "unassigned" both collapse onto the legacy -1 marker: the
	# legacy model derives Keyboard 1/2 from the slot index, so legacy -> typed
	# -> legacy is exact, while typed -> legacy -> typed normalizes a keyboard
	# source on P3/P4 (which the model never accepts) to "unassigned".
	if input_source_kind(source) == INPUT_KIND_PAD:
		return input_source_index(source)
	return LEGACY_NO_DEVICE
