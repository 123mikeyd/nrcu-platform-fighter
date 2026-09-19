extends "res://tests/test_core_recovery_acceptance.gd"
const Kit = preload("res://scripts/core/kits/turbofit_kit.gd")
const Pose = preload("res://scripts/core/kits/turbofit_contact_pose.gd")
func run():
	for clip in ["AirSideKick","AirDownKick"]:
		for facing in [-1.0,1.0]:
			var aim := Vector2(facing,1 if clip == "AirDownKick" else 0)
			var age := .4 if clip == "AirDownKick" else 5.0/30
			var k = Kit.new(); k.start("hit",aim,true,facing); k.tick(age)
			var center: Vector3 = Pose.new().center(clip,age,facing)
			var position := Vector3(facing,-1,0)
			var target := {"id":2,"position":position,"geometry_mode":"generated_hurtboxes","hurtbox_snapshot":{"ok":true,"primitives":[{"id":"limb","a":center,"b":center,"radius":.1}]},"capsules":[]}
			var contacts: Array = k.contacts(1,Vector3.ZERO,[target])
			check(contacts.size() == 1,"body miss limb hit "+clip+str(facing))
			if not contacts.is_empty():
				check(contacts[0].damage == 14 and contacts[0].base_knockback == 5.5,"unchanged damage/launch")
				check(contacts[0].get("geometry_mode","") == "generated_hurtboxes","explicit generated evidence")
			check(k.contacts(1,Vector3.ZERO,[target]).is_empty(),"once victim across limbs/ticks")
			k = Kit.new(); k.start("miss",aim,true,facing); k.tick(age)
			target.hurtbox_snapshot.primitives[0].a += Vector3(10,0,0); target.hurtbox_snapshot.primitives[0].b += Vector3(10,0,0)
			target.capsules = [{"transform":Transform3D(Basis.IDENTITY,center),"radius":.4,"height":1.8}]
			check(k.contacts(1,Vector3.ZERO,[target]).is_empty(),"body hit limb miss never falls back")
			target.hurtbox_snapshot.ok = false
			check(k.contacts(1,Vector3.ZERO,[target]).is_empty(),"invalid generated snapshot never falls back")
	if not failures: print("PASS: hurtbox match contact seam (%d checks)" % checks)
	quit(1 if failures else 0)
