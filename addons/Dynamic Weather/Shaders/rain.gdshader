shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

uniform float drop_opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec3  rain_color : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
    float alpha = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
    float width_mask = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x);
    ALBEDO = rain_color;
    ALPHA  = alpha * width_mask * drop_opacity;
}