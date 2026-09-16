class_name Fighter
extends CharacterBody3D

const CombatMathScript = preload("res://scripts/combat_math.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const GooProjectileScript = preload("res://scripts/goo_projectile.gd")
const BotScript = preload("res://scripts/bot_controller.gd")
var prototype_fire := false
var burn
var reaction_recovery
var humanoid_air_basic
var humanoid_air_side
var fitted_reaction

# Contact routing affects presentation only; the native damage sink remains authoritative.
func receive_contact_hit(amount: float, direction: Vector3, push: float, point: Vector3, region := "") -> void:
    var accepted = controls_enabled and stocks > 0 and not shielding and not is_knockdown_protected() and amount > 0
    var role = region if region in ["head", "body"] else (fitted_reaction.classify(point) if fitted_reaction else "")
    receive_hit(amount, direction, push)
    if accepted and fitted_reaction and controls_enabled and stocks > 0:
        fitted_reaction.begin(role, signf(direction.x))

func is_knockdown_protected() -> bool:
    return reaction_recovery != null and reaction_recovery.is_knockdown_protected()

func begin_uppercut_reaction() -> void:
    if reaction_recovery: reaction_recovery.begin_uppercut_reaction()

func apply_status_damage(amount: float) -> void:
    if is_knockdown_protected(): return
    damage_percent = CombatMathScript.apply_damage(damage_percent, amount)
    state_changed.emit()

func apply_burn(caster: Node3D) -> bool:
    if not controls_enabled or stocks <= 0 or shielding or not is_instance_valid(caster) or not caster.controls_enabled or not caster.can_hit(self): return false
    if burn == null:
        burn = preload("res://scripts/burn_status.gd").new()
        add_child(burn)
    burn.refresh()
    return true

# External opponent harness opts in after construction; never a roster identity.
func enable_fire_prototype() -> void:
    if character_id != "ice_mage" or prototype_fire: return
    prototype_fire = true
    fighter_name = "FIRE MAGE [PROTOTYPE]"
    body_color = Color(1.0, 0.22, 0.06)
    preload("res://scripts/fire_palette.gd").apply(_visual_root.get_node("IceMageVisual").model)

var witcheer_clip := ""
var witcheer_elapsed := 0.0
var witcheer_facing := 1.0
var witcheer_struck := false
var witcheer_basic_targets: Array = []
var witcheer_moves: Dictionary = {}
var witcheer_clear := false
var witcheer_absorbing := false
var witcheer_air_started := false

func _latch_witcheer_inputs() -> void:
    if character_id not in ["witcheer", "doge_man", "ggb", "mephisto"] or control_type != "human" or not is_inside_tree(): return
    var held := read_controls(0)
    _attack_was_down = held.attack
    _special_was_down = held.special
    _jump_was_down = held.jump or held.up
    _down_was_down = held.down

func _start_witcheer(clip: String) -> void:
    witcheer_absorbing = false
    witcheer_clip = clip
    witcheer_elapsed = 0
    witcheer_struck = false
    witcheer_basic_targets.clear()
    witcheer_facing = facing
    witcheer_air_started = not is_grounded()
    attack_cooldown = float(witcheer_moves[clip].duration)
    if clip == "Toss": attack_cooldown -= float(witcheer_moves.Toss.contact_time) * (1.0 - 1.0/3.0)
    last_move = clip
    _update_move_visuals()

func _cancel_witcheer() -> void:
    if _visual_root:
        var visual = _visual_root.get_node_or_null("WitcheerVisual")
        if visual and visual.accent: visual.accent.visible = false
    witcheer_clip = ""
    witcheer_elapsed = 0
    witcheer_struck = false
    witcheer_basic_targets.clear()
    witcheer_clear = false
    witcheer_absorbing = false

func absorb_witcheer_projectile(owner_fighter: Node3D, amount: float) -> bool:
    if character_id != "witcheer" or witcheer_clip != "Celebration" or not witcheer_absorbing: return false
    if shielding or not controls_enabled or stocks <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return false
    if not is_instance_valid(owner_fighter) or not owner_fighter.controls_enabled or not owner_fighter.can_hit(self): return false
    var move: Dictionary = witcheer_moves.Celebration
    if witcheer_elapsed < float(move.contact_time) or witcheer_elapsed >= float(move.active_end): return false
    damage_percent = maxf(0, damage_percent - maxf(0, amount))
    return true

func _drive_witcheer() -> void:
    if witcheer_clip.is_empty() or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return
    facing = witcheer_facing
    if witcheer_clip == "AirSwim":
        velocity.x = facing * 5.5
        velocity.y = 1.2
    else:
        velocity.x = move_toward(velocity.x, 0, 1.5)

func witcheer_source_time() -> float:
    if witcheer_clip != "Toss": return witcheer_elapsed
    var contact: float = witcheer_moves.Toss.contact_time
    var release := contact / 3.0
    return witcheer_elapsed * 3.0 if witcheer_elapsed < release else contact + witcheer_elapsed - release

func _tick_witcheer(delta: float) -> void:
    if witcheer_clip.is_empty(): return
    if hitstun > 0 or freeze_remaining > 0 or not controls_enabled or magic_locked():
        _cancel_witcheer()
        return
    var previous_source = witcheer_source_time()
    witcheer_elapsed += delta
    facing = witcheer_facing
    var move: Dictionary = witcheer_moves[witcheer_clip]
    if witcheer_clip == "TurnaroundKick":
        preload("res://scripts/witcheer_basic_contacts.gd").sample(self,previous_source,witcheer_source_time())
        if witcheer_source_time() >= float(move.duration):
            facing = -witcheer_facing
            _cancel_witcheer()
        return
    if witcheer_clip in ["NeutralHook","HighKick"]:
        if not is_grounded():
            _cancel_witcheer()
            return
        preload("res://scripts/witcheer_basic_contacts.gd").sample(self,previous_source,witcheer_source_time())
        if witcheer_source_time() >= float(move.duration): _cancel_witcheer()
        return
    if not witcheer_struck and witcheer_source_time() + 0.000001 >= float(move.contact_time):
        witcheer_struck = true
        # Seek the exact authored event pose before the damaging/spawn event.
        var visual = _visual_root.get_node("WitcheerVisual")
        visual.show_move(witcheer_clip, float(move.contact_time), facing)
        if witcheer_clip == "Toss":
            var shot = ProjectileScript.new()
            shot.source = self
            shot.direction = facing
            shot.color = Color(0.8,0.65,0.25)
            get_parent().add_child(shot)
            shot.global_position = visual.hand_world()
            shot.global_position.z = 0
        elif witcheer_clip != "Celebration":
            for target in get_tree().get_nodes_in_group("fighters"):
                if not can_hit(target): continue
                var offset: Vector3 = target.global_position - global_position
                var forward: float = offset.x * facing
                var reaches: bool = absf(offset.z) < 1.0 and forward > 0 and forward < 2.5 and absf(offset.y) < 1.5
                if witcheer_clip == "CaneSweep" and not witcheer_clear:
                    reaches = reaches and offset.y < 0.8 and offset.y > -0.6
                if witcheer_clear:
                    reaches = offset.length() < 2.2
                if witcheer_clip == "SpinRise":
                    reaches = absf(offset.x) < 1.5 and absf(offset.z) < 1 and offset.y > -0.8 and offset.y < 2.2
                if reaches:
                    var direction := Vector3(facing,0.35,0)
                    if witcheer_clear: direction = Vector3(signf(offset.x),0.5,0)
                    if witcheer_clip == "SpinRise": direction = Vector3(facing*0.2,1,0)
                    target.receive_hit(7.0 if witcheer_clear else float(move.damage),direction,5.0 if witcheer_clear else 3.8)
        attack_flash_time = 0
    if witcheer_source_time() >= float(move.duration): _cancel_witcheer()

var teknium_magic
var caught_by
var grab_immunity := 0.0
var electrocution_presentation = preload("res://scripts/electrocution_presentation.gd").new()

func magic_locked() -> bool:
    return is_instance_valid(caught_by) or (teknium_magic != null and teknium_magic.phase != "idle")

func cancel_magic() -> void:
    if humanoid_air_basic: humanoid_air_basic.cancel()
    if humanoid_air_side: humanoid_air_side.cancel()
    if doge_air_drop: doge_air_drop.cancel()
    if fitted_reaction: fitted_reaction.clear()
    if reaction_recovery: reaction_recovery.clear()
    if mephisto_moves: mephisto_moves.cancel()
    electrocution_presentation.clear()
    if is_instance_valid(caught_by): caught_by.cancel()
    caught_by = null
    if teknium_magic: teknium_magic.cancel()

func _exit_tree() -> void:
    cancel_magic()

func cancel_for_grab() -> void:
    if humanoid_air_basic: humanoid_air_basic.cancel()
    if humanoid_air_side: humanoid_air_side.cancel()
    if doge_air_drop: doge_air_drop.cancel()
    if fitted_reaction: fitted_reaction.clear()
    if reaction_recovery: reaction_recovery.clear()
    if mephisto_moves: mephisto_moves.cancel()
    _cancel_witcheer()
    _cancel_ice_attack()
    _cancel_turbofit_attack()
    _cancel_doge_attack()
    _clear_sound_orb()
    torpedo_phase = "idle"
    torpedo_time = 0
    tackle_active = 0
    tackle_targets.clear()
    swing_windup = 0
    swing_followthrough = 0
    charging = false
    charge_time = 0
    recovery_active = 0
    recovery_targets.clear()
    drop_committed = false
    attack_flash_time = 0
    shielding = false
    hitstun = 0
    last_move = ""
    # A grab interrupts steel before the caught-pose path bypasses normal sync.
    if character_id == "ggb": _update_move_visuals(0, true)

signal state_changed
signal eliminated(fighter: Fighter)

@export var fighter_name := "Fighter"
@export var player_index := 1
@export var character_id := "teknium"
@export var team_id := -1
@export var input_device := -1
@export var control_type := "human"
@export var bot_difficulty := "normal"
@export var body_color := Color(0.2, 0.9, 0.35)

var damage_percent := 0.0
var stocks := 3
var spawn_position := Vector3.ZERO
var facing := 1.0
var jumps_used := 0
var hitstun := 0.0
const FREEZE_DURATION := 1.0
const FREEZE_IMMUNITY := 1.0
const ICE_CAST_COOLDOWN := 1.6
var freeze_remaining := 0.0
var freeze_immunity := 0.0
var ice_cast_cooldown := 0.0
var _frozen_shell: MeshInstance3D

func apply_freeze(caster: Node3D) -> bool:
    if not controls_enabled or shielding or freeze_remaining > 0 or freeze_immunity > 0 or not is_instance_valid(caster) or not caster.can_hit(self):
        return false
    if _visual_root:
        var rigid_reaction = _visual_root.get_node_or_null("GGBVisual")
        if rigid_reaction: rigid_reaction.freeze_reaction()
    cancel_magic()
    _cancel_witcheer()
    _cancel_ice_attack()
    _cancel_turbofit_attack()
    _cancel_doge_attack(true)
    _clear_sound_orb()
    torpedo_phase = "idle"
    torpedo_time = 0
    tackle_active = 0
    tackle_targets.clear()
    swing_windup = 0
    swing_followthrough = 0
    charging = false
    charge_time = 0
    recovery_active = 0
    recovery_targets.clear()
    drop_committed = false
    attack_flash_time = 0
    attack_cooldown = 0
    last_move = ""
    shielding = false
    hitstun = 0
    velocity.x = 0
    velocity.y = minf(velocity.y, 0)
    freeze_remaining = FREEZE_DURATION
    _update_move_visuals()
    return true

func _thaw() -> void:
    _thaw_rigid_reaction()
    _resume_frozen_animation()
    freeze_remaining = 0
    freeze_immunity = FREEZE_IMMUNITY
    _update_freeze_visual()

func _clear_freeze() -> void:
    _thaw_rigid_reaction()
    if freeze_remaining > 0:
        _resume_frozen_animation()
    freeze_remaining = 0
    freeze_immunity = 0
    _update_freeze_visual()

func _thaw_rigid_reaction() -> void:
    if _visual_root:
        var rigid_reaction = _visual_root.get_node_or_null("GGBVisual")
        if rigid_reaction: rigid_reaction.thaw_reaction()

func _resume_frozen_animation() -> void:
    if _visual_root:
        for player in _visual_root.find_children("*", "AnimationPlayer", true, false):
            if not player.assigned_animation.is_empty():
                player.play()

func _update_freeze_visual() -> void:
    if freeze_remaining > 0 and _visual_root:
        for player in _visual_root.find_children("*", "AnimationPlayer", true, false):
            player.pause()
    if freeze_remaining <= 0 and _move_status and _move_status.text == "FROZEN":
        _move_status.text = ""
    if _frozen_shell:
        _frozen_shell.visible = freeze_remaining > 0
    if _move_status and freeze_remaining > 0:
        _move_status.text = "FROZEN"
        _move_status.modulate = Color(0.45, 0.9, 1.0)

func _tick_freeze(delta: float) -> void:
    ice_cast_cooldown = maxf(0, ice_cast_cooldown - delta)
    freeze_immunity = maxf(0, freeze_immunity - delta)
    if freeze_remaining > 0:
        freeze_remaining = maxf(0, freeze_remaining - delta)
        if freeze_remaining == 0:
            _thaw()

func _cast_ice_bolt(aim: Vector2) -> void:
    if ice_cast_cooldown > 0:
        return
    if absf(aim.x) > 0.1:
        facing = signf(aim.x)
    ice_cast_cooldown = ICE_CAST_COOLDOWN
    _start_ice_attack("IceCast", Vector3(facing, 0, 0))
    last_move = "FIRE BOLT" if prototype_fire else "FROST BOLT"
    _update_move_visuals()
var ice_attack_clip := ""
var ice_attack_elapsed := 0.0
var ice_attack_direction := Vector3.RIGHT
var ice_attack_facing := 1.0
var _ice_struck := false

func _start_ice_attack(clip: String, direction: Vector3) -> void:
    ice_attack_clip = clip
    ice_attack_elapsed = 0
    ice_attack_direction = direction
    ice_attack_facing = facing
    _ice_struck = false
    attack_cooldown = 0.55 if clip == "IceStrike" else 0.5
    attack_flash_time = 0
    if _attack_flash:
        _attack_flash.visible = false
    _update_move_visuals()

func _cancel_ice_attack() -> void:
    ice_attack_clip = ""
    ice_attack_elapsed = 0
    _ice_struck = false

func _tick_ice_attack(delta: float) -> void:
    if freeze_remaining > 0 or hitstun > 0 or not controls_enabled:
        _cancel_ice_attack()
        return
    if ice_attack_clip.is_empty():
        return
    ice_attack_elapsed += delta
    facing = ice_attack_facing
    var duration := 0.55 if ice_attack_clip == "IceStrike" else 0.5
    if not _ice_struck and ice_attack_elapsed + 0.000001 >= 0.2:
        _ice_struck = true
        if ice_attack_clip == "IceStrike":
            _directional_hit(8.0, 3.8, 2.5, ice_attack_direction, maxf(0, duration - ice_attack_elapsed))
        elif last_move in ["FROST BOLT", "FIRE BOLT"]:
            var projectile = preload("res://scripts/fire_projectile.gd").new() if prototype_fire else ProjectileScript.new()
            projectile.source = self
            projectile.direction = ice_attack_facing
            projectile.freeze_bolt = not prototype_fire
            projectile.color = Color(0.35, 0.85, 1.0)
            get_parent().add_child(projectile)
            projectile.global_position = global_position + Vector3(ice_attack_facing * 0.85, 1.5, 0)
            if prototype_fire: projectile.place_at_cast_hand(_visual_root.get_node("IceMageVisual"), ice_attack_facing)
        attack_flash_time = 0
        if _attack_flash:
            _attack_flash.visible = false
    if ice_attack_elapsed >= duration:
        _cancel_ice_attack()

var attack_cooldown := 0.0
var attack_flash_time := 0.0
var shielding := false
var last_move := ""
var turbofit_attack_clip := ""
var turbofit_attack_elapsed := 0.0
var turbofit_attack_facing := 1.0
var turbofit_attack_timings: Dictionary = {}
var _turbofit_struck := false
const AIR_KICK_ACTIVE_START := 5.0 / 30.0 # Authored frame41 (clip begins36).
const AIR_KICK_ACTIVE_END := 6.0 / 30.0 # Peak forward extension, frame42.
const AIR_KICK_RADIUS := 0.22 # World units at the approved 1.25 visual scale.
var _air_kick_targets: Array = []
var _air_down_targets: Array = []
var doge_attack_timings: Dictionary = {}
var doge_goalkeeper_power := 0.0
var doge_goalkeeper_hold := 0.0
var doge_goalkeeper_source := 0.0
var _doge_goalkeeper_targets: Array = []
var doge_attack_clip := ""
var doge_attack_elapsed := 0.0
var doge_attack_facing := 1.0
var _doge_struck := false
var _doge_two_piece_event := 0
var doge_combo_reset_seconds := 0.45
var doge_combo_remaining := 0.0
var doge_combo_next := 1
var doge_tyson_followup := false
var doge_punch_buffered := false
var doge_buffer_branch := ""
var doge_ground_rush
var doge_ground_basic
var doge_air_drop
var charging := false
var charge_time := 0.0
var recovery_spent := false
var recovery_active := 0.0
var recovery_targets: Array = []
# Animation is in-place; only this controller translates the body.
const TORPEDO_LAUNCH_TIME := 0.4 # 20 source frames at ~2.1x.
const TORPEDO_TACKLE_TIME := 0.42
const TORPEDO_BRAKE_TIME := 0.18
const TORPEDO_LANDING_TIME := 0.6 # 36 source frames at 2.5x.
var torpedo_phase := "idle"
var torpedo_time := 0.0
var torpedo_facing := 1.0
var tackle_active := 0.0
var tackle_spent := false
var tackle_targets: Array = []
var drop_committed := false
var _ggb_impact_pending := false
var _ggb_dust: Node3D
var float_remaining := 1.2
var swing_windup := 0.0
var swing_followthrough := 0.0
var landing_lag := 0.0
var swing_direction := Vector3.RIGHT
const SOUND_ORB_DURATION := 0.55
const SOUND_ORB_RADIUS := 1.15
const SOUND_ORB_KNOCKBACK := 7.0
var sound_orb_time := 0.0
var _sound_orb_targets: Array = []
var _sound_orb_projectiles: Array = []
const MAX_CHARGE_TIME := 1.5
var controls_enabled := true:
    set(value):
        controls_enabled = value
        if character_id in ["doge_man", "ggb", "mephisto"]: _latch_witcheer_inputs()
        if character_id == "ggb" and not value:
            drop_committed = false
            _ggb_impact_pending = false
            _clear_ggb_dust()
            _update_move_visuals(0, true)
        if character_id == "witcheer":
            if not value: _cancel_witcheer()
            else: _latch_witcheer_inputs()
        if not value:
            if character_id == "doge_man":
                charging = false
                charge_time = 0.0
                _cancel_doge_attack()
            if character_id == "turbofit" and _visual_root:
                var view = _visual_root.get_node_or_null("TurboFitVisual")
                if view:
                    view.cancel_power_chord()
                    view.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, facing, 0)
            if character_id == "doge_man" and _visual_root:
                var view = _visual_root.get_node_or_null("DogeVisual")
                if view: view.cancel_up_special()
            if burn: burn.clear()
            if doge_ground_rush: doge_ground_rush.cancel()
            cancel_magic()
            _head_slip_direction = 0
            _floor_contacts_valid = false
