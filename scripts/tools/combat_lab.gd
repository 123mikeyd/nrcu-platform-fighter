extends Node3D
## First strike slice. Only Match.simulate advances actors.
const Match = preload("res://scripts/core/match/match_simulation.gd")
const MatchRules = preload("res://scripts/core/match/match_rules.gd")
const HitstopProfile = preload("res://scripts/core/combat/hitstop_profile.gd")
const CombatLabStage = preload("res://scripts/core/stage/combat_lab_stage.gd")
const LedgePolicy = preload("res://scripts/core/stage/ledge_policy.gd")
const DefenseProfile = preload("res://scripts/core/combat/defense_profile.gd")
const Recovery = preload("res://scripts/core/combat/recovery_ability.gd")
const Actor = preload("res://scripts/core/fighter/fighter_actor.gd")
const Source = preload("res://scripts/core/input/player_input_source.gd")
const Presenter = preload("res://scripts/core/presentation/teknium_presenter.gd")
const IcePresenter = preload("res://scripts/core/presentation/ice_mage_presenter.gd")
const TurboPresenter = preload("res://scripts/core/presentation/turbofit_presenter.gd")
const Pilot = preload("res://data/characters/teknium_movement.tres")
const CollisionDebug = preload("res://scripts/tools/collision_debug_overlay.gd")
var collision_debug: Node3D
var collision_shapes_button: CheckButton

func set_collision_shapes_visible(value: bool) -> void:
    if is_instance_valid(collision_debug):
        collision_debug.visible = value
        collision_debug.refresh()
    var legend = find_child("CollisionLegend", true, false)
    if legend != null: legend.visible = value
    if is_instance_valid(collision_shapes_button): collision_shapes_button.set_pressed_no_signal(value)
    _sync_top_support_label()

func _sync_top_support_label() -> void:
    var label = find_child("TopSupportTelemetry", true, false)
    if label == null: return
    label.visible = is_instance_valid(collision_debug) and collision_debug.visible
    var legend = find_child("CollisionLegend", true, false)
    var jostle: bool = simulation.fighter_interaction_mode == "grounded_jostle"
    if legend != null:
        legend.text = "F4: cyan terrain capsule / white grounded jostle range / green terrain / magenta hurtboxes / yellow witness [F6]" if jostle else ("F4: cyan solid body / orange one-way legacy support / green terrain / magenta hurtboxes / yellow witness [F6]" if generated_collision_enabled else "F4: cyan solid bodies / green terrain — attack queries not shown")
    if jostle:
        label.text = "Grounded jostle: white range when eligible; hidden in air/ineligible. Not a wall. Air passes through. No head platform."
        return
    var rows := PackedStringArray()
    for id in simulation.fighters:
        var record: Dictionary = simulation.top_support_telemetry(id)
        var geometry: Dictionary = record.get("geometry", {})
        var state: Dictionary = simulation.fighters[id]
        var category := str(geometry.get("pose_category", "off"))
        var relation: Dictionary = record.get("relation", {})
        var relation_text := "none" if relation.is_empty() else "P%d" % relation.carrier
        if not state.enabled or state.eliminated: category = "inactive"
        rows.append("P%d: %s h=%.2f / ephemeral rider->%s" % [id, category, geometry.get("height", 0.0), relation_text])
    label.text = "Top-support (stable category; not animated soles): " + " | ".join(rows)

var collision_snapshot_button: Button
var generated_collision_label: Label
var generated_controls: HBoxContainer
var collision_snapshot_phase := "current_pose"
func set_collision_snapshot_phase(value: String) -> bool:
    if value not in ["current_pose", "contact_snapshot"]: return false
    collision_snapshot_phase = value
    if is_instance_valid(collision_snapshot_button): collision_snapshot_button.text = ("Pose" if value == "current_pose" else "Hit") + " [F6]"
    if is_instance_valid(collision_debug): collision_debug.refresh()
    return true

var generated_collision_enabled := false
var generated_collision_notice := "Compatibility collision / legacy blended presentation"
var generated_collision_button: CheckButton
# Balance revision is distinct from the match host's reset/install generation.
var active_collision_profiles: Dictionary = {}

func _merge_anatomical_profile(base: Resource, override: Resource) -> Dictionary:
    # Partial overrides are mandatory in this draft; never fall back to the base.
    const Profile = preload("res://scripts/core/collision/character_collision_profile.gd")
    if not base is Profile or not override is Profile:
        return {"errors": ["missing or unsupported anatomical base/override"]}
    if override.source_asset != base.source_asset or override.source_sha256 != base.source_sha256:
        return {"errors": ["anatomical override source mismatch"]}
    var base_path := "res://data/collision/generated/%s.tres" % base.character_id
    if override.provenance.get("generated_profile_sha256", "") != FileAccess.get_sha256(base_path):
        return {"errors": ["anatomical override generated base hash mismatch"]}
    if override.hurtboxes.is_empty(): return {"errors": ["empty anatomical tuning"]}
    for hurtbox in override.hurtboxes:
        if hurtbox == null or not hurtbox.get("manual_override"):
            return {"errors": ["anatomical hurtbox must explicitly flag manual override"]}
    return base.merged_with(override)

func set_generated_collision_enabled(value: bool) -> bool:
    if not value and _ai_enabled():
        generated_collision_notice = "REFUSED: AI comparison keeps anatomical contacts ON. Choose interaction above; Human unlocks F5."
        if is_instance_valid(generated_collision_button): generated_collision_button.set_pressed_no_signal(true)
        return false
    if value and "ice_mage" in selected_fighters:
        generated_collision_notice = "REFUSED: Ice is unsupported. Select Teknium/Turbo first."
        if is_instance_valid(generated_collision_button): generated_collision_button.set_pressed_no_signal(generated_collision_enabled)
        return false
    var profiles := {}
    var identities := {}
    for slot in range(actors.size()):
        profiles[slot + 1] = null
        if value:
            var base_path := "res://data/collision/generated/%s.tres" % selected_fighters[slot]
            var override_path := "res://data/collision/overrides/%s_anatomical_v1.tres" % selected_fighters[slot]
            var base = load(base_path) if ResourceLoader.exists(base_path) else null
            var override = load(override_path) if ResourceLoader.exists(override_path) else null
            var merged: Dictionary = _merge_anatomical_profile(base, override)
            if not merged.get("errors", []).is_empty() or not merged.has("profile"):
                generated_collision_notice = "REFUSED: anatomical merge: " + str(merged.get("errors", []))
                if is_instance_valid(generated_collision_button): generated_collision_button.set_pressed_no_signal(generated_collision_enabled)
                return false
            profiles[slot + 1] = merged.profile
            identities[slot + 1] = {"base_path": base_path, "override_path": override_path, "revision": str(override.provenance.get("balance_override_version", "unversioned")), "source_asset": base.source_asset, "source_sha256": base.source_sha256, "base_sha256": FileAccess.get_sha256(base_path), "override_sha256": FileAccess.get_sha256(override_path)}
    if not simulation.reset_with_collision_profiles(spawns, profiles, comparison_interaction if value else "legacy_solid"):
        generated_collision_notice = "REFUSED: " + str(simulation.collision_install_diagnostics())
        if is_instance_valid(generated_collision_button): generated_collision_button.set_pressed_no_signal(generated_collision_enabled)
        return false
    active_collision_profiles = identities
    generated_collision_enabled = value
    generated_collision_notice = "DRAFT anatomically tuned hurtboxes / discrete canonical pose (no blend)" if value else "Compatibility collision / legacy blended presentation"
    if is_instance_valid(generated_collision_button): generated_collision_button.set_pressed_no_signal(value)
    _reset_round_input_and_visuals()
    return true

