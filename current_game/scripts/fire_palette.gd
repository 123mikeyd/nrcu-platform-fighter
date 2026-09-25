extends RefCounted
# Read-only sampling of the original texture, no source asset edits or eye glow.
const CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform vec4 source_tint : source_color = vec4(1.0);
void fragment() {
    vec4 c = source_tint;
    if (has_texture) { c *= texture(source_texture, UV); }
    // Only blue/cyan-painted regions change; neutral trim and skin stay intact.
    float blue = smoothstep(0.015, 0.16, c.b - c.r);
    vec3 red = vec3(min(c.b * 1.6, 1.0), c.r * 0.60, c.g * 0.28);
    ALBEDO = mix(c.rgb, red, blue);
    ROUGHNESS = 0.82;
    METALLIC = 0.0;
}
"""
static func apply(model: Node3D) -> void:
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var original = mesh.get_active_material(surface)
            if not original is StandardMaterial3D: continue
            var material := ShaderMaterial.new()
            var shader := Shader.new()
            shader.code = CODE
            material.shader = shader
            material.set_shader_parameter("source_texture", original.albedo_texture)
            material.set_shader_parameter("has_texture", original.albedo_texture != null)
            material.set_shader_parameter("source_tint", original.albedo_color)
            mesh.set_surface_override_material(surface, material)