var ready_settling := false
var _jump_was_down := false
var _attack_was_down := false
var _special_was_down := false
var _down_was_down := false
var _bot = BotScript.new()
var _ignored_platforms: Array = []
var _drop_platform: StaticBody3D
var _drop_time := 0.0
const HEAD_SLIP_SPEED := 1.5
var _head_slip_direction := 0.0
var _floor_contacts_valid := true

# Native capsule tops can be floors; gameplay support must be terrain.
func is_grounded() -> bool:
    if not _floor_contacts_valid or not is_on_floor():
        return false
    for i in get_slide_collision_count():
        var collision := get_slide_collision(i)
        for j in collision.get_collision_count():
            var body = collision.get_collider(j)
            if is_instance_valid(body) and not body.is_in_group("fighters") and collision.get_normal(j).dot(up_direction) >= cos(floor_max_angle):
                return true
    return false

func _apply_head_slip() -> void:
    if not _floor_contacts_valid or is_grounded() or velocity.y > 0:
        _head_slip_direction = 0
        return
    var support: Node3D
    for i in get_slide_collision_count():
        var collision := get_slide_collision(i)
        for j in collision.get_collision_count():
            var body = collision.get_collider(j)
            if is_instance_valid(body) and body.is_in_group("fighters") and collision.get_normal(j).y > 0.1 and global_position.y > body.global_position.y + 0.7:
                support = body
                break
    if not is_instance_valid(support):
        _head_slip_direction = 0
        return
    if _head_slip_direction == 0:
        var offset := global_position.x - support.global_position.x
        # Deterministic world +X breaks exact-center symmetry.
        _head_slip_direction = signf(offset) if absf(offset) > 0.01 else 1.0
    # If the selected side meets a wall, use the other side on the next
    # physics move. Never teleport or disable a collider to escape.
    for i in get_slide_collision_count():
        var collision := get_slide_collision(i)
        for j in collision.get_collision_count():
            if collision.get_normal(j).x * _head_slip_direction < -0.7:
                _head_slip_direction *= -1
                break
    # Small minimum escape speed, not an additive combat/knockback impulse.
    # Only move_and_slide displaces us: capsules and walls remain solid.
    if absf(velocity.x) < HEAD_SLIP_SPEED:
        velocity.x = _head_slip_direction * HEAD_SLIP_SPEED

var mephisto_moves
var _active_collision_layer := 1
var _active_collision_mask := 3
var _visual_root: Node3D
var _shield_visual: MeshInstance3D
var _attack_flash: MeshInstance3D
var _move_status: Label3D
var _sound_orb_visual: Node3D

const MOVE_SPEED := 7.5
const GROUND_ACCELERATION := 42.0
const AIR_ACCELERATION := 22.0
const JUMP_SPEED := 10.5
const GRAVITY := 25.0
const MAX_FALL_SPEED := 18.0

func get_hurtbox_shapes() -> Array:
    var pilot = get_node_or_null("BodyHurtboxes")
    if pilot:
        pilot.sync()
        return pilot.shapes
    return get_children()

