extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func metadata(player):
	var data := {}
	for key in player.get_animation_list():
		var a: Animation = player.get_animation(key)
		var tracks := []
		for t in a.get_track_count():
			var keys := []
			for k in a.track_get_key_count(t): keys.append([a.track_get_key_time(t,k),a.track_get_key_value(t,k),a.track_get_key_transition(t,k)])
			tracks.append([a.track_get_type(t),a.track_get_path(t),a.track_is_enabled(t),a.track_get_interpolation_type(t),keys])
		data[key] = [a.length,a.loop_mode,tracks]
	return data
func run():
	var host = load("res://scripts/core/kits/ice_mage_host.gd").new()
	check(host.has_method("cancel_for_status"), "source freeze cancellation needs distinct action refund, not cast refund")
	if failures: quit(1); return
	var model = load("res://assets/ice_mage/ice_mage_combat.glb").instantiate()
	root.add_child(model)
	var player = model.find_children("*","AnimationPlayer",true,false)[0]
	var before = metadata(player)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ice_mage/combat_manifest.json"))
	# Manifest combat hash differs from the installed asset; pin actual input.
	check(FileAccess.get_sha256("res://assets/ice_mage/ice_mage_combat.glb")=="b9bb3756bc2c359e496a9c43b64124a070a83efa838fdef1a46ec6aa02098712","installed combat source binary hash")
	check(FileAccess.get_sha256("res://assets/ice_mage/ice_mage_animations.glb")==manifest.original_glb_sha256,"original source binary hash")
	check(manifest.clips.IceStrike.duration==.55 and manifest.clips.IceCast.impact_time==.2,"immutable timing fixture")
	var legacy = load("res://scripts/fighter.gd").new()
	legacy.character_id = "ice_mage"
	root.add_child(legacy)
	legacy.set_physics_process(false)
	var victim = load("res://scripts/fighter.gd").new()
	victim.character_id = "ggb"
	root.add_child(victim)
	victim.set_physics_process(false)
	for aim in [Vector2.ZERO,Vector2.UP]:
		host.cancel(true)
		legacy.reset_fighter(Vector3.ZERO)
		legacy.start_special(aim)
		host.start_special("source",aim,1,true)
		host.initial_requests(1,Vector3.ZERO)
		legacy._tick_character_move(1.0/60.0)
		host.advance(false)
		for i in 40:
			check(is_equal_approx(host.snapshot().special.age,legacy.ice_attack_elapsed) or legacy.ice_attack_clip.is_empty(), "source accepted episode age")
			check(is_equal_approx(host.snapshot().cast_cooldown,legacy.ice_cast_cooldown), "source cast budget decrement ordering")
			legacy.attack_cooldown = maxf(0,legacy.attack_cooldown-1.0/60.0)
			legacy._tick_freeze(1.0/60.0)
			legacy._tick_character_move(1.0/60.0)
			host.prepare(false)
			host.advance(false)
			host.collect(1,Vector3.ZERO,[])
		for p in get_nodes_in_group("projectiles"): p.free()
	for airborne in [false,true]:
		for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			host.cancel(true)
			legacy.reset_fighter(Vector3.ZERO)
			legacy.facing = -1
			victim.reset_fighter(Vector3(20,0,0))
			legacy.basic_attack(aim,airborne)
			host.start_basic("basic-source",aim,airborne,-1)
			legacy._tick_character_move(1.0/60.0)
			host.advance(false)
			for i in 36:
				check(host.locked()==(legacy.attack_cooldown>0), "source basic accepted action lock endpoint")
				legacy.attack_cooldown = maxf(0,legacy.attack_cooldown-1.0/60.0)
				legacy._tick_character_move(1.0/60.0)
				host.prepare(false)
				host.advance(false)
				host.collect(1,Vector3.ZERO,[])
	# Explicit source oracle, NOT a replacement shared status owner.
	victim.reset_fighter(Vector3.RIGHT)
	check(victim.apply_freeze(legacy), "source freeze starts")
	victim.receive_hit(0,Vector3.RIGHT,7)
	check(victim.freeze_remaining==1, "zero-damage push does not shatter")
	victim.receive_hit(4,Vector3.RIGHT,1)
	check(victim.freeze_remaining==0 and victim.freeze_immunity==1 and not victim.apply_freeze(legacy), "second bolt shatters then immunity rejects same-hit refreeze")
	victim._tick_freeze(.999)
	check(not victim.apply_freeze(legacy), "before immunity endpoint rejected")
	victim._tick_freeze(.0011)
	check(victim.apply_freeze(legacy), "after immunity endpoint refreeze")
	victim._tick_freeze(1.0)
	check(victim.freeze_remaining==0 and victim.freeze_immunity==1, "thaw grants full immunity after old immunity decrement")
	host.cancel(true)
	host.start_special("frozen-cast",Vector2.ZERO,1,true)
	host.cancel_for_status("frozen")
	check(not host.locked() and host.snapshot().cast_cooldown==1.6,"source freeze clears action cooldown but retains cast budget")
	check(host.collect(1,Vector3.ZERO,[]).is_empty(),"freeze cancels pending cast")
	check(host.has_method("advance_inactive"),"inactive-status cooldown clock seam exists")
	if host.has_method("advance_inactive"):
		host.advance_inactive(.6)
		check(is_equal_approx(host.snapshot().cast_cooldown,1.0),"cast budget advances while actor remains frozen/hitstunned")
	check(metadata(player)==before,"all imported clip keys/loops/lengths immutable after legacy/module exercise")
	legacy.free()
	victim.free()
	model.free()
	if failures==0: print("PASS: immutable Ice assets, source clock comparison and freeze/shatter/immunity oracle")
	quit(1 if failures else 0)
