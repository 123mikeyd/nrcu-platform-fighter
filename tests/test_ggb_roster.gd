extends SceneTree
func _initialize():
    var roster=load("res://scripts/roster.gd").new()
    if roster.ids()!=["teknium","doge_man","ggb","turbofit","ice_mage", "witcheer", "mephisto"] or roster.display_name("ggb")!="GGB":
        printerr("FAIL: GGB must replace third identity, without an old alias")
        quit(1)
        return
    if not ResourceLoader.exists("res://assets/ggb/ggb.glb"):
        printerr("FAIL: approved GGB asset missing")
        quit(1)
        return
    print("PASS: GGB roster and approved asset")
    quit()