func _ready() -> void:
    if character_id == "witcheer":
        witcheer_moves = JSON.parse_string(FileAccess.get_file_as_string("res://assets/witcheer/move_manifest.json")).moves
    if character_id == "turbofit":
        turbofit_attack_timings = JSON.parse_string(FileAccess.get_file_as_string("res://assets/turbofit/new_motion_manifest.json")).attacks
    if character_id == "doge_man":
        var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/doge_man/attack_timing.json"))
        doge_attack_timings = manifest.attacks
        doge_combo_reset_seconds = float(manifest.combo_reset_seconds)
        doge_ground_rush = preload("res://scripts/doge_ground_rush.gd").new()
        doge_ground_rush.name = "DogeGroundRush"
        add_child(doge_ground_rush)
    collision_mask |= 2
    _active_collision_layer = collision_layer
    _active_collision_mask = collision_mask
    spawn_position = global_position
    if not is_in_group("fighters"):
        add_to_group("fighters")
    _build_visuals()
    if character_id == "doge_man":
        doge_ground_basic = preload("res://scripts/doge_ground_basic.gd").new()
        doge_ground_basic.name = "DogeGroundBasic"
        add_child(doge_ground_basic)
        doge_air_drop = preload("res://scripts/doge_air_drop.gd").new()
        doge_air_drop.name = "DogeAirDrop"
        add_child(doge_air_drop)
    if character_id in preload("res://scripts/humanoid_air_side.gd").VIEWS:
        humanoid_air_side = preload("res://scripts/humanoid_air_side.gd").new()
        humanoid_air_basic = preload("res://scripts/humanoid_air_basic.gd").new()
        humanoid_air_basic.name = "HumanoidAirBasic"
        add_child(humanoid_air_basic)
        humanoid_air_side.name = "HumanoidAirSide"
        add_child(humanoid_air_side)
    if character_id in ["doge_man", "ice_mage", "mephisto", "bobo"]:
        fitted_reaction = preload("res://scripts/approved_fitted_reaction.gd").new()
        fitted_reaction.name = "ApprovedFittedReaction"
        add_child(fitted_reaction)
    if character_id == "teknium":
        reaction_recovery = preload("res://scripts/approved_teknium_recovery.gd").new()
        reaction_recovery.name = "ApprovedRecovery"
        add_child(reaction_recovery)
    if character_id in ["teknium", "turbofit"]:
        var hurtboxes = preload("res://scripts/body_hurtboxes.gd").new()
        hurtboxes.name = "BodyHurtboxes"
        add_child(hurtboxes)
    if character_id == "mephisto":
        mephisto_moves = preload("res://scripts/mephisto_moves.gd").new()
        mephisto_moves.name = "MephistoMoves"
        add_child(mephisto_moves)
    if character_id == "teknium":
        teknium_magic = preload("res://scripts/teknium_magic.gd").new()
        teknium_magic.name = "TekniumMagic"
        add_child(teknium_magic)

func _physics_process(delta: float) -> void:
    if doge_ground_basic: doge_ground_basic.before_tick()
    if humanoid_air_basic: humanoid_air_basic.before_tick()
    if humanoid_air_side: humanoid_air_side.before_tick()
    if doge_air_drop: doge_air_drop.before_tick()
    if reaction_recovery: reaction_recovery.before_tick(delta)
    if burn: burn.tick(delta)
    grab_immunity = maxf(0, grab_immunity - delta)
    _tick_freeze(delta)
    landing_lag = maxf(0, landing_lag - delta)
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    attack_flash_time = maxf(0.0, attack_flash_time - delta)
    if _attack_flash:
        _attack_flash.visible = attack_flash_time > 0.0

    if not controls_enabled:
        if ready_settling:
            velocity.x = 0
            velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)
            _update_platform_collisions(delta)
            move_and_slide()
            _floor_contacts_valid = true
            global_position.z = 0
        _clear_ggb_dust()
        drop_committed = false
        _clear_freeze()
        _cancel_witcheer()
        _cancel_ice_attack()
        _cancel_turbofit_attack()
        _cancel_doge_attack()
        _update_move_visuals()
        return

    var input := read_controls(delta)
    var left_down: bool = input.left
    var right_down: bool = input.right
    var up_down: bool = input.up
    var down_down: bool = input.down
    var jump_down: bool = input.jump or up_down
    var attack_down: bool = input.attack
    var special_down: bool = input.special
    shielding = not magic_locked() and freeze_remaining <= 0 and input.shield and not _torpedo_committed() and hitstun <= 0.0 and not charging and not drop_committed and attack_cooldown <= 0.0
    if doge_ground_rush and doge_ground_rush.phase != "idle": shielding = false
    if _shield_visual:
        _shield_visual.visible = shielding and hitstun <= 0.0

    velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)
    if is_grounded() and velocity.y <= 0.0:
        reset_air_resources()

    if freeze_remaining <= 0 and character_id == "ggb" and jump_down and not is_grounded() and velocity.y < 0 and float_remaining > 0 and not drop_committed and not recovery_spent and hitstun <= 0:
        float_remaining = maxf(0, float_remaining - delta)
        velocity.y = maxf(velocity.y, -1.5)

    if freeze_remaining > 0:
        velocity.x = 0
    elif is_instance_valid(caught_by):
        if not is_instance_valid(caught_by.actor) or not caught_by.actor.controls_enabled or caught_by.actor.freeze_remaining > 0:
            cancel_magic()
        else:
            var hold_anchor: Vector3 = caught_by.anchor()
            if global_position.distance_to(hold_anchor) > 0.8 or not caught_by.clear_path(global_position + Vector3.UP, hold_anchor + Vector3.UP, self):
                cancel_magic()
            else:
                velocity = ((hold_anchor - global_position) / maxf(delta, 0.001)).limit_length(3.0)
                _visual_root.position = Vector3(0, sin(caught_by.elapsed * 35.0) * 0.018, 0)
    elif teknium_magic and teknium_magic.phase != "idle":
        velocity.x = move_toward(velocity.x, 0, GROUND_ACCELERATION * delta)
    elif hitstun > 0.0:
        hitstun -= delta
    else:
        var move_axis := float(int(right_down) - int(left_down))
        if mephisto_moves and not mephisto_moves.move.is_empty(): move_axis = 0
        if doge_ground_rush and doge_ground_rush.phase != "idle": move_axis = 0
        var aim := Vector2(move_axis, float(int(down_down) - int(up_down)))
        # Capture opposite+basic before movement auto-turns; no held-input retrigger.
        var witcheer_turn_edge := character_id == "witcheer" and attack_down and not _attack_was_down and aim.x * facing < -0.1 and absf(aim.y) <= 0.1
        var acceleration := GROUND_ACCELERATION if is_grounded() else AIR_ACCELERATION
        velocity.x = move_toward(velocity.x, (0.0 if charging or shielding or landing_lag > 0 else move_axis * MOVE_SPEED * ground_speed_multiplier()), acceleration * delta)
        if absf(move_axis) > 0.1 and not charging and not _torpedo_committed() and not drop_committed and not witcheer_turn_edge and witcheer_clip != "TurnaroundKick":
            facing = signf(move_axis)
            if _visual_root:
                _visual_root.scale.x = facing

        if charging:
            advance_charge(delta)
            if not special_down:
                release_special()
        elif not shielding and not (doge_ground_rush and doge_ground_rush.phase != "idle"):
            # Attack chords take priority over tap-up jumping.
            if attack_down and not _attack_was_down:
                basic_attack(aim, not is_grounded())
            elif special_down and not _special_was_down:
                start_special(aim)
            elif jump_down and not _jump_was_down and not attack_down and not special_down:
                # Holding Up for Tyson's next press must not cancel it via tap-jump.
                # The dedicated jump key retains its explicit cancel behavior.
                if input.jump or doge_attack_clip != "TysonTwoPiece":
                    try_jump()
            elif down_down and not _down_was_down and not attack_down and not special_down:
                try_drop_through()

    _jump_was_down = jump_down
    _attack_was_down = attack_down
    _special_was_down = special_down
    _down_was_down = down_down

    _tick_character_move(delta)
    if doge_ground_rush: doge_ground_rush.tick(delta)
    if reaction_recovery: reaction_recovery.before_move(delta)
    if humanoid_air_basic: humanoid_air_basic.before_move()
    if humanoid_air_side: humanoid_air_side.before_move()
    if doge_air_drop: doge_air_drop.before_move()
    if doge_ground_basic: doge_ground_basic.before_move()
    _update_platform_collisions(delta)
    _apply_head_slip()
    move_and_slide()
    _floor_contacts_valid = true
    if is_grounded() and velocity.y <= 0.0:
        if doge_attack_clip in ["SupermanMoves2", "AirDownKarate"]:
            _cancel_doge_attack()
        if turbofit_attack_clip in ["AirSideKick", "AirDownKick"]:
            _cancel_turbofit_attack()
            attack_cooldown = 0.0
        if torpedo_phase in ["tackle", "fall"]:
            torpedo_phase = "landing"
            torpedo_time = TORPEDO_LANDING_TIME
            tackle_active = 0
            tackle_targets.clear()
            landing_lag = TORPEDO_LANDING_TIME
            attack_cooldown = maxf(attack_cooldown, TORPEDO_LANDING_TIME)
        reset_air_resources()
    if is_grounded() and velocity.y <= 0 and witcheer_clip in ["JumpPunch","AirSwim","SpinRise"]:
        _cancel_witcheer()
        attack_cooldown = 0
        landing_lag = maxf(landing_lag,0.12)
    _tick_witcheer(delta)
    _tick_recovery(delta)
    _update_move_visuals(delta)
    # Imported aerial kicks query the current combat-clock pose AFTER movement
    # and landing cancellation, never yesterday's skeleton/pre-move position.
    _query_air_side_kick()
    _query_air_down_kick()
    _query_doge_superman()
    _query_doge_two_piece()
    _query_doge_air_karate()
    _query_doge_goalkeeper()
    if doge_ground_rush: doge_ground_rush.after_move()
    if teknium_magic: teknium_magic.tick(delta)
    if mephisto_moves: mephisto_moves.tick(delta)
    if reaction_recovery: reaction_recovery.after_tick(delta)
    if humanoid_air_basic: humanoid_air_basic.after_tick(delta)
    if humanoid_air_side: humanoid_air_side.after_tick(delta)
    if doge_air_drop: doge_air_drop.after_tick(delta)
    if doge_ground_basic: doge_ground_basic.after_tick(delta)
    global_position.z = 0.0
    if global_position.y < -8.0 or absf(global_position.x) > 16.0 or global_position.y > 15.0:
        _handle_blast_zone()

func can_hit(target: Node) -> bool:
    if reaction_recovery and not reaction_recovery.knockdown_phase.is_empty(): return false
    if is_instance_valid(target) and target.has_method("is_knockdown_protected") and target.is_knockdown_protected(): return false
    return is_instance_valid(target) and target != self and target.is_in_group("fighters") and target.controls_enabled and (team_id < 0 or target.team_id < 0 or team_id != target.team_id)

func read_controls(delta: float) -> Dictionary:
    var result = _read_raw_controls(delta)
    if humanoid_air_basic: result = humanoid_air_basic.filter_controls(result)
    if humanoid_air_side: result = humanoid_air_side.filter_controls(result)
    if doge_air_drop: result = doge_air_drop.filter_controls(result)
    return reaction_recovery.filter_controls(result) if reaction_recovery else result