const RepoInputs = preload("res://scripts/core/input/repo_ai_match_input.gd")
var repo_inputs = RepoInputs.new()
const SparringInputs = preload("res://scripts/core/input/sparring_match_input.gd")
var sparring_inputs = SparringInputs.new()
var p2_input_owner := "human"

func _ai_enabled() -> bool:
    return repo_inputs.enabled or sparring_inputs.enabled

func _selected_inputs():
    return sparring_inputs if p2_input_owner == "sparring_easy" else repo_inputs
var main_support_shape: CollisionShape3D

func _refresh_ai_stage_bounds() -> bool:
    # Read the actual terrain collider, never the mesh or comparison arm.
    if not is_instance_valid(main_support_shape) or main_support_shape.disabled or not main_support_shape.shape is BoxShape3D:
        repo_inputs.stage_bounds = {}
        sparring_inputs.stage_bounds = {}
        generated_collision_notice = "REFUSED: AI stage sensing requires an enabled horizontal box support."
        return false
    var transform := main_support_shape.global_transform
    var basis := transform.basis
    if not transform.is_finite() or basis.x.x <= 0 or basis.y.y <= 0 or basis.z.z <= 0 or not is_zero_approx(basis.x.y) or not is_zero_approx(basis.x.z) or not is_zero_approx(basis.y.x) or not is_zero_approx(basis.y.z) or not is_zero_approx(basis.z.x) or not is_zero_approx(basis.z.y):
        repo_inputs.stage_bounds = {}
        sparring_inputs.stage_bounds = {}
        generated_collision_notice = "REFUSED: AI stage sensing requires axis-aligned positive support transforms."
        return false
    var half: Vector3 = main_support_shape.shape.size * 0.5
    var low := transform * -half
    var high := transform * half
    repo_inputs.stage_bounds = {"left": low.x, "right": high.x, "top": high.y}
    sparring_inputs.stage_bounds = repo_inputs.stage_bounds.duplicate(true)
    return true
var ai_difficulty := "normal"
var comparison_interaction := "grounded_jostle"
var p2_input_button: OptionButton
var ai_difficulty_button: OptionButton
var comparison_button: OptionButton

func _comparison_choice(parent: Node, control_name: String, items: Array, callback: Callable) -> OptionButton:
    var button := OptionButton.new()
    button.name = control_name
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 12)
    for item in items: button.add_item(item)
    parent.add_child(button)
    button.get_popup().about_to_popup.connect(func(): set_paused(true))
    button.get_popup().popup_hide.connect(func(): button.release_focus())
    button.item_selected.connect(callback)
    return button

func _sync_comparison_controls() -> void:
    if not is_instance_valid(p2_input_button): return
    p2_input_button.select(["human", "sparring_easy", "repo_ai"].find(p2_input_owner))
    ai_difficulty_button.select(0 if p2_input_owner == "sparring_easy" else ["easy", "normal", "hard"].find(ai_difficulty))
    ai_difficulty_button.disabled = not repo_inputs.enabled
    ai_difficulty_button.tooltip_text = "Easy only: our beginner practice policy, not Mikey Easy. Delayed decisions and deliberate openings; damage unchanged." if p2_input_owner == "sparring_easy" else "Mikey's original Easy / Normal / Hard intervals: .42 / .22 / .10 seconds. Deterministic sequence; unchanged tuning."
    comparison_button.select(0 if comparison_interaction == "grounded_jostle" else 1)
    comparison_button.disabled = not generated_collision_enabled
    if not generated_collision_enabled: comparison_button.select(2)
    generated_collision_button.disabled = _ai_enabled()
    var help = find_child("RosterHelp", true, false)
    if help != null: help.text = _roster_help_text()

func set_p2_repo_ai(value: bool) -> bool:
    return set_p2_input_owner("repo_ai" if value else "human")

func set_p2_input_owner(value: String) -> bool:
    if value not in ["human", "sparring_easy", "repo_ai"]: return false
    var use_ai := value != "human"
    if use_ai and not _refresh_ai_stage_bounds(): return false
    if use_ai and "ice_mage" in selected_fighters:
        generated_collision_notice = "REFUSED: AI comparison supports Teknium/Turbo only. Select both kits first."
        return false
    if use_ai:
        if not set_generated_collision_enabled(true): return false
    else:
        reset_lab()
    p2_input_owner = value
    repo_inputs.configure(2, value == "repo_ai", ai_difficulty)
    sparring_inputs.configure(2, value == "sparring_easy", "easy")
    _reset_round_input_and_visuals()
    return true

func set_ai_difficulty(value: String) -> bool:
    if p2_input_owner == "sparring_easy" or value not in ["easy", "normal", "hard"]: return false
    ai_difficulty = value
    repo_inputs.configure(2, repo_inputs.enabled, value)
    reset_lab()
    return true

func set_comparison_interaction(value: String) -> bool:
    if value not in ["grounded_jostle", "legacy_solid"]: return false
    var previous := comparison_interaction
    comparison_interaction = value
    if not set_generated_collision_enabled(true):
        comparison_interaction = previous
        return false
    return true

var selected_fighters: Array = ["teknium", "teknium"]
var fighter_buttons: Array = []

func select_fighter(slot: int, kit_id: String) -> bool:
    if slot < 0 or slot >= actors.size() or kit_id not in ["teknium", "turbofit", "ice_mage"]: return false
    if generated_collision_enabled and kit_id == "ice_mage":
        generated_collision_notice = "REFUSED: Ice is unsupported. Turn draft generated collision OFF first (reset)."
        return false
    if selected_fighters[slot] == kit_id: return true
    if not simulation.configure_actor_kit(slot + 1, kit_id): return false
    selected_fighters[slot] = kit_id
    var help = find_child("RosterHelp", true, false)
    if help is Label: help.text = _roster_help_text()
    if slot < fighter_buttons.size(): fighter_buttons[slot].text = "P%d: %s (change)" % [slot + 1, kit_id.capitalize()]
    if is_instance_valid(imported_visuals[slot]): imported_visuals[slot].free()
    var visual = IcePresenter.new() if kit_id == "ice_mage" else (TurboPresenter.new() if kit_id == "turbofit" else Presenter.new())
    actors[slot].add_child(visual)
    imported_visuals[slot] = visual
    if generated_collision_enabled: return set_generated_collision_enabled(true)
    reset_lab()
    return true
