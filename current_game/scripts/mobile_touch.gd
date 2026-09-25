extends CanvasLayer
# P1-only touch state, independent of keyboard/gamepad state. Never synthesize keys.
var touch_mode := false
var gameplay_enabled := false
var contacts: Dictionary = {}
var surface: Control
var scene_id := 0
var rotate_pause_owned := false
var web_cancel_callback

func _web_cancel(_arguments: Array) -> void:
    cancel_contacts()

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 40
    process_priority = -100
    touch_mode = DisplayServer.is_touchscreen_available()
    surface = TouchSurface.new()
    surface.owner_pad = self
    surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(surface)
    get_viewport().size_changed.connect(cancel_contacts)
    if OS.has_feature("web"):
        # Web touchcancel can reach Godot as an ordinary release. Capture the
        # DOM cancellation first so it stores/aborts rather than firing a charge.
        web_cancel_callback = JavaScriptBridge.create_callback(_web_cancel)
        JavaScriptBridge.get_interface("window").addEventListener("touchcancel", web_cancel_callback, true)

func _process(_delta: float):
    var scene = get_tree().current_scene
    var next_id: int = scene.get_instance_id() if is_instance_valid(scene) else 0
    if next_id != scene_id:
        cancel_contacts()
        scene_id = next_id

    var active := false
    if is_instance_valid(scene) and scene.has_method("start_match"):
        active = not scene.setup.visible and not scene.story_panel.visible and scene.screen in ["battle","freeplay","practice"] and not scene.match_over and is_instance_valid(scene.player_one) and scene.player_one.controls_enabled and scene.player_one.control_type == "human" and scene.player_one.player_index == 1
    # Own only our rotate pause; never resume a player's existing Pause menu.
    var rotate_block := touch_mode and portrait() and active
    if rotate_block and not get_tree().paused:
        cancel_contacts()
        get_tree().paused = true
        rotate_pause_owned = true
    elif rotate_pause_owned and not rotate_block:
        get_tree().paused = false
        rotate_pause_owned = false
    set_gameplay_enabled(active and not get_tree().paused and not portrait())
    if surface: surface.queue_redraw()

func portrait() -> bool:
    var dimensions := get_window().size
    return dimensions.y > dimensions.x

class TouchSurface extends Control:
    var owner_pad
    func _draw():
        if not owner_pad.touch_mode: return
        var v := get_viewport_rect().size
        var font := ThemeDB.fallback_font
        if owner_pad.portrait():
            draw_rect(Rect2(Vector2.ZERO,v), Color(0.03,0.05,0.08,0.92))
            draw_string(font,Vector2(v.x/2-250,v.y/2),"Rotate your phone to landscape",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color.WHITE)
            return
        if not owner_pad.gameplay_enabled: return
        var zones: Dictionary = owner_pad.regions(v)
        var state: Dictionary = owner_pad.controls()
        var base := Color(0.07,0.13,0.19,0.70)
        var edge := Color(0.65,0.85,1,0.80)
        draw_circle(zones.pad,110,base)
        draw_arc(zones.pad,110,0,TAU,64,edge,3,true)
        for item in [["<",Vector2(-79,9),state.left],[">",Vector2(64,9),state.right],["UP",Vector2(-17,-61),state.up],["DOWN",Vector2(-32,81),state.down]]:
            draw_string(font,zones.pad + item[1],item[0],HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color(1,0.85,0.3) if item[2] else Color.WHITE)
        draw_string(font,zones.pad + Vector2(-37,8),"MOVE",HORIZONTAL_ALIGNMENT_LEFT,-1,20,edge)
        for role in ["attack","special"]:
            draw_circle(zones[role],66,Color(0.35,0.45,0.16,0.85) if state[role] else base)
            draw_arc(zones[role],66,0,TAU,48,edge,3,true)
            draw_string(font,zones[role]+Vector2(-39,8),role.capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color.WHITE)
        draw_style_box(menu_style(),Rect2(v.x-150,20,126,52))
        draw_string(font,Vector2(v.x-133,53),"Pause",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color.WHITE)
    func menu_style() -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = Color(0.06,0.10,0.14,0.85)
        box.set_corner_radius_all(10)
        return box

func regions(view_size: Vector2) -> Dictionary:
    return {"pad": Vector2(156, view_size.y - 152), "attack": Vector2(view_size.x - 250, view_size.y - 118), "special": Vector2(view_size.x - 105, view_size.y - 205)}

func set_gameplay_enabled(enabled: bool):
    if gameplay_enabled != enabled: cancel_contacts()
    gameplay_enabled = enabled

func cancel_contacts():
    var held_special := false
    for contact in contacts.values():
        held_special = held_special or contact.role == "special"
    if held_special and is_inside_tree():
        var scene = get_tree().current_scene
        if is_instance_valid(scene) and scene.has_method("start_match") and is_instance_valid(scene.player_one):
            scene.player_one.cancel_touch_charge()
    contacts.clear()

func _notification(what: int):
    if what in [MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_PAUSED]:
        cancel_contacts()

func _exit_tree():
    if web_cancel_callback:
        JavaScriptBridge.get_interface("window").removeEventListener("touchcancel", web_cancel_callback, true)
    cancel_contacts()

func controls() -> Dictionary:
    var state := {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false, "shield": false}
    if not gameplay_enabled: return state
    for contact in contacts.values():
        if contact.role == "pad":
            var direction: Vector2 = contact.point - regions(get_viewport().get_visible_rect().size).pad
            state.left = direction.x < -30
            state.right = direction.x > 30
            state.up = direction.y < -30
            state.down = direction.y > 30
        else:
            state[contact.role] = true
    return state

func _input(event: InputEvent):
    # Godot's native touch->mouse route keeps Buttons and PopupMenus tappable.
    # Stop its emulated events at the rotate guard rather than clicking through it.
    if event is InputEventMouse and touch_mode and (portrait() or (gameplay_enabled and event.device == -1)):
        get_viewport().set_input_as_handled()
        return
    if event is InputEventScreenDrag:
        if contacts.has(event.index):
            contacts[event.index].point = event.position
            get_viewport().set_input_as_handled()
        return
    if not event is InputEventScreenTouch: return
    touch_mode = true
    if portrait():
        cancel_contacts()
        get_viewport().set_input_as_handled()
        return
    if not gameplay_enabled:
        return
    if event.canceled:
        cancel_contacts()
        get_viewport().set_input_as_handled()
        return
    if not event.pressed:
        if contacts.has(event.index): get_viewport().set_input_as_handled()
        contacts.erase(event.index)
        return
    if not gameplay_enabled: return
    var view_size := get_viewport().get_visible_rect().size
    if Rect2(view_size.x-150,20,126,52).has_point(event.position):
        var scene = get_tree().current_scene
        if is_instance_valid(scene) and scene.has_method("show_setup"):
            cancel_contacts()
            set_gameplay_enabled(false)
            scene.pause_game()
            get_viewport().set_input_as_handled()
        return
    var zones := regions(view_size)
    for role in ["pad", "attack", "special"]:
        if event.position.distance_to(zones[role]) <= (110 if role == "pad" else 66):
            for contact in contacts.values():
                if contact.role == role: return
            contacts[event.index] = {"role": role, "point": event.position}
            get_viewport().set_input_as_handled()
            return