func _read_raw_controls(delta: float) -> Dictionary:
    if control_type == "bot":
        return _bot.read(self, delta)
    var result := {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false, "shield": false}
    if input_device >= 0:
        var x := Input.get_joy_axis(input_device, JOY_AXIS_LEFT_X)
        var y := Input.get_joy_axis(input_device, JOY_AXIS_LEFT_Y)
        result.left = x < -0.35 or Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_LEFT)
        result.right = x > 0.35 or Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_RIGHT)
        result.up = y < -0.35 or Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_UP)
        result.down = y > 0.35 or Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_DOWN)
        result.jump = Input.is_joy_button_pressed(input_device, JOY_BUTTON_A)
        result.attack = Input.is_joy_button_pressed(input_device, JOY_BUTTON_X)
        result.special = Input.is_joy_button_pressed(input_device, JOY_BUTTON_B)
        result.shield = Input.is_joy_button_pressed(input_device, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(input_device, JOY_BUTTON_RIGHT_SHOULDER)
    elif player_index in [1, 2]:
        var keys := [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_F, KEY_G, KEY_E] if player_index == 1 else [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_K, KEY_L, KEY_O]
        var names := ["left", "right", "up", "down", "jump", "attack", "special", "shield"]
        for i in keys.size():
            result[names[i]] = Input.is_key_pressed(keys[i])
    return result

func _update_platform_collisions(delta: float) -> void:
    _drop_time = maxf(0, _drop_time - delta)
    for platform in get_tree().get_nodes_in_group("pass_through_platforms"):
        if not platform is StaticBody3D:
            continue
        var top: float = platform.get_meta("top_y", platform.global_position.y)
        var ignore: bool = velocity.y > 0.05 or global_position.y < top - 0.06 or (platform == _drop_platform and _drop_time > 0)
        if ignore and platform not in _ignored_platforms:
            add_collision_exception_with(platform)
            _ignored_platforms.append(platform)
        elif not ignore and platform in _ignored_platforms:
            remove_collision_exception_with(platform)
            _ignored_platforms.erase(platform)

func try_drop_through() -> bool:
    if reaction_recovery and not reaction_recovery.knockdown_phase.is_empty(): return false
    if doge_ground_rush and doge_ground_rush.phase != "idle": return false
    if magic_locked(): return false
    if freeze_remaining > 0:
        return false
    if not is_grounded() or drop_committed or attack_cooldown > 0 or charging or shielding:
        return false
    for i in get_slide_collision_count():
        var collision := get_slide_collision(i)
        var platform := collision.get_collider() as StaticBody3D
        if platform and platform.is_in_group("pass_through_platforms") and collision.get_normal().y > 0.6:
            var top: float = platform.get_meta("top_y", platform.global_position.y)
            var half_width: float = platform.get_meta("half_width", 0.0)
            if absf(global_position.y - top) < 0.15 and absf(global_position.x - platform.global_position.x) <= half_width + 0.5:
                _drop_platform = platform
                _drop_time = 0.3
                velocity.y = -3.0
                _update_platform_collisions(0)
                return true
    return false

func receive_hit(hit_damage: float, direction: Vector3, base_knockback: float) -> void:
    if is_knockdown_protected(): return
    var episode = reaction_recovery != null and not reaction_recovery.knockdown_phase.is_empty()
    var old_reaction_facing = reaction_recovery.reaction_facing if reaction_recovery else facing
    cancel_magic()
    if hit_damage > 0 and freeze_remaining > 0:
        _thaw()
    _cancel_witcheer()
    _cancel_ice_attack()
    _cancel_turbofit_attack()
    _cancel_doge_attack()
    _clear_sound_orb()
    torpedo_phase = "idle"
    torpedo_time = 0
    tackle_active = 0.0
    tackle_targets.clear()
    swing_windup = 0.0
    charging = false
    charge_time = 0.0
    recovery_active = 0.0
    drop_committed = false
    var damage_scale := 0.35 if shielding else 1.0
    var knockback_scale := 0.28 if shielding else 1.0
    damage_percent = CombatMathScript.apply_damage(damage_percent, hit_damage * damage_scale)
    var strength: float = CombatMathScript.knockback_strength(damage_percent, hit_damage, base_knockback) * knockback_scale
    velocity = direction.normalized() * strength
    hitstun = 0.08 + strength * 0.025
    if character_id == "doge_man" and _visual_root:
        _visual_root.get_node("DogeVisual").begin_hit()
    _update_move_visuals()
    if reaction_recovery: reaction_recovery.after_hit(episode, old_reaction_facing)
    state_changed.emit()

func lose_stock() -> void:
    _clear_move_state()
    stocks -= 1
    damage_percent = 0.0
    velocity = Vector3.ZERO
    state_changed.emit()

func reset_fighter(new_spawn: Vector3, reset_stocks := false) -> void:
    _clear_move_state()
    collision_layer = _active_collision_layer
    collision_mask = _active_collision_mask
    if reset_stocks:
        stocks = 3
    damage_percent = 0.0
    velocity = Vector3.ZERO
    hitstun = 0.0
    attack_cooldown = 0.0
    global_position = new_spawn
    spawn_position = new_spawn
    visible = true
    controls_enabled = true
    state_changed.emit()

func reset_air_resources() -> void:
    # Grounded Cinder startup already reserved this recovery. Ordinary terrain
    # contact must not refund its jumps before the lift leaves the floor.
    if mephisto_moves and mephisto_moves.move=="CinderToss" and not mephisto_moves.impulse_done:return
    _land_character_move()
    tackle_spent = false
    float_remaining = 1.2
    jumps_used = 0
    recovery_spent = false
    recovery_active = 0.0
    recovery_targets.clear()

func _clear_move_state() -> void:
    if burn: burn.clear()
    _head_slip_direction = 0
    _floor_contacts_valid = false
    cancel_magic()
    grab_immunity = 0
    if teknium_magic: teknium_magic.cooldown = 0
    _clear_ggb_dust()
    _clear_freeze()
    ice_cast_cooldown = 0
    _cancel_witcheer()
    _cancel_ice_attack()
    _cancel_turbofit_attack()
    _cancel_doge_attack()
    _clear_sound_orb()
    for platform in _ignored_platforms:
        if is_instance_valid(platform):
            remove_collision_exception_with(platform)
    _ignored_platforms.clear()
    _drop_platform = null
    _drop_time = 0.0
    _bot.reset()
    _down_was_down = false
    _jump_was_down = false
    _attack_was_down = false
    _special_was_down = false
    _latch_witcheer_inputs()
    drop_committed = false
    torpedo_phase = "idle"
    torpedo_time = 0
    tackle_active = 0.0
    tackle_targets.clear()
    swing_windup = 0.0
    if is_inside_tree():
        swing_followthrough = 0.0
        landing_lag = 0.0
        for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
            if projectile.source == self:
                projectile.queue_free()
    reset_air_resources()
    charging = false
    charge_time = 0.0
    shielding = false
    attack_cooldown = 0.0
    attack_flash_time = 0.0
    last_move = ""
    _update_move_visuals(0, true)

func ground_speed_multiplier() -> float:
    var multiplier := 1.0
    if not is_inside_tree(): return multiplier
    for puddle in get_tree().get_nodes_in_group("goo_puddles"):
        if puddle.affects(self):
            multiplier = minf(multiplier, puddle.SPEED_MULTIPLIER)
    return multiplier

func try_jump() -> bool:
    if reaction_recovery and not reaction_recovery.knockdown_phase.is_empty(): return false
    if mephisto_moves and not mephisto_moves.move.is_empty(): return false
    if doge_ground_rush and doge_ground_rush.phase != "idle": return false
    if not witcheer_clip.is_empty(): return false
    if magic_locked(): return false
    if freeze_remaining > 0:
        return false
    if _torpedo_committed() or landing_lag > 0 or drop_committed or tackle_active > 0 or recovery_spent or jumps_used >= (5 if character_id == "ggb" else 2) or charging or hitstun > 0.0 or not controls_enabled:
        return false
    _cancel_witcheer()
    _cancel_ice_attack()
    torpedo_phase = "idle"
    velocity.y = JUMP_SPEED * pow(0.84, jumps_used) if character_id == "ggb" else JUMP_SPEED
    _cancel_turbofit_attack()
    _cancel_doge_attack()
    jumps_used += 1
    if character_id == "doge_man" and _visual_root:
        _visual_root.get_node("DogeVisual").begin_jump()
    if character_id == "teknium" and _visual_root:
        var jump_visual = _visual_root.get_node_or_null("TekniumVisual")
        if jump_visual: jump_visual.begin_jump()
    _update_move_visuals()
    return true

func start_special(aim: Vector2) -> void:
    if reaction_recovery and not reaction_recovery.knockdown_phase.is_empty(): return
    if doge_ground_rush and doge_ground_rush.phase != "idle": return
    if magic_locked(): return
    if freeze_remaining > 0:
        return
    # The return toggle alone bypasses steel's action/landing lock. Keyboard
    # dispatch already requires a fresh special edge; holding never retriggers.
    if character_id == "ggb" and drop_committed:
        if aim.y > 0.1 and controls_enabled and hitstun <= 0:
            drop_committed = false
            _ggb_impact_pending = false
            last_move = "NORMAL FORM"
            _update_move_visuals()
        return
    if not doge_attack_clip.is_empty() and aim.y < -0.1 and not recovery_spent and controls_enabled and hitstun <= 0:
        _cancel_doge_attack()
    if not doge_attack_clip.is_empty():
        return
    if _torpedo_committed() or landing_lag > 0 or drop_committed or attack_cooldown > 0.0 or hitstun > 0.0 or not controls_enabled or charging:
        return
    _cancel_doge_attack()
    if character_id == "mephisto":
        if not mephisto_moves.move.is_empty(): return
        mephisto_moves.start_kit(mephisto_moves.route(aim,not is_grounded(),true),signf(aim.x) if absf(aim.x)>.1 else facing)
        return
    if character_id == "witcheer":
        if absf(aim.x) > 0.1: facing = signf(aim.x)
        if aim.y < -0.1:
            if recovery_spent: return
            recovery_spent = true
            jumps_used = 2
            velocity = Vector3(facing*5.5,1.2,0)
            _start_witcheer("AirSwim")
        elif aim.y > 0.1:
            _start_witcheer("Celebration")
            witcheer_absorbing = true
            last_move = "ABSORB DANCE"
        elif absf(aim.x) > 0.1:
            _start_witcheer("Toss")
        else:
            _start_witcheer("Celebration")
        return
    if character_id == "ice_mage" and aim.y >= -0.1:
        _cast_ice_bolt(aim)
        return
    if aim.y < -0.1:
        if recovery_spent:
            return
        torpedo_phase = "idle"
        recovery_spent = true
        jumps_used = 2
        velocity.y = 13.5
        recovery_active = 0.38
        recovery_targets.clear()
        last_move = "RISING CHORD" if character_id == "turbofit" else "RISING STRIKE"
        attack_cooldown = 0.65
        attack_flash_time = 0.38
        if character_id == "doge_man" and _visual_root:
            var view = _visual_root.get_node_or_null("DogeVisual")
            if view: view.begin_up_special(facing)
        if character_id == "ice_mage":
            _start_ice_attack("IceCast", Vector3.UP)
            last_move = "FROST RISE"
            attack_cooldown = 0.65
        if _attack_flash:
            _attack_flash.position = Vector3(0, 2.3, 0)
            _attack_flash.scale = Vector3(0.8, 1.7, 0.8)
    elif aim.y > 0.1:
        if character_id == "turbofit":
            sound_orb_time = SOUND_ORB_DURATION
            _sound_orb_targets.clear()
            _sound_orb_projectiles.clear()
            last_move = "SOUND ORB"
            attack_cooldown = 0.75
            attack_flash_time = 0.0
            if _attack_flash:
                _attack_flash.visible = false
            _tick_sound_orb(0.0)
            _update_move_visuals()
        elif character_id == "doge_man":
            doge_ground_rush.start()
        elif character_id == "ggb":
            drop_committed = true
            _ggb_impact_pending = true
            velocity = Vector3(0, -24, 0)
            last_move = "STEEL FORM"
            _update_move_visuals()
            if is_grounded():
                _land_character_move()
        return
    elif absf(aim.x) > 0.1:
        if character_id == "teknium":
            teknium_magic.start_force(signf(aim.x))
            return
        if character_id == "doge_man":
            if tackle_spent or recovery_spent or torpedo_phase != "idle":
                return
            facing = signf(aim.x)
            torpedo_facing = facing
            tackle_spent = true
            torpedo_phase = "launch"
            torpedo_time = TORPEDO_LAUNCH_TIME
            tackle_active = 0
            tackle_targets.clear()
            velocity = Vector3(facing * 2.0, 6.0, 0)
            attack_cooldown = TORPEDO_LAUNCH_TIME + TORPEDO_TACKLE_TIME
            last_move = "FLYING TACKLE"
            _update_move_visuals()
            return
        facing = signf(aim.x)
        var projectile = GooProjectileScript.new() if character_id == "ggb" else (preload("res://scripts/turbofit_sound_wave.gd").new() if character_id == "turbofit" else ProjectileScript.new())
        projectile.source = self
        projectile.direction = facing
        projectile.color = body_color
        projectile.sound_wave = character_id == "turbofit"
        get_parent().add_child(projectile)
        projectile.global_position = global_position + Vector3(facing * 0.8, 1, 0)
        if character_id == "ggb" and _visual_root:
            var view = _visual_root.get_node_or_null("GGBVisual")
            if view: projectile.global_position.y = view.body_center_world().y
        attack_cooldown = 0.55
        last_move = "STICKY GOO" if character_id == "ggb" else ("SOUND WAVE" if character_id == "turbofit" else "PROJECTILE")
    elif aim == Vector2.ZERO:
        if character_id == "doge_man" and not is_grounded(): return
        doge_goalkeeper_hold = 0.0
        if character_id == "teknium":
            teknium_magic.start_grab()
            return
        torpedo_phase = "idle"
        charging = true
        charge_time = 0.0
        last_move = "CHARGING"
        if character_id == "turbofit" and _visual_root:
            var view = _visual_root.get_node_or_null("TurboFitVisual")
            if view: view.begin_power_chord()

func advance_charge(delta: float) -> void:
    if charging:
        doge_goalkeeper_hold += delta
        charge_time = minf(doge_ground_rush.MAX_CHARGE if doge_ground_rush and doge_ground_rush.phase == "charge" else MAX_CHARGE_TIME, charge_time + delta)

func release_special() -> void:
    if doge_ground_rush and doge_ground_rush.phase == "charge":
        doge_ground_rush.release()
        return
    if not charging:
        return
    charging = false
    var power := charge_time / MAX_CHARGE_TIME
    charge_time = 0.0
    if character_id == "doge_man":
        if not is_grounded(): return
        doge_goalkeeper_power = power
        _start_doge_attack("GoalkeeperKick", Vector2.ZERO)
        doge_attack_elapsed = doge_goalkeeper_source / 2.0
        _doge_goalkeeper_targets.clear()
        last_move = "GOALKEEPER KICK"
        return
    last_move = "POWER CHORD" if character_id == "turbofit" else "CHARGE RELEASE"
    if character_id == "turbofit" and _visual_root:
        var view = _visual_root.get_node_or_null("TurboFitVisual")
        if view: view.power_chord_contact(facing)
    _directional_hit(lerpf(10.0, 26.0, power), lerpf(4.0, 9.0, power), 3.0, Vector3(facing, 0, 0), 0.7)

func _tick_recovery(delta: float) -> void:
    if recovery_active <= 0.0:
        return
    recovery_active = maxf(0.0, recovery_active - delta)
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target) or target in recovery_targets:
            continue
        var offset: Vector3 = target.global_position - global_position
        if absf(offset.x) < 1.3 and absf(offset.z) < 1.0 and offset.y > -0.4 and offset.y < 2.6:
            recovery_targets.append(target)
            target.receive_hit(12.0, Vector3(facing * 0.2, 1, 0), 5.5)

