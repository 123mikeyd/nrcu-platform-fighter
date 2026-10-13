extends RefCounted
# SSB64 feel pass, Batch 3 "Presentation": KO beat, Smash-style camera, hit feedback.
# Every feature has ONE switch below (static so tests / Dev tools can flip it at runtime).
# Hooks in shared files are single lines that call the static funcs here:
#   fighter.gd blast-zone check -> begin_ko(self)      (KO beat before Return to Sender)
#   fighter.gd _clear_move_state -> cancel_ko(self)    (reset / match end abort a running beat)
#   fighter.gd receive_hit (end)  -> on_hit(self, source, damage, base_knockback)
#   fortress_shared_camera.gd reads the CAMERA_* switches and exposes add_shake().
#          [CAL]  = calibrated for NRCU's world/pacing (reason next to it).

const KoBeatScript = preload("res://scripts/ssb_ko_beat.gd")
const FxScript = preload("res://scripts/ssb_fx.gd")
const KnockbackMath = preload("res://scripts/combat_math.gd")

# ---------------------------------------------------------------- switches
static var KO_BEAT_ENABLED := true          # side/bottom explosion + 0.75 s delay before Return to Sender
static var STAR_KO_ENABLED := true          # top KO -> star KO / screen KO (off = top KOs use the side/bottom beat)
static var SCREEN_KO_ENABLED := true        # 1-in-6 "hit the camera" gag on top KOs
static var KO_SHAKE_ENABLED := true         # short camera shake on KO explosion / screen-KO thud
static var RUMBLE_ENABLED := true           # gamepad rumble on hits and KOs (human pad players only)
static var HIT_SPARK_ENABLED := true        # in-world hit spark that scales with damage
static var CAMERA_FAST_ZOOM := true         # near-instant zoom out, SSB-rate zoom in
static var CAMERA_LOOK_AHEAD := true        # more room in front of each fighter than behind (smoothed)
static var CAMERA_PLAYER_PADDING := true    # 1.5 / 1.32 / 1.16 / 1.0 framing for 1-4 fighters
# Toy Room and Hermes Weaver were authored for a fixed camera (backdrops end just off-frame),
# so the dynamic camera stays on the default stage unless this is turned on. Shake applies everywhere.
static var CAMERA_DYNAMIC_ON_THEMED_STAGES := false

# Test/dev override for top KOs: "" = random, "star" or "screen".
static var FORCE_TOP_KO := ""
# Sound hook: no boom/star/thud sfx exists in the project yet (only airdoge_shutter.wav).
# Put a res:// path here and the KO beat plays it; empty = silent.
static var KO_BOOM_SFX := ""
static var STAR_KO_SFX := ""
static var SCREEN_KO_SFX := ""

# ---------------------------------------------------------------- KO timing
const DEAD_WAIT := 45.0 / 60.0              # [FACT] FTCOMMON_DEAD_WAIT 45 f: side/bottom KO -> respawn
const SCREEN_KO_CHANCE := 1.0 / 6.0         # [FACT] ftcommondead.c:637
# [CAL] SSB star/screen KO = 180 f flight + 45 f = 3.77 s. NRCU's Return to Sender is much faster than
# SSB's 1.5 s halo descent, so the top-KO beat is scaled to ~0.6x: 1.45 s flight + 0.4 s twinkle + 0.45 s.
const STAR_FLIGHT := 1.45
const STAR_TWINKLE := 0.40
const STAR_TAIL := 0.45
const SCREEN_FLY_IN := 0.28                 # [CAL] fighter rushes at the lens
const SCREEN_HOLD := 0.30                   # [CAL] splat against the glass
const SCREEN_SLIDE := 1.27                  # [CAL] slides down out of frame (fly+hold+slide+tail = star total)
const SCREEN_TAIL := 0.45

# ---------------------------------------------------------------- shake / rumble
# [CAL] SSB quake curves are ROM data (unknown). 0.28 m at the 23 m default camera is a short, clear jolt;
# like SSB it scales with camera distance so it stays visible zoomed out. Decays to 0 in 0.32 s.
const KO_SHAKE := 0.28
const KO_SHAKE_SECONDS := 0.32
const SCREEN_KO_SHAKE := 0.18
const SHAKE_REF_DISTANCE := 23.0
# [FACT] KO rumble: victim 30 f, every other human 15 f. Hit rumble: victim int(0.75*dmg+4) f solid,
# attacker int(0.5*dmg+2) f (SSB pulses it 2 on / 1 off; Godot has no pulse, so it is a lighter motor) [CAL].
const KO_RUMBLE_VICTIM := 30.0 / 60.0
const KO_RUMBLE_OTHERS := 15.0 / 60.0

