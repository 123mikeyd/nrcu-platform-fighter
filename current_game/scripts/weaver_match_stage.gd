extends "res://scripts/weaver_gap_controller.gd"
# Approved single-gap-floor P2 integrated into the live match lifecycle.
var arena
var saved_camera: Camera3D
var saved_world: WorldEnvironment
var saved_environment: Environment
var saved_lights: Array=[]
var saved_main_layer=1
var fighter_settings: Array=[]
var bound_ids: Array=[]
var was_live=false

func _ready():
    name="WeaverStage"
    arena=get_parent()
    saved_camera=get_viewport().get_camera_3d()
    for child in arena.get_children():
        if child is WorldEnvironment:
            saved_world=child; saved_environment=child.environment; child.environment=null
        if child is Light3D:
            saved_lights.append([child,child.visible]); child.visible=false
    var main=arena.get_node("MainPlatform")
    saved_main_layer=main.collision_layer; main.collision_layer=0
    super._ready()
    for i in decks.size():
        decks[i].name="WeaverStoneHalf"+str(i)
        decks[i].reparent(arena)
    _bind_fighters()

func _bind_fighters():
    var incoming: Array=arena.fighters.duplicate()
    var ids: Array=[]
    for p in incoming:
        if is_instance_valid(p): ids.append(p.get_instance_id())
    if ids==bound_ids: return
    _restore_fighter_settings()
    fighters=incoming; bound_ids=ids
    for p in fighters:
        fighter_settings.append([p,p.platform_on_leave])
        p.platform_on_leave=CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
    automatic=false
    reset_trial()

func _restore_fighter_settings():
    for item in fighter_settings:
        if is_instance_valid(item[0]): item[0].platform_on_leave=item[1]
    fighter_settings.clear()

func reset_trial():
    if not configured: return
    set_solid(false)
    phase="ready"; elapsed=0; gap=0; net_y=START_Y; net_x=0; visual_time=0
    blockers.clear(); freeze_stage=false
    sync_surfaces()

func _unhandled_key_input(event):
    if not arena.match_active() or arena.ready_remaining>0 or get_tree().paused: return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode==KEY_C:
            start_cycle(); get_viewport().set_input_as_handled()
        elif event.keycode==KEY_T:
            automatic=not automatic; get_viewport().set_input_as_handled()

func _physics_process(delta):
    if not is_instance_valid(arena) or not configured: return
    _bind_fighters()
    var live: bool=arena.match_active() and arena.ready_remaining<=0
    if not live:
        if was_live:
            automatic=false; reset_trial()
        was_live=false
        return
    was_live=true
    super._physics_process(delta)

func _exit_tree():
    # Root-level stone halves retain native ledge discovery.
    var owned: Array=decks+nets+side_decks
    if is_instance_valid(arena):
        for p in arena.fighters:
            if not is_instance_valid(p): continue
            for b in owned:
                if not is_instance_valid(b): continue
                if b in p._ignored_platforms:
                    p.remove_collision_exception_with(b); p._ignored_platforms.erase(b)
                if p._drop_platform==b: p._drop_platform=null
                if p.ledge_grab and p.ledge_grab.active() and p.ledge_grab.ledge_key.begins_with(str(b.get_instance_id())+":"):
                    p.ledge_grab.cancel()
        var main=arena.get_node_or_null("MainPlatform")
        if main: main.collision_layer=saved_main_layer
    _restore_fighter_settings()
    for b in decks:
        if is_instance_valid(b):
            b.collision_layer=0
            b.queue_free()
    if is_instance_valid(saved_world): saved_world.environment=saved_environment
    for item in saved_lights:
        if is_instance_valid(item[0]): item[0].visible=item[1]
    if is_instance_valid(saved_camera) and saved_camera.is_inside_tree(): saved_camera.make_current()
