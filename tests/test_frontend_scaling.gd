extends SceneTree
# Frontend scalability — the WP-2 gate (Doc 04 §10/§15, Doc 08 §5, ledger
# C-050/C-051): the Character Select composition AND its focus topology must be
# valid at 7 / 10 / 11 / 20 / 30 fighters.
#
# For every size the suite RE-DERIVES the expected directional topology from the
# resolved Control rectangles (nearest x-center inside each semantic zone, never
# index arithmetic or modulo) and compares it with the neighbours the screen
# generated, then proves the whole focusable surface stays connected.
#
#   within a row        left/right = the adjacent tile in that row (no wrap)
#   between rows        up/down    = the nearest x-center in the adjacent
#                                    occupied row
#   top roster row      up         = the nearest header destination by x
#   bottom roster row   down       = Ready while shown, else the nearest bay by x
#   bay                 up         = the nearest bottom-row tile by x
#   Ready               up / down  = the nearest bottom-row tile / bay
#
# SSS keeps its frozen field/preview separation.
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const SIZES := [7, 10, 11, 20, 30]
const BAY_HEIGHTS := {1: 420.0, 2: 330.0, 3: 245.0}
const TILE_W := 108.0
const TILE_H := 82.0
const ROW_PITCH := 90.0
const BAYS_BOTTOM := 690.0
const READY_GAP := 18.0
const DIRECTIONS := ["top", "bottom", "left", "right", "next", "previous"]

var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(n: int) -> void:
    for i in n:
        await process_frame

# --- geometry helpers (the expected topology is re-derived here) ------------
func rows_of(tiles: Array) -> Array:
    # Occupied rows from the RESOLVED rectangles: tiles whose centers agree.
    var ordered: Array = []
    for i in tiles.size():
        ordered.append(i)
    ordered.sort_custom(func(a, b):
        var ca: Vector2 = (tiles[a] as Control).get_global_rect().get_center()
        var cb: Vector2 = (tiles[b] as Control).get_global_rect().get_center()
        if absf(ca.y - cb.y) > 1.0:
            return ca.y < cb.y
        return ca.x < cb.x)
    var rows: Array = []
    var current: Array = []
    for i in ordered:
        if current.is_empty():
            current.append(i)
            continue
        var row_y: float = (tiles[current[0]] as Control).get_global_rect().get_center().y
        var y: float = (tiles[i] as Control).get_global_rect().get_center().y
        if absf(y - row_y) > TILE_H * 0.5:
            rows.append(current)
            current = []
        current.append(i)
    if not current.is_empty():
        rows.append(current)
    return rows

func center_x(control: Control) -> float:
    return control.get_global_rect().get_center().x

func nearest_by_x(controls: Array, x: float) -> Control:
    var best: Control = null
    var best_d := INF
    for control in controls:
        if control == null or not is_instance_valid(control):
            continue
        var d: float = absf(center_x(control) - x)
        if d < best_d:
            best_d = d
            best = control
    return best

func row_controls(tiles: Array, row: Array) -> Array:
    var out: Array = []
    for i in row:
        out.append(tiles[i])
    return out

func focusable(control: Control) -> bool:
    return control != null and is_instance_valid(control) and control.is_visible_in_tree() \
        and control.focus_mode != Control.FOCUS_NONE

func synth(count: int) -> Array:
    # Synthetic roster entries keep the canonical ids so portraits/presentations
    # stay real while the SIZE is what is under test.
    var ids: Array = load("res://scripts/roster.gd").ids()
    var cards: Array = []
    for i in count:
        var id := str(ids[i % ids.size()])
        cards.append({"id": id, "name": "%s %02d" % [id.to_upper(), i]})
    return cards

