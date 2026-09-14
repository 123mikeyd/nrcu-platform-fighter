extends SceneTree
# WP-4 Story tracer: Main -> Story Select -> Encounter Briefing.
# Public pointer input drives the shipped controls; no private selection helpers.
const Support = preload("res://tools/acceptance_support.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for i in count:
		await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var story = load("res://tests/fixtures/story_route.gd").new()
	var host = await story.enter(self, "turbofit")
	check(host != null, "Story enters the frontend host")
	if host == null:
		quit(1)
		return
	check(host.active_surface() == "story_select", "Story entry presents Story Fighter Select")
	check(host.route_stack_names() == ["story_select"], "Story entry starts the select route")
	var select = host.story_select()
	var briefing = host.story_briefing()
	check(select != null and select.visible, "Story Select is visible on entry")
	check(briefing != null and not briefing.visible, "Encounter Briefing is not skipped on entry")
	if select != null:
		var tiles: Array = select.roster_tiles()
		check(tiles.size() > 1, "Story Select exposes the playable roster")
		if tiles.size() > 1:
			Support.click_center(self, tiles[1])
			await frames(3)
			Support.click_center(self, select.continue_button())
			var reached := await Support.wait_until(self, func() -> bool:
				return host.active_surface() == "story_briefing"
			, 180)
			check(reached, "Story Select Continue reaches Encounter Briefing")
			check(host.route_stack_names() == ["story_select", "story_briefing"],
				"the Story Select -> Briefing edge is a real PUSH")
			check(host.story_selection_id() == str(tiles[1].fighter_id),
				"the selected fighter survives the step transition")
			check(briefing.visible and briefing.selected_fighter_id() == host.story_selection_id(),
				"Briefing presents the selected fighter")
	await story.free_hosts(self)
	print("STORY_TWO_STEP failures=", failures)
	quit(1 if failures else 0)
