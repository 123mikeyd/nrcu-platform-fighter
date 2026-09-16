extends Node3D
# Approved A1 native poses and warm dissolve; presentation only, never a combat ability.
const SOURCES = [preload("res://assets/mephisto/demon_detailed28.glb"), preload("res://assets/mephisto/demon_older24.glb")]
var forms: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var materials: Array[ShaderMaterial] = []
var active_form := 0
var hidden := false
var combat_pose := false
var transition := ""
var transition_time := 0.0
var flow_clock := 0.0
var warm_wisps: Node3D
var fighter: CharacterBody3D
var previous_stocks := -1
const TRANSITION_SECONDS := 2.0
const BASE_HEIGHTS := [.14, .43]
func tag_native_right_hand(mesh: MeshInstance3D):
    # Presentation-only color mask from original influences; no vertex, UV,
    # rest, skin weight or installed GLB array is edited.
    var tagged=ArrayMesh.new()
    var skin: Skin=mesh.skin
    var skeleton: Skeleton3D=mesh.get_node(mesh.skeleton)
    var selected=[]
    for i in skin.get_bind_count():
        var name_=String(skin.get_bind_name(i))
        if name_.is_empty() and skin.get_bind_bone(i)>=0:name_=skeleton.get_bone_name(skin.get_bind_bone(i))
        if name_ in ["RightForeArm","RightHand","RightHand_End"]:selected.append(i)
    for surface in mesh.mesh.get_surface_count():
        var arrays=mesh.mesh.surface_get_arrays(surface)
        var count=arrays[Mesh.ARRAY_VERTEX].size()
        var bones=arrays[Mesh.ARRAY_BONES]
        var weights=arrays[Mesh.ARRAY_WEIGHTS]
        var influences=int(bones.size()/count)
        var colors=PackedColorArray()
        for vertex in count:
            var amount=0.0
            for k in influences:
                if bones[vertex*influences+k] in selected:amount+=weights[vertex*influences+k]
            colors.append(Color(amount,0,0,1))
        arrays[Mesh.ARRAY_COLOR]=colors
        tagged.add_surface_from_arrays(mesh.mesh.surface_get_primitive_type(surface),arrays,[],{},mesh.mesh.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
    mesh.mesh=tagged
func _process(delta: float) -> void:
    tick_visual(delta)
func review_switch() -> void:
    if not transition.is_empty() or hidden: return
    transition = "switch"
    transition_time = 0.0
func review_hide() -> void:
    if not transition.is_empty(): return
    transition = "reveal" if hidden else "hide"
    transition_time = 0.0
func reset_presentation() -> void:
    if warm_wisps: warm_wisps.reset()
    active_form = 0
    hidden = false
    transition = ""
    transition_time = 0.0
    flow_clock = 0.0
    for i in forms.size():
        _set_form(i, BASE_HEIGHTS[i] if i == 0 else 1.25, 0.0 if i == 0 else 1.0)
func _set_form(index: int, height: float, dark: float) -> void:
    materials[index].set_shader_parameter("dissolve_height", height)
    materials[index].set_shader_parameter("darkening", dark)
    materials[index].set_shader_parameter("flow_clock", flow_clock)
    forms[index].visible = height < 1.24
func tick_visual(delta: float) -> void:
    if combat_pose:
        if fighter and fighter.controls_enabled and fighter.stocks>0 and fighter.hitstun<=0 and fighter.freeze_remaining<=0 and not is_instance_valid(fighter.caught_by):
            tick_warm_effects(delta)
        return
    if not fighter or forms.is_empty(): return
    if not fighter.controls_enabled or fighter.stocks <= 0 or (previous_stocks >= 0 and fighter.stocks != previous_stocks) or fighter.hitstun > 0:
        previous_stocks = fighter.stocks
        reset_presentation()
        for player in players: player.pause()
        return
    previous_stocks = fighter.stocks
    if fighter.freeze_remaining > 0 or is_instance_valid(fighter.caught_by):
        for player in players: player.pause()
        return
    tick_warm_effects(delta)
    for i in 2:
        if forms[i].visible:
            if not players[i].is_playing(): players[i].play("NativePresentation")
        else: players[i].pause()
        materials[i].set_shader_parameter("flow_clock", flow_clock)
    if transition.is_empty(): return
    transition_time += delta
    var progress := clampf(transition_time / TRANSITION_SECONDS, 0, 1)
    if transition == "switch":
        var outgoing := smoothstep(0.0, .64, progress)
        var incoming := smoothstep(.32, 1.0, progress)
        _set_form(active_form, lerpf(BASE_HEIGHTS[active_form], 1.25, outgoing), outgoing)
        _set_form(1-active_form, lerpf(1.25, BASE_HEIGHTS[1-active_form], incoming), 1-incoming)
    else:
        var amount := smoothstep(0.0, 1.0, progress)
        if transition == "reveal": amount = 1.0-amount
        _set_form(active_form, lerpf(BASE_HEIGHTS[active_form], 1.25, amount), amount)
    if progress >= 1.0:
        if transition == "switch": active_form = 1-active_form
        else: hidden = transition == "hide"
        if hidden and warm_wisps: warm_wisps.reset()
        transition = ""
func tick_warm_effects(delta: float) -> void:
    flow_clock += delta
    for material in materials: material.set_shader_parameter("flow_clock",flow_clock)
    if warm_wisps: warm_wisps.tick(delta,self)
func _ready() -> void:
    var ancestor = get_parent()
    while ancestor and not ancestor is CharacterBody3D: ancestor = ancestor.get_parent()
    fighter = ancestor
    for i in 2:
        var form: Node3D = SOURCES[i].instantiate()
        add_child(form)
        forms.append(form)
        var player: AnimationPlayer = form.find_children("*", "AnimationPlayer", true, false)[0]
        players.append(player)
        var source_clip = player.get_animation_list()[0]
        for clip in player.get_animation_list():
            if clip not in ["RESET","RubberGuillotine","ShadowDownStrike"]: source_clip = clip
        var rubber = player.get_animation("RubberGuillotine").duplicate(true) if player.has_animation("RubberGuillotine") else null
        var down = player.get_animation("ShadowDownStrike").duplicate(true) if player.has_animation("ShadowDownStrike") else null
        var animation: Animation = player.get_animation(source_clip).duplicate(true)
        animation.loop_mode = Animation.LOOP_LINEAR
        var library = AnimationLibrary.new()
        library.add_animation("NativePresentation", animation)
        if down:
            down.loop_mode = Animation.LOOP_NONE
            library.add_animation("ShadowDownStrike",down)
        if rubber:
            rubber.loop_mode = Animation.LOOP_NONE
            library.add_animation("RubberGuillotine", rubber)
        for name_ in player.get_animation_library_list(): player.remove_animation_library(name_)
        player.add_animation_library("", library)
        player.play("NativePresentation")
        var material = ShaderMaterial.new()
        material.shader = preload("res://scripts/mephisto_shadow.gdshader")
        material.set_shader_parameter("hand_hide",0.0)
        materials.append(material)
        for mesh in form.find_children("*", "MeshInstance3D", true, false):
            if i==0:tag_native_right_hand(mesh)
            var bounds: AABB = mesh.get_aabb()
            # Compatibility vertex() receives post-skin coordinates. The older
            # mesh AABB is 1.7 but its native 0.01 rig skins in 170-unit space.
            var skin_units := 1.0 if i == 0 else 100.0
            material.set_shader_parameter("height_min", bounds.position.y * skin_units)
            material.set_shader_parameter("height_span", bounds.size.y * skin_units)
            mesh.material_override = material
        # Both exports retain native object units (older rig carries .01 scale).
        form.scale = Vector3.ONE * 1.30
        # New gameplay staging counteracts the native rig object's saved yaw.
        form.rotation.y = -1.041408
        form.position = Vector3(0.0, .12, -.10)
        material.set_shader_parameter("dissolve_height", .14 if i == 0 else 1.25)
        form.visible = i == 0
    warm_wisps = preload("res://scripts/mephisto_wisps.gd").new()
    warm_wisps.name = "WarmWisps"
    add_child(warm_wisps)