var simulation = Match.new()
var actors: Array = []
var sources: Array = []
var imported_visuals: Array = []
# Read-only reconciliation of match-owned shots. No collision or simulation.
var projectile_visuals: Dictionary = {}
var orb_visuals: Dictionary = {}
# Diagnostic render geometry only, not authored final FX or contact volumes.
var grab_visuals: Dictionary = {}
var spawns := {1: Vector3(-1, 0.1, 0), 2: Vector3(1, 0.1, 0)}

func _ready() -> void:
    repo_inputs.configure(2, false, ai_difficulty)
    sparring_inputs.configure(2, false, "easy")
    _build_world()
    _refresh_ai_stage_bounds()
    for slot in range(2):
        var actor = Actor.new()
        actor.profile = Pilot
        add_child(actor)
        actors.append(actor)
        simulation.register_actor(slot + 1, actor)
        var source = Source.new()
        source.slot = slot
        # A newly entered scene must not turn already-held keys into presses.
        source.reset()
        # Deliberately no load/save profile: fixed combat controls, no disk changes.
        sources.append(source)
        var visual = Presenter.new()
        actor.add_child(visual)
        imported_visuals.append(visual)
        var label := Label3D.new()
        label.text = "P%d" % (slot + 1)
        label.position.y = 2.6
        label.font_size = 44
        label.pixel_size = 0.008
        label.modulate = Color("61e6b3") if slot == 0 else Color("ffb665")
        actor.add_child(label)
    simulation.reset(spawns)
    collision_debug = CollisionDebug.new()
    collision_debug.name = "CollisionDebugOverlay"
    collision_debug.visible = false
    add_child(collision_debug)
    _build_overlay()
    _sync_visuals()

var paused := false
var pending_steps := 0
var last_input_physics := -1
var last_lifecycle_event := ""
var sandbox_defense_enabled := false
var sandbox_ledges_enabled := false

func set_ledges_enabled(value: bool) -> void:
    if simulation.rules == null: sandbox_ledges_enabled = value
    simulation.configure_ledges(CombatLabStage.new().create_anchors(), LedgePolicy.new() if value else null)
    reset_lab()

func set_defense_enabled(value: bool) -> void:
    # Configuration changes are round boundaries, never live timer/resource edits.
    if simulation.rules == null: sandbox_defense_enabled = value
    simulation.configure_defense(DefenseProfile.new() if value else null)
    reset_lab()

func set_paused(value: bool) -> void:
    paused = value
    pending_steps = 0
    for slot in range(sources.size()):
        sources[slot].reset()
        simulation.fighters[slot + 1].buffer.clear()

func step_once() -> void:
    if paused and simulation.result.is_empty(): pending_steps += 1

func start_stock_match() -> void:
    # Complete roster is registered in _ready; the stage resource owns stock data.
    simulation.configure_rules(MatchRules.new())
    set_hitstop_enabled(true)
    simulation.configure_defense(DefenseProfile.new())
    simulation.configure_ledges(CombatLabStage.new().create_anchors(), LedgePolicy.new())
    rematch_lab()

func set_hitstop_enabled(value: bool) -> void:
    # Match copies tuning; never mutate an active profile or own stop timers here.
    var profile = HitstopProfile.new() if value else null
    if profile != null: profile.direct_hit_ticks = 4 # Proposed initial tuning.
    simulation.configure_hitstop(profile)
    if is_instance_valid(hitstop_button): hitstop_button.set_pressed_no_signal(value)

func enter_sandbox() -> void:
    # Swap the optional rules reference only between rounds, never mutate its
    # copied stage. Retain Match (and its engine-frame guard) and source owners.
    simulation.rules = null
    set_hitstop_enabled(false)
    simulation.configure_defense(DefenseProfile.new() if sandbox_defense_enabled else null)
    simulation.configure_ledges(CombatLabStage.new().create_anchors(), LedgePolicy.new() if sandbox_ledges_enabled else null)
    reset_lab()

func rematch_lab() -> void:
    if simulation.rules == null: return
    simulation.rematch()
    _reset_round_input_and_visuals()

func reset_lab() -> void:
    if simulation.rules != null:
        rematch_lab()
        return
    simulation.reset(spawns)
    _reset_round_input_and_visuals()

func _reset_round_input_and_visuals() -> void:
    _refresh_ai_stage_bounds()
    repo_inputs.reset()
    sparring_inputs.reset()
    pending_steps = 0
    last_lifecycle_event = ""
    for source in sources: source.reset()
    for visual in imported_visuals:
        if is_instance_valid(visual): visual.reset()
    _consume_lifecycle()
    _sync_visuals()

func _consume_lifecycle() -> void:
    # Events are a completed batch. Never intervene inside Match's combat/KO
    # pass. A source reset preserves bindings/device/slot and suppresses held
    # actions at the next real sample. Local frames never survive a callback.
    if simulation.lifecycle_events.is_empty(): return
    if simulation.lifecycle_events.back().event_id == last_lifecycle_event: return
    var affected := {}
    for event in simulation.lifecycle_events:
        match event.kind:
            "ko", "respawn", "eliminated": affected[event.entity_id] = true
            "result", "rematch":
                for id in simulation.fighters: affected[id] = true
    if not simulation.lifecycle_events.is_empty():
        last_lifecycle_event = simulation.lifecycle_events.back().event_id
    if not affected.is_empty():
        pending_steps = 0
        repo_inputs.reset()
        sparring_inputs.reset()
    for id in affected:
        sources[id - 1].reset()
        simulation.fighters[id].buffer.clear()
        if is_instance_valid(imported_visuals[id - 1]): imported_visuals[id - 1].reset()

func _notification(what: int) -> void:
    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT: set_paused(true)

func _physics_process(_delta: float) -> void:
    if not simulation.result.is_empty():
        pending_steps = 0
        return # Discard gameplay during results, never accumulate future edges.
    if paused and pending_steps == 0: return
    if last_input_physics == Engine.get_physics_frames(): return
    last_input_physics = Engine.get_physics_frames()
    if paused: pending_steps -= 1
    if not _refresh_ai_stage_bounds() and _ai_enabled():
        set_paused(true)
        return
    var human_frames := {}
    for slot in range(2):
        if slot == 1 and _ai_enabled(): continue
        human_frames[slot + 1] = sources[slot].sample(simulation.tick)
        if not sources[slot].connected:
            sources[slot].reset()
            simulation.set_enabled(slot + 1, false)
    simulation.simulate(_selected_inputs().sample_all(simulation, human_frames))
    _consume_lifecycle()
    _sync_visuals()

