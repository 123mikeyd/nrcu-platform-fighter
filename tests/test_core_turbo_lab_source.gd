extends "res://tests/test_core_turbo_present_source.gd"
# Characterization of the completed kit/presenter through physical lab input.
func key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)
func tick(lab) -> void:
    await physics_frame
    lab._physics_process(1.0/60)
func run() -> void:
    var source = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
    root.add_child(source)
    var ap: AnimationPlayer = source.find_children("*","AnimationPlayer",true,false)[0]
    var sk: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
    ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    var before := fingerprint(ap)
    for name in ap.get_animation_library_list():
        var lib := AnimationLibrary.new()
        for clip in ap.get_animation_library(name).get_animation_list():
            var a: Animation = ap.get_animation(clip).duplicate(true)
            a.loop_mode = Animation.LOOP_NONE
            lib.add_animation(clip,a)
        ap.remove_animation_library(name)
        ap.add_animation_library(name,lib)
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0,"turbofit")
    lab.select_fighter(1,"turbofit")
    for slot in range(2):
        var attack := KEY_F if slot == 0 else KEY_K
        var special := KEY_G if slot == 0 else KEY_L
        var up := KEY_W if slot == 0 else KEY_UP
        var down := KEY_S if slot == 0 else KEY_DOWN
        var side := KEY_D if slot == 0 else KEY_LEFT
        var jump := KEY_SPACE if slot == 0 else KEY_ENTER
        for route in [[false,side,attack,"MeleeHorizontal",.8],[false,up,attack,"MeleeBackhand",.8],[false,down,attack,"GoalkeeperKick",59.0/60],[true,side,attack,"AirSideKick",.5],[true,up,attack,"MeleeBackhand",.8],[true,down,attack,"AirDownKick",38.0/30],[false,0,special,"TwoHandCombo",0],[false,side,special,"TwoHandCombo",.7],[false,down,special,"BlockIdle",0],[false,up,special,"Jump",0]]:
            lab.reset_lab()
            lab.actors[1-slot].position.x = 10 if slot == 0 else -10
            for i in range(40): await tick(lab)
            key(side,true)
            await tick(lab)
            key(side,false)
            if route[0]:
                key(jump,true)
                for i in range(9): await tick(lab)
                key(jump,false)
                check(not lab.actors[slot].is_on_floor(),"actual physical jump prerequisite")
            if route[1]: key(route[1],true)
            key(route[2],true)
            for i in range(12): await tick(lab)
            var request: Dictionary = lab.simulation.kit_telemetry(slot+1).presentation
            var v = lab.imported_visuals[slot]
            check(v.output.clip == route[3],"physical ground/air/special route " + str(route))
            var elapsed: float = request.get("elapsed",request.get("age",0))
            var seconds := elapsed
            if route[2] == attack: seconds = elapsed/route[4]*ap.get_animation(route[3]).length
            elif route[1] == side: seconds = elapsed/.7*ap.get_animation(route[3]).length
            elif route[1] == 0: seconds = (lerpf(1,16,sin(minf(elapsed/.25,1)*PI/2))-1)/30
            if route[3] == "BlockIdle": seconds = fmod(seconds,ap.get_animation(route[3]).length)
            seconds = minf(seconds,ap.get_animation(route[3]).length)
            check(is_equal_approx(v.output.seconds,seconds),"real committed clock source mapping")
            ap.play(route[3],0)
            ap.seek(seconds,true)
            sk.force_update_all_bone_transforms()
            source.position = lab.actors[slot].global_position
            source.rotation.y = request.facing*PI/2
            source.scale = Vector3.ONE*1.25
            for b in sk.get_bone_count(): check((v.skeleton.global_transform*v.skeleton.get_bone_global_pose(b)).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"actual lab world skeleton source parity")
            if route[1]: key(route[1],false)
            key(route[2],false)
            await tick(lab)
            if route[1] == 0:
                check(lab.simulation.kit_telemetry(slot+1).special.phase == "release", "physical release changes phase")
                check(is_equal_approx(v.output.seconds,19.0/30),"physical release starts original source release frame")
    var untouched = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
    check(fingerprint(untouched.find_children("*","AnimationPlayer",true,false)[0]) == before,"imported source fingerprint immutable through real lab")
    untouched.free()
    lab.free()
    source.free()
    if not failures: print("PASS: actual physical six Turbo basics four specials both-facing source skeleton immutable")
    quit(1 if failures else 0)