# ---------------------------------------------------------------- hit spark
const SPARK_BASE_RADIUS := 0.26             # [CAL] 10% hit spark ~0.5 m across next to a ~2 m fighter
const SPARK_MAX_SCALE := 3.6                # [CAL] SSB 30% hit = 3.6x; cap there so 40%+ moves stay readable
# [CAL] SSB heavy spark at knockback >= 180. NRCU launch speed (m/s) that reliably reaches a blast line
# is ~13-15; 13 marks "big knockback". Re-check after Batch 1 changes the knockback scale.
const HEAVY_SPARK_STRENGTH := 13.0

# ---------------------------------------------------------------- camera
const CAM_PLAYER_ZOOM := [1.0, 1.50, 1.32, 1.16, 1.00]   # [FACT] gmcamera.c:40-47 (index = fighters framed)
const CAM_BOX_FRONT := 1000.0                            # [FACT] box in front of facing
const CAM_BOX_BACK := 700.0                              # [FACT] box behind
const CAM_ZOOM_IN_RATE := 4.68                           # [FACT] 7.5 %/frame -> -ln(0.925)*60 = 4.68 /s
const CAM_ZOOM_OUT_RATE := 30.0                          # [CAL] SSB snaps out; 30 /s (~40 %/frame) closes a
                                                         # gap in ~0.1 s so respawn teleports don't jump-cut
const CAM_LOOK_AHEAD_RATE := 3.0                         # [CAL] look-ahead side swaps over ~0.5 s, no whip pans

static func _rng() -> RandomNumberGenerator:
    var r := RandomNumberGenerator.new()
    r.randomize()
    return r

# Spark scale (SSB efmanager.c:2171): dmg<10 -> 1-0.05*(10-dmg), else 1+0.13*(dmg-10).   [FACT]
static func spark_scale(dmg: float) -> float:
    var s: float = 1.0 - 0.05 * (10.0 - dmg) if dmg < 10.0 else 1.0 + 0.13 * (dmg - 10.0)
    return clampf(s, 0.5, SPARK_MAX_SCALE)

static func victim_rumble_seconds(dmg: float) -> float:
    return float(int(0.75 * dmg + 4.0)) / 60.0          # [FACT] ftmain.c:3920

static func attacker_rumble_seconds(dmg: float) -> float:
    return float(int(0.5 * dmg + 2.0)) / 60.0           # [FACT] ftmain.c:3960

static func camera_padding(count: int) -> float:
    if not CAMERA_PLAYER_PADDING: return 1.32           # old framing == today's 2-player box
    return CAM_PLAYER_ZOOM[clampi(count, 1, 4)]

static func is_pad_human(f) -> bool:
    return is_instance_valid(f) and f.get("control_type") != "bot" and int(f.get("input_device") if f.get("input_device") != null else -1) >= 0

static func rumble(f, weak: float, strong: float, seconds: float) -> void:
    if not RUMBLE_ENABLED or seconds <= 0.0 or not is_pad_human(f): return
    Input.start_joy_vibration(int(f.input_device), clampf(weak, 0, 1), clampf(strong, 0, 1), seconds)

static func shake(node: Node, amount: float, seconds: float) -> void:
    if not KO_SHAKE_ENABLED or not is_instance_valid(node) or not node.is_inside_tree(): return
    var cam := node.get_viewport().get_camera_3d()
    if cam and cam.has_method("add_shake"): cam.add_shake(amount, seconds)

static func play_sfx(node: Node, path: String, at: Vector3) -> void:
    if path.is_empty() or not ResourceLoader.exists(path) or not is_instance_valid(node): return
    var player := AudioStreamPlayer3D.new()
    player.stream = load(path)
    var host: Node = node.get_parent() if node.get_parent() else node
    host.add_child(player)
    player.global_position = at
    player.finished.connect(player.queue_free)
    player.play()

static func fx_host(f: Node) -> Node:
    var p: Node = f.get_parent()
    return p if p else f