# --- the WP-2 gate: geometry + focus validity at one roster size ------------
func assert_geometry(tiles: Array, bays: Array, field: Control, band: Control, frame: Control, count: int) -> void:
    var tag := "%d fighters" % count
    # Every vertical expectation is expressed against the centered 1280x720
    # ReferenceFrame's own origin (the viewport may letterbox it).
    var frame_top: float = frame.get_global_rect().position.y
    var rows := clampi(int(ceil(float(count) / 10.0)), 1, 3)
    var expected_h: float = BAY_HEIGHTS[rows]
    # tiles: fixed 108x82, contained in the occupied field, no overlaps
    var fr: Rect2 = field.get_global_rect()
    var in_field := true
    var min_w := 999.0
    var min_h := 999.0
    for t in tiles:
        var r: Rect2 = t.get_global_rect()
        min_w = minf(min_w, r.size.x)
        min_h = minf(min_h, r.size.y)
        if r.position.x < fr.position.x - 0.01 or r.end.x > fr.end.x + 0.01 \
                or r.position.y < fr.position.y - 0.01 or r.end.y > fr.end.y + 0.01:
            in_field = false
    check(in_field, "%s: every tile stays inside the occupied roster field" % tag)
    check(absf(min_w - TILE_W) < 0.01 and absf(min_h - TILE_H) < 0.01,
        "%s: tiles never shrink below %dx%d" % [tag, int(TILE_W), int(TILE_H)])
    check(absf(field.size.y - (float(rows - 1) * ROW_PITCH + TILE_H + 8.0)) < 1.0,
        "%s: the roster field reserves exactly %d occupied row(s)" % [tag, rows])
    var overlaps := 0
    for i in tiles.size():
        for j in range(i + 1, tiles.size()):
            if (tiles[i] as Control).get_rect().intersects((tiles[j] as Control).get_rect()):
                overlaps += 1
    check(overlaps == 0, "%s: no two roster tiles overlap" % tag)
    # stations: locked height, stable lower line, no overlap with each other
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
    check(bays_ok, "%s: the stations take the locked %d px height on the stable lower line" % [tag, int(expected_h)])
    # Ready: the reserved slot sits between the roster and the stations
    var br: Rect2 = band.get_global_rect()
    check(absf(br.position.y - (fr.position.y + float(rows - 1) * ROW_PITCH + TILE_H + READY_GAP)) < 1.0,
        "%s: Ready sits at the occupied bottom + %d" % [tag, int(READY_GAP)])
    check(fr.end.y <= br.position.y + 0.01 and br.end.y <= station_top - 1.0,
        "%s: the reserved Ready slot never collides with the roster or the stations" % tag)

