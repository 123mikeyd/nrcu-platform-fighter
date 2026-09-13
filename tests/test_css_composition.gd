extends SceneTree
# CSS composition contract (visual spec §13): four regions, reserved selection
# gutter, stable scalable cells, structural player color. Runs the screen in
# isolation (no arena), so it stays fast and independent of the other screens.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var Roster = load("res://scripts/roster.gd")
    var Tokens = load("res://scripts/ui_tokens.gd")
    var css = load("res://scripts/char_select.gd").new()
    css.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(css)
    await process_frame
    var cards: Array = []
    for id in Roster.ids():
        cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper(), "palette": Roster.palette(str(id), 0)})
    css.build(cards)
    await process_frame
    var state = load("res://scripts/match_selection_state.gd").new()
    css.open_with(state)
    for i in 40: await process_frame
    check(css.get_cards().size() == 7, "roster builds seven cells")
    # regions
    check(css.find_child("HeroRig", true, false) != null, "hero region exists")
    check(css.find_child("FighterName", true, false) != null, "fighter name exists")
    check(css.find_child("PanelBox0", true, false) != null and css.find_child("PanelBox3", true, false) != null, "four player bays exist")
    check(css.find_child("ModeToggle", true, false) != null and css.find_child("ReadyButton", true, false) != null, "header controls exist")
    # roster cells stay inside the reserved field and keep compact scale
    var min_w := 999.0
    var in_field := true
    var max_y := 0.0
    for b in css.get_cards():
        var r: Rect2 = b.get_rect()
        min_w = minf(min_w, r.size.x)
        max_y = maxf(max_y, r.end.y)
        if r.position.x < 0.0 or r.end.x > 660.0 or r.position.y < 100.0 or r.end.y > 545.0:
            in_field = false
    check(in_field, "cells stay inside the roster field (left of the hero)")
    check(min_w >= 60.0 and min_w <= 160.0, "seven cells keep compact scale (%.0f px)" % min_w)
    check(max_y <= 545.0, "roster never runs into the player bays")
    # hero region sits in the right half and never overlaps the roster
    var hero: Control = css.find_child("HeroRig", true, false)
    check(hero.position.x >= 660.0, "hero region is the right half")
    check(hero.size.x >= 400.0 and hero.size.y >= 280.0, "hero region has real presence")
    # selection plate grows into the reserved gutter only
    css.hover_slot(0)
    await process_frame
    var box: Panel = css.find_child("SelectBox", true, false)
    var card0: Button = css.get_cards()[0]
    check(box.visible, "selection plate follows the hover")
    var overhang: float = card0.get_rect().position.y - box.position.y
    check(overhang > 0.0 and overhang <= Tokens.SELECTION_GUTTER / 2.0, "plate stays inside the reserved gutter (%.1f px)" % overhang)
    var plate_gap: float = card0.get_rect().position.x - box.position.x
    check(not box.get_rect().intersects(css.get_cards()[1].get_rect().grow(-1.0)), "plate never reaches the neighbouring cell")
    # player color is structural: the bay carries a 6 px left bar in its color
    var bay: Button = css.find_child("PanelBox0", true, false)
    var bay_style: StyleBoxFlat = bay.get_theme_stylebox("normal")
    check(bay_style != null and bay_style.border_width_left >= 4, "bay header carries a structural player-color bar")
    # bays span the design canvas without drifting past the margin
    var bay3: Button = css.find_child("PanelBox3", true, false)
    check(bay3.position.x + bay3.size.x <= Tokens.DESIGN.x - Tokens.MARGIN + 1.0, "four bays fit the design width")
    css.queue_free()
    await process_frame
    if failures == 0: print("PASS: css composition (four regions, gutter-safe selection, bay structure)")
    quit(1 if failures else 0)