# ---------------------------------------------------------------- KO beat
# Fighters with their own blast handling (Story Bobo encounter teleports home, Heavy Bag never dies)
# keep it: the beat only wraps the ordinary stock KO.
static func uses_stock_ko(f) -> bool:
    if not is_instance_valid(f) or f.has_method("is_heavy_bag"): return false
    var path: String = f.get_script().resource_path if f.get_script() else ""
    return not path.ends_with("bobo_fighter.gd") and not path.ends_with("heavy_bag.gd")

static func ko_kind(pos: Vector3) -> String:
    # SSB check order: bottom, right, left, top.   [FACT] ftcommondead.c:533-647
    if pos.y < -8.0: return "bottom"
    if absf(pos.x) > 16.0: return "side"
    return "top"

static func in_ko(f) -> bool:
    if not is_instance_valid(f): return false
    var beat = f.get_node_or_null("SsbKoBeat")
    return beat != null and beat.active

# Called where fighter.gd detects a blast-zone crossing. Returns true when the beat owns the KO
# (it calls fighter._handle_blast_zone() itself when the beat ends, so stock loss, Return to Sender,
# elimination and winner detection run exactly as before, just later).
static func begin_ko(f) -> bool:
    if not KO_BEAT_ENABLED or not uses_stock_ko(f) or f.stocks <= 0: return false
    var beat = f.get_node_or_null("SsbKoBeat")
    if beat == null:
        beat = KoBeatScript.new()
        beat.name = "SsbKoBeat"
        f.add_child(beat)
    if beat.active: return true
    var kind := ko_kind(f.global_position)
    if kind == "top":
        if not STAR_KO_ENABLED: kind = "side"
        elif FORCE_TOP_KO in ["star", "screen"]: kind = FORCE_TOP_KO
        elif SCREEN_KO_ENABLED and _rng().randf() < SCREEN_KO_CHANCE: kind = "screen"
        else: kind = "star"
        if kind == "screen" and not SCREEN_KO_ENABLED: kind = "star"
    beat.start(f, kind)
    return true

static func cancel_ko(f) -> void:
    if not is_instance_valid(f): return
    var beat = f.get_node_or_null("SsbKoBeat")
    if beat and beat.active: beat.cancel()

static func ko_rumble(victim) -> void:
    rumble(victim, 0.9, 1.0, KO_RUMBLE_VICTIM)
    if not victim.is_inside_tree(): return
    for other in victim.get_tree().get_nodes_in_group("fighters"):
        if other != victim and other.get("stocks") != null and other.stocks > 0:
            rumble(other, 0.55, 0.0, KO_RUMBLE_OTHERS)

# ---------------------------------------------------------------- hit feedback
# One call at the end of fighter.receive_hit (accepted hits only). Never touches knockback/hitstun.
static func on_hit(victim, source, damage: float, base_knockback: float) -> void:
    if damage <= 0.0 or not is_instance_valid(victim) or not victim.is_inside_tree(): return
    rumble(victim, 0.7, 0.85, victim_rumble_seconds(damage))
    if is_instance_valid(source) and source != victim and source.get("input_device") != null:
        rumble(source, 0.5, 0.0, attacker_rumble_seconds(damage))
    if not HIT_SPARK_ENABLED: return
    # Launch speed if already applied, else the shared knockback formula (works if a hitlag pass defers launch).
    var strength: float = maxf(victim.velocity.length(), float(KnockbackMath.knockback_strength(victim.damage_percent, damage, base_knockback)))
    var center: Vector3 = victim.global_position + Vector3.UP * 1.05
    var point := center
    var color := Color(1, 0.95, 0.75)
    if is_instance_valid(source) and source is Node3D and source != victim:
        # SSB: spark at the midpoint of hitbox and hurtbox; here the actor centres, kept on the victim's body.
        var src: Vector3 = (source as Node3D).global_position + Vector3.UP * 1.05
        var offset := (src - center) * 0.5
        point = center + offset.limit_length(0.65)
        if source.get("body_color") != null: color = source.body_color
    point.z = 0.35   # just in front of the fighter plane so the body doesn't hide it
    var fx = FxScript.new()
    fx.setup_spark(color, SPARK_BASE_RADIUS * spark_scale(damage), strength >= HEAVY_SPARK_STRENGTH)
    fx_host(victim).add_child(fx)
    fx.global_position = point
