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
    # CSS: synthetic rosters must not need a redesign (brief Phase 5).
    var css = arena.char_panel.find_child("CharSelect", true, false)
    check(css != null, "css exists")
    if css == null:
        arena.queue_free(); await process_frame; quit(1); return
    for count in [7, 12, 20, 30]:
        var cards: Array = []
        for i in count:
            cards.append({"id": "teknium", "name": "SYNTH %d" % i, "palette": Color(0.5, 0.5, 0.5)})
        css.build(cards)
        for i in 3: await process_frame
        var boxes: Array = css.get_cards()
        check(boxes.size() == count, "css builds %d cards" % count)
        var min_w := 999.0
        var in_bounds := true
        for b in boxes:
            var r: Rect2 = b.get_rect()
            min_w = minf(min_w, r.size.x)
            if r.position.x < 0.0 or r.end.x > 1280.0 or r.position.y < 0.0 or r.end.y > 545.0:
                in_bounds = false
        check(in_bounds, "cards stay inside the reserved field at %d" % count)
        check(min_w >= 60.0, "cells stay readable at %d fighters" % count)
        if count == 7:
            check(min_w <= 160.0, "seven fighters do not become giant cards")
    # SSS: synthetic stage lists keep the tile/preview regions separated.
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
    if failures == 0: print("PASS: frontend scalability (CSS 7/12/20/30, SSS 3/6/12/20, regions stable)")
    quit(1 if failures else 0)
