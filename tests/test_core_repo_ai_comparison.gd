extends "res://tests/test_core_top_support_lifecycle.gd"
const Owner = preload("res://scripts/core/input/repo_ai_match_input.gd")
func run():
	for mode in ["legacy_solid","grounded_jostle"]:
		for kit in ["teknium","turbofit"]:
			var f = setup_pair(kit,"teknium",false,mode)
			var geom = load("res://scripts/core/stage/combat_lab_stage.gd").new().geometry()[0]
			f.floor.position = geom.position; f.floor.get_child(0).shape.size = geom.size
			f.m.configure_defense(load("res://scripts/core/combat/defense_profile.gd").new())
			f.m.configure_hitstop(load("res://scripts/core/combat/hitstop_profile.gd").new())
			f.m.configure_rules(load("res://scripts/core/match/match_rules.gd").new())
			f.m.rematch()
			var owner = Owner.new(); owner.configure(2,true,"hard")
			var moved = false; var attacked = false; var special = false; var damage = false
			var max_damage := 0.0
			for i in 600:
				await physics_frame
				owner.advance(f.m)
				moved = moved or f.b.position.x < 3
				var move: String = f.m.fighters[2].move_id
				attacked = attacked or move != ""
				special = special or f.m.fighters[2].force != null or f.m.fighters[2].grab != null or (f.m.fighters[2].kit != null and f.m.fighters[2].kit.snapshot().special.phase != "idle")
				max_damage = maxf(max_damage,f.m.fighters[1].percent)
				damage = damage or max_damage > 0
			check(moved and attacked and damage,"finite actual kit contact "+mode+" "+kit)
			check(special,"actual accepted special "+mode+" "+kit)
			print("AI_MATCH ",mode," ",kit," moved=",moved," attacked=",attacked," special=",special," max_damage=",max_damage," stocks=",f.m.fighters[1].stocks)
			# Hitstop retains intent and does not advance decision time.
			f.m.fighters[2].hitstop_left = 3
			var timer = owner.ai.timer; var seq = owner.ai.sequence
			for i in 3: await physics_frame; owner.advance(f.m)
			check(owner.ai.timer == timer and owner.ai.sequence == seq,"AI frozen exactly with actor hitstop")
			# Terminal stock boundary + generation reset: no held cast carried.
			for i in 3:
				f.b.position = Vector3(0,-9,0)
				await physics_frame; owner.advance(f.m)
			check(not f.m.result.is_empty(),"real finite result")
			await physics_frame
			check(not owner.advance(f.m),"result stops input source")
			f.m.rematch()
			var reset_frame = owner.sample_all(f.m)[2]
			check(owner.ai.sequence == 1 and not reset_frame.held.special,"rematch resets sequence and held cast")
			dispose(f)
	if not failures: print("PASS: repo AI A/B finite kits hitstop stocks rematch")
	quit(1 if failures else 0)
