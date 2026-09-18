extends SceneTree
# Character Select — adaptive composition & geometry (Doc 01 §8, Doc 04 §10,
# ledger C-019/C-050/C-051). Supersedes the old test that protected the
# rejected right-side global HeroRig layout.
#
# The locked composition under test:
#   * only the OCCUPIED roster rows consume vertical height — never the
#     permanently reserved 10x3 envelope ("Do not leave two invisible rows of
#     dead UI");
#   * tiles keep the fixed 108x82 reference size and never shrink for roster
#     growth (capacity stays 10x3 = 30; past capacity is a paging design, out
#     of this pass);
#   * the four stations keep a STABLE lower line (y ~690) and take the locked
#     heights 420/330/245 for 1/2/3 occupied rows;
#   * Ready sits at occupied_bottom + 18 in a RESERVED slot (the band appearing
#     never moves the stations);
#   * the fighter presentation owns ~70-78% of the station height at every
#     height, and empty stations recede;
#   * the active bay large-previews the browsing candidate without committing.
#
# The focus topology derived from this geometry is asserted in
# tests/test_frontend_scaling.gd (WP-2 gate: 7/10/11/20/30) and driven for real
# in tests/test_focus_traversal_manifest.gd.
var failures := 0
# The locked Doc 04 §10 table (occupied rows -> station height).
const BAY_HEIGHTS := {1: 420.0, 2: 330.0, 3: 245.0}
const TILE_W := 108.0
const TILE_H := 82.0
const ROW_PITCH := 90.0
const ROSTER_TOP := 96.0
const BAYS_BOTTOM := 690.0
const READY_GAP := 18.0
const PRESENTATION_MIN := 0.70
const PRESENTATION_MAX := 0.78

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(n: int) -> void:
    for i in n:
        await process_frame

func synth(count: int) -> Array:
    var cards: Array = []
    for i in count:
        cards.append({"id": "teknium", "name": "SYNTH %02d" % i})
    return cards

func occupied_rows(count: int) -> int:
    return clampi(int(ceil(float(count) / 10.0)), 1, 3)

