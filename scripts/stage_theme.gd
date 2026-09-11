extends Node3D
# Collision-free presentation; the original four platform bodies remain authoritative.
var level_id := "toy_room"
var environment: Environment
var original_background: int
var original_canvas_layer: int
var original_ambient: Color
const MODELS = {
    "teknium": preload("res://assets/teknium/teknium_animations.glb"),
    "doge_man": preload("res://assets/doge_man/doge_attacks.glb"),
    "ggb": preload("res://assets/ggb/ggb.glb"),
    "turbofit": preload("res://assets/turbofit/turbofit_animations.glb"),
    "ice_mage": preload("res://assets/ice_mage/ice_mage_combat.glb"),
    "witcheer": preload("res://assets/witcheer/witcheer_run.glb"),
    "mephisto": preload("res://assets/mephisto/mephisto_girl.glb")}
func _ready():
    name = "StageTheme"
    environment = get_parent().find_children("*", "WorldEnvironment", false, false)[0].environment
    original_background = environment.background_mode
    original_canvas_layer = environment.background_canvas_max_layer
    original_ambient = environment.ambient_light_color
    environment.ambient_light_color = Color(0.9,0.78,0.61) if level_id == "toy_room" else Color(0.66,0.82,1)
    for item in [[Vector3(0,-0.55,0),Vector3(18,1,5)], [Vector3(-5.2,3,0),Vector3(5,0.45,3.8)], [Vector3(5.2,3,0),Vector3(5,0.45,3.8)], [Vector3(0,6,0),Vector3(4.5,0.4,3.4)]]:
        box(item[0],item[1],Color(0.58,0.32,0.13) if level_id == "toy_room" else Color(0.58,0.72,0.79))
        box(item[0] + Vector3(0,item[1].y*0.5-0.035,0), Vector3(item[1].x,0.07,item[1].z), Color(0.88,0.62,0.32) if level_id == "toy_room" else Color(0.85,0.91,0.89))
        box(item[0] + Vector3(0,0,item[1].z*0.5+0.01),Vector3(item[1].x,0.09,0.03),Color(0.94,0.72,0.38))
    if level_id == "toy_room": build_room()
    else: build_sky()
    var details = preload("res://scripts/stage_details.gd").new()
    details.level_id = level_id
    add_child(details)
    var hud_layer := CanvasLayer.new()
    hud_layer.layer = 0
    add_child(hud_layer)
    for rect in [Rect2(0,0,1280,65),Rect2(0,595,1280,125)]:
        var backing := ColorRect.new()
        backing.name = "HUDContrast"
        backing.position = rect.position
        backing.size = rect.size
        backing.color = Color(0.015,0.025,0.045,0.88)
        backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hud_layer.add_child(backing)

func _exit_tree():
    if environment:
        environment.background_mode = original_background
        environment.background_canvas_max_layer = original_canvas_layer
        environment.ambient_light_color = original_ambient

func build_room():
    box(Vector3(0,5,-9),Vector3(80,25,0.3),Color(0.41,0.59,0.58))
    for x in range(-39,40,2):
        box(Vector3(x,5,-8.8),Vector3(0.04,25,0.02),Color(0.54,0.69,0.65))
    box(Vector3(0,-2,-5),Vector3(40,0.3,18),Color(0.43,0.24,0.12))
    # Broad collector shelf high on the bedroom wall, above combat silhouettes.
    box(Vector3(0,6.8,-5.8),Vector3(25,0.35,2.8),Color(0.55,0.29,0.12))
    box(Vector3(0,6.68,-4.36),Vector3(25,0.12,0.12),Color(0.92,0.65,0.31))
    for x in [-11.8,11.8]:
        box(Vector3(x,4.8,-6.8),Vector3(0.3,4,0.5),Color(0.45,0.24,0.11))
    var ids = preload("res://scripts/roster.gd").ids()
    for i in ids.size():
        figurine(ids[i], Vector3((float(i)/maxi(ids.size()-1,1)-0.5)*21.6,6.99,-5.6))
    # Oversized books and bedside storage make the fighters feel toy-sized.
    var colors = [Color(0.8,0.27,0.18),Color(0.13,0.39,0.52),Color(0.85,0.62,0.18),Color(0.34,0.48,0.25)]
    for i in 7:
        var x := -12.5+i*0.52
        var h := 3.0+float(i%3)*0.45
        box(Vector3(x,h*0.5-1.8,-5.4),Vector3(0.43,h,1.4),colors[i%4])
        for y in [-1.2,0.4]: box(Vector3(x,y,-4.68),Vector3(0.36,0.06,0.02),Color(0.94,0.81,0.5))
    box(Vector3(11,0,-6),Vector3(3.1,3.6,2.5),Color(0.78,0.43,0.21))
    for y in [-0.9,0.2,1.3]:
        box(Vector3(11,y,-4.7),Vector3(2.85,0.94,0.08),Color(0.88,0.58,0.31))
        box(Vector3(11,y,-4.6),Vector3(0.45,0.1,0.12),Color(0.98,0.82,0.44))
    # Window with warm ivory frame and a soft blue evening view.
    box(Vector3(-9,4,-8.5),Vector3(5.8,5.2,0.2),Color(0.93,0.84,0.64))
    box(Vector3(-9,4,-8.3),Vector3(5.2,4.6,0.1),Color(0.3,0.57,0.75))
    box(Vector3(-9,4,-8.2),Vector3(0.13,4.6,0.1),Color(0.96,0.87,0.69))
    box(Vector3(-9,4,-8.2),Vector3(5.2,0.13,0.1),Color(0.96,0.87,0.69))


