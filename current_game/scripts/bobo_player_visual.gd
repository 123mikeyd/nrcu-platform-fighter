extends "res://scripts/bobo_visual.gd"
# Player-only library. The installed painted model and Story route are untouched.
const TAKEOFF_SECONDS := 0.12
var takeoff := -1.0
var airborne := false
var landing := -1.0
const GAIT_SPEED := 0.4925375339290258
var gait_phase := 0.0
var contact
var ground_mode := ""
var blend_pose := []
var blend_time := 0.0
func _ready() -> void:
    super._ready()
    animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    var library: AnimationLibrary = animation_player.get_animation_library("")
    var motions: AnimationLibrary = load("res://assets/bobo/player_locomotion.res")
    for clip in motions.get_animation_list():
        var animation: Animation = motions.get_animation(clip).duplicate(true)
        animation.loop_mode = Animation.LOOP_LINEAR if clip == "OrcWalk" else Animation.LOOP_NONE
        library.add_animation(clip,animation)
    var crouch_motions: AnimationLibrary = load("res://assets/bobo/player_crouch_down_a.res")
    for clip in crouch_motions.get_animation_list():
        library.add_animation(clip,crouch_motions.get_animation(clip).duplicate(true))
    var specials: AnimationLibrary = load("res://assets/bobo/player_specials.res")
    for clip in specials.get_animation_list():
        library.add_animation(clip,specials.get_animation(clip).duplicate(true))
    pose_at("OrcWalk",0)
    contact=load("res://scripts/bobo_foot_contact.gd").new()
    contact.setup(self)
    pose_at("Idle",0)
var crouch_time := 0.0
var crouch_exit := -1.0
func present_crouch(actor, delta: float) -> bool:
    var raw: Dictionary = actor._read_raw_controls(0)
    var allowed: bool = actor.is_grounded() and actor.velocity.y <= 0 and actor.attack_cooldown <= 0 and actor.landing_lag <= 0 and actor.counter_hitstop <= 0 and not actor.magic_locked()
    if not allowed or raw.left or raw.right or raw.up or raw.jump or raw.special:
        crouch_time = 0.0
        crouch_exit = -1.0
        return false
    if raw.down:
        crouch_exit = -1.0
        crouch_time = minf(37.0/30.0,crouch_time+delta)
        if contact: contact.clear()
        ground_mode = ""
        pose_at("TuckedCrouch",crouch_time)
        return true
    if crouch_time <= 0: return false
    if crouch_time >= 37.0/30.0 or crouch_exit >= 0:
        if crouch_exit < 0: crouch_exit = 56.0/30.0
        crouch_exit += delta
        if crouch_exit < 89.0/30.0:
            pose_at("TuckedCrouch",crouch_exit)
            return true
        crouch_exit = -1.0
        crouch_time = 0.0
    else:
        # A released partial entry reverses that exact native segment.
        crouch_time = maxf(0,crouch_time-delta)
        if crouch_time > 0:
            pose_at("TuckedCrouch",crouch_time)
            return true
    return false
func begin_jump() -> void:
    if contact: contact.clear()
    ground_mode=""
    takeoff = 0.0
    landing = -1.0
    airborne = true
    pose_at("JumpStart",0.0)
func cancel_locomotion() -> void:
    # Cancellation changes episode bookkeeping, not a frozen displayed pose.
    if contact: contact.clear(true)
    crouch_time = 0.0
    crouch_exit = -1.0
    gait_phase=0.0
    ground_mode=""
    takeoff = -1.0
    landing = -1.0
    airborne = false
func pose_at(clip: String, time: float) -> void:
    if contact:contact.sk.clear_bones_global_pose_override()
    if current_clip != clip:
        current_clip = clip
        animation_player.stop()
        animation_player.play(clip,0)
    animation_player.seek(time,true)
    animation_player.pause()
    model.find_children("*","Skeleton3D",true,false)[0].force_update_all_bone_transforms()
func react(clip: String) -> void:
    if contact:contact.clear()
    # This player is manually sampled. A timed AnimationPlayer crossfade never
    # advances under seek/pause and pins Idle to the outgoing thrust pose.
    elapsed = 0.0
    current_clip = ""
    pose_at(clip, 0.0)
func seek_thrust(time: float) -> void:
    if contact:contact.clear()
    super.seek_thrust(time)
func locomotion(actor, delta: float) -> void:
    if delta<=0: return
    contact.sk.clear_bones_global_pose_override()
    # Jump is event-driven; upward knockback and ledge/drop exits never fake takeoff.
    var grounded: bool = actor.is_grounded() and actor.velocity.y <= 0.0
    if not grounded:
        contact.clear()
        ground_mode=""
        airborne = true
        landing = -1.0
        if takeoff >= 0 and actor.velocity.y > 0:
            takeoff += delta
            if takeoff < TAKEOFF_SECONDS:
                pose_at("JumpStart",takeoff / TAKEOFF_SECONDS * 0.3)
                return
        takeoff = -1.0
        if actor.velocity.y > 0:
            # The remaining ascent ends at the exact approved apex pose.
            var remaining_speed: float = actor.JUMP_SPEED - actor.GRAVITY * TAKEOFF_SECONDS
            pose_at("JumpRise",clampf(1.0-actor.velocity.y/remaining_speed,0,1)*0.4)
        else:
            pose_at("JumpFall",clampf(-actor.velocity.y/actor.JUMP_SPEED,0,1)*0.4)
        return
    takeoff = -1.0
    if airborne:
        airborne = false
        landing = 0.0
    if landing >= 0:
        landing += delta
        if landing < animation_player.get_animation("JumpLand").length:
            pose_at("JumpLand",landing)
            contact.apply(actor,gait_phase,true,true)
            return
        landing = -1.0
    # Advance by realized controller displacement, never requested velocity.
    # A wall cannot pedal the gait; teleports/lifecycle updates do not contribute.
    var distance:float=absf(actor.global_position.x-actor.motion_origin.x)
    var moving:bool=distance>0.00001
    if distance<GAIT_SPEED*delta*2.0:
        gait_phase=fposmod(gait_phase+distance/GAIT_SPEED,5.5)
    var mode="OrcWalk" if moving else "Idle"
    if mode!=ground_mode:
        blend_pose.clear()
        for i in contact.sk.get_bone_count():blend_pose.append(contact.sk.get_bone_pose(i))
        blend_time=0.0
        ground_mode=mode
    pose_at(mode,gait_phase if moving else fposmod(elapsed,animation_player.get_animation("Idle").length))
    blend_time+=delta
    if blend_time<0.22 and not blend_pose.is_empty():
        for i in contact.sk.get_bone_count():
            contact.sk.set_bone_pose(i,blend_pose[i].interpolate_with(contact.sk.get_bone_pose(i),smoothstep(0,0.22,blend_time)))
        contact.sk.force_update_all_bone_transforms()
    contact.apply(actor,gait_phase,not moving,false)
    elapsed+=delta
