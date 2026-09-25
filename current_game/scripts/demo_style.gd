extends RefCounted
const CREAM = Color("fff0cb")
const TEAL = Color("284e50")
static func make() -> Theme:
    var t := Theme.new()
    var f = preload("res://assets/fonts/ZillaSlab-Bold.ttf")
    t.default_font = f
    t.default_font_size = 18
    for type in ["Label", "Button", "OptionButton", "PopupMenu", "CheckButton"]:
        t.set_color("font_color", type, CREAM)
        t.set_color("font_hover_color", type, CREAM)
        t.set_color("font_focus_color", type, CREAM)
    for type in ["Button", "OptionButton"]:
        t.set_stylebox("normal",type,box(Color("284e50")))
        t.set_stylebox("hover",type,box(Color("416b69")))
        t.set_stylebox("pressed",type,box(Color("956442")))
        t.set_stylebox("disabled",type,box(Color("302e29")))
        t.set_stylebox("focus",type,box(Color.TRANSPARENT,Color("e5ad69"),2))
    t.set_stylebox("panel", "PopupMenu", box(Color("263d3d")))
    return t
static func box(color: Color, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = color
    s.border_color = border
    s.set_border_width_all(width)
    s.set_corner_radius_all(8)
    s.content_margin_left = 14
    s.content_margin_right = 14
    s.content_margin_top = 8
    s.content_margin_bottom = 8
    return s
const CONTROLS = "P1  WASD move / aim · Space or W jump\n    F basic · G special\n\nP2  Arrows move / aim · Enter or Up jump\n    K basic · L special\n\nPAD Stick / D-pad aim · A jump · X basic\n    B special\n\nDirection + attack changes your move.\nTap down on an upper platform to drop.\nEsc: match setup · R after winner: rematch.\nConnect controllers before launching.\nNo universal shield; defensive specials remain.\nTouch: pad + Attack/Special; Up jumps."
const MOVES = "TEKNIUM · G hold/release charge shot\nWhile charging: fresh direction stores; Up/Jump jumps\nRelease, press G to resume; initial chords stay specials\nA/D+G Shadow Kick · W+G aim recovery\nS+G grenade; next fresh S+G detonates\n\nDOGE MAN · S+G finite counter, hit during flash: hook\nA/D+G flying tackle · airborne A/D+F Superman\n\nGGB REVIEW · Five jumps; hold jump to float\nF double chomp · A/D+F short sting\nG sticky goo · Side+G UNASSIGNED\nW+G wing rise / flip / dive / ripple\nS+G Steel; release G, fresh S+G cancels\nSteel: 3s max, 40% resistance; any hit breaks\nTURBOFIT · G charged chord · A/D+G wave\nS+G sound reflector · W+G recovery\n\nMEPHISTO · Girl G barrier · A/D+G ember\nW+G paired teleport · ground S+G switches lead\nDemon G smoke · A/D+G chain · W+G paired vanish\nICE MAGE · G Frost Bolt · W+G Frost Rise\nWITCHEER · A/D+G coin · W+G swim · S+G absorb"
static func help(parent: Control, closed: Callable) -> Control:
    var page := Panel.new()
    page.name = "HelpPage"
    page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    page.add_theme_stylebox_override("panel",box(Color("252c28")))
    parent.add_child(page)
    var title := Label.new()
    title.text = "HOW TO PLAY"
    title.position = Vector2(60,36)
    title.add_theme_font_size_override("font_size",32)
    page.add_child(title)
    for i in 2:
        var label := Label.new()
        label.text = CONTROLS if i == 0 else MOVES
        label.position = Vector2(60+i*590,105)
        label.size = Vector2(560,480)
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.add_theme_font_size_override("font_size",18 if i == 0 else 16)
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
