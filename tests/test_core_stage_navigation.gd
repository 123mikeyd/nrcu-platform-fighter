extends SceneTree
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1; printerr("FAIL: ",label)
func _initialize(): call_deferred("run")
func surfaces() -> Array:
	return [{"id":"main","rect":Rect2(-9,-1.05,18,1),"one_way":false},
		{"id":"left","rect":Rect2(-7.7,2.775,5,0.45),"one_way":true},
		{"id":"right","rect":Rect2(2.7,2.775,5,0.45),"one_way":true},
		{"id":"top","rect":Rect2(-2.25,5.8,4.5,0.4),"one_way":true}]
func caps() -> Dictionary:
	return {"full_jump_speed":13.0,"air_jump_speed":11.5,"air_jumps":1,"gravity":32.0,"air_speed":7.0}
func run():
	var path := "res://scripts/core/input/stage_navigation.gd"
	check(FileAccess.file_exists(path),"explicit shared support navigation exists")
	if failures: quit(1); return
	var nav = load(path).new()
	var supplied := surfaces()
	check(nav.configure(supplied,caps()),"authored horizontal support geometry accepted")
	supplied[0].rect = Rect2()
	check(nav.route("main","top") == ["main","left","top"],"deterministic reachable multi-hop, copied geometry")
	check(nav.route("left","right") == ["left","top","right"],"different upper requires intermediate support")
	check(nav.route("top","main") == ["top","main"],"one-way drop to main")
	if not failures: print("PASS: copied support graph bounded two-jump route")
	quit(1 if failures else 0)
