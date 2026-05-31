shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3  sun_dir       = vec3(0.0, 1.0, 0.0);
uniform float sun_energy    : hint_range(0.0, 8.0) = 1.0;
uniform vec3  moon_dir      = vec3(0.0, -1.0, 0.0);
uniform float cloud_coverage: hint_range(0.0, 1.0) = 0.5;
uniform float precipitation : hint_range(0.0, 1.0) = 0.0;
uniform float light_multiplier : hint_range(0.0, 3.0) = 1.0;
uniform float shell_layer = 0.0;

uniform float puff_scale     : hint_range(0.5, 3.0) = 1.0;
uniform float puff_contrast  : hint_range(0.5, 3.0) = 1.4;
uniform float gap_sharpness  : hint_range(0.0, 1.0) = 0.6;
uniform float clump_strength : hint_range(0.0, 1.0) = 0.7;
uniform float warp_strength  : hint_range(0.0, 2.0) = 1.1;
uniform vec2  wind_dir       = vec2(1.0, 0.3);
uniform float wind_speed     : hint_range(0.0, 10.0) = 1.0;

uniform float min_coverage_threshold : hint_range(0.0,  1.0) = 0.85;
uniform float max_coverage_threshold : hint_range(-0.5, 1.0) = -0.05;
uniform float coverage_smoothness    : hint_range(0.05, 0.5) = 0.25;

varying vec2 world_xz;

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.31);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),             hash(i + vec2(1,0)), u.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x),
        u.y
    );
}

// Fix: dropped from 5 octaves to 3 — altocumulus is a mid-level sheet,
// fine detail is lost at cloud viewing distance anyway
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}

// Fix: domain_warp2 called fbm twice inside, then was called 3× per fragment
// = 6 fbm calls just for warping. Replaced with single-level warp using
// cheaper noise() calls — warp shape is indistinguishable at cloud scale
vec2 domain_warp_cheap(vec2 p, float strength) {
    vec2 offset = vec2(
        noise(p + vec2(1.7, 9.2)),
        noise(p + vec2(8.3, 2.8))
    );
    return p + offset * strength;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_xz = world_pos.xz;

    // Fix: vertex displacement reduced to 2 noise() calls — same as nimbostratus fix,
    // large-scale displacement needs no FBM detail
    vec2 disp_uv = world_xz * 0.010 + TIME * 0.010 * wind_speed;
    float disp = noise(disp_uv) * 0.6 + noise(disp_uv * 2.1) * 0.3;
    VERTEX.y += (disp - 0.5) * mix(10.0, 3.0, shell_layer);
}

void fragment() {
    float layer_t = shell_layer;
    float dist = length(world_xz);
    if (dist > 1400.0) discard;

    vec2 wd = normalize(wind_dir);
    float base_scale = 0.013 / puff_scale;
    vec2 uv = world_xz * base_scale;
    float ws = wind_speed;

    vec2 uv_a = uv + wd * TIME * (0.022 - layer_t * 0.001) * ws;
    vec2 uv_b = uv + wd * TIME * (0.015 - layer_t * 0.001) * ws + vec2(17.3, 5.1);

    // Fix: was 3 macro fbm calls — reduced to 2, third was nearly invisible
    vec2 macro_uv_a = world_xz * 0.0014 + vec2(TIME * 0.0040, TIME * 0.0023) * ws;
    vec2 macro_uv_b = world_xz * 0.0031 + vec2(TIME * 0.0026, TIME * 0.0036) * ws;
    float macro_a = fbm(macro_uv_a + vec2(1.3, 4.7));
    float macro_b = fbm(macro_uv_b + vec2(8.1, 2.3));
    float macro = macro_a * 0.6 + macro_b * 0.4;
    macro = pow(smoothstep(0.28, 0.78, macro), mix(1.0, 2.2, clump_strength));

    // Fix: was domain_warp2 (double fbm inside) called 3× — now single-level
    // warp with noise() called 2× total, then fbm on the warped result
    vec2 warped_a = domain_warp_cheap(uv_a * 1.8, warp_strength * 0.5);
    float large_a = fbm(warped_a * 2.2);

    vec2 warped_b = domain_warp_cheap(uv_b * 2.6, warp_strength * 0.38);
    float large_b = fbm(warped_b * 2.0 + vec2(31.1, 74.4));

    // Fix: dropped third puff layer (large_c + warped_c) entirely —
    // it contributed only 17% to the final shape, invisible at sky distance
    float puff_raw = large_a * 0.60 + large_b * 0.40;
    float puff = pow(clamp(puff_raw, 0.0, 1.0), mix(0.7, 1.8, (puff_contrast - 0.5) / 2.5));

    float shape = puff * (0.3 + macro * 0.7);

    float cloud_threshold = mix(min_coverage_threshold, max_coverage_threshold, cloud_coverage);
    float cloud = smoothstep(cloud_threshold, cloud_threshold + coverage_smoothness, shape);
    cloud *= smoothstep(0.05, 0.25, cloud_coverage);

    // ── Color ──────────────────────────────────────────────────────────────
    vec3 light_color = vec3(0.92, 0.94, 0.98);
    vec3 dark_color  = vec3(0.00, 0.00, 0.00);
    vec3 base_color  = mix(dark_color, light_color, 0.32 + layer_t * 0.44);

    // Fix: color variation dropped from fbm to single noise() — same as nimbostratus
    float color_var = noise(uv_a * 0.85 + vec2(7.1, 3.3));
    base_color = mix(base_color * 0.86, base_color * 1.10, color_var);

    vec3  safe_sun  = length(sun_dir) > 0.001 ? normalize(sun_dir) : vec3(0,1,0);
    float sun_dot   = clamp(-safe_sun.y, -0.3, 1.0);
    float day_night = smoothstep(-0.3, 0.3, sun_dot);
    float moonlight = clamp(moon_dir.y, 0.0, 1.0) * 0.06;
    float brightness = mix(0.0015 + moonlight, min(sun_energy * 0.85, 1.0), day_night);
    base_color *= brightness;

    base_color = mix(base_color * vec3(0.78, 0.85, 1.0), base_color, day_night);

    float sv_dot = clamp(dot(safe_sun, vec3(0,-1,0)), 0.0, 1.0);
    float sunset  = smoothstep(0.0, 0.22, sv_dot) * (1.0 - smoothstep(0.22, 0.55, sv_dot));
    base_color = mix(base_color, base_color * vec3(1.2, 0.82, 0.60), sunset * 0.35);

    base_color = mix(base_color, vec3(0.12, 0.13, 0.16), precipitation * 0.6);

    float lightning = clamp(light_multiplier - 1.0, 0.0, 2.0);
    base_color = mix(base_color, vec3(0.88, 0.90, 0.96), lightning * cloud * 0.5);

    // ── Alpha ──────────────────────────────────────────────────────────────
    float coverage_fade = smoothstep(0.15, 0.65, cloud_coverage);
    float alpha = cloud * mix(0.93, 0.80, layer_t) * coverage_fade;
    alpha *= 1.0 - smoothstep(900.0, 1400.0, dist);

    if (layer_t < 0.5) {
        alpha *= mix(smoothstep(0.06, 0.44, cloud), 1.0, layer_t * 2.0);
    }

    ALBEDO = base_color;
    ALPHA  = alpha;
}