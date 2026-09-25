extends RefCounted
# Shared victim-only presentation. No timer, damage, ownership or world motion.
# Only reviewed/installed clips opt in. Other rigs keep the existing caught pose.
var active_visual: Node3D
var active_player: AnimationPlayer

func present(fighter) -> bool:
    var grab = fighter.caught_by
    if not is_instance_valid(grab) or grab.phase != "hold" or fighter.freeze_remaining > 0 or not fighter.controls_enabled or fighter.stocks <= 0:
        clear()
        return false
    for visual in fighter._visual_root.get_children():
        if visual.has_method("present_electrocution"):
            active_visual = visual
            visual.present_electrocution(grab.elapsed)
            return true
        var player = visual.get("animation_player")
        if not player is AnimationPlayer or not player.has_animation("Electrocution"): continue
        active_visual = visual
        active_player = player
        # Never replay a long non-seam-tested clip or compress it to the hold.
        # At the optional maximum hold, retain the last authored pose briefly.
        if visual.current_clip != "Electrocution": player.play("Electrocution", 0)
        visual.current_clip = "Electrocution"
        player.speed_scale = 1
        player.seek(minf(grab.elapsed, player.get_animation("Electrocution").length), true)
        player.pause()
        return true
    return false

func clear() -> void:
    if is_instance_valid(active_visual):
        if active_visual.has_method("clear_electrocution"): active_visual.clear_electrocution()
        else: active_visual.current_clip = ""
    if is_instance_valid(active_player): active_player.speed_scale = 1
    active_visual = null
    active_player = null
