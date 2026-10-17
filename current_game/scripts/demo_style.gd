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
const CONTROLS = "P1  WASD move / aim · Space or W jump\n    F basic · G special\n\nP2  Arrows move / aim · Enter or Up jump\n    K basic · L special\n\nPAD Stick / D-pad aim · A jump · X basic\n    B special\n\nDirection + attack changes your move.\nTap down on an upper platform to drop.\nEsc: pause · R after winner: rematch.\nOptions → Dev Mode · Connect pads before launch.\nWeaver: C repair cycle · T repeat toggle.\nNo universal shield; defensive specials remain.\nTouch: pad + Attack/Special; Up jumps."
const MOVES = "LEDGES (Tek, Doge, Turbo) · auto-grab\n  ↑/toward climb · Space jump · ↓ drop\nTEKNIUM · F jab > straight > scoop kick\n  G Laser Blast, works in air; jump or G again\n  before the white flash cancels\n  ↔+G Shadow Kick · ↑+G aim recovery\n  ↓+G remote grenade; next fresh ↓+G detonates\nDOGE MAN · F combo · hold ↓ all-fours\n  ↓+fresh F bark; air ↔+F dropkick · ↔+G tackle\n  G Super Doge Punch: tap, committed windup\n  Ground only; no hold-charge or early cancel\n  ↑+G Air Doge: Jordan leap, catch + spike down\n  ↓+G finite counter, hit during flash: hook\nGGB · Five jumps; hold jump to float\n  F double chomp · ↔+F short sting\n  G sticky goo · ↔+G Wing Gust (no damage)\n  ↑+G wing rise / flip / dive / ripple\n  ↓+G Steel: 3s max, 40% resist; any hit breaks\nTURBOFIT · G charged chord · ↔+G wave\n  ↑+G Snapline grapple\n  Ground: hold Down+Special for Sound Orb\n  Release either to end; interruption ends it\n  Reflects projectiles; not melee immunity\nBOBO · G Charge Blast · ↔+G Rocket Dash\n  ↑+G Thruster Rise · ↔+F Thrust Slash\n  Ground ↓+F Low Claw\n  Air Down+basic: Claw Hammer Drop\nMEPHISTO · air ↓+F Meteor Heel · G barrier\n  ↔+G ember\n  ↑+G paired teleport · ↓+G Dream Hand (sleep)\nWITCHEER · F cane swipe · ↑+F rising cane\n  Ground ↔+F kicks · ↓+F low cane poke\n  Hold ↓ crouch; release to rise; fresh F only\n  Platforms: ↓ drops first; air basics unchanged\n  ↔+G coin · ↑+G swim · ↓+G absorb\nICE MAGE (CPU) · G Frost Bolt · ↑+G Frost Rise"
const KEY_TEXTURE = preload("res://assets/menu/help_key_legend.png")
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
        var scroll := ScrollContainer.new()
        scroll.name = "ControlsScroll" if i == 0 else "MovesScroll"
        scroll.position = Vector2(60+i*590,105)
        scroll.size = Vector2(560,375 if i == 0 else 510)
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        page.add_child(scroll)
        label.position = Vector2.ZERO
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(label)
    # Key legend has a reserved lower-left area outside the controls viewport.
    var key := TextureRect.new()
    key.name = "HelpKeyLegend"
    key.texture = KEY_TEXTURE
    key.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    key.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    key.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    key.position = Vector2(66,492)
    key.size = Vector2(540,130)
    key.mouse_filter = Control.MOUSE_FILTER_IGNORE
    page.add_child(key)
    var back := Button.new()
    back.text = "Back"
    back.name = "HelpBack"
    back.position = Vector2(60,630)
    back.size = Vector2(250,50)
    page.add_child(back)
    back.pressed.connect(func(): page.queue_free(); closed.call())
    back.grab_focus()
    return page
