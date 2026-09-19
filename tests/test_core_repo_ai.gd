extends SceneTree
var failures := 0
func check(ok, message):
	if not ok: failures += 1; print("FAIL: ",message)
func _initialize(): call_deferred("run")
func run():
	var path = "res://scripts/core/input/repo_ai_input_source.gd"
	check(ResourceLoader.exists(path),"repo AI adapter exists, separate from pursuit dummy")
	if failures: quit(1); return
	var ai = load(path).new()
	var actor = {"id":2,"position":Vector3.ZERO,"velocity":Vector3.ZERO,"character_id":"turbofit","enabled":true,"team":-1,"attack_cooldown":0.0,"can_jump":true,"recovery_spent":false,"magic_locked":false,"magic_cooldown":0.0}
	var target = actor.duplicate(); target.id = 1; target.position = Vector3(4,0,0)
	var first = ai.sample(0,actor,[target])
	check(first.axis.x == 1 and first.source_id == "repo_ai","original pursuit becomes frame")
	check(ai.sequence == 1,"first original decision")
	ai.sample(0,actor,[target])
	check(ai.sequence == 1,"duplicate tick does not advance decision")
	ai.reset()
	check(ai.sample(0,actor,[target]).to_dict() == first.to_dict(),"reset exact first frame")
	if not failures: print("PASS: repo AI frame tracer")
	quit(1 if failures else 0)
