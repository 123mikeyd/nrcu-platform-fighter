extends SceneTree
# Focused check for the frontend brief §3 boot route: BOOT -> TITLE -> MAIN MENU.
# The title card must be a pure Control scene over the shelf texture, exposing
# begin() as the one transition path (key / click / pad buttons all go through
# it, behind a short entry lock).
const Tokens = preload("res://scripts/ui_tokens.gd")

func _initialize(): call_deferred("run")

func fail(message: String) -> void:
    print("FAIL: " + message)
    quit(1)

func label_containing(node: Node, needle: String) -> Label:
    for child in node.find_children("*", "Label", true, false):
        if str(child.text).find(needle) != -1:
            return child
    return null

func start_event() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_F
    event.pressed = true
    return event

# The menu must arrive as a NEW "Home" instance (a repeat scene change swaps
# the previous one out), so compare against the instance seen before.
func route_to_menu(previous) -> bool:
    for i in 300:
        await process_frame
        var current = root.get_node_or_null("Home")
        if current != null and current != previous:
            return true
    return false

func run():
    if not ResourceLoader.exists("res://scenes/title.tscn"):
        fail("static title scene missing"); return
    var title = load("res://scenes/title.tscn").instantiate()
    root.add_child(title)
    for i in 3: await process_frame
    if title.find_children("*", "Node3D", true, false).size() != 0:
        fail("title must be a pure Control card, no 3D nodes"); return
    var background = title.find_child("ShelfBackground", true, false)
    if background == null or not (background is TextureRect) or background.texture == null:
        fail("title background must be the room texture"); return
    if background.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
        fail("title background must use linear filtering for stable presentation"); return
    # The Title is deliberately static: a shelf raster must not turn ambient
    # motion into an intermittent one-pixel layout error.
    title._process(0.0)
    if title.current_drift() != Vector2.ZERO:
        fail("title background must remain completely static"); return
    var reference_frame: Control = title.find_child("ReferenceFrame", true, false)
    var left_column_left := 32.0
    var left_column_right := 268.0
    var left_column_center := 150.0
    for container_name in ["TitleGroup", "StartRegion"]:
        var container: Control = title.find_child(container_name, true, false)
        var container_rect := container.get_global_rect()
        var frame_rect := reference_frame.get_global_rect()
        var container_left := container_rect.position.x - frame_rect.position.x
        var container_center := container_left + container_rect.size.x * 0.5
        if absf(container_center - left_column_center) > 0.5:
            fail(container_name + " is not centered over the wood column"); return
    for node_name in ["NRCUTitle", "AccentRule", "Subtitle", "LeftRule", "Prompt", "RightRule"]:
        var node: Control = title.find_child(node_name, true, false)
        var rect := node.get_global_rect()
        var frame_rect := reference_frame.get_global_rect()
        var left_edge := rect.position.x - frame_rect.position.x
        var right_edge := left_edge + rect.size.x
        if left_edge < left_column_left - 0.5 or right_edge > left_column_right + 0.5:
            fail(node_name + " escapes the centered inner wood column"); return
    var prompt: Label = title.find_child("Prompt", true, false)
    if prompt.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
        fail("title prompt must vertically center its text line"); return
    var left_rule: Control = title.find_child("LeftRule", true, false)
    var right_rule: Control = title.find_child("RightRule", true, false)
    var prompt_center := prompt.position.y + prompt.size.y * 0.5
    if absf(left_rule.position.y + left_rule.size.y * 0.5 - prompt_center) > 0.5 \
            or absf(right_rule.position.y + right_rule.size.y * 0.5 - prompt_center) > 0.5:
        fail("title prompt rules must share the prompt's vertical center"); return
    if title.find_child("StartRegion", true, false).position.y > 430.0:
        fail("title prompt is too far below the NRCU title block"); return
    var wordmark = label_containing(title, "NRCU")
    if wordmark == null or wordmark.get_theme_font_size("font_size") < Tokens.T_HERO:
        fail("hero NRCU wordmark missing or below hero scale"); return
    if title.find_child("Prompt", true, false) == null:
        fail("start prompt missing"); return
    if not title.has_method("begin"):
        fail("title must expose begin()"); return
    if title.prompt_alpha() >= 0.1:
        fail("the prompt is pulse-written early instead of staying hidden during entry"); return
    for i in 20: await process_frame
    if title.prompt_alpha() <= 0.4:
        fail("the prompt did not enter its restrained idle range after the entry tween"); return
    var stable_prompt_alpha: float = title.prompt_alpha()
    for i in 60: await process_frame
    if absf(title.prompt_alpha() - stable_prompt_alpha) > 0.001:
        fail("title prompt must remain static after its entry reveal"); return
    # A key held before Title activation blocks arming until its real release;
    # the route must not rely on an arbitrary post-entry timer.
    var held := InputEventKey.new()
    held.keycode = KEY_F
    held.pressed = true
    Input.parse_input_event(held)
    var blocked = load("res://scenes/title.tscn").instantiate()
    root.add_child(blocked)
    await create_timer(0.5).timeout
    if blocked.is_armed() or blocked._leaving:
        fail("a held carry-over key skipped Title release-arming"); return
    var released := InputEventKey.new()
    released.keycode = KEY_F
    released.pressed = false
    Input.parse_input_event(released)
    for i in 3: await process_frame
    if not blocked.is_armed():
        fail("Title did not arm after the held input was released"); return
    blocked.queue_free()
    await process_frame
    # begin() is the callable the key/click/pad path uses: no error, and it
    # reaches the main menu.
    title.begin()
    var routed: bool = await route_to_menu(null)
    if not routed:
        fail("begin() did not route to the main menu"); return
    # Any key must also route — but never inside the entry lock.
    var locked = load("res://scenes/title.tscn").instantiate()
    root.add_child(locked)
    await process_frame
    locked._unhandled_input(start_event())
    if locked._leaving:
        fail("title skipped instantly, entry lock is not armed"); return
    await create_timer(0.5).timeout
    # Other pad buttons are not controller confirm/Start actions.
    var pad_other := InputEventJoypadButton.new()
    pad_other.button_index = JOY_BUTTON_X
    pad_other.pressed = true
    locked._unhandled_input(pad_other)
    if locked._leaving:
        fail("a non-confirm pad button incorrectly activated Title"); return
    # Modifier-only input is not a Start even though the visible copy accepts
    # broad non-modifier keyboard input.
    var modifier := InputEventKey.new()
    modifier.keycode = KEY_SHIFT
    modifier.physical_keycode = KEY_SHIFT
    modifier.pressed = true
    locked._unhandled_input(modifier)
    if locked._leaving:
        fail("modifier-only key incorrectly activated Title"); return
    locked._unhandled_input(start_event())
    if not locked._leaving:
        fail("fresh key did not activate the armed Title"); return
    if locked.start_count() != 1:
        fail("repeated activation was not latched to one Start")
    var menu = root.get_node_or_null("Home")
    locked._unhandled_input(start_event())
    routed = await route_to_menu(menu)
    if not routed:
        fail("key input did not route to the main menu"); return
    print("PASS title card and BOOT -> TITLE -> MENU route")
    for child in root.get_children():
        if child.name == "Home":
            child.queue_free()
    locked.queue_free()
    title.queue_free()
    await process_frame
    quit(0)
