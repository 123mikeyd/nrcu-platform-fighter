extends RefCounted
# Legacy theme helper — now a thin delegate over the canonical token theme
# (Doc 08/09: no Courier New, no rounded generic Button chrome).
#
# The `help()` page and the CONTROLS/MOVES strings below are the OLD
# prototype How-to-Play; they are replaced by the structured How to Play
# screen during the secondary-surfaces work package and removed afterwards.

const Tokens = preload("res://scripts/ui_tokens.gd")

static func make() -> Theme:
    return Tokens.make_theme()

static func box(color: Color, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
    return Tokens.flat(color, border, width, Tokens.RADIUS_PLATE)

const CONTROLS = "P1  WASD move / aim · Space or W jump\n    F basic · G special · E shield\n\nP2  Arrows move / aim · Enter or Up jump\n    K basic · L special · O shield\n\nPAD Stick / D-pad aim · A jump · X basic\n    B special · shoulder shield\n\nDirection + attack changes your move.\nTap down on an upper platform to drop.\nEsc: match setup · R after winner: rematch.\nConnect controllers before launching."
const MOVES = "TEKNIUM\nG hold/release charge shot · Space/E stores\nA/D+G Shadow Kick · W+G charge, aim recovery\nS+G holy grenade · next fresh S+G remote detonate\n\nDOGE MAN\nS+G Counter: brief stance, retaliates on incoming hit\nA/D+G flying tackle · jump then F Superman punch\n\nGGB\nFive jumps · hold jump to float\nA/D + G sticky goo · S + G steel/normal toggle\nSteel fast-drops, stays planted; tap S+G again to move\n\nTURBOFIT\nBasic strikes and sound attacks\n\nICE MAGE\nF palm · G Frost Bolt · W + G Frost Rise\n\nWITCHEER\nF kick/punch · ground S+F sweep · air W+F up basic\nA/D+G coin · W+G swim · G celebrate · S+G absorb/heal"

static func help(parent: Control, closed: Callable) -> Control:
    # LEGACY prototype page (replaced by the structured How to Play screen).
    var page := Panel.new()
    page.name = "HelpPage"
    page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    page.add_theme_stylebox_override("panel", box(Color("252c28")))
    parent.add_child(page)
    var title := Label.new()
    title.text = "HOW TO PLAY"
    title.position = Vector2(60,36)
    title.add_theme_font_size_override("font_size", Tokens.T_SCREEN)
    page.add_child(title)
    for i in 2:
        var label := Label.new()
        label.text = CONTROLS if i == 0 else MOVES
        label.position = Vector2(60+i*590,105)
        label.size = Vector2(560,480)
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.add_theme_font_size_override("font_size", Tokens.T_HELP)
        page.add_child(label)
    var back := Button.new()
    back.text = "Back"
    back.name = "HelpBack"
    back.position = Vector2(60,630)
    back.size = Vector2(250,50)
    page.add_child(back)
    back.pressed.connect(func(): page.queue_free(); closed.call())
    back.grab_focus()
    return page