func run():
    # WP-0 steps 7-8: the CSS/SSS are hosted by the MatchFlow owner (the
    # in-arena panels are gone); the composition contract is unchanged.
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var host = await vs.enter(self)
    var css = host.char_select()
    check(css != null, "css exists")
    if css == null:
        host.queue_free(); await process_frame; quit(1); return
    await frames(20)
    # --- rejected architecture ---------------------------------------------
    check(css.find_child("HeroRig", true, false) == null, "no global right-side HeroRig region")
    check(css.find_child("HeroFrame", true, false) == null, "no global hero frame")
    var frame: Control = css.find_child("ReferenceFrame", true, false)
    check(frame != null and absf(frame.size.x - 1280.0) < 1.0 and absf(frame.size.y - 720.0) < 1.0,
        "core UI lives in a centered 1280x720 ReferenceFrame")
    var field: Control = css.find_child("RosterField", true, false)
    check(field != null, "the roster field exists")
    var bays: Array = css.get_bays()
    check(bays.size() == 4, "four player bay components exist")
    var band = css.get_ready_band()
    var state = host.selection_state
    # --- the shipped roster occupies ONE row (no dead reserved rows) -------
    var tiles: Array = css.get_tiles()
    check(tiles.size() == 7, "seven roster tiles")
    check(css.roster_rows() == 1, "the shipped seven-fighter roster occupies ONE row")
    check(css.roster_capacity() == 30, "authored capacity stays 10x3 = 30 fighters")
    assert_composition(css, bays, tiles, field, band, frame, 1, 7)
    # --- empty stations recede ---------------------------------------------
    var empty_ok := true
    for i in bays.size():
        if str(state.slots[i]["kind"]) == "empty":
            var bay: Control = bays[i]
            if bay.render_view() != null and bay.render_view().visible:
                empty_ok = false
            if bay.render_area_rect().size.y <= 0.0 or bay.render_area_rect().size.x <= 0.0:
                empty_ok = false
    check(empty_ok, "empty stations recede (no fighter presentation) and keep a valid presentation area")
    # --- candidate large-preview in the active bay (Doc 01 §5 / Doc 04 §12) --
    var hand = root.get_node_or_null("/root/Cursor").hand
    check(hand != null, "cursor service reachable")
    if hand != null:
        var idx := -1
        for i in tiles.size():
            if str(tiles[i].fighter_id) == "ggb":
                idx = i
        check(idx >= 0, "the roster carries ggb for the preview row")
        var motion := InputEventMouseMotion.new()
        motion.position = tiles[idx].get_global_rect().get_center()
        motion.relative = Vector2(24.0, 0.0)
        hand._input(motion)
        css._on_tile_entered(idx)
        await frames(3)
        check(css.get_candidate() == idx, "hovering a tile makes it the candidate")
        var bay0: Control = bays[0]
        check(bay0.presented_fighter() == "ggb", "the active bay LARGE-PREVIEWS the candidate")
        var view = bay0.render_view()
        check(view != null and view.visible, "the previewed candidate is presented by the bay's render view")
        check(view.size.x > 0.0 and view.size.y > 0.0
            and absf(view.size.y - bay0.render_area_rect().size.y) < 1.0,
            "the preview fills the station's presentation area")
        check(str(state.slots[0]["character"]) == "", "previewing never commits the fighter")
        css._leave_field()
        await frames(3)
        check(bay0.presented_fighter() == "", "leaving the roster returns the bay to its committed (blank) state")
    # --- the Ready slot is reserved: showing the band never moves the bays --
    var bay_rest: Rect2 = bays[0].get_global_rect()
    state.slots[0]["character"] = "ggb"
    state.slots[1]["character"] = "doge_man"
    css.refresh_devices()
    await frames(3)
    check(band.is_shown(), "the band shows for the valid configuration")
    check(bays[0].get_global_rect().is_equal_approx(bay_rest), "showing Ready never moves a station (reserved slot)")
    state.slots[1]["character"] = ""
    css.refresh_devices()
    await frames(3)
    check(not band.is_shown(), "the band hides when the configuration becomes invalid")
    check(bays[0].get_global_rect().is_equal_approx(bay_rest), "hiding Ready never moves a station either")
    state.slots[0]["character"] = ""
    # --- occupied-row composition at 7/10/11/20/30 -------------------------
    for count in [10, 11, 20, 30]:
        css.build(synth(count))
        await frames(3)
        var rows := occupied_rows(count)
        check(css.get_tiles().size() == count, "css builds %d synthetic tiles" % count)
        check(css.roster_rows() == rows, "%d fighters occupy %d row(s)" % [count, rows])
        assert_composition(css, css.get_bays(), css.get_tiles(), field, band, frame, rows, count)
    # --- past the authored capacity: tiles never shrink, bays stay minimum --
    css.build(synth(34))
    await frames(3)
    var fixed := true
    for b in css.get_tiles():
        var r: Rect2 = b.get_rect()
        if absf(r.size.x - TILE_W) > 0.01 or absf(r.size.y - TILE_H) > 0.01:
            fixed = false
    check(fixed, "growth past the 10x3 capacity never shrinks a tile (paging design is out of this pass)")
    check(css.roster_rows() == 3, "the composition stays at the 3-row minimum past capacity")
    check(absf(css.get_bays()[0].size.y - BAY_HEIGHTS[3]) < 1.0, "…and the stations stay at the minimum height")
    # restore the real roster for the rest of the suite
    css.build([])
    await frames(3)
    check(css.get_tiles().size() == 7, "the real roster restores")
    check(css.roster_rows() == 1, "…and the composition returns to the one-row geometry")
    host.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: css composition (occupied rows only, fixed 108x82 tiles, locked bay heights, reserved Ready slot, candidate preview)")
    quit(1 if failures else 0)

