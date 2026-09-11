extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
    if not ok:failures+=1;printerr("FAIL: "+message)
func run():
    var theme_script=load("res://scripts/stage_theme.gd")
    var ids=load("res://scripts/roster.gd").ids()
    for id in ids:
        if not theme_script.MODELS.has(id):
            printerr("FAIL: missing shelf model: "+id);quit(1);return
    var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
    arena.setup.level.select(1);arena.setup._start();await process_frame
    var figures=arena.stage_theme.find_children("Figure_*","Node3D",false,false)
    check(figures.size()==ids.size(),"every roster figure")
    var positions=[]
    for figure in figures:positions.append(figure.position.x)
    positions.sort()
    check(is_equal_approx(positions[0],-positions[-1]),"centered expanded shelf")
    for i in range(1,positions.size()):check(positions[i]-positions[i-1]>=3.5,"separated figures")
    var figure=arena.stage_theme.get_node("Figure_witcheer")
    var model=figure.get_child(0)
    var player=model.find_children("*","AnimationPlayer",true,false)[0]
    check(player.assigned_animation=="Run" and not player.is_playing(),"frozen approved Run not bind pose")
    check(model.scale.is_equal_approx(Vector3.ONE*1.2) and is_equal_approx(model.position.y,0.13),"verified fighter scale and floor offset")
    check(figure.find_children("*","CollisionObject3D",true,false).is_empty(),"display only")
    arena.queue_free();await process_frame
    if failures==0:print("PASS: complete centered roster toy shelf, Witcheer frozen Run and safe scale")
    quit(0 if failures==0 else 1)