func figurine(id: String, pos: Vector3):
    var figure := Node3D.new()
    figure.name = "Figure_"+id
    add_child(figure)
    var model: Node3D = MODELS[id].instantiate()
    figure.add_child(model)
    for player in model.find_children("*","AnimationPlayer",true,false):
        var pose_clip := "Run" if id == "witcheer" else "Idle"
        if player.has_animation(pose_clip):
            player.play(pose_clip)
            player.seek(0,true)
            player.pause()
    # Normalize imported unit conventions while preserving mesh/material resources.
    var bounds := AABB()
    var first := true
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        var b: AABB = figure.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
        bounds = b if first else bounds.merge(b)
        first = false
    # Reuse the measured gameplay scale: raw AABB includes unused origin space.
    # Normalizing that AABB would shrink the actual GGB silhouette a second time.
    var factor := preload("res://scripts/ggb_visual.gd").PRESENTATION_SCALE
    if id == "ggb":
        model.scale *= factor
        model.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
    elif id == "mephisto":
        model.scale *= preload("res://scripts/mephisto_visual.gd").VISUAL_SCALE
        model.position.y = preload("res://scripts/mephisto_visual.gd").FLOOR_OFFSET
    elif id == "witcheer":
        model.scale *= preload("res://scripts/witcheer_visual.gd").VISUAL_SCALE
        model.position.y = preload("res://scripts/witcheer_visual.gd").FLOOR_OFFSET
    else:
        # Skinned mesh AABBs are in bind space, not evaluated skeleton space.
        # Match the established fighter presentation scale instead.
        model.scale *= 1.15 if id == "ice_mage" else 1.25
        if id == "teknium":
            # Plinth top is 0.01 above figure origin; same posed Idle correction.
            model.position.y = preload("res://scripts/teknium_visual.gd").IDLE_FLOOR_OFFSET + 0.01
    for skeleton in model.find_children("*","Skeleton3D",true,false):
        skeleton.force_update_all_bone_transforms()
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        for surface in mesh.mesh.get_surface_count():
            var source = mesh.get_active_material(surface)
            if source is StandardMaterial3D and id != "ggb":
                var material: StandardMaterial3D = source.duplicate()
                material.metallic = 0.0
                material.roughness = 0.75
                material.emission_enabled = false
                mesh.set_surface_override_material(surface,material)
    figure.position = pos
    figure.process_mode = Node.PROCESS_MODE_DISABLED
    box(pos+Vector3(0,-0.04,0),Vector3(2.5,0.1,1.6),Color(0.21,0.19,0.16))
    label(preload("res://scripts/roster.gd").display_name(id).to_upper(),pos+Vector3(0,-0.16,1.43),0.0038,Color(1,0.86,0.59))

func label(text: String, pos: Vector3, pixels: float, color: Color):
    var node := Label3D.new()
    node.text = text
    node.position = pos
    node.pixel_size = pixels
    node.font_size = 48
    node.modulate = color
    node.no_depth_test = false
    add_child(node)

func build_sky():
    environment.background_mode = Environment.BG_CANVAS
    environment.background_canvas_max_layer = -1
    var layer := CanvasLayer.new()
    layer.layer = -1
    add_child(layer)
    var video := VideoStreamPlayer.new()
    video.name = "CloudVideo"
    video.stream = load("res://assets/stages/sky_cloud_loop.ogv")
    video.expand = true
    video.loop = true
    video.volume_db = -80
    video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(video)
    video.play()
    # Faceted suspended foundations and gold ribs; no extra collision surfaces.
    for item in [[Vector3(0,-1.7,0),Vector3(15,1.3,3.8)], [Vector3(-5.2,2.4,0),Vector3(3.7,0.6,2.7)], [Vector3(5.2,2.4,0),Vector3(3.7,0.6,2.7)], [Vector3(0,5.45,0),Vector3(3.0,0.7,2.3)]]:
        box(item[0],item[1],Color(0.25,0.39,0.5))
    for x in [-7.5,-5,-2.5,0,2.5,5,7.5]:
        box(Vector3(x,-1,2.52),Vector3(0.1,0.9,0.08),Color(0.95,0.74,0.34))
    for x in [-10.8,10.8]:
        box(Vector3(x,1,-6),Vector3(1.1,6,1.1),Color(0.57,0.69,0.74))
        box(Vector3(x,4,-6),Vector3(2,0.35,1.7),Color(0.94,0.8,0.48))
func box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.position = pos
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color * Color(0.48,0.48,0.48,1) if level_id == "toy_room" else color
    mat.roughness = 0.82
    if size.x >= 3.0 and size.z > 1.0 and size.y < 1.5:
        mat.albedo_texture = load("res://assets/stages/detail/woodgrain.png" if level_id == "toy_room" else "res://assets/stages/detail/ivory_stone.png")
        mat.albedo_color = Color(0.62,0.62,0.62) if level_id == "toy_room" else Color(0.82,0.86,0.88)
    node.material_override = mat
    add_child(node)
    return node