func _sync_visuals() -> void:
    _sync_projectiles()
    _sync_orbs()
    for slot in range(2):
        actors[slot].visible = not simulation.fighters[slot + 1].eliminated
        if not is_instance_valid(imported_visuals[slot]): continue
        if generated_collision_enabled:
            imported_visuals[slot].present_canonical(simulation.collision_telemetry(slot + 1))
            continue
        var data: Dictionary = actors[slot].telemetry()
        data.facing = simulation.fighters[slot + 1].facing
        var fighter: Dictionary = simulation.fighters[slot + 1]
        data.committed_identity = [simulation.generation, fighter.enabled, fighter.activation_id, data.get("status", ""), data.get("hit_id", null)]
        var defense: Dictionary = simulation.defense_telemetry(slot + 1)
        if not defense.delegate_legacy:
            data.committed_identity.append(defense.state)
            # Existing snapshot inputs only. These are labeled asset fallbacks,
            # never new statuses, animation clips, immunity or runtime writers.
            if defense.state == "break" and data.get("status", "") == "normal":
                data.hit = true
                data.hit_id = [simulation.generation, "defense_break", slot]
            elif defense.state.begins_with("dodge_") and data.get("action", "") == "movement_lock":
                data.action = "" # Existing locomotion pose, not protective Block.
        data.strike_id = fighter.activation_id if fighter.move_id in ["SIDE STRIKE", "AIR STRIKE", "UPPERCUT", "UP AIR", "LOW SWEEP", "DOWN STRIKE"] else ""
        # Opt in only the new directional basics: accepted SIDE/AIR retain P3
        # source-seconds and zero strike placement. This is never contact timing.
        if fighter.move_id in ["UPPERCUT", "UP AIR", "LOW SWEEP", "DOWN STRIKE"]:
            data.strike_move = fighter.move_id
            data.strike_elapsed = (simulation.tick - fighter.ready_tick + 20) / 60.0
        # Presentation episode follows committed identity, NOT contact lifetime.
        # Match shifts live ready_tick on skipped actor ticks: world minus ready
        # is an actor-relative age, including contact expiry and terrain landing.
        if fighter.move_id == "RISING STRIKE":
            data.recovery_id = fighter.activation_id
            data.recovery_elapsed = (simulation.tick - fighter.ready_tick + Recovery.COOLDOWN_TICKS) / 60.0
        if fighter.force != null:
            data.force_id = fighter.force.activation_id
            data.force_source_time = fighter.force.source_time(fighter.force.age / 60.0)
            data.facing = fighter.force.facing
        if fighter.grab != null:
            var grab = fighter.grab
            data.facing = grab.facing
            var seconds: float = grab.elapsed
            var clip := "GrabEnd"
            if grab.phase == "startup":
                clip = "GrabStart"
                seconds = seconds * (13.0 / 24.0) / .20 if seconds <= .20 else 13.0 / 24.0 + seconds - .20
            elif grab.phase == "hold":
                clip = "GrabLoop"
                seconds = fmod(seconds, 1.25) if seconds > 1.25 else seconds
            data.grab_pose = {"clip": clip, "seconds": seconds}
        elif fighter.caught_by != 0:
            var owner: Dictionary = simulation.fighters.get(fighter.caught_by, {})
            if not owner.is_empty() and owner.grab != null and owner.grab.victim == slot + 1 and owner.grab.phase == "hold" and fighter.enabled and not fighter.frozen:
                data.grab_pose = {"clip": "Electrocution", "seconds": owner.grab.elapsed}
                if selected_fighters[slot] == "ice_mage":
                    data.electrocution = {"activation_id": owner.grab.activation_id, "elapsed": owner.grab.elapsed}
        # World time continues for shots; bones/blends use only committed actor
        # advancement. In particular remaining==0 is still the last stopped tick.
        if selected_fighters[slot] in ["turbofit", "ice_mage"]:
            var kit: Dictionary = simulation.kit_telemetry(slot + 1)
            data.presentation = kit.presentation
            # Pause already holds committed ticks. A manual Step must still
            # consume its new age; only an actual actor-local stop freezes it.
            data.stopped = kit.stopped
            # Kit locks are not shields. Only actual defense selects BlockIdle.
            if not str(kit.presentation.get("activation_id", "")).is_empty() and data.action == "movement_lock": data.action = ""
            # There is no authored Turbofit electrocution/ledge clip. Keep the
            # honest generic restrained pose; Teknium's caster/arcs are unchanged.
            if fighter.caught_by != 0: data.action = "block"
        imported_visuals[slot].present(data, simulation.hitstop_telemetry(slot + 1).simulation_tick)
    _sync_grab_visuals()
    _sync_top_support_label()
    if is_instance_valid(collision_debug): collision_debug.refresh()

func _sync_grab_visuals() -> void:
    var live := {}
    for id in simulation.fighters:
        var f: Dictionary = simulation.fighters[id]
        var grab = f.grab
        if grab == null or grab.phase != "hold" or grab.victim == 0: continue
        var victim: Dictionary = simulation.fighters.get(grab.victim, {})
        if victim.is_empty() or victim.caught_by != id or not victim.enabled or victim.frozen: continue
        if not is_instance_valid(imported_visuals[id - 1]): continue
        var visual = imported_visuals[id - 1]
        if not visual.visible: continue
        var identity: String = grab.activation_id
        live[identity] = true
        if not is_instance_valid(grab_visuals.get(identity)):
            var arc := MeshInstance3D.new()
            arc.name = "DiagnosticGrabArcs"
            var material := StandardMaterial3D.new()
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.albedo_color = Color(.65, .86, 1)
            material.cull_mode = BaseMaterial3D.CULL_DISABLED
            arc.material_override = material
            add_child(arc)
            grab_visuals[identity] = arc
        var arc: MeshInstance3D = grab_visuals[identity]
        if arc.get_meta("tick", -1) == simulation.tick: continue
        arc.set_meta("tick", simulation.tick)
        var skeleton: Skeleton3D = visual.skeleton
        var start: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")) * Vector3(0, 19.50612449645996, 0)
        var center: Vector3 = victim.actor.global_position + Vector3(0, 1.25, 0)
        var mesh := ImmediateMesh.new()
        mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
        for strand in range(4):
            var previous := start
            for point in range(1, 7):
                var t := point / 6.0
                var next := start.lerp(center + Vector3(0, (strand - 1.5) * .16, .18 * sin(strand)), t)
                next += Vector3(0, sin(point * 4 + grab.elapsed * 32 + strand) * .055, cos(point * 3 + grab.elapsed * 29 + strand) * .055) * sin(t * PI)
                var side := (next - previous).cross(Vector3.BACK).normalized() * .012
                for vertex in [previous-side, previous+side, next+side, previous-side, next+side, next-side]:
                    mesh.surface_add_vertex(arc.to_local(vertex))
                previous = next
        mesh.surface_end()
        arc.mesh = mesh
    for identity in grab_visuals.keys():
        if not live.has(identity):
            if is_instance_valid(grab_visuals[identity]): grab_visuals[identity].free()
            grab_visuals.erase(identity)

