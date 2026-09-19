extends "res://tests/test_full_game_stage_visual_geometry.gd"
## Current authored shelf: real keyboard -> PlayerInputSource -> Match only.
## Old four-platform height assertions never checked visible geometry.
func run():
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	app.input_owner = "human"
	await click("StartMatch")
	await frames(130)
	var authored: Array = load("res://scripts/stage_layouts.gd").surfaces("toy_room")
	var p: Vector3 = authored[0][0]
	var size: Vector3 = authored[0][1]
	var bounds := {"left":p.x-size.x/2,"right":p.x+size.x/2,"top":p.y+size.y/2}
	check(app.session.stage.ai_bounds() == bounds,"AI bounds equal actual visible authored support")
	var rules = app.session.simulation.rules.stage
	check(rules.blast_left < bounds.left and rules.blast_right > bounds.right,"authored floor ends inside unchanged upstream blast bounds")
	for spawn in rules.spawns.values():
		check(spawn.x > bounds.left and spawn.x < bounds.right and spawn.y > bounds.top,"stock spawn over actual authored floor")
	for anchor in app.session.stage.anchors():
		check(is_equal_approx(anchor.edge.x,bounds.left if anchor.outward < 0 else bounds.right) and is_equal_approx(anchor.edge.y,bounds.top),"ledge belongs to actual authored endpoint")
	for slot in 2:
		var actor = app.session.actors[slot]
		for side in [-1,1]:
			app.session.rematch(); await frames(45)
			var away = (KEY_A if side == -1 else KEY_D) if slot == 0 else (KEY_LEFT if side == -1 else KEY_RIGHT)
			var toward = (KEY_D if side == -1 else KEY_A) if slot == 0 else (KEY_RIGHT if side == -1 else KEY_LEFT)
			var down = KEY_S if slot == 0 else KEY_DOWN
			var jump = KEY_SPACE if slot == 0 else KEY_ENTER
			# Down must not drop through the solid authored shelf.
			key(down,true); await frames(12); key(down,false)
			check(actor.runtime.grounded,"solid floor refuses down-drop kit %d" % slot)
			key(jump,true); await frames(12); key(jump,false)
			check(not actor.runtime.grounded and actor.position.y > bounds.top+0.2,"actual kit %d jump accepted" % slot)
			await frames(85)
			check(actor.runtime.grounded and absf(actor.position.y-bounds.top)<0.04,"actual kit %d jump lands" % slot)
			key(away,true)
			var reached := false
			var edge: float = bounds.left if side < 0 else bounds.right
			for i in 220:
				await frames(1)
				if actor.position.x*side >= absf(edge)-0.35:
					reached = actor.runtime.grounded
					break
			key(away,false)
			check(reached,"kit %d side %d stays supported to rendered shelf end (not old +/-9)" % [slot,side])
			# Capture only the stable hang/climb below: waiting for a render
			# here changes which physics tick consumes the braking key.
			await frames(18)
			key(away,true)
			var left_floor := false
			for i in 35:
				await frames(1)
				if not actor.runtime.grounded:
					left_floor = true
					break
			key(away,false); key(toward,true)
			check(left_floor,"kit %d side %d really leaves authored floor" % [slot,side])
			var caught := false
			for i in 40:
				await frames(1)
				if not app.session.simulation.ledge_telemetry(slot+1).anchor_id.is_empty():
					caught = true
					break
			key(toward,false)
			check(caught,"kit %d side %d catches authored ledge" % [slot,side])
			await capture("kit-%d-hang-%d" % [slot,side])
			var up = KEY_W if slot == 0 else KEY_UP
			key(up,true); await frames(3); key(up,false); await frames(20)
			check(caught and app.session.simulation.fighters[slot+1].stocks == 3 and actor.runtime.grounded and absf(actor.position.y-bounds.top)<0.04,"kit %d side %d climbs onto rendered support" % [slot,side])
			await capture("kit-%d-climb-%d" % [slot,side])
	app.free(); await frames(3)
	if not failures: print("PASS: current authored shelf both kits jump land solid drop edges ledge catch climb")
	quit(1 if failures else 0)
