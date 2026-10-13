extends "res://scripts/weaver_gap_base.gd"
# P2: one centered temporary floor. No lateral actor delivery.
const KO_Y = -8.0 # native fighter.gd lower blast-zone root threshold
const START_Y = -9.25
const ENTRY_END_Y = -4.0
const ENTRY_SPEED = 18.0
const LIFT_SPEED = 0.75
var bridge: AnimatableBody3D
var bridge_shape: BoxShape3D
var strands: Array=[]
var bridge_solid=false
var entry_kos: Array=[]
var entry_contact_samples: Array=[]
var configured=false

func _ready():
    super._ready()
    for n in nets:
        remove_child(n); n.queue_free()
    nets.clear()
    # Static stone collision follows visible geometry without imposing horizontal
    # conveyor velocity on fighters standing at the closing seam.
    for i in 2:
        var old=decks[i]; remove_child(old); old.queue_free()
        var b=StaticBody3D.new(); b.name="StoneHalf"+str(i)
        b.collision_layer=1; b.collision_mask=0; add_child(b)
        var c=CollisionShape3D.new(); var box=BoxShape3D.new(); box.size=Vector3(8,1.04,3.8)
        c.shape=box; b.add_child(c); decks[i]=b
    net_y=START_Y; net_x=0
    bridge=body("SingleGapFloor",Vector3(0,START_Y-0.06,0),Vector3(4.7,0.12,3.4),true)
    nets.append(bridge)
    bridge_shape=bridge.get_child(0).shape
    for k in 29:
        var m=strand(bridge,Vector3(-2.32+float(k)*4.64/28,0.05,0),Vector3(0.028,0.02,3.4))
        strands.append({"mesh":m,"warp":true,"u":float(k)/28})
    for k in 23:
        var m=strand(bridge,Vector3(0,0.045,-1.66+float(k)*3.32/22),Vector3(4.7,0.02,0.028))
        strands.append({"mesh":m,"warp":false,"u":float(k)/22})
    for s in strands:
        var mat: StandardMaterial3D=s.mesh.material_override
        mat.albedo_color=Color("d4b374")
        mat.emission_enabled=true; mat.emission=Color("896335"); mat.emission_energy_multiplier=0.22
    configured=true
    help_panel.text="HERMES WEAVER P2 - SINGLE GAP FLOOR\nP1 Tek: WASD / Space / F basic / G special\nP2 Doge: Arrows / Enter / K basic / L special\nC cycle   T repeat   R reset   Esc pause   F1 help\nFast entry has NO collision or damage in recoverable space.\nOnly existing lower blast-zone victims can be KO'd.\nOne weave rises to deck height, stays centered, and seals the gap.\nDown drops through the rising weave; joined-height weave is solid."
    sync_surfaces()
    print("P2_READY single_floor=true lower_ko_root=",KO_Y)



func set_solid(value: bool):
    if bridge_solid==value: return
    bridge_solid=value
    if value:
        bridge.remove_from_group("pass_through_platforms")
        for p in fighters:
            if bridge in p._ignored_platforms:
                p.remove_collision_exception_with(bridge); p._ignored_platforms.erase(bridge)
            if p._drop_platform==bridge: p._drop_platform=null
    else:
        bridge.add_to_group("pass_through_platforms")

func check_entry_contact(next_y: float):
    # Swept contact is clipped OUTSIDE the real lower blast boundary. The fighter
    # origin must independently satisfy the unchanged native KO rule too.
    var bottom=minf(net_y,next_y)-0.12
    var top=minf(maxf(net_y,next_y),KO_Y-0.001)
    if top<=bottom: return
    var sweep=AABB(Vector3(-2.35,bottom,-1.7),Vector3(4.7,top-bottom,3.4))
    for p in fighters:
        if p.stocks<=0 or not p.controls_enabled: continue
        if p.revival and p.revival.phase!="idle": continue
        if p.position.y>=KO_Y: continue
        if not sweep.intersects(capsule_bounds(p)): continue
        var row={"player":p.player_index,"root_y":p.position.y,"sweep_top":top,"stocks_before":p.stocks}
        p._handle_blast_zone() # native stock/revival route; never generic damage
        row.stocks_after=p.stocks
        entry_kos.append(row)

func seal_blockers() -> Array:
    var found: Array=[]
    for p in fighters:
        if p.stocks<=0: continue
        var b=capsule_bounds(p)
        # Standing feet contact is permitted; a crossing torso must clear first.
        if b.position.y>=-0.025: continue
        if b.intersects(AABB(Vector3(-2.35,-0.12,-1.7),Vector3(4.7,0.12,3.4))): found.append(p.player_index)
    return found

func closure_blockers(_next_gap: float) -> Array:
    var found: Array=[]
    for p in fighters:
        if p.stocks<=0: continue
        var b=capsule_bounds(p)
        var hang=p.ledge_grab and p.ledge_grab.active()
        if hang:
            found.append(p.player_index); continue
        # A fighter planted on the flush temporary floor must NOT stall repair.
        if b.position.y>=-0.025 and p.is_grounded(): continue
        b=b.merge(AABB(b.position+p.velocity/60.0,b.size)).grow(0.03)
        if b.intersects(AABB(Vector3(-gap-0.04,-1.10,-1.9),Vector3(gap*2+0.08,1.10,3.8))): found.append(p.player_index)
    return found

