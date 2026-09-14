extends SceneTree
# Carry diagnostic probe (dev tool, NOT a test): why the carried token did not
# show up in the csscarry evidence render.
#
# A) reproduces the OLD evidence path: the hand hotspot is parked OFF the
#    populated roster envelope and `css._on_tile_entered()` is called directly.
# B) reproduces the repaired path: the hotspot is driven ONTO a roster tile the
#    way a real pointer resting there does, and re-asserted every frame.
#
# Prints carrying / token parent / visibility / centre vs pinch point for both.
#
# Run:  godot --headless --path <repo> --script res://tools/carry_probe.gd

const PARK := Vector2(640.0, 200.0)     # what the old harness parked the hand at
const TILE := 2

var hand: Control = null
var css: Control = null


func _initialize() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = Vector2(24.0, 0.0)
	return event


func report(tag: String) -> void:
	var token: Control = hand.carried_token()
	var pinch: Vector2 = hand.carry_pinch_point()
	var line := "%s: carrying=%s carried_by=%d texture=%s hotspot=%s in_roster=%s" % [
		tag, str(hand.is_carrying()), int(css.get_carried_by()),
		str(hand.active_texture().resource_path if hand.active_texture() else "-"),
		str(hand.hotspot), str(css.roster_bounds().has_point(hand.hotspot))]
	print(line)
	if token == null:
		print("    token=NONE (nothing for the renderer to draw)")
		return
	var centre: Vector2 = token.global_position + token.size * 0.5
	print("    token=%s parent=%s visible=%s in_tree=%s centre=%s pinch=%s err_px=%.3f size=%s" % [
		token.name, str(token.get_parent().name), str(token.visible),
		str(token.is_visible_in_tree()), str(centre), str(pinch),
		centre.distance_to(pinch), str(token.size)])


func run() -> void:
	var vs = load("res://tests/fixtures/vs_route.gd").new()
	var host = await vs.enter(self)
	css = host.char_select()
	if css == null or not await vs.wait_css_ready(host, self):
		print("probe: character select never became ready")
		quit(1)
		return
	hand = root.get_node_or_null("/root/Cursor").hand
	await frames(10)

	print("--- A) old evidence path: hotspot parked at %s, then _on_tile_entered(%d)" % [
		str(PARK), TILE])
	hand._input(motion(PARK))
	await frames(2)
	css._on_tile_entered(TILE)
	await process_frame          # the screen now enforces the roster envelope
	report("A frame+1")
	await frames(4)
	report("A frame+5")

	print("--- B) repaired path: hotspot driven onto tile %d and held there" % TILE)
	for i in 12:
		var at: Vector2 = (css.get_tiles()[TILE] as Control).get_global_rect().get_center()
		hand._input(motion(at))
		if i == 0:
			css._on_tile_entered(TILE)
		await process_frame
	report("B held")

	vs.free_hosts(self)
	await frames(2)
	quit(0)