# --- the ONE composition assertion used at every roster size ----------------
func assert_composition(css, bays: Array, tiles: Array, field: Control, band: Control, frame: Control, rows: int, count: int) -> void:
    var tag := "%d fighters / %d rows" % [count, rows]
    # Every vertical expectation is expressed against the centered 1280x720
    # ReferenceFrame's own origin (the viewport may letterbox it).
    var frame_top: float = frame.get_global_rect().position.y
    var fr: Rect2 = field.get_global_rect()
    # stations: locked height, stable lower line, one tight row, equal widths
    var expected_h: float = BAY_HEIGHTS[rows]
    var expected_top := BAYS_BOTTOM - expected_h
    var station_top := INF
    var bays_ok := true
    for i in bays.size():
        var r: Rect2 = bays[i].get_global_rect()
        station_top = minf(station_top, r.position.y)
        if absf(r.size.y - expected_h) > 1.0 or absf(r.end.y - (frame_top + BAYS_BOTTOM)) > 1.0:
            bays_ok = false
        if i > 0:
            var prev: Rect2 = bays[i - 1].get_global_rect()
            if r.position.x <= prev.position.x or r.position.x - prev.end.x > 24.0:
                bays_ok = false
    check(bays_ok, "%s: the four stations take the locked %d px height on the stable lower line (y %d)" % [
        tag, int(expected_h), int(BAYS_BOTTOM)])
    check(absf(station_top - (frame_top + expected_top)) < 1.0, "%s: the stations top out at y %d" % [tag, int(expected_top)])
    # the fighter presentation owns ~70-78% of the station height
    for i in bays.size():
        var share: float = bays[i].presentation_share()
        check(share >= PRESENTATION_MIN and share <= PRESENTATION_MAX,
            "%s: bay %d fighter presentation owns %.1f%% of the station" % [tag, i, share * 100.0])
    # the roster: only the occupied rows, fixed tiles, contained, no overlaps
    var expected_roster_h: float = float(rows - 1) * ROW_PITCH + TILE_H
    check(absf(field.size.y - (expected_roster_h + 8.0)) < 1.0,
        "%s: the roster field reserves only the %d occupied row(s)" % [tag, rows])
    check(absf(fr.position.y - (frame_top + ROSTER_TOP)) < 1.0, "%s: the first roster row starts at y %d" % [tag, int(ROSTER_TOP)])
    var min_w := 999.0
    var min_h := 999.0
    var in_field := true
    var top := INF
    for t in tiles:
        var r: Rect2 = t.get_global_rect()
        min_w = minf(min_w, r.size.x)
        min_h = minf(min_h, r.size.y)
        top = minf(top, r.position.y)
        if r.position.x < fr.position.x - 0.01 or r.end.x > fr.end.x + 0.01 \
                or r.position.y < fr.position.y - 0.01 or r.end.y > fr.end.y + 0.01:
            in_field = false
    check(in_field, "%s: every tile stays inside the occupied roster field" % tag)
    check(absf(min_w - TILE_W) < 0.01 and absf(min_h - TILE_H) < 0.01,
        "%s: tiles keep the fixed %dx%d reference size" % [tag, int(TILE_W), int(TILE_H)])
    check(absf(top - fr.position.y) < 1.0, "%s: the tiles start at the roster field's own top" % tag)
    var overlaps := 0
    for i in tiles.size():
        for j in range(i + 1, tiles.size()):
            if tiles[i].get_rect().intersects(tiles[j].get_rect()):
                overlaps += 1
    check(overlaps == 0, "%s: no tile overlaps" % tag)
    # Ready: occupied_bottom + 18, inside its reserved slot, never colliding
    var occupied_bottom := ROSTER_TOP + expected_roster_h
    var br: Rect2 = band.get_global_rect()
    check(absf(br.position.y - (fr.position.y + expected_roster_h + READY_GAP)) < 1.0,
        "%s: Ready sits at the occupied bottom + %d" % [tag, int(READY_GAP)])
    check(br.end.y <= station_top - 1.0, "%s: the Ready slot clears the stations" % tag)
    check(br.end.y <= frame_top + BAYS_BOTTOM and br.position.y > frame_top, "%s: Ready stays inside the reference frame" % tag)
    check(fr.end.y <= br.position.y + 0.01, "%s: the roster and Ready never overlap" % tag)
    check(fr.end.y < station_top, "%s: the roster sits above the stations" % tag)
    check(css.roster_rows() == rows, "%s: the composition reports the occupied rows" % tag)
