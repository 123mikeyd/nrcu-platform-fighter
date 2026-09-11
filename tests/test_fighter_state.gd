extends SceneTree

var failures := 0
var fighter_script: Script

func _init() -> void:
    fighter_script = load("res://scripts/fighter.gd")
    if fighter_script == null:
        push_error("RED: Fighter script is missing")
        quit(1)
        return
    if not fighter_script.can_instantiate():
        push_error("RED: Fighter script cannot instantiate")
        quit(1)
        return

    test_receive_hit_updates_percent_and_velocity()
    test_lose_stock_resets_fighter_state()

    if failures == 0:
        print("PASS: fighter state")
        quit(0)
    else:
        push_error("FAIL: %d fighter assertion(s)" % failures)
        quit(1)

func test_receive_hit_updates_percent_and_velocity() -> void:
    var fighter: CharacterBody3D = fighter_script.new()
    fighter.receive_hit(12.0, Vector3.RIGHT, 5.0)
    assert_equal(fighter.damage_percent, 12.0, "hit adds damage")
    assert_true(fighter.velocity.x > 0.0, "rightward hit produces rightward velocity")
    fighter.free()

func test_lose_stock_resets_fighter_state() -> void:
    var fighter: CharacterBody3D = fighter_script.new()
    if not fighter.has_method("lose_stock"):
        failures += 1
        push_error("RED: lose_stock is missing")
        fighter.free()
        return
    fighter.damage_percent = 85.0
    fighter.stocks = 3
    fighter.velocity = Vector3(4.0, 2.0, 0.0)
    fighter.lose_stock()
    assert_equal(fighter.stocks, 2, "stock count decreases")
    assert_equal(fighter.damage_percent, 0.0, "damage resets after stock loss")
    assert_equal(fighter.velocity, Vector3.ZERO, "velocity resets after stock loss")
    fighter.free()

func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
    if actual != expected:
        failures += 1
        push_error("%s: expected %s, got %s" % [label, expected, actual])

func assert_true(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        push_error(label)