func _sync_projectiles() -> void:
    var live := {}
    for shot in simulation.projectile_telemetry():
        var id: String = shot.activation_id
        live[id] = true
        if not is_instance_valid(projectile_visuals.get(id)):
            var visual := MeshInstance3D.new()
            var mesh := SphereMesh.new()
            mesh.radius = 0.14
            mesh.height = 0.28
            visual.mesh = mesh
            if shot.kind == "frost_bolt": visual.name = "DebugFrostBolt"
            if shot.kind == "sound_wave":
                var ring := TorusMesh.new()
                ring.inner_radius = .38
                ring.outer_radius = .46
                visual.mesh = ring
                visual.name = "DebugSoundWave"
                visual.rotation.z = PI / 2
            var material := StandardMaterial3D.new()
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            visual.material_override = material
            add_child(visual)
            projectile_visuals[id] = visual
        var visual: MeshInstance3D = projectile_visuals[id]
        visual.global_position = shot.position
        visual.set_meta("source", shot.source)
        visual.set_meta("facing", shot.facing)
        visual.set_meta("committed", shot.duplicate(true))
        visual.rotation.y = 0 if shot.facing > 0 else PI
        var color := Color("61e6b3") if shot.source == 1 else Color("ffb665")
        color.a = float(shot.get("opacity", 1.0))
        visual.material_override.albedo_color = color
    for id in projectile_visuals.keys():
        if not live.has(id):
            if is_instance_valid(projectile_visuals[id]): projectile_visuals[id].free()
            projectile_visuals.erase(id)

func _sync_orbs() -> void:
    var live := {}
    for id in simulation.fighters:
        if not is_instance_valid(simulation.fighters[id].actor): continue
        var kit: Dictionary = simulation.kit_telemetry(id)
        var special: Dictionary = kit.get("special", {})
        if special.get("move", "") != "sound_orb" or special.get("phase", "") != "active": continue
        var identity: String = special.activation_id
        live[identity] = true
        if not is_instance_valid(orb_visuals.get(identity)):
            var visual := MeshInstance3D.new()
            visual.name = "DebugSoundOrb"
            var mesh := SphereMesh.new()
            mesh.radius = 1.15
            mesh.height = 2.3
            visual.mesh = mesh
            var material := StandardMaterial3D.new()
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            visual.material_override = material
            add_child(visual)
            orb_visuals[identity] = visual
        var visual: MeshInstance3D = orb_visuals[identity]
        visual.global_position = simulation.fighters[id].actor.global_position + Vector3.UP
        visual.set_meta("source", id)
        visual.set_meta("committed", special.duplicate(true))
        var color := Color("61e6b3") if id == 1 else Color("ffb665")
        color.a = .16
        visual.material_override.albedo_color = color
    for identity in orb_visuals.keys():
        if not live.has(identity):
            if is_instance_valid(orb_visuals[identity]): orb_visuals[identity].free()
            orb_visuals.erase(identity)

var telemetry_label: Label
var pause_button: Button
var reset_button: Button
var stock_label: Label
var rematch_button: Button
var hitstop_button: CheckButton
var defense_button: CheckButton
var ledges_button: CheckButton

func get_snapshot() -> Dictionary:
    var players: Array = []
    for slot in range(actors.size()):
        var f: Dictionary = simulation.fighters[slot + 1]
        var data: Dictionary = actors[slot].telemetry().duplicate(true)
        var pos: Vector3 = actors[slot].position
        var vel: Vector3 = actors[slot].velocity
        data.position = [pos.x, pos.y, pos.z]
        data.velocity = [vel.x, vel.y, vel.z]
        data.percent = f.percent
        data.kit = simulation.kit_telemetry(slot + 1) if selected_fighters[slot] != "teknium" else {"kit_id": "teknium"}
        data.freeze = simulation.status_telemetry(slot + 1)
        data.freeze.erase("generation") # Reset-local diagnostic; preserve round trace compatibility.
        data.kit_id = selected_fighters[slot]
        if generated_collision_enabled:
            var collision: Dictionary = simulation.collision_telemetry(slot + 1)
            data.collision = {"geometry_mode": collision.get("geometry_mode", ""), "ok": collision.get("ok", false), "diagnostics": collision.get("diagnostics", []), "current_pose": _collision_pose_summary(collision), "contact_snapshot": _collision_pose_summary(collision.get("contact_snapshot", {}))}
        data.ledge = simulation.ledge_telemetry(slot + 1)
        data.defense = simulation.defense_telemetry(slot + 1)
        if not data.defense.delegate_legacy:
            var motion: Vector2 = data.defense.motion_velocity
            data.defense.motion_velocity = [motion.x, motion.y]
        var hitstop: Dictionary = simulation.hitstop_telemetry(slot + 1)
        data.simulation_tick = hitstop.simulation_tick
        data.hitstop_remaining_ticks = hitstop.remaining_ticks
        data.hitstop_stopped_this_tick = hitstop.stopped_this_tick
        data.cooldown_ticks = maxi(0, f.ready_tick - simulation.tick)
        if selected_fighters[slot] != "teknium":
            data.cooldown_ticks = int(ceil(maxf(data.kit.interrupted_cooldown, maxf(data.kit.basic.remaining, data.kit.special.cooldown)) * 60.0 - .000001))
        data.move_id = f.move_id
        data.recovery_spent = actors[slot].runtime.recovery_spent
        data.recovery_active = f.recovery != null
        data.recovery_age = f.recovery.age if f.recovery != null else -1
        data.recovery_id = f.activation_id if f.move_id == "RISING STRIKE" else ""
        data.recovery_elapsed = (simulation.tick - f.ready_tick + Recovery.COOLDOWN_TICKS) / 60.0 if not data.recovery_id.is_empty() else -1.0
        data.force_age = f.force.age if f.force != null else -1
        data.force_source_time = f.force.source_time(f.force.age / 60.0) if f.force != null else -1.0
        data.grab_phase = f.grab.phase if f.grab != null else "idle"
        data.caught_by = f.caught_by
        data.grab_ordinal = f.grab.ordinal if f.grab != null else 0
        data.grab_immunity_ticks = maxi(0, f.grab_immune_until - simulation.tick)
        data.enabled = f.enabled
        data.stocks = f.stocks
        data.eliminated = f.eliminated
        data.pending = f.buffer.debug_pending()
        players.append(data)
    var shots: Array = []
    for shot in simulation.projectile_telemetry():
        if shot.kind == "force":
            shots.append({"activation_id": shot.activation_id, "source": shot.source, "facing": shot.facing, "position": [shot.position.x, shot.position.y, shot.position.z], "ttl": shot.ttl, "spawn_tick": shot.spawn_tick})
        else:
            shot.position = [shot.position.x, shot.position.y, shot.position.z]
            shots.append(shot)
    return {"lab": "first-strike", "fighter_interaction_mode": simulation.fighter_interaction_mode, "generated_collision_enabled": generated_collision_enabled, "active_collision_profiles": active_collision_profiles.duplicate(true), "generated_collision_notice": generated_collision_notice, "collision_snapshot_phase": collision_snapshot_phase, "scope": "strikes-force-push-recovery", "tick": simulation.tick, "paused": paused, "hitstop_enabled": simulation.hitstop_profile != null, "defense_enabled": not simulation.defense_telemetry(1).delegate_legacy, "ledges_enabled": simulation.ledge_policy != null, "actors": players, "projectiles": shots, "mode": "sandbox" if simulation.rules == null else "stocks", "result": simulation.result.duplicate(true)}

