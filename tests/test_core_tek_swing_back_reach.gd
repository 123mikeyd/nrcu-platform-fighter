extends "res://tests/test_core_tek_swing_mode_exit.gd"
const Melee = preload("res://scripts/core/combat/source_melee.gd")
const Queries = preload("res://scripts/core/collision/recipient_queries.gd")
const OUT := "res://.verification/core/teknium-swing-reach-authoring/"

func distances(hand: Vector3, capsules: Array) -> Array:
    var rows := []
    for c in capsules:
        var nearest := Geometry3D.get_closest_point_to_segment(hand,c.a,c.b)
        rows.append({"id":c.id,"a":c.a,"b":c.b,"radius":c.radius,"nearest":nearest,"center_distance":hand.distance_to(nearest),"gap":hand.distance_to(nearest)-c.radius-.16})
    rows.sort_custom(func(a,b): return a.gap < b.gap)
    return rows

func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false); lab.set_paused(true)
    check(lab.set_generated_collision_enabled(true),"generated install")
    lab.set_hitstop_enabled("hitstop" in OS.get_cmdline_user_args())
    var records := []
    for scenario in [[0,false,"teknium",false],[1,false,"teknium",false],[0,true,"teknium",false],[1,true,"teknium",false],[0,false,"turbofit",false],[1,false,"turbofit",false],[0,true,"turbofit",false],[1,true,"turbofit",false],[0,false,"teknium",true],[1,false,"teknium",true],[0,false,"turbofit",true],[1,false,"turbofit",true]]:
        var slot: int = scenario[0]
        var inward: bool = scenario[1]
        var other: String = scenario[2]
        var far: bool = scenario[3]
        check(lab.select_fighter(slot,"teknium"),"attacker selection")
        check(lab.select_fighter(1-slot,other),"target selection")
        lab.reset_lab()
        # Selection reinstalls auto mode; this trace explicitly measures legacy blocking.
        check(lab.simulation.reset_with_collision_profiles(lab.spawns, {1:lab.simulation.fighters[1].collision_host.builder._profile,2:lab.simulation.fighters[2].collision_host.builder._profile}, "legacy_solid"),"explicit legacy native-blocking fixture")
        lab._reset_round_input_and_visuals()
        for i in 20: lab.step_once(); await tick(lab)
        # P2 defaults right: turn P2 for inward, P1 left for mirrored rear.
        if inward or slot == 1:
            key(KEY_LEFT,true); lab.step_once(); await tick(lab); key(KEY_LEFT,false)
            lab.step_once(); await tick(lab)
        if slot == 1 and not inward:
            key(KEY_A,true); lab.step_once(); await tick(lab); key(KEY_A,false)
            lab.step_once(); await tick(lab)
        var direction: int = KEY_D if slot == 0 else KEY_LEFT
        key(direction,true)
        var approach := []
        for i in 35:
            lab.step_once(); await tick(lab)
            approach.append([lab.actors[0].position,lab.actors[1].position])
        key(direction,false)
        for i in 10: lab.step_once(); await tick(lab)
        check(approach[-1][slot].distance_to(approach[-5][slot]) < .001,"native blocking plateau before retreat")
        if far:
            var retreat: int = KEY_A if slot == 0 else KEY_RIGHT
            key(retreat,true)
            for i in 15: lab.step_once(); await tick(lab)
            key(retreat,false); key(direction,true)
            lab.step_once(); await tick(lab); key(direction,false)
            for i in 10: lab.step_once(); await tick(lab)
        check(lab.actors[0].runtime.grounded and lab.actors[1].runtime.grounded,"standing native floor prerequisite")
        var m = lab.simulation
        var source: Dictionary = m.fighters[slot+1]
        var target: Dictionary = m.fighters[2-slot]
        var host = source.collision_host
        var baseline: Dictionary = target.collision_host.telemetry().contact_snapshot
        var origin: Transform3D = source.actor.global_transform
        var face: float = source.facing
        var label := "p%d-%s-inward%s-far%s" % [slot+1,other,str(inward),str(far)]
        check((target.actor.position.x-source.actor.position.x)*face > 0,"attacker faces target "+label)
        check((source.facing != target.facing) == inward,"victim orientation prerequisite "+label)
        check(approach[-1][slot].distance_to(approach[-5][slot]) < .001,"native blocking plateau "+label)
        var rec := {"hitstop_enabled":"hitstop" in OS.get_cmdline_user_args(),"label":label,"attacker_facing":face,"target_facing":target.facing,"approach":approach,"attacker_position":source.actor.position,"target_position":target.actor.position,"separation":absf(source.actor.position.x-target.actor.position.x),"samples":[],"old_punch":[]}
        var attack: int = KEY_F if slot == 0 else KEY_K
        key(attack,true); lab.step_once(); await tick(lab); key(attack,false)
        check(host.telemetry().pose_request.clip == "SwingPunchV1","actual swing accepted "+label)
        var placement: Transform3D = host.telemetry().pose_request.modelplacement
        var native_view = lab.imported_visuals[slot]
        for age in range(36):
            if age > 0: lab.step_once(); await tick(lab)
            var record: Dictionary = host.telemetry().contact_snapshot
            var r: Dictionary = record.pose_request
            var pose: Dictionary = host.sampler.sample(r.clip,r.source_seconds,r.time_policy)
            var hand: Vector3 = source.actor.global_transform*r.modelplacement*pose.LeftHand.origin
            var shapes: Array = Melee.shapes(host,source.actor.global_transform)
            var caps: Array = Queries.primitives(target)
            var ds := distances(hand,caps)
            var hit: Dictionary = Melee.contact(target,shapes)
            check(hit.is_empty() == (shapes.is_empty() or ds[0].gap > .000001),"independent true intersection agrees "+label+" age "+str(age))
            if r.clip == "SwingPunchV1":
                var visible_hand: Vector3 = native_view.skeleton.global_transform*native_view.skeleton.get_bone_global_pose(native_view.skeleton.find_bone("LeftHand")).origin
                check(visible_hand.is_equal_approx(hand),"actual visible hand matches query "+label)
            rec.samples.append({"age":age,"clip":r.clip,"seconds":r.source_seconds,"hand":hand,"torso":source.actor.global_transform*r.modelplacement*pose.Spine.origin,"distances":ds,"query":hit,"shapes":shapes,"events":m.events.duplicate(true),"source_status":source.actor.runtime.states.status,"target_status":target.actor.runtime.states.status,"source_hitstop":m.hitstop_telemetry(slot+1),"target_hitstop":m.hitstop_telemetry(2-slot),"damage":target.percent,"idle_baseline_distances":distances(hand,baseline.primitives)})
            if DisplayServer.get_name() != "headless" and age in [0,4,7,9,10,12,15,30]:
                await process_frame; await RenderingServer.frame_post_draw
                root.get_texture().get_image().save_png(OUT+label+"-age"+str(age)+".png")
        # Counterfactual unchanged imported Punch at identical legal transforms
        # and preattack Idle recipient; not a fabricated match hit.
        for frame in range(0,85):
            var seconds := frame/60.0
            var pose: Dictionary = host.sampler.sample("Punch",seconds,0)
            var hand: Vector3 = origin*placement*pose.LeftHand.origin
            rec.old_punch.append({"source_frame":frame,"seconds":seconds,"active":seconds >= .6 and seconds <= .8,"hand":hand,"distances":distances(hand,baseline.primitives)})
        check(rec.samples[30].clip == "Idle", "idle after episode "+label)
        check(rec.samples[35].damage == rec.samples[20].damage,"no late damage "+label)
        check(target.percent == (0 if far else 8), "visible swing reaches standing victim exactly once; distant misses "+label)
        check(rec.samples[0].damage == 0,"startup harmless "+label)
        if not far:
            var first := -1
            var stopped := 0
            for i in rec.samples.size():
                if first < 0 and rec.samples[i].damage > 0: first = i
                if rec.samples[i].source_hitstop.stopped_this_tick:
                    stopped += 1
                    check(rec.samples[i].seconds == rec.samples[i-1].seconds and rec.samples[i].hand.is_equal_approx(rec.samples[i-1].hand),"committed pose freezes with hitstop "+label)
                    check(rec.samples[i].target_hitstop.stopped_this_tick,"victim joint stop "+label)
            check(first >= 9 and first <= 12,"hit inside unchanged window "+label)
            check(rec.samples[first].target_status == "hitstun","real victim hit reaction "+label)
            check(stopped == (4 if rec.hitstop_enabled else 0),"bounded authoritative hitstop "+label)
        records.append(rec)
        FileAccess.open(OUT+("headless" if DisplayServer.get_name() == "headless" else "native")+"-reach.json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
        print("TRACE ",label," separation ",rec.separation," damage ",target.percent)
    lab.free()
    if not failures: print("PASS: actual native blocking reach trace and independent capsule oracle")
    quit(1 if failures else 0)
