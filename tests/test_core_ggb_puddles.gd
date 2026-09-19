extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1; printerr("FAIL: "+message)
func run():
	var path := "res://scripts/core/kits/ggb_puddles.gd"
	check(ResourceLoader.exists(path),"finite GGB surface host exists")
	if failures: quit(1);return
	var pool = load(path).new()
	var floor_body := StaticBody3D.new();var box := BoxShape3D.new();box.size=Vector3(20,1,4)
	var shape := CollisionShape3D.new();shape.shape=box;floor_body.add_child(shape);root.add_child(floor_body);floor_body.position.y=-.5
	var body := CharacterBody3D.new();var capsule := CapsuleShape3D.new();capsule.radius=.4;capsule.height=2
	shape=CollisionShape3D.new();shape.shape=capsule;shape.position.y=1;body.add_child(shape);root.add_child(body);body.position.y=.03
	for i in 10:
		await physics_frame;await process_frame
		body.velocity=Vector3(0,-4,0);body.move_and_slide()
	check(body.is_on_floor(),"fixture reaches native top")
	var request := {"kind":"spawn_puddle","source":1,"team":1,"activation_id":"p1","surface":floor_body,"position":Vector3(0,.025,0),"normal":Vector3.UP}
	check(pool.spawn(request),"top puddle accepted")
	check(not pool.spawn(request),"duplicate spawn identity rejected")
	var target := {"id":2,"team":2,"body":body,"position":body.position,"grounded":true,"velocity":body.velocity,"support_surface":floor_body}
	var effects = pool.collect([target,target])
	check(effects.size()==1 and effects[0].kind=="ground_speed_modifier" and effects[0].multiplier==.65 and effects[0].source==1,"one source-owned transient grounded slow")
	for key in ["shielding","frozen"]:
		target[key]=true
		check(pool.collect([target]).size()==1,"environment slow independent of "+key)
	target.velocity=Vector3.UP
	check(pool.collect([target]).is_empty(),"rising stale floor no slow")
	target.velocity=Vector3.ZERO;target.grounded=false
	check(pool.collect([target]).is_empty(),"air over pool excluded")
	target.grounded=true;target.support_surface=body
	check(pool.collect([target]).is_empty(),"other actual surface excluded")
	target.support_surface=floor_body;target.team=1
	check(pool.collect([target]).is_empty(),"friendly excluded")
	target.team=2;target.id=1
	check(pool.collect([target]).is_empty(),"owner excluded")
	target.id=2;target.position=Vector3(0,.19,0)
	check(pool.collect([target]).is_empty(),"height band source .16")
	target.position=Vector3(.851,0,0)
	check(pool.collect([target]).is_empty(),"outside .85 radius")
	target.position=body.position
	for i in 4:
		request.activation_id="more%d"%i;check(pool.spawn(request),"new puddle")
	check(pool.snapshots().size()==3 and pool.snapshots()[0].activation_id=="more1","per-owner three oldest eviction")
	check(pool.collect([target]).size()==3,"overlap emits source modifiers for shared min, never multiplies")
	var before = pool.snapshots()
	pool.tick(1,{"paused":true})
	check(pool.snapshots()==before,"world stopped clocks")
	pool.tick(2.99)
	check(pool.collect([target]).size()==3,"before ttl")
	pool.tick(.01)
	check(pool.collect([target]).is_empty(),"expiry no stale slow")
	request.activation_id="current";request.source=3;request.team=3;pool.spawn(request)
	pool.expire_source(1);check(pool.snapshots().size()==1,"new reflected owner pool survives old owner reset")
	check(pool.collect([target],{3:{"enabled":false}}).is_empty(),"disable immediately suppresses without physics tick")
	pool.expire_source(3);check(pool.snapshots().is_empty(),"current source reset cleans")
	request.activation_id="surface";pool.spawn(request);floor_body.free()
	check(pool.collect([target]).is_empty(),"surface freed no ghost slow")
	pool.tick(0);check(pool.snapshots().is_empty(),"invalid surface pruned even no advancement")
	pool.reset();body.free()
	if failures==0: print("PASS: GGB finite surface puddles, top-only grounded slow, source ownership/lifetime/cap")
	quit(1 if failures else 0)