func assert_focus_validity(css, tiles: Array, bays: Array, header: Array, band: Control) -> void:
    var count: int = tiles.size()
    var tag := "%d fighters" % count
    var rows := rows_of(tiles)
    var top_row: Array = row_controls(tiles, rows[0])
    var bottom_row: Array = row_controls(tiles, rows[rows.size() - 1])
    var band_shown: bool = band.is_shown()
    check(css.roster_rows() == rows.size(), "%s: the composition agrees with the occupied rows" % tag)
    # every neighbour is a LIVE focusable control (never a hidden leftover)
    var all: Array = []
    all.append_array(tiles)
    all.append_array(bays)
    all.append_array(header)
    all.append(band)
    for bay in bays:
        all.append_array(bay.state_controls())
    for control in all:
        for direction in DIRECTIONS:
            var neighbour := FocusGraph.neighbour(control, StringName(direction))
            if neighbour == null:
                continue
            check(all.has(neighbour), "%s: %s.%s points at a live control" % [tag, str(control.get_path()).get_file(), direction])
            check(focusable(neighbour), "%s: %s.%s target is focusable" % [tag, str(control.get_path()).get_file(), direction])
    # roster: in-row runs and adjacent-row up/down, both re-derived from rects
    for r in rows.size():
        var row: Array = rows[r]
        for j in row.size():
            var tile: Control = tiles[row[j]]
            var left := FocusGraph.neighbour(tile, &"left")
            var right := FocusGraph.neighbour(tile, &"right")
            if j > 0:
                check(left == tiles[row[j - 1]], "%s: %s.left is the adjacent tile in its row" % [tag, str(tile.get_path()).get_file()])
            else:
                check(left == null, "%s: the first tile of a row has no left (no wrap)" % tag)
            if j + 1 < row.size():
                check(right == tiles[row[j + 1]], "%s: %s.right is the adjacent tile in its row" % [tag, str(tile.get_path()).get_file()])
            else:
                check(right == null, "%s: the last tile of a row has no right (no wrap)" % tag)
            var cx: float = center_x(tile)
            var up := FocusGraph.neighbour(tile, &"top")
            var down := FocusGraph.neighbour(tile, &"bottom")
            if r > 0:
                check(up == nearest_by_x(row_controls(tiles, rows[r - 1]), cx),
                    "%s: %s.top is the nearest tile of the row above" % [tag, str(tile.get_path()).get_file()])
            else:
                check(header.has(up) and up == nearest_by_x(header, cx),
                    "%s: %s.top is the nearest header destination by x" % [tag, str(tile.get_path()).get_file()])
            if r + 1 < rows.size():
                check(down == nearest_by_x(row_controls(tiles, rows[r + 1]), cx),
                    "%s: %s.bottom is the nearest tile of the row below (never a skipped row)" % [tag, str(tile.get_path()).get_file()])
            elif band_shown:
                check(down == band, "%s: the bottom row exits into the shown Ready band" % tag)
            else:
                check(down == nearest_by_x(bays, cx),
                    "%s: %s.bottom is the nearest station by x" % [tag, str(tile.get_path()).get_file()])
    # stations: up into the ACTUAL bottom row (never tiles 0..3 by index)
    for bay in bays:
        check(FocusGraph.neighbour(bay, &"top") == nearest_by_x(bottom_row, center_x(bay)),
            "%s: %s.top is the nearest bottom-row tile by x" % [tag, str(bay.get_path()).get_file()])
    # Ready: the intermediate row between the bottom roster row and the stations
    check(FocusGraph.neighbour(band, &"top") == nearest_by_x(bottom_row, center_x(band)),
        "%s: Ready.top is the nearest bottom-row tile by x" % tag)
    check(FocusGraph.neighbour(band, &"bottom") == nearest_by_x(bays, center_x(band)),
        "%s: Ready.bottom is the nearest station by x" % tag)
    # header: the authored chain by x, each owning the tile under it
    var by_x: Array = header.duplicate()
    by_x.sort_custom(func(a, b): return center_x(a) < center_x(b))
    for i in by_x.size():
        if i + 1 < by_x.size():
            check(FocusGraph.neighbour(by_x[i], &"right") == by_x[i + 1], "%s: header destinations follow x" % tag)
        else:
            check(FocusGraph.neighbour(by_x[i], &"right") == null, "%s: the header chain does not wrap" % tag)
        check(FocusGraph.neighbour(by_x[i], &"bottom") == nearest_by_x(top_row, center_x(by_x[i])),
            "%s: %s.bottom is the nearest top-row tile by x" % [tag, str(by_x[i].get_path()).get_file()])
    # Tab order: header, roster, stations — explicit, never tree order
    for i in tiles.size():
        var tile: Control = tiles[i]
        var expected_next: Control = tiles[i + 1] if i + 1 < tiles.size() else bays[0]
        var expected_prev: Control = tiles[i - 1] if i > 0 else by_x[by_x.size() - 1]
        check(FocusGraph.neighbour(tile, &"next") == expected_next, "%s: Tab order runs the roster then the stations" % tag)
        check(FocusGraph.neighbour(tile, &"previous") == expected_prev, "%s: Shift-Tab order is the exact reverse" % tag)
    # connectivity: every focusable control of the composition is reachable
    var seen: Array = []
    var queue: Array = [tiles[0]]
    seen.append(tiles[0])
    while not queue.is_empty():
        var node: Control = queue.pop_front()
        for direction in DIRECTIONS:
            var neighbour := FocusGraph.neighbour(node, StringName(direction))
            if neighbour == null or seen.has(neighbour):
                continue
            seen.append(neighbour)
            queue.append(neighbour)
    var reachable_missing := 0
    var required: Array = []
    required.append_array(tiles)
    required.append_array(bays)
    required.append_array(header)
    for bay in bays:
        required.append_array(bay.state_controls())
    if band_shown:
        required.append(band)
    for control in required:
        if not seen.has(control):
            reachable_missing += 1
            printerr("        unreachable: %s" % str(control.get_path()))
    check(reachable_missing == 0, "%s: every roster/station/header control is reachable from the roster (%d missing)" % [tag, reachable_missing])