func _update_move_visuals(delta := 0.0, interrupted := false) -> void:
    if character_id == "turbofit" and _visual_root and (interrupted or hitstun > 0 or freeze_remaining > 0 or magic_locked() or not controls_enabled or stocks <= 0):
        var view = _visual_root.get_node_or_null("TurboFitVisual")
        if view: view.cancel_power_chord()
    if character_id == "doge_man" and _visual_root and (interrupted or hitstun > 0 or not controls_enabled or is_instance_valid(caught_by)):
        var view = _visual_root.get_node_or_null("DogeVisual")
        if view:
            view.cancel_up_special()
            view.air_uppercut = false
    if is_instance_valid(caught_by):
        if electrocution_presentation.present(self): return
        if _visual_root:
            for player in _visual_root.find_children("*", "AnimationPlayer", true, false): player.pause()
        return
    if _visual_root and character_id == "ggb":
        var ggb_visual = _visual_root.get_node_or_null("GGBVisual")
        if ggb_visual:
            _visual_root.scale = Vector3.ONE
            ggb_visual.sync_pose(is_grounded(), velocity, drop_committed, facing, delta, interrupted or hitstun > 0 or freeze_remaining > 0 or not controls_enabled)
    if freeze_remaining > 0:
        _update_freeze_visual()
        return
    if _visual_root:
        var witcheer_visual = _visual_root.get_node_or_null("WitcheerVisual")
        var mephisto_visual = _visual_root.get_node_or_null("MephistoVisual")
        if mephisto_visual:
            _visual_root.scale = Vector3.ONE
            _visual_root.rotation = Vector3.ZERO
            mephisto_visual.sync_pose(is_grounded(), velocity, hitstun > 0, shielding or charging or attack_cooldown > 0 or recovery_active > 0, not controls_enabled or interrupted, facing)
        if witcheer_visual:
            _visual_root.scale = Vector3.ONE
            _visual_root.rotation = Vector3.ZERO
            if not controls_enabled or interrupted: _cancel_witcheer()
            if not witcheer_clip.is_empty():
                witcheer_visual.show_move(witcheer_clip, witcheer_source_time(), facing)
            else:
                witcheer_visual.sync_pose(is_grounded(), velocity, interrupted or hitstun > 0 or not controls_enabled or charging or attack_cooldown > 0 or recovery_active > 0, shielding, facing)
        var doge_visual = _visual_root.get_node_or_null("DogeVisual")
        if doge_visual:
            _visual_root.scale = Vector3.ONE
            _visual_root.rotation = Vector3.ZERO
            var attack_duration := float(doge_attack_timings[doge_attack_clip].duration) if not doge_attack_clip.is_empty() else 1.0
            if doge_ground_basic and not doge_ground_basic.clip.is_empty():
                doge_ground_basic.present(doge_ground_basic.elapsed)
            elif doge_ground_rush and doge_ground_rush.phase != "idle":
                doge_ground_rush.present(doge_visual,delta)
            elif charging and (not doge_ground_rush or doge_ground_rush.phase == "idle"):
                # Draw back once over 1.2s to source frame58 (rear-most right foot).
                # Neutral G holds this pose; S+G's separate bull charge still loops.
                doge_goalkeeper_source = 0.6 * smoothstep(0.0, 1.2, doge_goalkeeper_hold)
                if doge_goalkeeper_hold > 1.2:
                    # A tiny settled sway, never another full anticipation cycle.
                    doge_goalkeeper_source -= 0.0015 * (1.0 - cos((doge_goalkeeper_hold - 1.2) * TAU / 1.6))
                doge_visual.sync_pose("idle", facing, TORPEDO_LAUNCH_TIME, TORPEDO_TACKLE_TIME, TORPEDO_BRAKE_TIME, TORPEDO_LANDING_TIME, true, velocity, false, 0, "GoalkeeperKick", doge_goalkeeper_source / 2.0, float(doge_attack_timings.GoalkeeperKick.duration))
            elif doge_visual.present_up_special(velocity, facing, delta):
                if _attack_flash: _attack_flash.visible = false
            elif doge_visual.present_air_uppercut(is_grounded(), velocity, facing, attack_cooldown, doge_attack_timings.Uppercut):
                if _attack_flash: _attack_flash.visible = false
            else:
                doge_visual.tyson_followup = doge_tyson_followup
                doge_visual.sync_pose(torpedo_phase, facing, TORPEDO_LAUNCH_TIME, TORPEDO_TACKLE_TIME, TORPEDO_BRAKE_TIME, TORPEDO_LANDING_TIME, is_grounded(), velocity, interrupted or hitstun > 0 or not controls_enabled or magic_locked() or charging or (attack_cooldown > 0 and doge_attack_clip.is_empty()), delta, doge_attack_clip, doge_attack_elapsed, attack_duration, hitstun > 0 and controls_enabled and not interrupted and not magic_locked())

        var turbofit_visual = _visual_root.get_node_or_null("TurboFitVisual")
        if turbofit_visual:
            _visual_root.scale = Vector3.ONE
            _visual_root.rotation = Vector3.ZERO
            var active_move := last_move if charging or attack_cooldown > 0.0 else ""
            var turbo_duration := float(turbofit_attack_timings[turbofit_attack_clip].duration) if not turbofit_attack_clip.is_empty() else 1.0
            turbofit_visual.power_charging = charging
            turbofit_visual.power_cooldown = attack_cooldown
            turbofit_visual.sync_pose(is_grounded(), velocity, interrupted or hitstun > 0.0 or not controls_enabled, shielding, active_move, swing_direction, facing, delta, turbofit_attack_clip, turbofit_attack_elapsed, turbo_duration)


        var teknium_visual = _visual_root.get_node_or_null("TekniumVisual")
        if teknium_visual:
            _visual_root.scale = Vector3.ONE
            _visual_root.rotation = Vector3.ZERO
            var teknium_move := last_move if charging or attack_cooldown > 0.0 else ""
            teknium_visual.sync_pose((is_grounded() and velocity.y <= 0) or not controls_enabled or interrupted, velocity, hitstun > 0.0, shielding, teknium_move, facing, delta)
            if teknium_magic: teknium_magic.present()

        var ice_mage_visual = _visual_root.get_node_or_null("IceMageVisual")
        if ice_mage_visual:
            _visual_root.scale = Vector3.ONE
            _visual_root.rotation = Vector3.ZERO
            var ice_move := last_move if charging or attack_cooldown > 0.0 else ""
            ice_mage_visual.sync_pose(is_grounded() or not controls_enabled, velocity, hitstun > 0.0 or freeze_remaining > 0, shielding, ice_move, facing, delta, ice_attack_clip, ice_attack_elapsed)

    _update_freeze_visual()
    if freeze_remaining > 0:
        return
    if not _move_status:
        return
    _move_status.text = "LAND TO RESET" if recovery_spent else ""
    _move_status.modulate = Color(1.0, 0.8, 0.35) if recovery_spent else Color.WHITE
    if charging:
        _move_status.text += "\nCHARGE %d%%" % roundi(charge_time / (doge_ground_rush.MAX_CHARGE if doge_ground_rush and doge_ground_rush.phase == "charge" else MAX_CHARGE_TIME) * 100)
        _attack_flash.visible = not (doge_ground_rush and doge_ground_rush.phase == "charge")
        _attack_flash.position = Vector3(facing * 0.9, 1.2, 0)
        _attack_flash.scale = Vector3.ONE * lerpf(0.3, 1.2, charge_time / MAX_CHARGE_TIME)
    # Match the approved preview: the primitive flash must not hide the hands.
    if character_id == "turbofit" and (charging or last_move == "POWER CHORD") and _attack_flash:
        _attack_flash.visible = false


