extends Node3D
## Local-only approved static reference cameo, not a reconstructed/vector logo.
## Whole crop includes its original bezel, perspective and edge artifacts.
## No collision, dialogue, affiliation, ability, animation or light spill.

const REFERENCE = preload("res://assets/kainan/detail_crop_screen_01m00s.png")
const SCREEN_WIDTH := 1.8
const SCREEN_HEIGHT := SCREEN_WIDTH * 685.0 / 600.0

func _ready() -> void:
    name = "KainanTerminal"
    # Back wall front=-5.15; mount back=-5.10, face=-4.70.
    # Mount intersects existing wall rail; screen=-4.695 clears its -4.725 face.
    # This root can move to a future stage without touching fighter code.
    var mount := MeshInstance3D.new()
    mount.name = "WallMount"
    var casing := BoxMesh.new()
    casing.size = Vector3(SCREEN_WIDTH + 0.16, SCREEN_HEIGHT + 0.16, 0.4)
    mount.mesh = casing
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.055, 0.075, 0.09)
    metal.metallic = 0.35
    metal.roughness = 0.72
    mount.material_override = metal
    mount.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mount)

    var screen := MeshInstance3D.new()
    screen.name = "ReferenceScreen"
    screen.position.z = 0.205
    var quad := QuadMesh.new()
    quad.size = Vector2(SCREEN_WIDTH, SCREEN_HEIGHT)
    screen.mesh = quad
    var display := StandardMaterial3D.new()
    display.albedo_texture = REFERENCE
    display.albedo_color = Color(0.8, 0.8, 0.8)
    display.roughness = 1.0
    display.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    display.emission_enabled = true
    display.emission = Color.WHITE
    display.emission_texture = REFERENCE
    display.emission_energy_multiplier = 0.25
    display.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    screen.material_override = display
    screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(screen)