func run():
    # WP-0 steps 7-8: the CSS/SSS are hosted by the MatchFlow owner (the
    # in-arena panels are gone); the scaling contract is unchanged.
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var host = await vs.enter(self)
    var css = host.char_select()
    check(css != null, "css exists")
    if css == null:
        host.queue_free(); await process_frame; quit(1); return
    var field: Control = css.find_child("RosterField", true, false)
    var frame: Control = css.find_child("ReferenceFrame", true, false)
    var band = css.get_ready_band()
    var state = host.selection_state
    var header: Array = [
        css.find_child("ModeFree", true, false),
        css.find_child("ModeTeams", true, false),
        css.find_child("BackAction", true, false),
    ]
    check(header[0] != null and header[1] != null and header[2] != null, "the header destinations resolve")
    # --- the WP-2 gate: 7/10/11/20/30 --------------------------------------
    for count in SIZES:
        css.build(synth(count))
        await frames(4)
        var tiles: Array = css.get_tiles()
        var bays: Array = css.get_bays()
        check(tiles.size() == count, "css builds %d roster tiles" % count)
        assert_geometry(tiles, bays, field, band, frame, count)
        # band hidden (the fresh configuration): the bottom row exits to a bay
        check(not band.is_shown(), "%d fighters: the fresh configuration shows no Ready band" % count)
        var bay_rest: Rect2 = bays[0].get_global_rect()
        assert_focus_validity(css, tiles, bays, header, band)
        # band shown (a valid configuration): the SAME geometry, the band added
        state.slots[0]["character"] = str(load("res://scripts/roster.gd").ids()[0])
        state.slots[1]["character"] = str(load("res://scripts/roster.gd").ids()[1])
        css.refresh_devices()
        await frames(3)
        check(band.is_shown(), "%d fighters: the band shows for a valid configuration" % count)
        check(bays[0].get_global_rect().is_equal_approx(bay_rest),
            "%d fighters: the reserved Ready slot never moves the stations" % count)
        assert_focus_validity(css, tiles, bays, header, band)
        state.slots[0]["character"] = ""
        state.slots[1]["character"] = ""
        css.refresh_devices()
        await frames(2)
    css.build([])
    await frames(3)
    check(css.get_tiles().size() == 7 and css.roster_rows() == 1, "the real roster restores at one occupied row")
    # --- SSS: synthetic stage lists keep the tile/preview regions ---------
    var css2 = host.char_select()
    # Locked fresh defaults (Doc 01 §2): no preselection, and the ONE ready
    # authority requires every active slot to own a fighter — the minimal
    # valid VS state (P1 Human + P2 CPU) opens the stage page.
    host.selection_state.slots[0]["character"] = "ggb"
    host.selection_state.slots[1]["character"] = "doge_man"
    css2.ready_requested.emit()
    var opened: bool = await vs.wait_for(self, func() -> bool: return host.is_surface_presented("sss"), 240)
    check(opened, "stage page opens through the production route")
    var sss = host.stage_select()
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
    host.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: frontend scalability (CSS 7/10/11/20/30 occupied-row geometry + focus validity, SSS 3/6/12/20, stations stable)")
    quit(1 if failures else 0)