func basic_attack(aim: Vector2, airborne: bool) -> void:
    if reaction_recovery:
        if not reaction_recovery.knockdown_phase.is_empty(): return
        if not airborne and reaction_recovery.side_continue(aim): return
        if not airborne and aim.y < -0.1:
            reaction_recovery.lab_start("uppercut")
            return
        if not airborne and absf(aim.x) > .1 and absf(aim.y) <= .1:
            reaction_recovery.lab_start("side_basic")
            return
    if doge_ground_rush and doge_ground_rush.phase != "idle": return
    if magic_locked(): return
    if freeze_remaining > 0:
        return
    if not doge_attack_clip.is_empty():
        # One fresh edge reserves one next strike, never an arbitrary cancel.
        # Tyson's second press accepts any held direction; keep later links separate.
        if controls_enabled and hitstun <= 0 and not airborne and doge_attack_clip == "TysonTwoPiece" and doge_attack_elapsed >= 0.15 and doge_attack_elapsed <= 0.35 and not doge_tyson_followup:
            doge_tyson_followup = true
        elif controls_enabled and hitstun <= 0 and not airborne and aim.y >= -0.1:
            if doge_attack_clip == "TysonTwoPiece":
                if doge_attack_elapsed >= 0.45 and doge_buffer_branch.is_empty():
                    doge_buffer_branch = "tyson" if aim.y > 0.1 else "normal"
                    doge_punch_buffered = true
            elif doge_attack_clip in ["Punch1", "Punch2", "Punch3", "Punch4"] and doge_buffer_branch.is_empty():
                var impact := float(doge_attack_timings[doge_attack_clip].impact_time)
                if doge_attack_elapsed >= maxf(0.06, impact - 0.1):
                    doge_buffer_branch = "tyson" if aim.y > 0.1 else "normal"
                    doge_punch_buffered = true
        return
    if doge_ground_basic and not doge_ground_basic.clip.is_empty():
        doge_ground_basic.press()
        return
    if _torpedo_committed() or landing_lag > 0 or drop_committed or attack_cooldown > 0.0 or hitstun > 0.0 or not controls_enabled or charging:
        return
    if character_id == "witcheer" and absf(aim.y) <= 0.1 and aim.x * facing < -0.1:
        _start_witcheer("TurnaroundKick")
        return
    # Doge-only neutral air shares the existing native-limb Superman route.
    # Horizontal-only air basic uses the approved edited Drop Kick below.
    if character_id == "doge_man" and humanoid_air_side and airborne and absf(aim.x) <= .1 and absf(aim.y) <= .1:
        humanoid_air_side.start(Vector2(facing, 0))
        return
    if humanoid_air_basic and airborne and (absf(aim.y) > .1 or absf(aim.x) <= .1):
        humanoid_air_basic.start(aim)
        return
    if doge_air_drop and airborne and absf(aim.x) > .1 and absf(aim.y) <= .1:
        doge_air_drop.start(aim)
        return
    # Horizontal AIR BASIC only; vertical diagonals retain existing priority.
    if humanoid_air_side and airborne and absf(aim.x) > .1 and absf(aim.y) <= .1:
        humanoid_air_side.start(aim)
        return
    if character_id == "witcheer":
        if absf(aim.x) > 0.1: facing = signf(aim.x)
        _start_witcheer(("SpinRise" if aim.y < -0.1 else "JumpPunch") if airborne else ("CaneSweep" if aim.y > 0.1 else ("NeutralHook" if absf(aim.y) <= 0.1 and absf(aim.x) <= 0.1 else "HighKick")))
        return
    if reaction_recovery and airborne and aim.y < -.1:
        reaction_recovery.lab_start("air_up")
        return
    if reaction_recovery and not airborne and absf(aim.x) <= .1 and absf(aim.y) <= .1:
        reaction_recovery.lab_start("jab")
        return
    # A fresh accepted input can share the cooldown-expiry physics tick.
    if character_id == "mephisto":
        if not mephisto_moves.move.is_empty(): return
        mephisto_moves.start_kit(mephisto_moves.route(aim,airborne,false),signf(aim.x) if absf(aim.x)>.1 else facing)
        return
    # Clear only the old visual episode, never the combat/resource state.
    if character_id == "doge_man" and _visual_root:
        var view = _visual_root.get_node_or_null("DogeVisual")
        if view: view.air_uppercut = false
    if character_id == "doge_man" and airborne and aim.y > 0.1:
        _start_doge_attack("AirDownKarate", aim)
        return
    if character_id == "doge_man" and airborne and absf(aim.y) <= 0.1:
        _start_doge_attack("SupermanMoves2", aim)
        return
    if character_id == "doge_man" and not airborne:
        if absf(aim.y) <= 0.1:
            doge_ground_basic.start(aim)
            return
        _start_doge_attack("Uppercut" if aim.y < -0.1 else ("TysonTwoPiece" if aim.y > 0.1 else "Punch%d" % doge_combo_next), aim)
        return
    if character_id == "turbofit" and ((not airborne and aim.y > 0.1) or (airborne and aim.y >= -0.1)):
        turbofit_attack_clip = ("AirDownKick" if aim.y > 0.1 else "AirSideKick") if airborne else "GoalkeeperKick"
        turbofit_attack_elapsed = 0.0
        _turbofit_struck = false
        _air_kick_targets.clear()
        _air_down_targets.clear()
        if absf(aim.x) > 0.1:
            facing = signf(aim.x)
        turbofit_attack_facing = facing
        attack_cooldown = float(turbofit_attack_timings[turbofit_attack_clip].duration)
        last_move = ("AIR DOWN KICK" if turbofit_attack_clip == "AirDownKick" else "AIR SIDE KICK") if airborne else "GOALKEEPER KICK"
        _update_move_visuals()
        return
    torpedo_phase = "idle"
    var direction := Vector3(facing, 0.0, 0.0)
    if aim.y < -0.1:
        direction = Vector3.UP
        last_move = "UP AIR" if airborne else "UPPERCUT"
    elif aim.y > 0.1:
        direction = Vector3.DOWN if airborne else Vector3(facing, -0.25, 0.0).normalized()
        last_move = "DOWN STRIKE" if airborne else "LOW SWEEP"
    else:
        if absf(aim.x) > 0.1:
            facing = signf(aim.x)
        direction = Vector3(facing, 0.0, 0.0)
        last_move = "AIR STRIKE" if airborne else "SIDE STRIKE"
    if character_id == "ice_mage":
        _start_ice_attack("IceStrike", direction)
        return
    if character_id == "turbofit":
        swing_direction = direction
        swing_windup = 0.28
        attack_cooldown = 0.8
        last_move = "GUITAR SWING"
    else:
        _directional_hit(8.0, 3.8, 2.5, direction, 0.32)
        if character_id == "doge_man" and airborne and aim.y < -0.1 and _visual_root:
            var view = _visual_root.get_node_or_null("DogeVisual")
            if view:
                view.begin_air_uppercut()
                _update_move_visuals()

func _tick_character_move(delta: float) -> void:
    _drive_witcheer()
    _tick_ice_attack(delta)
    _tick_turbofit_attack(delta)
    _tick_doge_attack(delta)
    _tick_sound_orb(delta)
    swing_followthrough = maxf(0, swing_followthrough - delta)
    if swing_windup > 0.0:
        swing_windup = maxf(0.0, swing_windup - delta)
        if swing_windup == 0.0:
            swing_followthrough = 0.22
            _directional_hit(14.0, 5.5, 2.8, swing_direction, 0.5)
    _tick_torpedo(delta)
    if drop_committed:
        velocity = Vector3(0, -24, 0)
    if _visual_root:
        _visual_root.rotation.z = 0.0


func _cancel_turbofit_attack() -> void:
    if character_id == "turbofit" and _visual_root:
        var view = _visual_root.get_node_or_null("TurboFitVisual")
        if view: view.cancel_power_chord()
    turbofit_attack_clip = ""
    turbofit_attack_elapsed = 0.0
    _turbofit_struck = false
    _air_kick_targets.clear()
    _air_down_targets.clear()

func _tick_turbofit_attack(delta: float) -> void:
    if hitstun > 0 or not controls_enabled:
        _cancel_turbofit_attack()
        return
    if turbofit_attack_clip.is_empty():
        return
    var timing: Dictionary = turbofit_attack_timings[turbofit_attack_clip]
    turbofit_attack_elapsed += delta
    facing = turbofit_attack_facing
    if turbofit_attack_clip not in ["AirSideKick", "AirDownKick"] and not _turbofit_struck and turbofit_attack_elapsed + 0.000001 >= float(timing.impact_time):
        _turbofit_struck = true
        # Side kick is horizontal, never the grounded low/down attack.
        var direction := Vector3(facing, 0.0, 0.0) if turbofit_attack_clip == "AirSideKick" else Vector3(facing, -0.25, 0.0).normalized()
        _directional_hit(float(timing.damage), float(timing.knockback), 2.5, direction, maxf(0, float(timing.duration) - turbofit_attack_elapsed))
        attack_flash_time = 0.0
        if _attack_flash:
            _attack_flash.visible = false
    if turbofit_attack_elapsed >= float(timing.duration):
        _cancel_turbofit_attack()

func _query_air_side_kick() -> void:
    if turbofit_attack_clip != "AirSideKick" or hitstun > 0 or not controls_enabled or is_grounded():
        return
    if turbofit_attack_elapsed + 0.000001 < AIR_KICK_ACTIVE_START or turbofit_attack_elapsed > AIR_KICK_ACTIVE_END + 0.000001:
        return
    var visual = _visual_root.get_node_or_null("TurboFitVisual")
    if not visual:
        return
    var volume: Dictionary = visual.air_side_kick_volume(turbofit_attack_elapsed, float(turbofit_attack_timings.AirSideKick.duration), turbofit_attack_facing)
    if volume.is_empty():
        return
    var center: Vector3 = volume.center
    var radius: float = AIR_KICK_RADIUS * float(volume.scale_factor)
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target) or target in _air_kick_targets:
            continue
        if (target.global_position.x - global_position.x) * turbofit_attack_facing <= 0:
            continue
        for child in target.get_hurtbox_shapes():
            if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D:
                continue
            # Actual hurtbody/movement capsule, including node offset, rotation
            # and uniform world scale. No feet-origin cone or widened range.
            var capsule: CapsuleShape3D = child.shape
            var transform: Transform3D = child.global_transform
            var half_axis := maxf(0, capsule.height * 0.5 - capsule.radius)
            var a := transform * Vector3(0, -half_axis, 0)
            var b := transform * Vector3(0, half_axis, 0)
            var body_radius := capsule.radius * maxf(transform.basis.x.length(), transform.basis.z.length())
            var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
            if center.distance_squared_to(nearest) <= pow(radius + body_radius, 2):
                _air_kick_targets.append(target)
                var timing: Dictionary = turbofit_attack_timings.AirSideKick
                preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,float(timing.damage), Vector3(turbofit_attack_facing, 0.35, 0), float(timing.knockback),child,nearest,center)
                break

func _query_air_down_kick() -> void:
    if turbofit_attack_clip != "AirDownKick" or hitstun > 0 or not controls_enabled or is_grounded():
        return
    var timing: Dictionary = turbofit_attack_timings.AirDownKick
    if turbofit_attack_elapsed + 0.000001 < float(timing.active_start) or turbofit_attack_elapsed > float(timing.active_end) + 0.000001:
        return
    var visual = _visual_root.get_node_or_null("TurboFitVisual")
    if not visual:
        return
    var volume: Dictionary = visual.air_down_kick_volume(turbofit_attack_elapsed, float(timing.duration), turbofit_attack_facing)
    if volume.is_empty():
        return
    var center: Vector3 = volume.center
    var radius: float = float(timing.radius) * float(volume.scale_factor)
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target) or target in _air_down_targets:
            continue
        # Down-basic requires a lower opponent AND actual foot/body contact.
        if target.global_position.y >= global_position.y:
            continue
        for child in target.get_hurtbox_shapes():
            if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D:
                continue
            var capsule: CapsuleShape3D = child.shape
            var transform: Transform3D = child.global_transform
            var half_axis := maxf(0, capsule.height * 0.5 - capsule.radius)
            var a := transform * Vector3(0, -half_axis, 0)
            var b := transform * Vector3(0, half_axis, 0)
            var body_radius := capsule.radius * maxf(transform.basis.x.length(), transform.basis.z.length())
            var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
            if center.distance_squared_to(nearest) <= pow(radius + body_radius, 2):
                _air_down_targets.append(target)
                preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,float(timing.damage), Vector3.DOWN, float(timing.knockback),child,nearest,center)
                break

func _tick_sound_orb(delta: float) -> void:
    if sound_orb_time <= 0.0:
        return
    var center := global_position + Vector3.UP
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target) or target in _sound_orb_targets:
            continue
        var offset: Vector3 = target.global_position + Vector3.UP - center
        if offset.length() <= SOUND_ORB_RADIUS:
            _sound_orb_targets.append(target)
            var push_direction := offset.normalized() if offset.length() > 0.001 else Vector3(facing, 0.25, 0).normalized()
            target.receive_hit(0.0, push_direction, SOUND_ORB_KNOCKBACK)
    for projectile in get_tree().get_nodes_in_group("projectiles"):
        if not is_instance_valid(projectile) or projectile.source == self or projectile in _sound_orb_projectiles:
            continue
        if center.distance_to(projectile.global_position) <= SOUND_ORB_RADIUS and projectile.has_method("reflect"):
            _sound_orb_projectiles.append(projectile)
            projectile.reflect(self, body_color)
    sound_orb_time = maxf(0.0, sound_orb_time - delta)
    if _sound_orb_visual:
        _sound_orb_visual.visible = sound_orb_time > 0.0
        if _sound_orb_visual.visible:
            var progress := 1.0 - sound_orb_time / SOUND_ORB_DURATION
            _sound_orb_visual.scale = Vector3.ONE * (1.0 + sin(progress * TAU * 3.0) * 0.035)
    if sound_orb_time == 0.0:
        _sound_orb_targets.clear()
        _sound_orb_projectiles.clear()

