extends SceneTree
# Doc 01 §5 / ledger C-008 — the CARRY ART contract (hand pose + per-player
# token), proven against the artist's own grip sprite.
#
# The carry pose is the artist's TOP-LEFT grip pose (hand_sheet_v3.png top-left
# cell): the grip that HOLDS an object.  Its production sprite,
# assets/ui/hand_carry.png, shipped with the per-player token BAKED IN (a red
# disc labelled "P1"), so tools/mask_carry_coin.py clears the baked coin (fill,
# shady red rim and label) while keeping the finger line-art that curled over
# the coin; the result is assets/ui/hand_hold.png on the IDENTICAL 129x160
# canvas with the same content placement, so the anchor TIP_CARRY stays exact.
#
#   1. the carry visual mode draws hand_hold.png with TIP_CARRY (never the
#      empty-pinch hover sprite hand_hover.png, never hand_grab.png);
#   2. the baked coin is gone where it was — the pixel at the coin centre is
#      transparent — while real glove art remains all around it (the carry
#      sprite is a filled grip, not an emptied one);
#   3. the carried SEPARATE per-player PlayerTokenView has its centre exactly
#      on (hotspot + CARRY_CENTER) on screen — the sprite pixel the baked coin
#      occupied — within 1 px, for every player colour;
#   4. the token layer sits BELOW the hand node, so the gripping fingers draw
#      over the token's near edge (fingers in front, like the baked sprite);
#   5. the ordinary pose still points (hand_point.png / TIP_POINT); the hover
#      pose stays available and unused by the carry, and hand_grab.png stays
#      available but unused by the carry.

const Tokens = preload("res://scripts/ui_tokens.gd")

const HOLD_TEXTURE := "res://assets/ui/hand_hold.png"
const HOVER_TEXTURE := "res://assets/ui/hand_hover.png"
const CARRY_SOURCE_TEXTURE := "res://assets/ui/hand_carry.png"
const GRAB_TEXTURE := "res://assets/ui/hand_grab.png"
const POINT_TEXTURE := "res://assets/ui/hand_point.png"
const SCREEN_TOLERANCE := 1.0

# The coin mask the carry sprite was cleaned with (tools/mask_carry_coin.py):
# the measured baked-coin disc of hand_carry.png. Nothing inside this disc is
# promised to be byte-identical; everything OUTSIDE it must be.
const COIN_CENTRE := Vector2(34.45, 33.46)
const COIN_DISC_R := 32.0

var failures := 0
var vs
var host: Node = null
var css: Control = null
var hand: Control = null

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = Vector2(24.0, 0.0)
	return event

func mouse_move(at: Vector2) -> void:
	# The hand's engine input callback receives the motion exactly as the engine
	# delivers it (repo harness convention); the hotspot is never the OS pointer.
	hand._input(motion(at))

func hover_tile(index: int) -> void:
	# Hover a roster tile through the public mouse path: the hotspot is ON the
	# tile (a carry only survives inside the populated roster envelope, ledger
	# C-004/C-005) and the tile's own `mouse_entered` entry fires.
	var tile: Control = css.get_tiles()[index]
	mouse_move(tile.get_global_rect().get_center())
	tile.mouse_entered.emit()
	await frames(4)

func activate_bay(index: int) -> void:
	var bay: Control = css.get_bays()[index]
	var at: Vector2 = bay.get_global_rect().get_center()
	mouse_move(at)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = at
	down.pressed = true
	bay._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = at
	up.pressed = false
	bay._gui_input(up)
	await frames(4)

func texture_path(tex: Texture2D) -> String:
	return "" if tex == null else str(tex.resource_path)

func token_centre(token: Control) -> Vector2:
	return token.global_position + token.size * 0.5

func alpha_at(texture: Texture2D, x: int, y: int) -> float:
	var image := texture.get_image()
	if image == null:
		return -1.0
	return image.get_pixel(x, y).a

func image_of(path: String) -> Image:
	var tex: Texture2D = load(path)
	return null if tex == null else tex.get_image()