func _collision_pose_summary(record: Dictionary) -> Dictionary:
    var pose: Dictionary = record.get("pose_request", {})
    return {"ok": record.get("ok", false), "clip": pose.get("clip", ""), "source_seconds": pose.get("source_seconds", 0.0), "episode_id": pose.get("episode_id", []), "primitive_count": record.get("primitives", []).size(), "blend_policy": pose.get("blend_policy", "")}

func _process(_delta: float) -> void:
    _frame_camera()
    # Match utility cancellation is synchronous even when simulation is paused.
    # Reconcile live relations before rendering, never rely on stale events.
    _sync_visuals()
    if not is_instance_valid(telemetry_label): return
    var snapshot := get_snapshot()
    if is_instance_valid(generated_collision_label):
        _sync_comparison_controls()
        generated_collision_label.visible = generated_collision_enabled or generated_collision_notice.begins_with("REFUSED")
        generated_controls.visible = generated_collision_label.visible
        collision_snapshot_button.visible = generated_collision_enabled
        var identity_lines := PackedStringArray()
        var identity_details := PackedStringArray()
        for id in active_collision_profiles:
            var identity: Dictionary = active_collision_profiles[id]
            identity_lines.append("P%d: %s / %s" % [id, identity.override_path.get_file().get_basename(), identity.revision])
            identity_details.append("P%d: %s + %s\nBalance revision: %s; source SHA256: %s\nBase SHA256: %s; override SHA256: %s" % [id, identity.base_path, identity.override_path, identity.revision, identity.source_sha256, identity.base_sha256, identity.override_sha256])
        var status := "DRAFT anatomically tuned: all accepted Teknium/Turbo recipient routes. No blend; ON/OFF resets."
        if generated_collision_notice.begins_with("REFUSED"): status = generated_collision_notice
        generated_collision_label.text = status + ("\n" + "  |  ".join(identity_lines) if not identity_lines.is_empty() else "")
        generated_collision_label.tooltip_text = "\n".join(identity_details) + "\nCyan terrain capsule dimensions unchanged from generated base; not fighter blocking in grounded jostle. Recipient wiring is not visual fist/foot contact acceptance."
    var phase := "RESULTS" if not simulation.result.is_empty() else ("PAUSED" if paused else "LIVE")
    telemetry_label.text = "Tick %d / %s / shots %d" % [simulation.tick, phase, simulation.projectile_telemetry().size()]
    for slot in range(2):
        var ledge: Dictionary = snapshot.actors[slot].ledge
        telemetry_label.text += " | P%d ledge %s / protected %s / regrab %d" % [slot + 1, ledge.anchor_id if ledge.anchor_id != "" else "free", str(ledge.protected), maxi(0, int(ledge.get("unlock_tick", 0)) - simulation.tick)]
    telemetry_label.text += "\n"
    for slot in range(2):
        var data: Dictionary = snapshot.actors[slot]
        var eligibility := " / ELIMINATED" if data.eliminated else (" / DISCONNECTED: reset to reenter" if not data.enabled else "")
        telemetry_label.text += "P%d: %.1f%% | %s / %s | %s | cooldown %d ticks | queued %d%s | hitstop %d / stopped %s / actor tick %d\n" % [slot + 1, data.percent, data.locomotion, data.status, data.move_id, data.cooldown_ticks, data.pending.size(), eligibility, data.hitstop_remaining_ticks, str(data.hitstop_stopped_this_tick), data.simulation_tick]
        if data.kit_id == "turbofit":
            var special: Dictionary = data.kit.special
            telemetry_label.text += "    recovery: spent %s / active %s | %s age %.2f / power %.2f | " % [str(data.recovery_spent), str(data.recovery_active), special.phase, special.age, special.power]
        elif data.kit_id == "ice_mage":
            telemetry_label.text += "    recovery: spent %s / active %s | cast budget %.2fs | " % [str(data.recovery_spent), str(data.recovery_active), data.kit.cast_cooldown]
        else:
            telemetry_label.text += "    recovery: spent %s / active %s | grab: %s / caught by %d / ordinal %d / immunity %d | " % [str(data.recovery_spent), str(data.recovery_active), data.grab_phase, data.caught_by, data.grab_ordinal, data.grab_immunity_ticks]
        telemetry_label.text += "freeze %.2f / immune %.2f | " % [data.freeze.freeze_remaining, data.freeze.freeze_immunity]
        var defense: Dictionary = data.defense
        if defense.delegate_legacy:
            telemetry_label.text += "defense: legacy lock only\n"
        else:
            telemetry_label.text += "defense: %s %dt / shield %.0f / air %d / defCD %d\n" % [defense.state, defense.remaining_ticks, defense.shield_health, defense.air_charges, defense.cooldown_ticks]
    telemetry_label.text = telemetry_label.text.trim_suffix("\n")
    pause_button.text = "Resume [F1]" if paused else "Pause [F1]"
    defense_button.set_pressed_no_signal(snapshot.defense_enabled)
    ledges_button.set_pressed_no_signal(snapshot.ledges_enabled)
    var stock_mode: bool = simulation.rules != null
    reset_button.text = "Rematch [F3]" if stock_mode else "Reset sandbox [F3]"
    rematch_button.visible = stock_mode
    stock_label.text = "SANDBOX / Fall off: reset"
    if stock_mode:
        var outcome := "FIGHTING"
        if not simulation.result.is_empty():
            outcome = "DRAW" if simulation.result.kind == "DRAW" else "WIN — P%d" % simulation.result.winner_id
        stock_label.text = "%s | P1 %d / P2 %d stocks" % [outcome, simulation.fighters[1].stocks, simulation.fighters[2].stocks]
    if OS.has_feature("web"):
        JavaScriptBridge.eval("window.__nrcuLab = " + JSON.stringify(snapshot) + ";", true)

func open_collision_editor() -> void:
    set_paused(true)
    get_tree().change_scene_to_file("res://scenes/collision_authoring_lab.tscn")

func back_to_movement() -> void:
    set_paused(true)
    get_tree().change_scene_to_file("res://scenes/training_lab.tscn")

func _exit_tree() -> void:
    for source in sources:
        source.reset()
        if Input.joy_connection_changed.is_connected(source._on_joy_connection_changed):
            Input.joy_connection_changed.disconnect(source._on_joy_connection_changed)
    for id in simulation.fighters:
        simulation.set_enabled(id, false)
    _sync_projectiles()
    _sync_grab_visuals()
    _sync_orbs()
    simulation.fighters.clear()
    sources.clear()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    match event.physical_keycode:
        KEY_F1: set_paused(not paused)
        KEY_F2: step_once()
        KEY_F3: reset_lab()
        KEY_F4: set_collision_shapes_visible(not collision_debug.visible)
        KEY_F5: set_generated_collision_enabled(not generated_collision_enabled)
        KEY_F6: set_collision_snapshot_phase("contact_snapshot" if collision_snapshot_phase == "current_pose" else "current_pose")
        KEY_ESCAPE:
            # Scene replacement detaches this node; consume input while attached.
            get_viewport().set_input_as_handled()
            back_to_movement()
            return
        _: return
    get_viewport().set_input_as_handled()

