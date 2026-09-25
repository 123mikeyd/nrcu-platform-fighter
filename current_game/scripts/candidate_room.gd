extends Control
var warm := false
func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var holder := SubViewportContainer.new()
    holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    holder.stretch = true
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(holder)
    var view := SubViewport.new()
    view.size = Vector2i(1280,720)
    view.own_world_3d = true
    holder.add_child(view)
    var set_piece = preload("res://scripts/candidate_fortress.gd").new()
    set_piece.warm = warm
    view.add_child(set_piece)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("08121d")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("7394b0")
    env.ambient_light_energy = 0.7
    environment.environment = env
    view.add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-30,-25,0)
    light.light_energy = 1.5
    view.add_child(light)
    var camera := Camera3D.new()
    view.add_child(camera)
    camera.position = Vector3(13,7,18)
    camera.look_at(Vector3(0,6,-12))
    camera.fov = 58
