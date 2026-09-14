extends SceneTree
# Stage Select — PRODUCTION route contract (Doc 05 §6/§11).
#
# WP-0 steps 7-8: the CSS/SSS production route lives in the MatchFlow host (the
# in-arena char/stage panels were removed with the rest of the gameplay-side
# production frontend), so this suite drives exactly the player route: the host
# owns CSS -> READY -> SSS, its confirm LAUNCHes gameplay from the immutable
# MatchLaunchConfig, and its Back POPs the SSS back to the CSS. Debug-adapter
# coverage lives in tests/test_debug_match_setup.gd.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var host = await vs.enter(self)
    check(host.has_method("push_surface") and host.char_select() != null, "MatchFlow exposes the VS route")
    # --- production entry: Main -> CSS -> READY -> SSS ---------------------
    var css = host.char_select()
    check(css != null, "character select exists")
    css.ready_requested.emit()
    # Poll for the SSS to open, then inspect the ENTRY window immediately:
    # the scene-start guard is active and the tiles are still parked/flying.
    var opened: bool = await vs.wait_for(self, func() -> bool: return host.is_surface_presented("sss"), 240)
    check(opened, "READY from the CSS opens the stage page")
    var stage = host.stage_select()
    check(stage != null, "stage page exists")
    if stage == null:
        host.queue_free(); await process_frame; quit(1); return
    check(host.is_surface_presented("sss") and not host.is_surface_presented("css"), "READY from the CSS opens the stage page")
    check(stage.get_input_lock() > 0.0, "scene-start lock is active during the entrance")
    var early_tiles: Array = stage.get_tiles()
    check(early_tiles.size() == 3 and early_tiles[2].position.x > 1280.0, "tiles start parked off-screen right")
    await create_timer(0.9).timeout
    var hand = root.get_node_or_null("/root/Cursor").hand
    check(hand != null, "cursor service reachable")
    # --- cursor contract on entry -----------------------------------------
    check(not hand.is_carrying(), "the CSS token can never leak into the stage page")
    check(hand.mode == 0, "stage page presents the regular mouse cursor")
    # --- composition guards (unchanged product invariants) ----------------
    var tiles: Array = stage.get_tiles()
    check(tiles.size() == 3, "three stage tiles")
    var vw: float = stage.get_viewport_rect().size.x
    await create_timer(0.7).timeout
    for i in tiles.size():
        check(tiles[i].position.x + 170.0 < vw, "tile %d flew into view" % i)
    check(stage.get_hovered_id() == str(host.selection_state.stage), "entry hovers the stored stage")
    check(stage.get_box_visible(), "highlight box sits on the hovered tile")
    var preview = stage.find_child("StagePreview", true, false)
    check(preview != null and preview is TextureRect, "the preview region is its own TextureRect")
    check(preview != null and preview.position.x >= 700.0, "the preview region stays right of the field")
    var preview_image = stage.find_child("StagePreviewImage", true, false)
    check(preview_image != null and preview_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "the preview image is cover-cropped")
    var box = stage.find_child("SelectBox", true, false)
    check(box != null, "the selection plate exists")
    var covered := true
    var clipped := true
    for i in tiles.size():
        var thumb = tiles[i].find_child("StageThumbnail" + str(i), true, false)
        if thumb == null or not (thumb is TextureRect) or thumb.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
            covered = false
        var node = thumb
        var masked := false
        while node != null:
            if node is Control and node.clip_contents:
                masked = true
                break
            node = node.get_parent()
        if not masked:
            clipped = false
    check(covered, "every tile image is cover-cropped")
    check(clipped, "every tile image is clipped by its frame")
    var overlaps := 0
    var gaps_ok := true
    for i in tiles.size():
        for j in range(i + 1, tiles.size()):
            var a: Rect2 = tiles[i].get_rect()
            var b: Rect2 = tiles[j].get_rect()
            if a.intersects(b):
                overlaps += 1
            elif absf(a.position.y - b.position.y) < 1.0:
                if maxf(a.position.x, b.position.x) - minf(a.end.x, b.end.x) < 22.0:
                    gaps_ok = false
    check(overlaps == 0, "tiles never overlap each other")
    check(gaps_ok, "tiles keep the reserved selection gutter")
    var share := 0
    if box != null:
        var box_rect := Rect2(box.position, box.size)
        for t in tiles:
            if box_rect.intersects(t.get_rect()):
                share += 1
    check(share == 1, "the highlight only overlaps the hovered tile")
    var separated := true
    if preview != null:
        var preview_rect := Rect2(preview.position, preview.size)
        for t in tiles:
            if preview_rect.intersects(t.get_rect()):
                separated = false
    check(separated, "the preview region never overlaps the stage field")
    check(stage.find_child("StageReserve3", true, false) != null, "the field shows its reserved slots")
    # --- focus anchors (Step 0): authored tile anchors, no mouse warp ------
    var anchor_one: Control = stage.get_tile_anchor(1)
    check(anchor_one != null, "every tile exposes an authored CursorAnchor")
    # MIGRATED (Doc 03 §2, WP-1a): focus is claimed by MEANINGFUL navigation
    # input only. KEY_TAB relied on the rejected blanket "any key => focus"
    # rule; ui_down is a semantic frontend action and claims FOCUS.
    var key := InputEventKey.new()
    key.keycode = KEY_DOWN
    key.pressed = true
    hand._input(key)
    check(hand.mode == 1, "semantic keyboard navigation switches the cursor to focus mode")
    var mouse_before: Vector2 = hand._mouse
    var stage_slot2: int = stage._index_of(stage.get_hovered_id())
    stage.hover_slot(1 if stage_slot2 != 1 else 2)
    check(hand._focus_anchor != null, "focus mode targets the hovered tile's anchor")
    var anchor_pos: Vector2 = hand._focus_anchor.get_global_rect().position
    for i in 40:
        await process_frame
    check(hand._mouse == mouse_before, "the physical pointer coordinate is untouched by focus movement")
    check(hand.hotspot.distance_to(anchor_pos) < 6.0, "the focus hand settles at the authored anchor")
    # --- hover vs confirm semantics (unchanged) ---------------------------
    var first: int = 0 if stage.get_hovered_id() != "debug" else 1
    var confirmed_id := str(stage._slots[first]["id"])
    tiles[first].pressed.emit()
    check(stage.get_hovered_id() == confirmed_id, "first press previews the stage")
    check(stage.get_confirmed_id() == "", "hovering never commits the stage")
    check(str(host.selection_state.stage) == "debug", "hover does not mutate the persistent stage")
    tiles[first].pressed.emit()
    check(stage.get_confirmed_id() == confirmed_id, "second press confirms")
    check(stage.is_confirming(), "confirm lock engaged")
    tiles[0].pressed.emit()
    check(stage.get_confirmed_id() == confirmed_id, "presses swallowed while confirming")
    # The confirm LAUNCHes through the router's §6 handshake: the destination is
    # captured before the released host frees itself.
    var arena: Node = host.gameplay_node()
    for i in 300:
        await process_frame
        if is_instance_valid(host) and host.launch_state() == "launched":
            check(not host.is_surface_presented("sss") and not host.is_surface_presented("css"), "VS screens closed after the confirm")
            check(str(host.selection_state.stage) == confirmed_id, "the persistent stage holds the confirmed value")
            break
    var launched := false
    for i in 300:
        await process_frame
        if arena != null and is_instance_valid(arena) and not arena.fighters.is_empty() and not is_instance_valid(host):
            launched = true
            break
    check(launched, "the confirmed stage LAUNCHes gameplay through the flow")
    check(arena != null and is_instance_valid(arena), "gameplay exists after the launch")
    if arena != null and is_instance_valid(arena):
        check(arena.active_level == confirmed_id, "confirmed stage launches the match through the selection state")
    # --- backtracking: CSS -> SSS -> CSS preserves the selection ----------
    var host2 = await vs.enter(self)
    var css2 = host2.char_select()
    host2.selection_state.slots[0]["character"] = "ggb"
    css2.ready_requested.emit()
    var opened2: bool = await vs.wait_for(self, func() -> bool: return host2.is_surface_presented("sss"), 240)
    check(opened2, "stage page opens again")
    await create_timer(0.9).timeout
    var stage2 = host2.stage_select()
    stage2.request_back()
    var restored: bool = await vs.wait_for(self, func() -> bool: return host2.is_surface_presented("css"), 240)
    check(restored and not host2.is_surface_presented("sss"), "SSS Back returns to the CSS")
    check(str(host2.selection_state.slots[0]["character"]) == "ggb", "Back preserves the fighter configuration")
    check(not hand.is_carrying(), "returning from SSS carries no token")
    host2.queue_free()
    await process_frame
    if failures == 0: print("PASS: production stage select (route, cursor anchors, hover/confirm, backtracking preservation)")
    quit(1 if failures else 0)
