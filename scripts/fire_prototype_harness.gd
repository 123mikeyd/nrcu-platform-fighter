extends Node
# Loaded only by the external local opponent launcher/tests. Normal menus never load it.
var arena: Node3D
func install(target: Node3D) -> void:
    arena = target
    arena.setup.start_requested.disconnect(arena.start_match)
    arena.setup.start_requested.connect(start)
    var rows: Array = arena.setup.rows
    rows[0].kind.select(0)
    rows[0].character.select(0)
    rows[0].character.set_item_disabled(4, true)
    rows[1].kind.select(1)
    rows[1].character.select(4)
    rows[1].character.set_item_text(4, "Fire [prototype]")
    for i in [2, 3]: rows[i].kind.select(2)
    arena.setup.mode.select(0)
    arena.setup._refresh()
    arena.setup.mode.disabled = true
    for i in 4:
        rows[i].kind.disabled = true
        if i > 0: rows[i].character.disabled = true
    arena.setup.find_child("StartMatchButton", true, false).text = "START FIRE OPPONENT TEST"
    for label in arena.setup.find_children("*", "Label", true, false):
        if label.text == "NRCU  /  SET UP YOUR MATCH": label.text = "FIRE MAGE / PROTOTYPE OPPONENT TEST"
        if label.text == "Choose your fighters. Make unused slots Empty.": label.text = "P1: choose your fighter. P2: Fire bot. E blocks new burn; existing burn expires."
    DisplayServer.window_set_title("NRCU — Fire Mage Prototype Test")
func start(slots: Array, _teams: bool) -> void:
    var safe := slots.duplicate(true)
    safe[0].kind = "human"
    if safe[0].character == "ice_mage": safe[0].character = "teknium"
    safe[1].kind = "bot"
    safe[1].character = "ice_mage"
    safe[2].kind = "empty"
    safe[3].kind = "empty"
    if not arena.start_match(safe, false): return
    arena.player_two.enable_fire_prototype()
    arena.hud_labels[1].modulate = arena.player_two.body_color
    arena.hud_title.text = "FIRE MAGE — PROTOTYPE OPPONENT TEST"
    arena.hud_controls.text = "P1: WASD move/aim · Space jump · F basic · G special · Esc setup\nFirebolt: 6 impact + up to 4 burn. Non-stacking refresh only. Provisional balance."
