extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var a = F.new()
    var b = F.new()
    root.add_child(a)
    root.add_child(b)
    a.set_physics_process(false)
    b.set_physics_process(false)
    check(a.has_method("can_hit"), "team-aware hit API exists")
    if a.has_method("can_hit"):
        a.team_id = 0
        b.team_id = 0
        b.position.x = 1
        a.basic_attack(Vector2.RIGHT, false)
        check(b.damage_percent == 0, "allied melee is harmless")
        check(not a.can_hit(b), "allies rejected")
        b.team_id = 1
        check(a.can_hit(b), "enemy accepted")
        a.attack_cooldown = 0
        a.basic_attack(Vector2.RIGHT, false)
        check(b.damage_percent > 0, "enemy melee damages")
        check(a.character_id == "teknium" and a.input_device == -1 and a.control_type == "human", "compatible defaults")
    a.queue_free()
    check(ResourceLoader.exists("res://scripts/roster.gd"), "roster exists")
    if ResourceLoader.exists("res://scripts/roster.gd"):
        var roster = load("res://scripts/roster.gd")
        check(roster.ids() == ["teknium", "doge_man", "ggb", "turbofit", "ice_mage", "witcheer", "mephisto"], "seven stable identities; original six retained")
        check(roster.palette("ggb", 0) != roster.palette("ggb", 1), "duplicate palettes differ")
        check(roster.display_name("doge_man") == "Doge Man", "readable names")
    b.queue_free()
    await process_frame
    if failures == 0: print("PASS roster gameplay")
    quit(1 if failures else 0)