func _button(parent: Node, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _roster_help_text() -> String:
    var lines: PackedStringArray = []
    for slot in range(2):
        var prefix := "P%d %s: " % [slot + 1, str(selected_fighters[slot]).capitalize()]
        if slot == 1 and p2_input_owner == "sparring_easy":
            lines.append("P2 Sparring / Easy (ours): beginner practice; delayed reactions, deliberate openings. P2 keyboard ignored. Damage unchanged.")
            continue
        if slot == 1 and repo_inputs.enabled:
            lines.append("P2 Repo AI (Mikey adaptation) / %s / %s. P2 keyboard ignored. Not exact original-game parity." % [selected_fighters[slot].capitalize(), ai_difficulty.capitalize()])
            continue
        var movement := "A/D move, Space jump; F basic, W/S+F up/down" if slot == 0 else "arrows move, Enter jump; K basic, Up/Down+K up/down"
        var special := "G" if slot == 0 else "L"
        var recovery := "W+G" if slot == 0 else "Up+L"
        if selected_fighters[slot] == "teknium":
            lines.append(prefix + movement + ". SIDE / AIR STRIKE; UPPERCUT / UP AIR; LOW SWEEP / DOWN STRIKE.")
            lines.append(prefix + special + ": neutral ELECTRIC GRAB (exact no-axis); side FORCE PUSH; up RISING STRIKE recovery (" + recovery + "); down no-op (source intent).")
        elif selected_fighters[slot] == "ice_mage":
            lines.append(prefix + movement + ". IceStrike: all ground/air directions, 8 damage at .2s; .55s action; hit/air: Idle fallback.")
            lines.append(prefix + special + ": neutral/side/down FROST BOLT (same bolt), 1.6s cast budget; up FROST RISE (" + recovery + ", no bolt).")
        else:
            lines.append(prefix + movement + ". Ground side guitar / up backhand / down kick; air side/down foot, up backhand.")
            lines.append(prefix + special + ": neutral hold/release POWER CHORD; side SOUND WAVE; down SOUND ORB; up RISING CHORD recovery (" + recovery + ").")
    lines.append("Ledges: fall outside, turn inward; release to hang. Space/Enter jump; S/Down drop; W/Up or inward climb. Finite E/O: fresh press+direction dodge; neutral ground shield / air spot.")
    lines.append("Release after pause/reset. Opt-in stocks; 33-tick respawn stun, protection 0 (not new defense). Dodge/break; Hang/climb: fallback. Ice full freeze: Idle; Turbo caught: Block. Debug FX: not authored final FX.")
    return "\n".join(lines)

func _build_overlay() -> void:
    var overlay := CanvasLayer.new()
    add_child(overlay)
    # Reserve the middle for the unchanged camera's recovery arc. Scroll inside
    # the edge bands on small viewports instead of growing over the fighters.
    var panel := _overlay_band(overlay, 0.0, 0.26, 14.0, 0.0)
    var column := VBoxContainer.new()
    panel.add_child(column)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 0)
    column.add_theme_font_size_override("font_size", 14)
    var title := Label.new()
    title.text = "NRCU / COMBAT LAB"
    title.add_theme_font_size_override("font_size", 20)
    var title_row := HFlowContainer.new()
    column.add_child(title_row)
    title_row.add_child(title)
    var editor_button := _button(title_row, "Collision editor", open_collision_editor)
    editor_button.name = "CollisionEditor"
    editor_button.tooltip_text = "Isolated authoring opens the protected generated base, not the active merged anatomical profile. Load its separate override explicitly to inspect tuning; never overwrite generated data. Returning starts fresh default combat; save edits before leaving."
    collision_shapes_button = CheckButton.new()
    collision_shapes_button.name = "CollisionShapes"
    collision_shapes_button.text = "Collision shapes"
    collision_shapes_button.tooltip_text = "F4 visibility only. Cyan is the real native terrain capsule in grounded jostle, not fighter blocking. Legacy solid support is shown only in legacy mode. F5 separately resets collision mode."
    collision_shapes_button.focus_mode = Control.FOCUS_NONE
    collision_shapes_button.toggled.connect(set_collision_shapes_visible)
    title_row.add_child(collision_shapes_button)
    for slot in range(2):
        var button := _button(title_row, "P%d: Teknium (change)" % (slot + 1), func(): select_fighter(slot, ("turbofit" if selected_fighters[slot] == "teknium" else "teknium") if generated_collision_enabled else {"teknium": "turbofit", "turbofit": "ice_mage", "ice_mage": "teknium"}[selected_fighters[slot]]))
        fighter_buttons.append(button)
    var scope := Label.new()
    scope.name = "RosterHelp"
    scope.text = _roster_help_text()
    scope.add_theme_font_size_override("font_size", 12)
    scope.add_theme_constant_override("line_spacing", 0)
    column.add_child(scope)
    var collision_legend := Label.new()
    collision_legend.name = "CollisionLegend"
    collision_legend.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    collision_legend.text = "F4 view: cyan body / orange physical top-support (one-way) / green terrain / magenta hurtboxes / yellow witness [F6]"
    collision_legend.tooltip_text = "Visibility only, not collision mode. Grounded jostle is horizontal separation, not a floor or solid fighter capsule. Legacy support surface is not an active relation. Disabled/nonparticipants hidden; layers 2/1, masks and pair exceptions still filter. Not attack queries. Magenta post-contact current pose; yellow frozen pre-contact witness."
    collision_legend.add_theme_font_size_override("font_size", 12)
    collision_legend.visible = false
    column.add_child(collision_legend)
    column.move_child(collision_legend, 1)
    var row := HBoxContainer.new()
    column.add_child(row)
    pause_button = _button(row, "Pause [F1]", func(): set_paused(not paused))
    _button(row, "Step [F2]", step_once)
    reset_button = _button(row, "Reset sandbox [F3]", reset_lab)
    _button(row, "Movement lab [Esc]", back_to_movement)
    defense_button = CheckButton.new()
    defense_button.text = "Finite defense (reset)"
    defense_button.focus_mode = Control.FOCUS_NONE
    defense_button.toggled.connect(set_defense_enabled)
    row.add_child(defense_button)
    ledges_button = CheckButton.new()
    ledges_button.text = "Ledges (reset)"
    ledges_button.focus_mode = Control.FOCUS_NONE
    ledges_button.toggled.connect(set_ledges_enabled)
    row.add_child(ledges_button)
    column.move_child(row, 1)
    var generated_row := HBoxContainer.new()
    generated_controls = generated_row
    generated_row.visible = false
    column.add_child(generated_row)
    column.move_child(generated_row, 2)
    generated_collision_button = CheckButton.new()
    generated_collision_button.name = "GeneratedCollision"
    generated_collision_button.text = "Teknium / Turbo collision (reset) [F5]"
    generated_collision_button.tooltip_text = "Teknium / Turbo only: anatomically tuned draft (anatomical-v1), all accepted recipient routes. Cyan terrain capsule unchanged; grounded horizontal jostle, airborne pass-through, no head platform. Magenta tuned bone hurtboxes. Not visual-contact approval. ON/OFF fully resets. Release held actions. Ice refused."
    generated_collision_button.focus_mode = Control.FOCUS_NONE
    generated_collision_button.toggled.connect(set_generated_collision_enabled)
    title_row.add_child(generated_collision_button)
    for control in title_row.get_children(): control.add_theme_font_size_override("font_size", 12)
    collision_snapshot_button = _button(generated_row, "Pose [F6]", func(): set_collision_snapshot_phase("contact_snapshot" if collision_snapshot_phase == "current_pose" else "current_pose"))
    collision_snapshot_button.add_theme_font_size_override("font_size", 12)
    collision_snapshot_button.name = "CollisionSnapshotPhase"
    collision_snapshot_button.visible = false
    collision_snapshot_button.tooltip_text = "F4 outlines: magenta current_pose (post-contact render); yellow contact_snapshot (pre-contact witness, can differ after hit). Cyan stable body / green terrain. Conservative capsule enclosures, not mesh/attack geometry."
    generated_collision_label = Label.new()
    generated_collision_label.name = "GeneratedCollisionNotice"
    generated_collision_label.visible = false
    generated_collision_label.add_theme_font_size_override("font_size", 12)
    generated_collision_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    generated_row.add_child(generated_collision_label) # Identity and compact phase control share the visible band.
    telemetry_label = Label.new()
    telemetry_label.add_theme_font_size_override("font_size", 12)
    telemetry_label.add_theme_constant_override("line_spacing", 0)
    var diagnostics := _overlay_band(overlay, 0.8, 1.0, 0.0, -12.0)
    var bottom := VBoxContainer.new()
    bottom.add_theme_constant_override("separation", 0)
    diagnostics.add_child(bottom)
    var support_label := Label.new()
    support_label.name = "TopSupportTelemetry"
    support_label.add_theme_font_size_override("font_size", 12)
    support_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    support_label.visible = false
    bottom.add_child(support_label)
    var stock_row := HBoxContainer.new()
    bottom.add_child(stock_row)
    _button(stock_row, "Start 3-stock match", start_stock_match)
    _button(stock_row, "Sandbox", enter_sandbox)
    rematch_button = _button(stock_row, "Rematch", rematch_lab)
    rematch_button.visible = false
    stock_label = Label.new()
    stock_label.add_theme_font_size_override("font_size", 14)
    stock_row.add_child(stock_label)
    hitstop_button = CheckButton.new()
    hitstop_button.text = "Hitstop"
    hitstop_button.focus_mode = Control.FOCUS_NONE
    hitstop_button.toggled.connect(set_hitstop_enabled)
    stock_row.add_child(hitstop_button)
    bottom.add_child(telemetry_label)

    var comparison_row := HBoxContainer.new()
    column.add_child(comparison_row)
    column.move_child(comparison_row, 1)
    column.move_child(collision_legend, 2)
    p2_input_button = _comparison_choice(comparison_row, "P2Input", ["P2: Human", "P2: Sparring / Easy (ours)", "P2: Mikey AI adapted"], func(index):
        set_p2_input_owner(["human", "sparring_easy", "repo_ai"][index])
        _sync_comparison_controls())
    p2_input_button.tooltip_text = "Beginner recommendation: Sparring / Easy (ours), fixed Easy with practice openings; not a guarantee of winning. Mikey AI remains separate and unchanged. Source-derived adaptation of Mikey's scripts/bot_controller.gd with adapted stage sensing from the actual support collider, not exact legacy AI parity. Teknium/Turbo only. P1 remains human; P2 keyboard ignored when AI. Original whole game is a separate route, not this A/B comparator."
    ai_difficulty_button = _comparison_choice(comparison_row, "AIDifficulty", ["Easy", "Normal", "Hard"], func(index): set_ai_difficulty(["easy", "normal", "hard"][index]))
    ai_difficulty_button.tooltip_text = "Original easy / normal / hard decision intervals: .42 / .22 / .10 seconds. No RNG seed; original deterministic sequence."
    comparison_button = _comparison_choice(comparison_row, "ComparisonInteraction", ["New grounded jostle", "Previous solid bodies"], func(index):
        set_comparison_interaction("grounded_jostle" if index == 0 else "legacy_solid")
        _sync_comparison_controls())
    comparison_button.tooltip_text = "Both arms install identical generated anatomical hurtboxes and current attack/punch contacts, stage and rules. Previous solid includes prior top support; new mode has air pass-through, no head platform. NOT F5 OFF legacy damage."
    comparison_button.add_item("Interaction: F5 off")
    comparison_button.set_item_disabled(2, true)
    var reset_hint := Label.new()
    reset_hint.text = "Full reset; menus pause. F1 resumes."
    reset_hint.add_theme_font_size_override("font_size", 12)
    reset_hint.tooltip_text = "P2 / difficulty / interaction changes reset both fighters, stocks, human queues and AI sequence. Release held actions. F3 repeats the same round baseline."
    comparison_row.add_child(reset_hint)
    _sync_comparison_controls()

