extends "res://scripts/fighter.gd"
# Encounter-only health fighter. Ordinary roster fighters retain stocks/percent.
const MAX_HEALTH := 400.0 # Provisional first-encounter tuning.
var health := MAX_HEALTH
var reaction_serial := 0
func _ready() -> void:
    character_id = "bobo"
    fighter_name = "Bobo"
    super._ready()
func _build_visuals() -> void:
    super._build_visuals()
    for child in _visual_root.get_children():
        _visual_root.remove_child(child)
        child.queue_free()
    var visual = load("res://scripts/bobo_visual.gd").new()
    visual.name = "BoboVisual"
    _visual_root.add_child(visual)
    get_node("PlayerLabel").text = "BOBO"
    get_node("PlayerLabel").position.y = 3.2
func read_controls(_delta: float) -> Dictionary:
    return {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false, "shield": false}
func can_hit(_target: Node) -> bool: return false
func basic_attack(_aim: Vector2, _airborne: bool) -> void: pass
func start_special(_aim: Vector2) -> void: pass
func release_special() -> void: pass
func try_jump() -> bool: return false
func receive_hit(amount: float, direction: Vector3, base_knockback: float) -> void:
    if health <= 0 or not controls_enabled or amount < 0: return
    var blocked := shielding
    super.receive_hit(amount, direction, base_knockback)
    health = clampf(health - amount * (0.35 if blocked else 1.0), 0, MAX_HEALTH)
    damage_percent = 0
    velocity = Vector3.ZERO
    hitstun = 0.25 if amount > 0 else 0.0
    if amount > 0:
        reaction_serial += 1
        _visual_root.get_node("BoboVisual").react("Block" if blocked else ("Hit" if reaction_serial % 2 else "HitWaist"))
    _finish_health_change()
func apply_status_damage(amount: float) -> void:
    if health <= 0 or not controls_enabled: return
    health = clampf(health - maxf(0,amount),0,MAX_HEALTH)
    _finish_health_change()
func _finish_health_change() -> void:
    if health <= 0:
        stocks = 0
        controls_enabled = false
        _visual_root.get_node("BoboVisual").react("Defeat")
        eliminated.emit(self)
    state_changed.emit()
func _physics_process(delta: float) -> void:
    # Immovable sturdy dummy: keep shared finite freeze/grab/status processing,
    # gravity and real reactions, but no launch-to-stock shortcut or bot attacks.
    velocity.x = 0
    super._physics_process(delta)
    global_position.x = spawn_position.x
    global_position.z = 0
    velocity.x = 0
func _handle_blast_zone() -> void:
    global_position = spawn_position
    velocity = Vector3.ZERO
func lose_stock() -> void: pass
func reset_fighter(new_spawn: Vector3, reset_stocks := false) -> void:
    health = MAX_HEALTH
    reaction_serial = 0
    super.reset_fighter(new_spawn, reset_stocks)
    _visual_root.get_node("BoboVisual").react("Idle")
func _update_move_visuals(delta := 0.0, interrupted := false) -> void:
    super._update_move_visuals(delta, interrupted)
    if not _visual_root: return
    var visual = _visual_root.get_node_or_null("BoboVisual")
    if not visual: return
    _visual_root.scale = Vector3.ONE
    visual.model.rotation.y = facing * PI / 2
    if freeze_remaining > 0 or is_instance_valid(caught_by): return
    if interrupted and health > 0: visual.react("Idle")
    visual.tick(delta)
