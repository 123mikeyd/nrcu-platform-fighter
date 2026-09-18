extends Node
# Flow probe: reproduce the live route home -> PLAY -> main -> CSS and print
# the state of the character select after the scene change. Windowed run only.
func _ready() -> void:
    call_deferred("run")

func run() -> void:
    var home = load("res://scenes/home.tscn").instantiate()
    get_tree().root.add_child(home)
    get_tree().current_scene = home
    for i in 40: await get_tree().process_frame
    print("[probe] home in tree; children=", home.get_child_count())
    var play = home.find_child("MenuRow_Play", true, false)
    print("[probe] play row: ", play)
    var hit: Button = null
    if play != null:
        hit = play.get_node_or_null("HitArea")
    print("[probe] hit area: ", hit)
    if hit != null:
        hit.pressed.emit()
        print("[probe] play pressed")
    for i in 150: await get_tree().process_frame
    var cur = get_tree().current_scene
    print("[probe] current scene: ", cur.name if cur != null else "null")
    var main = cur
    if main != null:
        var panel = main.get("char_panel")
        print("[probe] char_panel=", panel, " visible=", panel.visible if panel != null else "?")
        var css = null
        if panel != null:
            css = panel.find_child("CharSelect", true, false)
        print("[probe] css=", css)
        if css != null:
            print("[probe] phase=", css.get_phase())
            var frame = css.get_node_or_null("ReferenceFrame")
            if frame != null:
                print("[probe] frame modulate.a=", frame.modulate.a, " visible=", frame.visible)
            var field = css.get_node_or_null("Field")
            if field != null:
                print("[probe] field modulate.a=", field.modulate.a, " color=", field.color if field is ColorRect else "?")
            print("[probe] tiles=", css.get_tiles().size())
    var vp := get_viewport()
    await RenderingServer.frame_post_draw
    var img := vp.get_texture().get_image()
    if img != null:
        var shot_dir: String = ProjectSettings.globalize_path("res://.verification")
        DirAccess.make_dir_recursive_absolute(shot_dir)
        var shot_path: String = shot_dir.path_join("flow_probe.png")
        img.save_png(shot_path)
        print("[probe] shot saved")
    get_tree().quit(0)