func _clear_sound_orb() -> void:
    sound_orb_time = 0.0
    _sound_orb_targets.clear()
    _sound_orb_projectiles.clear()
    if _sound_orb_visual:
        _sound_orb_visual.visible = false
        _sound_orb_visual.scale = Vector3.ONE

func _start_doge_attack(clip: String, aim: Vector2) -> void:
    if not doge_attack_timings.has(clip):
        return
    doge_attack_clip = clip
    _doge_karate_targets.clear()
    torpedo_phase = "idle"
    attack_flash_time = 0
    if _attack_flash:
        _attack_flash.visible = false
    doge_combo_remaining = 0
    doge_punch_buffered = false
    doge_buffer_branch = ""
    doge_attack_elapsed = 0
    doge_tyson_followup = false
    _doge_struck = false
    _doge_two_piece_event = 0
    if absf(aim.x) > 0.1:
        facing = signf(aim.x)
    doge_attack_facing = facing
    attack_cooldown = float(doge_attack_timings[clip].duration)
    last_move = "SUPERMAN PUNCH" if clip == "SupermanMoves2" else ("UPPERCUT" if clip == "Uppercut" else ("TWO-PIECE" if clip == "TysonTwoPiece" else "PUNCH " + clip.right(1)))
    if clip == "AirDownKarate": last_move = "AIR KARATE KICK"

func _tick_doge_attack(delta: float) -> void:
    if not controls_enabled or hitstun > 0:
        _cancel_doge_attack()
        return
    if doge_attack_clip.is_empty():
        doge_combo_remaining = maxf(0, doge_combo_remaining - delta)
        if doge_combo_remaining == 0:
            doge_combo_next = 1
        return
    var timing: Dictionary = doge_attack_timings[doge_attack_clip]
    doge_attack_elapsed += delta
    facing = doge_attack_facing
    if doge_attack_clip not in ["SupermanMoves2", "TysonTwoPiece", "AirDownKarate", "GoalkeeperKick"] and not _doge_struck and doge_attack_elapsed + 0.000001 >= float(timing.impact_time):
        _doge_struck = true
        if doge_attack_clip == "Uppercut":
            # Fighter origins are feet: test a front/upper chest volume instead.
            for target in get_tree().get_nodes_in_group("fighters"):
                if not can_hit(target):
                    continue
                var offset: Vector3 = target.global_position - global_position
                if offset.length() <= 2.5 and absf(offset.z) < 1.5 and offset.x * facing >= -0.2 and offset.x * facing <= 1.8 and offset.y >= -0.25:
                    target.receive_hit(8.0, Vector3.UP, 3.8)
        else:
            _directional_hit(8.0, 3.8, 2.5, Vector3(facing, 0, 0), maxf(0, float(timing.duration) - doge_attack_elapsed))
        # Imported fist motion is the cue; the prototype sphere obscures it.
        attack_flash_time = 0
        if _attack_flash:
            _attack_flash.visible = false
    attack_cooldown = maxf(0, float(timing.duration) - doge_attack_elapsed)
    if doge_attack_elapsed + 0.000001 >= float(timing.duration):
        var remainder := maxf(0, doge_attack_elapsed - float(timing.duration))
        var continue_combo := doge_punch_buffered
        var branch := doge_buffer_branch
        doge_combo_next = int(doge_attack_clip.right(1)) + 1 if doge_attack_clip in ["Punch1", "Punch2", "Punch3"] else 1
        doge_attack_clip = ""
        doge_punch_buffered = false
        doge_buffer_branch = ""
        doge_combo_remaining = maxf(0, doge_combo_reset_seconds - remainder)
        if continue_combo:
            _start_doge_attack("TysonTwoPiece" if branch == "tyson" else "Punch%d" % doge_combo_next, Vector2.ZERO)
            _tick_doge_attack(remainder)
        elif doge_combo_remaining == 0:
            doge_combo_next = 1

func _query_doge_two_piece() -> void:
    # Two discrete, once-only contact samples on the visible native skeleton.
    # Called after movement; hidden animation carriers never determine damage.
    if doge_attack_clip != "TysonTwoPiece" or hitstun > 0 or freeze_remaining > 0 or magic_locked() or not controls_enabled:
        return
    var timing: Dictionary = doge_attack_timings.TysonTwoPiece
    var events: Array = timing.hits
    var view = _visual_root.get_node("DogeVisual")
    var skeleton: Skeleton3D = view.model.find_children("*", "Skeleton3D", true, false)[0]
    while _doge_two_piece_event < events.size() and doge_attack_elapsed + 0.000001 >= float(events[_doge_two_piece_event].time):
        var event: Dictionary = events[_doge_two_piece_event]
        _doge_two_piece_event += 1
        if _doge_two_piece_event == 2 and not doge_tyson_followup:
            continue
        # Seek the exact authored contact even between physics ticks.
        view.sync_pose("idle", doge_attack_facing, TORPEDO_LAUNCH_TIME, TORPEDO_TACKLE_TIME, TORPEDO_BRAKE_TIME, TORPEDO_LANDING_TIME, true, velocity, false, 0, "TysonTwoPiece", float(event.time), float(timing.duration))
        skeleton.force_update_all_bone_transforms()
        var bone := skeleton.find_bone(str(event.bone))
        if bone < 0:
            push_error("Two-piece contact bone missing: " + str(event.bone))
            continue
        var center: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
        var radius: float = float(event.radius) * view.global_basis.x.length() / 1.25
        for target in get_tree().get_nodes_in_group("fighters"):
            if not can_hit(target) or (target.global_position.x - global_position.x) * doge_attack_facing <= 0:
                continue
            for child in target.get_hurtbox_shapes():
                if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D:
                    continue
                var capsule: CapsuleShape3D = child.shape
                var transform: Transform3D = child.global_transform
                var half_axis := maxf(0, capsule.height * 0.5 - capsule.radius)
                var a := transform * Vector3(0, -half_axis, 0)
                var b := transform * Vector3(0, half_axis, 0)
                var body_radius := capsule.radius * maxf(transform.basis.x.length(), transform.basis.z.length())
                var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
                if center.distance_squared_to(nearest) <= pow(radius + body_radius, 2):
                    var lift := 0.25 if _doge_two_piece_event == 2 else 0.0
                    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,float(event.damage), Vector3(doge_attack_facing, lift, 0), float(event.knockback),child,nearest,center)
                    if _doge_two_piece_event == 1:
                        # Setup jab retains ordinary damage/shield/hitstun, but
                        # must not push its victim out of the following right.
                        target.velocity = target.velocity.limit_length(0.2)
                    break
    _update_move_visuals()

var _doge_karate_targets: Array = []

func _query_doge_air_karate() -> void:
    if doge_attack_clip != "AirDownKarate" or is_grounded() or hitstun > 0 or freeze_remaining > 0 or magic_locked() or not controls_enabled:
        return
    var timing: Dictionary = doge_attack_timings.AirDownKarate
    if doge_attack_elapsed + 0.000001 < float(timing.active_start) or doge_attack_elapsed > float(timing.active_end) + 0.000001:
        return
    _update_move_visuals()
    var view = _visual_root.get_node("DogeVisual")
    var skeleton: Skeleton3D = view.model.find_children("*", "Skeleton3D", true, false)[0]
    skeleton.force_update_all_bone_transforms()
    var center: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
    var radius: float = float(timing.radius) * view.global_basis.x.length() / 1.25
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target) or target in _doge_karate_targets or (target.global_position.x - global_position.x) * doge_attack_facing <= 0:
            continue
        for child in target.get_hurtbox_shapes():
            if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D: continue
            var capsule: CapsuleShape3D = child.shape
            var transform: Transform3D = child.global_transform
            var half_axis := maxf(0, capsule.height * 0.5 - capsule.radius)
            var a := transform * Vector3(0, -half_axis, 0)
            var b := transform * Vector3(0, half_axis, 0)
            var body_radius := capsule.radius * maxf(transform.basis.x.length(), transform.basis.z.length())
            var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
            if center.distance_squared_to(nearest) <= pow(radius + body_radius, 2):
                _doge_karate_targets.append(target)
                preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,float(timing.damage), Vector3(doge_attack_facing * cos(deg_to_rad(30)), -0.5, 0), float(timing.knockback),child,nearest,center)
                break

func _query_doge_goalkeeper() -> void:
    if doge_attack_clip != "GoalkeeperKick" or not is_grounded() or hitstun > 0 or freeze_remaining > 0 or magic_locked() or not controls_enabled: return
    if doge_attack_elapsed < 0.4 or doge_attack_elapsed > 0.5: return
    _update_move_visuals()
    var view = _visual_root.get_node("DogeVisual")
    var skeleton: Skeleton3D = view.model.find_children("*", "Skeleton3D", true, false)[0]
    skeleton.force_update_all_bone_transforms()
    var center: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
    var radius: float = 0.22 * view.global_basis.x.length() / 1.25
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target) or target in _doge_goalkeeper_targets: continue
        for child in target.get_hurtbox_shapes():
            if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D: continue
            var capsule: CapsuleShape3D = child.shape
            var transform: Transform3D = child.global_transform
            var half_axis := maxf(0, capsule.height * 0.5 - capsule.radius)
            var a := transform * Vector3(0, -half_axis, 0)
            var b := transform * Vector3(0, half_axis, 0)
            var body_radius := capsule.radius * maxf(transform.basis.x.length(), transform.basis.z.length())
            var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
            if center.distance_squared_to(nearest) <= pow(radius + body_radius, 2):
                _doge_goalkeeper_targets.append(target)
                preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,lerpf(10, 26, doge_goalkeeper_power), Vector3(doge_attack_facing, 0.25, 0), lerpf(4, 9, doge_goalkeeper_power),child,nearest,center)
                break

func _query_doge_superman() -> void:
    # Same neutral aerial damage/reach, now once at the visible source punch.
    # Run AFTER movement and terrain landing cancellation, not on the input edge.
    if doge_attack_clip != "SupermanMoves2" or _doge_struck or hitstun > 0 or freeze_remaining > 0 or magic_locked() or not controls_enabled or is_grounded():
        return
    var timing: Dictionary = doge_attack_timings[doge_attack_clip]
    if doge_attack_elapsed + 0.000001 < float(timing.impact_time): return
    _doge_struck = true
    _directional_hit(8.0, 3.8, 2.5, Vector3(facing, 0, 0), maxf(0, float(timing.duration) - doge_attack_elapsed))
    attack_flash_time = 0
    if _attack_flash: _attack_flash.visible = false

func _cancel_doge_attack(preserve_up_pose := false) -> void:
    if doge_air_drop: doge_air_drop.cancel()
    if doge_ground_basic: doge_ground_basic.cancel()
    _doge_goalkeeper_targets.clear()
    doge_goalkeeper_hold = 0.0
    doge_goalkeeper_source = 0.0
    _doge_karate_targets.clear()
    if doge_ground_rush: doge_ground_rush.cancel()
    # End ordinary takeoff on every existing combat/lifecycle cancellation.
    # Do not seek here: freeze/grab must retain the visible paused pose.
    if character_id == "doge_man" and _visual_root:
        var view = _visual_root.get_node_or_null("DogeVisual")
        if view:
            view.jump_elapsed = -1.0
            view.cancel_up_special(preserve_up_pose)
            view.air_uppercut = false
    if not doge_attack_clip.is_empty():
        attack_cooldown = 0
        attack_flash_time = 0
    doge_attack_clip = ""
    doge_attack_elapsed = 0
    _doge_struck = false
    _doge_two_piece_event = 0
    doge_combo_next = 1
    doge_combo_remaining = 0
    doge_punch_buffered = false
    doge_tyson_followup = false
    doge_buffer_branch = ""

func _torpedo_committed() -> bool:
    return torpedo_phase in ["launch", "tackle", "landing"] or (torpedo_phase == "fall" and torpedo_time > 0)

