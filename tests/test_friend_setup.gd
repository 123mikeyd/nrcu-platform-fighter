extends SceneTree
func _initialize(): call_deferred("run")
func run():
    var setup = load("res://scripts/match_setup.gd").new()
    root.add_child(setup)
    for i in 5: await process_frame
    var thumbnails = setup.find_children("StageThumbnail*", "TextureRect", true, false)
    if thumbnails.size() != 3:
        print("FAIL: setup needs three actual stage thumbnails"); quit(1); return
    for picture in thumbnails:
        if not picture.get_parent().get_global_rect().encloses(picture.get_global_rect()):
            print("FAIL: stage thumbnail spills outside card"); quit(1); return
    for name in ["BackToMenu", "SetupHelp", "StartMatchButton"]:
        var button = setup.find_child(name,true,false)
        if button == null or not Rect2(0,0,1280,720).encloses(button.get_global_rect()):
            print("FAIL: missing or clipped action "+name); quit(1); return
    if setup.selected_level() != "debug":
        print("FAIL: debug launch default"); quit(1); return
    print("PASS setup thumbnails and bounded navigation")
    setup.queue_free(); await process_frame; quit(0)
