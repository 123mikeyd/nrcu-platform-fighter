extends SceneTree
var failures:=0
func check(ok:bool,text:String):
    if not ok:failures+=1;printerr("FAIL: "+text)
func _initialize():call_deferred("run")
func run():
    if not ResourceLoader.exists("res://tools/play_mephisto.gd"):
        printerr("FAIL: persistent Mephisto setup launcher");quit(1);return
    var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
    load("res://tools/play_mephisto.gd").configure(arena)
    var button=arena.setup.find_child("StartMatchButton",true,false)
    for i in 3:await process_frame
    check(root.get_visible_rect().encloses(button.get_global_rect()),"Start inside viewport")
    for level in 3:
        arena.setup.level.select(level)
        arena.setup._start();await process_frame
        check(arena.fighters.size()==2 and arena.fighters[0].character_id=="mephisto","actual Start selects girl, no extra match slots")
        check(arena.fighters[0].get_node_or_null("VisualRoot/MephistoVisual")!=null,"real presentation")
        if level==1:
            check(arena.stage_theme.get_node_or_null("Figure_mephisto")!=null,"toy shelf includes girl")
        for i in 5:await physics_frame
        arena.show_setup();await process_frame
        check(arena.setup.visible and not arena.fighters[0].controls_enabled,"safe setup stops match")
    arena.queue_free();await process_frame
    if failures==0:print("PASS: Mephisto preselection, visible Start callback, every level and safe setup")
    quit(1 if failures else 0)