func _tick_torpedo(delta: float) -> void:
    if torpedo_phase == "idle":
        return
    if _torpedo_committed():
        facing = torpedo_facing
    torpedo_time = maxf(0, torpedo_time - delta)
    match torpedo_phase:
        "launch":
            velocity.x = facing * 2.0
            if torpedo_time <= 0:
                torpedo_phase = "tackle"
                tackle_active = TORPEDO_TACKLE_TIME
                velocity = Vector3(facing * 17.0, 0, 0)
        "tackle":
            velocity = Vector3(facing * 17.0, 0, 0)
            for target in get_tree().get_nodes_in_group("fighters"):
                if can_hit(target) and target not in tackle_targets and global_position.distance_to(target.global_position) < 2.0:
                    tackle_targets.append(target)
                    target.receive_hit(14.0, Vector3(facing, 0.3, 0), 5.5)
            tackle_active = maxf(0, tackle_active - delta)
            if tackle_active <= 0:
                torpedo_phase = "fall"
                torpedo_time = TORPEDO_BRAKE_TIME
        "fall":
            if torpedo_time > 0:
                velocity.x = move_toward(velocity.x, 0, 22 * delta)
        "landing":
            velocity.x = 0
            if torpedo_time <= 0:
                torpedo_phase = "idle"

func _clear_ggb_dust() -> void:
    if is_instance_valid(_ggb_dust):
        _ggb_dust.get_parent().remove_child(_ggb_dust)
        _ggb_dust.queue_free()
    _ggb_dust = null

func _land_character_move() -> void:
    if not drop_committed:
        return
    if character_id == "ggb":
        # reset_air_resources runs before and after movement on every floor
        # tick. Retain steel, but consume the old impact exactly once.
        if not _ggb_impact_pending: return
        _ggb_impact_pending = false
    else:
        drop_committed = false
    attack_cooldown = 0.65
    landing_lag = 0.65
    attack_flash_time = 0.0
    if _attack_flash:
        _attack_flash.visible = false
    _clear_ggb_dust()
    if character_id == "ggb":
        _ggb_dust = preload("res://scripts/ggb_dust.gd").new()
        _ggb_dust.name = "GGBDustImpact"
        get_parent().add_child(_ggb_dust)
        _ggb_dust.global_position = global_position
    _update_move_visuals()
    for target in get_tree().get_nodes_in_group("fighters"):
        if can_hit(target) and global_position.distance_to(target.global_position) < 2.8:
            target.receive_hit(18.0, Vector3(signf(target.global_position.x - global_position.x), 0.8, 0), 6.0)

func _directional_hit(hit_damage: float, base_knockback: float, attack_range: float, direction: Vector3, cooldown: float) -> void:
    attack_cooldown = cooldown
    attack_flash_time = 0.18
    if _attack_flash:
        _attack_flash.position = Vector3.UP + direction * attack_range * 0.62
        _attack_flash.scale = Vector3.ONE * (0.65 if hit_damage < 10.0 else 1.0)
    for target in get_tree().get_nodes_in_group("fighters"):
        if not can_hit(target):
            continue
        var offset: Vector3 = target.global_position - global_position
        if absf(offset.z) < 1.5 and offset.length() <= attack_range and offset.normalized().dot(direction) > 0.4:
            var launch := direction
            if absf(direction.y) < 0.5:
                launch.y = 0.35
            target.receive_hit(hit_damage, launch, base_knockback)

func _handle_blast_zone() -> void:
    lose_stock()
    if stocks > 0:
        global_position = spawn_position
        velocity = Vector3.ZERO
        hitstun = 0.55
    else:
        controls_enabled = false
        collision_layer = 0
        collision_mask = 0
        visible = false
        eliminated.emit(self)

func _build_visuals() -> void:
    _frozen_shell = MeshInstance3D.new()
    _frozen_shell.name = "FrozenShell"
    var ice_mesh := CylinderMesh.new()
    ice_mesh.top_radius = 0.48
    ice_mesh.bottom_radius = 0.72
    ice_mesh.height = 2.2
    ice_mesh.radial_segments = 6
    _frozen_shell.mesh = ice_mesh
    _frozen_shell.position.y = 1.05
    var ice_material := StandardMaterial3D.new()
    ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    ice_material.albedo_color = Color(0.25, 0.8, 1.0, 0.4)
    ice_material.roughness = 0.2
    _frozen_shell.material_override = ice_material
    _frozen_shell.visible = false
    add_child(_frozen_shell)
    _visual_root = Node3D.new()
    _visual_root.name = "VisualRoot"
    add_child(_visual_root)

    var material := StandardMaterial3D.new()
    material.albedo_color = body_color
    material.metallic = 0.28
    material.roughness = 0.34

    var body := MeshInstance3D.new()
    var body_mesh := CapsuleMesh.new()
    body_mesh.radius = 0.55
    body_mesh.height = 1.65
    body.mesh = body_mesh
    body.material_override = material
    body.position.y = 0.9
    _visual_root.add_child(body)

    var head := MeshInstance3D.new()
    var head_mesh := SphereMesh.new()
    head_mesh.radius = 0.45
    head_mesh.height = 0.9
    head.mesh = head_mesh
    head.material_override = material
    head.position = Vector3(0.0, 1.95, 0.0)
    _visual_root.add_child(head)

    var accent_material := StandardMaterial3D.new()
    accent_material.albedo_color = Color(0.8, 0.55, 0.25)
    accent_material.metallic = 0.05
    accent_material.roughness = 0.8
    accent_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    if character_id == "teknium":
        var staff := MeshInstance3D.new()
        var staff_mesh := CylinderMesh.new()
        staff_mesh.top_radius = 0.07
        staff_mesh.bottom_radius = 0.07
        staff_mesh.height = 2.35
        staff.mesh = staff_mesh
        staff.material_override = accent_material
        staff.position = Vector3(0.72, 0.9, 0.0)
        staff.rotation.z = -0.18
        _visual_root.add_child(staff)
    elif character_id == "doge_man":
        var ears := MeshInstance3D.new()
        var ears_mesh := BoxMesh.new()
        ears_mesh.size = Vector3(0.9, 0.48, 0.55)
        ears.mesh = ears_mesh
        ears.material_override = accent_material
        ears.position = Vector3(0.0, 2.32, 0.0)
        _visual_root.add_child(ears)

    if character_id == "ggb":
        for placeholder in _visual_root.get_children():
            _visual_root.remove_child(placeholder)
            placeholder.queue_free()
        var ggb_visual = preload("res://scripts/ggb_visual.gd").new()
        ggb_visual.name = "GGBVisual"
        _visual_root.add_child(ggb_visual)
    if character_id == "turbofit":
        # Use the imported character without the retired primitive guitar prop.
        for placeholder in _visual_root.get_children():
            if placeholder is MeshInstance3D:
                _visual_root.remove_child(placeholder)
                placeholder.queue_free()
        var turbofit_visual = preload("res://scripts/turbofit_visual.gd").new()
        turbofit_visual.name = "TurboFitVisual"
        turbofit_visual.palette = body_color
        _visual_root.add_child(turbofit_visual)

    if character_id == "doge_man":
        # Replace all placeholder geometry, retaining independent collision/UI.
        for placeholder in _visual_root.get_children():
            _visual_root.remove_child(placeholder)
            placeholder.queue_free()
        var doge_visual = preload("res://scripts/doge_visual.gd").new()
        doge_visual.name = "DogeVisual"
        doge_visual.palette = body_color
        _visual_root.add_child(doge_visual)

    if character_id == "teknium":
        # One authoritative textured mesh; remove every primitive, including staff.
        for placeholder in _visual_root.get_children():
            _visual_root.remove_child(placeholder)
            placeholder.queue_free()
        var teknium_visual = preload("res://scripts/teknium_visual.gd").new()
        teknium_visual.name = "TekniumVisual"
        _visual_root.add_child(teknium_visual)

    if character_id == "ice_mage":
        for placeholder in _visual_root.get_children():
            _visual_root.remove_child(placeholder)
            placeholder.queue_free()
        var ice_mage_visual = preload("res://scripts/ice_mage_visual.gd").new()
        ice_mage_visual.name = "IceMageVisual"
        _visual_root.add_child(ice_mage_visual)

    if character_id == "witcheer":
        for placeholder in _visual_root.get_children():
            _visual_root.remove_child(placeholder)
            placeholder.queue_free()
        var witcheer_visual = preload("res://scripts/witcheer_visual.gd").new()
        witcheer_visual.name = "WitcheerVisual"
        _visual_root.add_child(witcheer_visual)

    if character_id == "mephisto":
        for placeholder in _visual_root.get_children():
            _visual_root.remove_child(placeholder)
            placeholder.queue_free()
        var mephisto_visual = preload("res://scripts/mephisto_visual.gd").new()
        mephisto_visual.name = "MephistoVisual"
        _visual_root.add_child(mephisto_visual)

    var collision := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.55
    shape.height = 1.8
    collision.shape = shape
    collision.position.y = 0.9
    add_child(collision)

    var label := Label3D.new()
    label.name = "PlayerLabel"
    label.no_depth_test = true
    label.text = "P%d" % player_index
    if team_id >= 0:
        label.text += " · " + ("A" if team_id == 0 else "B")
    label.pixel_size = 0.012
    label.font_size = 36
    label.outline_size = 8
    label.position = Vector3(0.0, 2.9, 0.0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(label)

    _move_status = Label3D.new()
    _move_status.name = "MoveStatus"
    _move_status.font_size = 28
    _move_status.pixel_size = 0.02
    _move_status.no_depth_test = true
    _move_status.outline_size = 7
    _move_status.position = Vector3(0, 3.5, 0)
    _move_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(_move_status)

    _shield_visual = MeshInstance3D.new()
    var shield_mesh := SphereMesh.new()
    shield_mesh.radius = 1.25
    shield_mesh.height = 2.5
    _shield_visual.mesh = shield_mesh
    var shield_material := StandardMaterial3D.new()
    shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    shield_material.albedo_color = Color(0.2, 0.75, 1.0, 0.24)
    shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _shield_visual.material_override = shield_material
    _shield_visual.position.y = 1.0
    _shield_visual.visible = false
    add_child(_shield_visual)

    _sound_orb_visual = Node3D.new()
    _sound_orb_visual.name = "SoundOrb"
    _sound_orb_visual.position = Vector3.UP
    _sound_orb_visual.visible = false
    add_child(_sound_orb_visual)
    var orb_shell := MeshInstance3D.new()
    orb_shell.name = "SphereShell"
    var orb_mesh := SphereMesh.new()
    orb_mesh.radius = SOUND_ORB_RADIUS
    orb_mesh.height = SOUND_ORB_RADIUS * 2.0
    orb_shell.mesh = orb_mesh
    var orb_material := StandardMaterial3D.new()
    orb_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    orb_material.albedo_color = Color(body_color.r, body_color.g, body_color.b, 0.16)
    orb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    orb_material.emission_enabled = true
    orb_material.emission = body_color
    orb_material.emission_energy_multiplier = 1.6
    orb_shell.material_override = orb_material
    _sound_orb_visual.add_child(orb_shell)
    for ring_name in ["WaveRingX", "WaveRingY", "WaveRingZ"]:
        var ring := MeshInstance3D.new()
        ring.name = ring_name
        var ring_mesh := TorusMesh.new()
        ring_mesh.inner_radius = SOUND_ORB_RADIUS * 0.84
        ring_mesh.outer_radius = SOUND_ORB_RADIUS * 0.9
        ring.mesh = ring_mesh
        var ring_material := orb_material.duplicate()
        ring_material.albedo_color.a = 0.48
        ring.material_override = ring_material
        if ring_name == "WaveRingX":
            ring.rotation.z = PI / 2.0
        elif ring_name == "WaveRingZ":
            ring.rotation.x = PI / 2.0
        _sound_orb_visual.add_child(ring)

    _attack_flash = MeshInstance3D.new()
    _attack_flash.name = "AttackTimingMarker"
    # Keep the existing timing/position handle for attack routes, but remove
    # the overbright prototype sphere. This node never owned collision.
    _attack_flash.position.y = 1.0
    _attack_flash.visible = false
    add_child(_attack_flash)
