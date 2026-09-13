extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    for i in 5: await process_frame
    check(arena.has_method("open_stage_select"), "arena exposes the stage page")
    # card path: opens with the clicked stage as the focus
    arena.setup.stage_select_requested.emit("toy_room")
    for i in 2: await process_frame
    var stage = arena.stage_panel.find_child("StageSelect", true, false)
    check(stage != null, "stage page exists")
    if stage == null:
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(arena.stage_panel.visible and not arena.setup.visible, "stage page replaces the setup screen")
    var tiles: Array = stage.get_tiles()
    check(tiles.size() == 3, "three stage tiles")
    check(stage.get_input_lock() > 0.0, "scene-start lock is active")
    check(tiles[2].position.x > 1280.0, "tiles start parked off-screen right")
    var vw: float = stage.get_viewport_rect().size.x
    await create_timer(0.6).timeout
    for i in tiles.size():
        check(tiles[i].position.x + 170.0 < vw, "tile %d flew into view" % i)
    check(stage.get_hovered_id() == "toy_room", "focus id hovered after the entrance")
    check(stage.get_box_visible(), "highlight box sits on the hovered tile")
    check(stage.get_name_text() == "TOY SHELF / BEDROOM", "name display follows the hover")
    # Composition gates (visual spec): the field and the preview are separate
    # regions, the highlight lives in the reserved gutter, and every stage
    # image is really cropped by a clipping frame instead of stretched.
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
    tiles[0].pressed.emit()
    check(stage.get_hovered_id() == "debug", "first press moves the hover")
    check(stage.get_confirmed_id() == "", "no confirm on a hover move")
    tiles[0].pressed.emit()
    check(stage.get_confirmed_id() == "debug", "second press confirms")
    check(stage.is_confirming(), "confirm lock engaged")
    check(arena.setup.level.selected == 0, "hidden model updated at confirm")
    tiles[1].pressed.emit()
    check(stage.get_confirmed_id() == "debug", "presses swallowed while confirming")
    await create_timer(0.9).timeout
    check(not arena.stage_panel.visible, "stage page closed after the confirm lock")
    check(arena.setup.visible, "setup is back")
    check(arena.setup.selected_level() == "debug", "the chosen stage is the selection")
    # back path: keeps the previous choice, hover falls back to the current stage
    arena.setup.stage_select_requested.emit("")
    for i in 2: await process_frame
    check(arena.stage_panel.visible, "stage page reopens")
    check(stage.get_hovered_id() == "", "no hover during the entrance")
    await create_timer(0.6).timeout
    check(stage.get_hovered_id() == "debug", "empty focus falls back to the current stage")
    stage.request_back()
    check(stage.is_exiting(), "back starts the exit")
    await create_timer(0.5).timeout
    check(not arena.stage_panel.visible, "back closes the page")
    check(arena.setup.selected_level() == "debug", "back keeps the choice")
    # the LEVEL row confirm opens the same page
    await create_timer(0.6).timeout
    arena.setup.main_menu.set_focus(1)
    arena.setup.main_menu.confirm()
    for i in 3: await process_frame
    check(arena.stage_panel.visible, "LEVEL row opens the stage page")
    stage.request_back()
    await create_timer(0.5).timeout
    check(arena.setup.visible and not arena.stage_panel.visible, "back from the row path returns to setup")
    # the stage cards in the setup open the page with their own stage focused
    await create_timer(0.4).timeout
    var card_one = arena.setup.find_child("StageCard1", true, false)
    check(card_one != null, "stage cards exist in the setup")
    card_one.pressed.emit()
    for i in 2: await process_frame
    check(arena.stage_panel.visible, "stage card opens the page")
    await create_timer(0.6).timeout
    check(stage.get_hovered_id() == "toy_room", "the clicked card is the hovered stage")
    check(arena.setup.selected_level() == "debug", "hovering a card does not change the selection")
    stage.request_back()
    await create_timer(0.5).timeout
    check(not arena.stage_panel.visible, "card path back closes the page")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: stage page (staggered entrance, sticky hover, name swap, confirm/back, model sync)")
    quit(1 if failures else 0)
