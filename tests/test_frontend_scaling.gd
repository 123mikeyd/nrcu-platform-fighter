extends SceneTree
# Frontend scalability (Doc 00 §11 / Doc 04 §31 / Doc 05 §9).
#
# CSS: fixed-density roster — tile geometry never changes with the count and
# the field absorbs 7..30 fighters without a redesign. SSS keeps its frozen
# field/preview separation. Player stations must not move with roster growth.
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
    arena.open_vs()
    for i in 3: await process_frame
    var css = arena.char_panel.find_child("CharSelect", true, false)
    check(css != null, "css exists")
    if css == null:
        arena.queue_free(); await process_frame; quit(1); return
    var field: Control = css.find_child("RosterField", true, false)
    var bay_y := -1.0
    for count in [7, 12, 20, 30]:
        var cards: Array = []
        for i in count:
            cards.append({"id": "teknium", "name": "SYNTH %d" % i})
        css.build(cards)
        for i in 3: await process_frame
        var boxes: Array = css.get_tiles()
        check(boxes.size() == count, "css builds %d cards" % count)
        var min_w := 999.0
        var in_bounds := true
        var fr: Rect2 = field.get_rect()
        for b in boxes:
            var r: Rect2 = b.get_rect()
            min_w = minf(min_w, r.size.x)
            if r.position.x < 0.0 or r.end.x > fr.end.x or r.position.y < 0.0 or r.end.y > fr.end.y:
                in_bounds = false
        check(in_bounds, "cards stay inside the reserved roster field at %d" % count)
        check(min_w >= 100.0, "tiles keep a stable readable width at %d fighters" % count)
        if count == 7:
            check(min_w <= 160.0, "seven fighters do not become giant cards")
        var bays: Array = css.get_bays()
        var y: float = bays[0].get_global_rect().position.y
        if bay_y < 0.0:
            bay_y = y
        check(absf(y - bay_y) < 1.0, "player stations do not move at %d fighters" % count)
    css.build([])
    await process_frame
    # --- SSS: synthetic stage lists keep the tile/preview regions ---------
    var css2 = arena.char_panel.find_child("CharSelect", true, false)
    css2.ready_requested.emit()
    var opened := false
    for i in 120:
        await process_frame
        if arena.stage_panel.visible:
            opened = true
            break
    check(opened, "stage page opens through the production route")
    var sss = arena.stage_panel.find_child("StageSelect", true, false)
    check(sss != null, "sss exists")
    for count in [3, 6, 12, 20]:
        var slots: Array = []
        for i in count:
            slots.append({"id": "debug", "name": "STAGE %d" % i, "tex": "res://assets/menu/stage_debug.png"})
        sss.build(slots)
        for i in 3: await process_frame
        var tiles: Array = sss.get_tiles()
        check(tiles.size() == count, "sss builds %d tiles" % count)
        var min_w := 999.0
        var in_bounds := true
        for t in tiles:
            var r: Rect2 = t.get_rect()
            min_w = minf(min_w, r.size.x)
            if r.position.x < 0.0 or r.end.x > 660.0 or r.position.y < 0.0 or r.end.y > 545.0:
                in_bounds = false
        check(in_bounds, "tiles stay inside the stage field at %d" % count)
        check(min_w >= 60.0, "tiles stay readable at %d stages" % count)
        var preview = sss.find_child("StagePreview", true, false)
        check(preview != null and preview.position.x >= 700.0, "preview region separate at %d stages" % count)
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: frontend scalability (CSS 7/12/20/30 fixed family, SSS 3/6/12/20, stations stable)")
    quit(1 if failures else 0)
