extends SceneTree
# Character Select — composition & geometry (Doc 04 §3/§5/§8/§30-§32).
#
# Supersedes the old test that protected the rejected right-side global
# HeroRig layout. Interaction contracts live in tests/test_char_select.gd.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    # WP-0 steps 7-8: the CSS is hosted by the MatchFlow owner (the in-arena
    # char panel is gone); the composition contract is unchanged.
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var host = await vs.enter(self)
    var css = host.char_select()
    check(css != null, "css exists")
    if css == null:
        host.queue_free(); await process_frame; quit(1); return
    for i in 20: await process_frame
    # --- no global hero region (rejected architecture) --------------------
    check(css.find_child("HeroRig", true, false) == null, "no global right-side HeroRig region")
    check(css.find_child("HeroFrame", true, false) == null, "no global hero frame")
    # --- four vertical player stations ------------------------------------
    var bays: Array = css.get_bays()
    check(bays.size() == 4, "four player bay components exist")
    var station_top := INF
    var bay_gap_ok := true
    for i in bays.size():
        var b: Control = bays[i]
        var r: Rect2 = b.get_global_rect()
        station_top = minf(station_top, r.position.y)
        check(r.size.y >= 240.0, "bay %d is a substantial player station" % i)
        if i > 0:
            var prev: Rect2 = bays[i - 1].get_global_rect()
            if r.position.x <= prev.position.x or r.position.x - prev.end.x > 24.0:
                bay_gap_ok = false
    check(bay_gap_ok, "the four stations are laid out in one row with a tight gap")
    check(station_top >= 430.0, "the stations occupy the lower field")
    for i in bays.size():
        var b: Control = bays[i]
        if str(host.selection_state.slots[i].kind) != "empty":
            check(b.render_view() != null, "bay %d has a fighter presentation area" % i)
    # --- roster occupies the reserved upper field -------------------------
    var tiles: Array = css.get_tiles()
    check(tiles.size() == 7, "seven roster tiles")
    var field: Control = css.find_child("RosterField", true, false)
    check(field != null, "the roster field exists")
    var in_field := true
    var size_ok := true
    var top := INF
    for t in tiles:
        var r: Rect2 = t.get_global_rect()
        var fr: Rect2 = field.get_global_rect()
        top = minf(top, r.position.y)
        if r.position.x < 0.0 or r.end.x > fr.end.x or r.position.y < 0.0 or r.end.y > fr.end.y:
            in_field = false
        if absf(r.size.x - 108.0) > 1.0 or absf(r.size.y - 82.0) > 1.0:
            size_ok = false
    check(in_field, "every tile stays inside the reserved roster field")
    check(size_ok, "tile geometry is the fixed 108x82 family")
    check(top < station_top, "the roster sits above the player stations")
    # --- reference frame centered (canvas_items + expand) -----------------
    var frame: Control = css.find_child("ReferenceFrame", true, false)
    check(frame != null and absf(frame.size.x - 1280.0) < 1.0 and absf(frame.size.y - 720.0) < 1.0, "core UI lives in a centered 1280x720 ReferenceFrame")
    check(css.find_child("ReadyBand", true, false) != null, "the ready band component exists")
    # --- no selection collision by construction ---------------------------
    for i in tiles.size():
        for j in range(i + 1, tiles.size()):
            if tiles[i].get_rect().intersects(tiles[j].get_rect()):
                check(false, "tiles %d and %d overlap" % [i, j])
    check(true, "no tile overlaps")
    # --- scalability: the roster grows inside the same field --------------
    for count in [12, 20, 30]:
        var cards: Array = []
        for i in count:
            cards.append({"id": "teknium", "name": "SYNTH %02d" % i})
        css.build(cards)
        for i in 3: await process_frame
        var boxes: Array = css.get_tiles()
        check(boxes.size() == count, "css builds %d synthetic tiles" % count)
        var fr: Rect2 = field.get_global_rect()
        var min_w := 999.0
        var bounded := true
        for b in boxes:
            var r: Rect2 = b.get_rect()
            min_w = minf(min_w, r.size.x)
            if r.position.x < 0.0 or r.end.x > fr.end.x or r.position.y < 0.0 or r.end.y > fr.end.y:
                bounded = false
        check(bounded, "%d fighters stay inside the reserved field" % count)
        check(min_w >= 100.0, "%d fighters keep the fixed tile width" % count)
        # player stations never move because of roster growth
        var bay0: Rect2 = bays[0].get_global_rect()
        check(absf(bay0.position.y - station_top) < 1.0, "player stations do not move at %d fighters" % count)
    # restore the real roster for the rest of the suite
    css.build([])
    await process_frame
    check(css.get_tiles().size() == 7, "the real roster restores")
    host.queue_free()
    await process_frame
    if failures == 0: print("PASS: css composition (no global hero, four stations, reserved roster field, fixed geometry, scalability)")
    quit(1 if failures else 0)
