extends RefCounted
var timer := 0.0
var sequence := 0
var intent: Dictionary = {}

func read(fighter: Node3D, delta: float) -> Dictionary:
    timer -= delta
    if timer > 0 and not intent.is_empty():
        return intent
    timer = {"easy": 0.42, "normal": 0.22, "hard": 0.10}.get(fighter.bot_difficulty, 0.22)
    sequence += 1
    intent = {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false, "shield": false}
    var target: Node3D
    var nearest := INF
    for other in fighter.get_tree().get_nodes_in_group("fighters"):
        if fighter.can_hit(other):
            var distance: float = fighter.global_position.distance_to(other.global_position)
            if distance < nearest:
                nearest = distance
                target = other
    var offstage: bool = absf(fighter.global_position.x) > 8.0 or fighter.global_position.y < -0.5
    var destination: float = 0.0 if offstage or target == null else target.global_position.x
    var dx := destination - fighter.global_position.x
    intent.left = dx < -0.5
    intent.right = dx > 0.5
    if offstage:
        if fighter.velocity.y <= 1.0:
            var jump_limit := 5 if fighter.character_id == "ggb" else 2
            if fighter.jumps_used < jump_limit and not fighter.recovery_spent:
                intent.jump = sequence % 2 == 1
            elif not fighter.recovery_spent:
                intent.up = true
                intent.special = sequence % 2 == 1
    elif target != null:
        if target.global_position.y > fighter.global_position.y + 1.8:
            intent.jump = sequence % 2 == 1
        if nearest < 2.4:
            intent.attack = sequence % 2 == 1
            intent.up = target.global_position.y > fighter.global_position.y + 0.8
            intent.down = target.global_position.y < fighter.global_position.y - 0.8
            intent.shield = fighter.bot_difficulty == "hard" and target.attack_cooldown > 0.3 and sequence % 4 == 0
            if fighter.character_id == "teknium" and nearest < 1.65 and nearest > 0.6 and not fighter.magic_locked() and fighter.teknium_magic.cooldown <= 0 and absf(target.global_position.y - fighter.global_position.y) < 0.4:
                # Reserve the close cast instead of issuing a basic immediately
                # before it: that basic's cooldown otherwise eats every grab edge.
                intent.attack = false
                intent.shield = false
                intent.left = false
                intent.right = false
                intent.up = false
                intent.down = false
                fighter.facing = signf(dx)
                intent.special = sequence % 6 == 0 and fighter.attack_cooldown <= 0
        elif nearest < 7.0:
            intent.special = sequence % (5 if fighter.bot_difficulty == "easy" else 3) == 0
        if fighter.prototype_fire and nearest < 6.5 and absf(target.global_position.y - fighter.global_position.y) < 0.6:
            # Prototype ranged spacing; don't walk past the cast's release point
            # or consume its special edge with a basic cooldown.
            intent.attack = false
            intent.shield = false
            intent.up = false
            intent.down = false
            intent.left = dx > 0 if nearest < 2.2 else (dx < 0 and nearest > 4.0)
            intent.right = dx < 0 if nearest < 2.2 else (dx > 0 and nearest > 4.0)
            fighter.facing = signf(dx)
            intent.special = nearest >= 2.2 and sequence % 3 == 0 and fighter.attack_cooldown <= 0 and fighter.ice_cast_cooldown <= 0
    return intent

func reset() -> void:
    timer = 0.0
    sequence = 0
    intent.clear()
