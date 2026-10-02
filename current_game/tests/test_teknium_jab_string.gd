extends "res://tests/test_teknium_jab.gd"
# Neutral jab string: left jab -> right straight -> scoop kick, one hit per fresh press.
func tap(n:=2):
	key(KEY_F,true);await frames(n);key(KEY_F,false)
func setup_pair(f,p,face,gap):
	for k in [KEY_F,KEY_E,KEY_SPACE,KEY_A,KEY_D,KEY_W,KEY_S]:key(k,false)
	f.controls_enabled=true;f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(face*gap,0,0),true);f.facing=face;p.facing=-face;await frames(20)
func run():
	var a=load("res://scenes/main.tscn").instantiate();root.add_child(a);await process_frame
	var ids=load("res://scripts/match_config.gd").CHARACTERS
	a.setup.rows[0].character.select(ids.find("teknium"));a.setup.rows[0].kind.select(0)
	a.setup.rows[1].character.select(ids.find("doge_man"));a.setup.rows[1].kind.select(0)
	a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();await frames(150)
	var f=a.fighters[0];var p=a.fighters[1];var c=f.reaction_recovery
	for face in [1,-1]:
		# Lone tap = the original jab exactly.
		await setup_pair(f,p,face,.96)
		await tap();await frames(40)
		check(p.damage_percent==8 and c.lab_move=="" and c.jab_step==0,"lone tap is the original 8% jab "+str(face))
		# Three fresh presses: full string, one hit each, kick launches.
		await setup_pair(f,p,face,.96)
		var steps=[];var max_y=0.0;var min_gap=99.0
		await tap();await frames(4);await tap()
		for i in 14:
			await frames(1);steps.append(c.jab_step)
		await tap()
		for i in 70:
			await frames(1);steps.append(c.jab_step);max_y=maxf(max_y,p.velocity.y)
		var strikes=[];for ct in c.lab_contacts:strikes.append(ct.strike)
		print("STRING face=",face," dmg=",p.damage_percent," strikes=",strikes," max_vy=",snappedf(max_y,.01)," contacts=",c.lab_contacts.map(func(x):return [x.strike,x.point,snappedf(x.time,.001)]))
		check(1 in steps and 2 in steps,"fresh presses advance jab->straight->kick "+str(face))
		check(p.damage_percent==19,"string damage 8+4+7=19 got "+str(p.damage_percent)+" "+str(face))
		check(max_y>0.5,"scoop kick launches "+str(face))
		check(c.lab_move=="" and f.attack_cooldown<=0,"string ends cleanly "+str(face))
	# Holding one press never buys the straight.
	await setup_pair(f,p,1,.96)
	key(KEY_F,true);await frames(45)
	check(c.jab_step==0 and p.damage_percent==8,"held press = jab only")
	key(KEY_F,false);await frames(20)
	# A late press (after the jab's decision point) does not continue the string mid-retraction.
	await setup_pair(f,p,1,.96)
	await tap();await frames(13);await tap();await frames(30)
	check(c.jab_step==0 and p.damage_percent==8,"late press does not buy straight")
	# Lone straight (two presses) ends with no kick.
	await setup_pair(f,p,1,.96)
	await tap();await frames(4);await tap();await frames(60)
	check(p.damage_percent==12 and c.lab_move=="","two presses = jab+straight only (12%)")
	# Jump cancels mid-string and clears the buffer.
	await setup_pair(f,p,1,.96)
	await tap();await frames(4);await tap();await frames(16)
	key(KEY_SPACE,true);await frames(3)
	check(c.lab_move=="" and c.lab_targets.is_empty(),"jump cancels the string")
	key(KEY_SPACE,false);await frames(60)
	check(c.lab_move=="","no ghost continuation after jump cancel")
	# Out of range: no damage.
	await setup_pair(f,p,1,2.6)
	await tap();await frames(4);await tap();await frames(12);await tap();await frames(70)
	check(p.damage_percent==0,"out of range string deals no damage")
	# Air neutral unchanged.
	f.reset_fighter(Vector3(0,4,0),true);p.reset_fighter(Vector3(8,0,0),true);await frames(2)
	key(KEY_F,true);await frames(2);key(KEY_F,false)
	check(c.lab_move=="","air neutral never enters the ground string")
	a.queue_free();await frames(2);quit(1 if fails else 0)