func run():
	vs = load("res://tests/fixtures/vs_route.gd").new()
	hand = root.get_node_or_null("/root/Cursor").hand
	check(hand != null, "the cursor service is reachable")
	if hand == null:
		quit(1)
		return
	host = await vs.enter(self)
	css = host.char_select()
	if css == null or not await vs.wait_css_ready(host, self):
		check(false, "character select mounted and idle")
		quit(1)
		return
	await frames(8)

	var tiles: Array = css.get_tiles()
	check(tiles.size() > 3, "the roster has tiles to carry from")

	# --- 1/2. the carry pose, its anchor, and the baked coin removed --------
	await hover_tile(0)
	check(hand.is_carrying(), "hovering a tile starts the carry")
	check(texture_path(hand.active_texture()) == HOLD_TEXTURE,
		"the carry is drawn with the masked artist grip " + HOLD_TEXTURE
		+ " (got " + texture_path(hand.active_texture()) + ")")
	check(texture_path(hand.active_texture()) != HOVER_TEXTURE,
		"the carry no longer draws the empty-pinch HOVER sprite")
	check(texture_path(hand.active_texture()) != GRAB_TEXTURE,
		"the carry does not draw the old grab sprite")
	check(texture_path(hand.active_texture()) != POINT_TEXTURE,
		"the carry is not the pointing pose")
	check(hand.active_tip().is_equal_approx(hand.TIP_CARRY),
		"the carry anchor is TIP_CARRY (%s)" % str(hand.TIP_CARRY))

	var hold_tex: Texture2D = hand.active_texture()
	var carry_src_tex: Texture2D = load(CARRY_SOURCE_TEXTURE)
	check(hold_tex.get_width() == carry_src_tex.get_width()
		and hold_tex.get_height() == carry_src_tex.get_height(),
		"hand_hold.png keeps hand_carry.png's canvas (%dx%d, got %dx%d)"
		% [carry_src_tex.get_width(), carry_src_tex.get_height(),
			hold_tex.get_width(), hold_tex.get_height()])

	var hold_img := hold_tex.get_image()
	var src_img := carry_src_tex.get_image()
	var w := hold_img.get_width()
	var h := hold_img.get_height()

	# the baked coin is GONE where it was ...
	var coin_x := int(round(COIN_CENTRE.x))
	var coin_y := int(round(COIN_CENTRE.y))
	check(alpha_at(hold_tex, coin_x, coin_y) < 0.1,
		"the coin centre (%d,%d) is transparent — no baked coin left" % [coin_x, coin_y])
	check(alpha_at(carry_src_tex, coin_x, coin_y) > 0.9,
		"the same pixel was the baked coin in hand_carry.png (control)")
	# ... while the glove is still solid around and inside the pocket
	var inside_opaque := 0
	for y in h:
		for x in w:
			var dx0 := float(x) - COIN_CENTRE.x
			var dy0 := float(y) - COIN_CENTRE.y
			if dx0 * dx0 + dy0 * dy0 <= COIN_DISC_R * COIN_DISC_R:
				if hold_img.get_pixel(x, y).a > 0.5:
					inside_opaque += 1
	check(inside_opaque >= 250,
		"the grip is still solid inside the emptied coin disc (%d glove px kept)" % inside_opaque)
	check(alpha_at(hold_tex, 50, 45) > 0.9 and alpha_at(hold_tex, 60, 60) > 0.9,
		"the finger pixels that curled over the coin survive")

	# --- 7. the glove silhouette outside the coin mask is untouched --------
	var outside_total := 0
	var outside_same := 0
	var inside_same := 0
	var inside_total := 0
	for y in h:
		for x in w:
			var a0 := 1 if hold_img.get_pixel(x, y).a > 0.5 else 0
			var a1 := 1 if src_img.get_pixel(x, y).a > 0.5 else 0
			var dx := float(x) - COIN_CENTRE.x
			var dy := float(y) - COIN_CENTRE.y
			if dx * dx + dy * dy <= COIN_DISC_R * COIN_DISC_R:
				inside_total += 1
				if a0 == a1:
					inside_same += 1
			else:
				outside_total += 1
				if a0 == a1:
					outside_same += 1
	var outside_pct := 100.0 * float(outside_same) / maxf(1.0, float(outside_total))
	var inside_pct := 100.0 * float(inside_same) / maxf(1.0, float(inside_total))
	var outside_msg := "the glove silhouette outside the coin mask is identical to hand_carry.png "
	outside_msg += "(%.4f%% of %d px, %d differ)" % [outside_pct, outside_total, outside_total - outside_same]
	check(outside_same == outside_total, outside_msg)
	check(inside_pct < 99.0,
		"the coin mask really changed pixels inside it (%.2f%% of %d px identical)"
		% [inside_pct, inside_total])
	print("carry sprite: %d/%d px identical outside the coin mask (%.4f%%), %d/%d inside (%.2f%%)"
		% [outside_same, outside_total, outside_pct, inside_same, inside_total, inside_pct])

	# --- 4. fingers in front of the token ----------------------------------
	var slot: Control = hand.get_node("CursorCarryLayer")
	check(slot.get_index() < hand.get_node("HandVisual").get_index(),
		"the token layer draws BELOW the hand, so the fingers overlap the token")

	# --- 3/4. every player colour, centre on the sprite's coin position ----
	var carried_seen: Array = []
	for player in 4:
		if player > 0:
			await activate_bay(player)
			check(int(css.get_active()) == player, "P%d is the active player" % (player + 1))
		await hover_tile(player % tiles.size())
		check(int(css.get_carried_by()) == player,
			"P%d's token is carried (carried_by=%d)" % [player + 1, css.get_carried_by()])
		var token: Control = hand.carried_token()
		check(token != null and token == css.token_view(player),
			"the hand carries P%d's own SEPARATE token object" % (player + 1))
		if token == null:
			continue
		check(token.visible and token.is_visible_in_tree(),
			"P%d's carried token is visible in the live carry" % (player + 1))
		check(str(token.get_parent().name) == "CursorCarryLayer",
			"P%d's carried token is parented to the cursor carry layer" % (player + 1))
		check(token.player_color().is_equal_approx(Tokens.PLAYER_COLORS[player]),
			"P%d's carried token keeps its player colour" % (player + 1))
		check(token.position.is_equal_approx(hand.CARRY_CENTER - token.size * 0.5),
			"P%d's token is placed by CARRY_CENTER %s" % [player + 1, str(hand.CARRY_CENTER)])
		var expected: Vector2 = hand.hotspot + hand.CARRY_CENTER
		var centre: Vector2 = token_centre(token)
		var error: float = centre.distance_to(expected)
		check(error <= SCREEN_TOLERANCE,
			"P%d's token centre %s is on (hotspot + CARRY_CENTER) %s (%.2f px)"
			% [player + 1, str(centre), str(expected), error])
		# the same point in the sprite's own texture pixels
		var tex_point: Vector2 = hand.active_tip() + (centre - hand.hotspot) / hand.HAND_SCALE
		check(tex_point.distance_to(COIN_CENTRE) <= 1.0,
			"P%d's token centre back-projects to the coin position in hand_hold.png "
			% (player + 1) + "(%s vs %s, %.2f texture px)"
			% [str(tex_point), str(COIN_CENTRE), tex_point.distance_to(COIN_CENTRE)])
		carried_seen.append(player)
	check(carried_seen.size() == 4, "the carry was exercised for all four player colours")

	# --- 5. the ordinary pose and the retired sprites ----------------------
	mouse_move(Vector2(640.0, 30.0))       # leave the populated roster
	await frames(8)
	check(not hand.is_carrying(), "leaving the roster ends the carry")
	check(texture_path(hand.active_texture()) == POINT_TEXTURE,
		"the ordinary pose still draws hand_point.png")
	check(hand.active_tip().is_equal_approx(hand.TIP_POINT),
		"the ordinary pose still uses TIP_POINT")
	check(load(HOVER_TEXTURE) != null,
		"the empty-pinch HOVER sprite stays available (unused by carry)")
	check(hand.hover_texture() != hand.active_texture(),
		"the HOVER sprite is reachable but is not what the ordinary pose draws")
	check(hand.HOVER_TIP.is_equal_approx(Vector2(23.1, 45.0)),
		"the HOVER pose keeps its measured pinch anchor TIP_HOLD (23.1, 45.0)")
	check(load(GRAB_TEXTURE) != null, "hand_grab.png stays available (just unused by carry)")

	vs.free_hosts(self)
	await frames(2)
	if failures > 0:
		print("FAILURES: %d" % failures)
		quit(1)
		return
	print("PASS: carry art (masked top-left grip hand_hold.png, baked coin gone, "
		+ "token centred on the coin position for P1-P4, fingers in front, "
		+ "hover pinch kept for hover)")
	quit(0)