func _overlay_band(overlay: CanvasLayer, top: float, bottom: float, inset_top: float, inset_bottom: float) -> ScrollContainer:
    var panel := PanelContainer.new()
    overlay.add_child(panel)
    panel.anchor_right = 1.0
    panel.anchor_top = top
    panel.anchor_bottom = bottom
    panel.offset_left = 20.0
    panel.offset_right = -20.0
    panel.offset_top = inset_top
    panel.offset_bottom = inset_bottom
    var scroll := ScrollContainer.new()
    scroll.focus_mode = Control.FOCUS_NONE
    panel.add_child(scroll)
    scroll.get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
    scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
    return scroll

func _frame_camera() -> void:
    # Bounded ledge framing: keep both full capsules and the outside-up-in
    # routes above the diagnostics. No actor tracking/zoom pumping or world edits.
    # Opt-out retains the accepted sandbox recovery framing exactly.
    var camera := get_viewport().get_camera_3d()
    if camera == null: return
    var ledges := simulation.ledge_policy != null
    camera.size = 15.5 if ledges else 14.0
    camera.position = Vector3(0, 5 if ledges else 6, 28)
    camera.look_at(Vector3(0, 2 if ledges else 3, 0))

func _build_world() -> void:
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("111b2b")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("a3c4df")
    environment.environment.ambient_light_energy = 0.7
    add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-35, -25, 0)
    add_child(light)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 14
    camera.position = Vector3(0, 6, 28)
    add_child(camera)
    camera.look_at(Vector3(0, 3, 0))
    camera.current = true
    var floor_body := StaticBody3D.new()
    floor_body.position.y = -0.4
    floor_body.collision_layer = 1
    floor_body.collision_mask = 0
    var shape := CollisionShape3D.new()
    shape.shape = BoxShape3D.new()
    shape.shape.size = Vector3(24, 0.8, 3)
    main_support_shape = shape
    floor_body.add_child(shape)
    var mesh := MeshInstance3D.new()
    mesh.mesh = BoxMesh.new()
    mesh.mesh.size = shape.shape.size
    floor_body.add_child(mesh)
    add_child(floor_body)