func _physics_process(delta):
    if not configured or get_tree().paused or freeze_stage: return
    elapsed+=delta
    match phase:
        "ready":
            if automatic and elapsed>4: start_cycle()
        "warning":
            visual_time=2+minf(elapsed/2,1)
            if elapsed>=2: set_phase("opening")
        "opening":
            var hang=false
            for p in fighters:
                if p.ledge_grab and p.ledge_grab.active(): hang=true
            if not hang: gap=move_toward(gap,2.35,delta*0.8)
            visual_time=3+gap/2.35*2
            if gap>=2.35: set_phase("open")
        "open":
            visual_time=5+minf(elapsed/1.5,1)*2.2
            if elapsed>=1.5: set_phase("grip")
        "grip":
            visual_time=7.2+minf(elapsed/2.3,1)*2.3
            if elapsed>=2.3: set_phase("weave")
        "weave":
            visual_time=9.5+minf(elapsed,1)*0.5
            if elapsed>=1: set_phase("entry")
        "entry":
            var next=move_toward(net_y,ENTRY_END_Y,delta*ENTRY_SPEED)
            check_entry_contact(next)
            net_y=next
            visual_time=10
            if net_y>=ENTRY_END_Y: set_phase("lift")
        "lift":
            var next=move_toward(net_y,0,delta*LIFT_SPEED)
            blockers=lift_blockers(next)
            if blockers.is_empty(): net_y=next
            else: blocked_ticks+=1
            visual_time=10+(net_y-ENTRY_END_Y)/(-ENTRY_END_Y)*2
            if net_y>=0: set_phase("seal")
        "seal":
            blockers=seal_blockers()
            if blockers.is_empty():
                set_solid(true)
                set_phase("closing")
            else: blocked_ticks+=1
        "closing":
            var next=move_toward(gap,0,delta*0.55)
            blockers=closure_blockers(next)
            if blockers.is_empty(): gap=next
            else: blocked_ticks+=1
            visual_time=12.5+(1-gap/2.35)*4
            if gap<=0: set_phase("handoff")
        "handoff":
            # Keep the flush bridge for several physics frames while stone takes over.
            visual_time=16.5+minf(elapsed,1)*2
            if elapsed>=0.25: set_phase("withdraw")
        "withdraw":
            visual_time=18.5+minf(elapsed,1)*3.4
            if elapsed>=1:
                cycle_count+=1
                set_solid(false)
                net_y=START_Y
                set_phase("ready")
    sync_surfaces()

func sync_surfaces():
    if not configured:
        return
    art.external_gap=gap; art.update_scene(visual_time)
    for i in 2:
        var s=-1.0 if i==0 else 1.0
        decks[i].position=Vector3(s*(4+gap),-0.52,0)
        side_decks[i].position=art.movers[i].position-Vector3(0,0.1,0)
        side_decks[i].set_meta("top_y",art.movers[i].position.y)
    bridge.position=Vector3(0,net_y-0.06,0)
    bridge.set_meta("top_y",net_y)
    var width=maxf(gap*2,0.035) if phase in ["closing","handoff","withdraw"] else 4.7
    bridge_shape.size=Vector3(width,0.12,3.4)
    bridge.set_meta("half_width",width/2)
    var enabled=phase in ["lift","seal","closing","handoff"]
    bridge.collision_layer=(1 if bridge_solid else 2) if enabled else 0
    bridge.visible=phase in ["entry","lift","seal","closing","handoff"] and gap>0.001
    # Interlaced strand reveal during the first slow rise, then a taut gold floor.
    var weave=clampf((net_y-ENTRY_END_Y+0.3)/0.9,0.0,1.0)
    for s in strands:
        var m: MeshInstance3D=s.mesh
        m.visible=weave>=s.u*0.75 if s.warp else weave>=0.20+s.u*0.75
        if s.warp:
            m.position.x=(s.u-0.5)*maxf(width-0.04,0)
            m.scale.x=1
            m.scale.z=clampf(weave*2-s.u*0.4,0,1)
        else:
            m.scale.x=width/4.7*clampf((weave-0.15)*2-s.u*0.3,0,1)
        # Small alternating over/under height gives a woven read without floor bumps.
        m.position.y=0.047+(0.002 if int(s.u*28)%2==0 else -0.002)
    for i in warning_threads.size():
        var m=warning_threads[i]; m.visible=phase=="warning"
        var u=clampf((elapsed-float(i)*0.04)/1.3,0,1)
        m.scale.x=1-u*0.9; m.position.x=sin(float(i)*2.7)*u*0.65
        m.position.y=0.07-u*0.7; m.rotation.z=sin(float(i))*u*0.8

func sample() -> Dictionary:
    var row=super.sample()
    row.single_floor=true
    row.solid=bridge_solid
    row.platform_x=bridge.position.x if is_instance_valid(bridge) else 0
    row.platform_width=bridge_shape.size.x if bridge_shape else 0
    row.platform_layer=bridge.collision_layer if is_instance_valid(bridge) else 0
    row.entry_kos=entry_kos.duplicate(true)
    return row
