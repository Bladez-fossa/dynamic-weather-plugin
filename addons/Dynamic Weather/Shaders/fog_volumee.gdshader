shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;  // nearest instead of mipmap
uniform vec4 fog_color : source_color = vec4(0.8, 0.82, 0.85, 1.0);
uniform float fog_density : hint_range(0.0, 0.02) = 0.008;
uniform float storm_weight = 0.0;
uniform float fog_radius = 300.0;

void fragment() {
    float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 world_pos = INV_VIEW_MATRIX * (INV_PROJECTION_MATRIX * vec4(ndc, 1.0));
    world_pos.xyz /= world_pos.w;

    float scene_dist = distance(CAMERA_POSITION_WORLD, world_pos.xyz);
    float fog_dist = min(scene_dist, fog_radius);

    float fog_amount = 1.0 - exp(-fog_density * fog_dist * storm_weight);
    float near_fade = smoothstep(0.0, 20.0, scene_dist);
    fog_amount *= near_fade;

    ALBEDO = fog_color.rgb;
    ALPHA = clamp(fog_amount * fog_color.a, 0.0, 0.85);
}