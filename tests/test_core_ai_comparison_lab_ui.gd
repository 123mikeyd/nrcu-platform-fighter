extends "res://tests/test_core_overlay_focus.gd"
func run():
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720); root.gui_embed_subwindows = true
	var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
	await process_frame; await process_frame
	var owner = lab.find_child("P2Input",true,false)
	check(owner is OptionButton,"visible P2 ownership selector")
	if owner == null: lab.free(); quit(1); return
	var difficulty = lab.find_child("AIDifficulty",true,false)
	var mode = lab.find_child("ComparisonInteraction",true,false)
	check(difficulty is OptionButton and mode is OptionButton,"difficulty and A/B selectors visible")
	check(mode.disabled and mode.get_item_text(mode.selected) == "Interaction: F5 off", "comparison is explicitly inactive outside anatomical mode")
	var human_index := owner_item_index(owner, "P2: Human")
	var sparring_index := owner_item_index(owner, "P2: Sparring / Easy (ours)")
	var mikey_index := owner_item_index(owner, "P2: Mikey AI adapted")
	check(human_index >= 0 and mikey_index >= 0,"truthful ownership labels")
	check(sparring_index > human_index and mikey_index > sparring_index,"separate Sparring option is first AI recommendation")
	if human_index < 0 or sparring_index < 0 or mikey_index < 0: lab.free(); quit(1); return
	check(mode.get_item_text(0) == "New grounded jostle" and mode.get_item_text(1) == "Previous solid bodies","explicit A/B labels")
	await click(owner)
	check(owner.get_popup().visible,"P2 menu mouse operable")
	owner.get_popup().set_focused_item(mikey_index - 1)
	await key(KEY_DOWN); await key(KEY_ENTER)
	check(lab.repo_inputs.enabled and not owner.get_popup().visible,"menu keyboard selection enables real AI")
	check(owner.selected == mikey_index and owner.get_item_text(owner.selected) == "P2: Mikey AI adapted" and lab.p2_input_owner == "repo_ai" and not lab.sparring_inputs.enabled,"actual selected item and exclusive owner are Mikey")
	check(lab.paused,"opening menu pauses gameplay to prevent menu keys issuing attacks")
	await key(KEY_SPACE); await key(KEY_ENTER)
	check(not owner.get_popup().visible and owner.selected == mikey_index,"Space/Enter after menu close do not reopen or change P2")
	check(root.gui_get_focus_owner() != owner,"closed menu releases focus")
	lab.set_paused(false)
	for i in 40: await physics_frame; lab._physics_process(1.0/60)
	for code in [KEY_SPACE,KEY_ENTER]:
		var event = InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = true
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	var jumped := false
	for i in 10:
		await physics_frame; lab._physics_process(1.0/60)
		jumped = jumped or lab.actors[0].velocity.y > 0
	check(jumped,"physical P1 Space jumps after selecting P2 menu")
	check(not lab.sources[1]._previous.get("jump",false),"physical Enter remains ignored on AI P2")
	for code in [KEY_SPACE,KEY_ENTER]:
		var event = InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = false
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	check(lab.generated_collision_button.disabled,"F5 checkbox locked while AI comparison active")
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size; await process_frame; await process_frame
		for c in [owner,difficulty,mode]:
			check(c.get_global_rect().end.x <= size.x and c.get_global_rect().position.x >= 0,"comparison controls fit width "+str(size))
	lab.free()
	if not failures: print("PASS: AI comparison menus focus keyboard and layout")
	quit(1 if failures else 0)

func owner_item_index(button: OptionButton, label: String) -> int:
	for index in button.item_count:
		if button.get_item_text(index) == label: return index
	return -1
