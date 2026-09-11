extends SceneTree

var failures := 0
var combat_math: Script

func _init() -> void:
    combat_math = load("res://scripts/combat_math.gd")
    if combat_math == null:
        push_error("RED: CombatMath is missing")
        quit(1)
        return

    test_damage_adds_hit_damage()
    test_knockback_increases_with_damage()

    if failures == 0:
        print("PASS: combat math")
        quit(0)
    else:
        push_error("FAIL: %d combat math assertion(s)" % failures)
        quit(1)

func test_damage_adds_hit_damage() -> void:
    assert_equal(combat_math.apply_damage(35.0, 12.0), 47.0, "damage adds to current percent")

func test_knockback_increases_with_damage() -> void:
    if not combat_math.has_method("knockback_strength"):
        failures += 1
        push_error("RED: knockback_strength is missing")
        return
    var low: float = combat_math.knockback_strength(10.0, 8.0, 4.0)
    var high: float = combat_math.knockback_strength(110.0, 8.0, 4.0)
    assert_true(high > low, "high damage produces stronger knockback")

func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
    if actual != expected:
        failures += 1
        push_error("%s: expected %s, got %s" % [label, expected, actual])

func assert_true(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        push_error(label)
