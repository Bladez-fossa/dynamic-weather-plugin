shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 sun_dir;
uniform float sun_energy: hint_range(0.0, 8.0) = 1.0;
uniform float precipitation : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.6;
uniform float light_multiplier : hint_range(0.0, 3.0) = 1.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);

uniform float shell_layer = 0.0;

uniform float coverage_fade_range : hint_range(0.1, 1.0) = 0.7;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.20;
uniform float storm_darkness : hint_range(0.0, 1.0) = 0.75;
uniform float light_brightness : hint_range(0.0, 1.0) = 0.10;
uniform float bottom_erosion : hint_range(0.0, 0.5) = 0.15;

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
        mix(hash(i + vec2(0,0)), hash(i + vec2(1,0)), u.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x),
        u.y
    );
}

// 2-octave FBM – cheap but gives organic detail for holes and texture
float fbm2(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    v += a * noise(p); p *= 2.1; a *= 0.5;
    v += a * noise(p);
    return v;
}

// LOD-aware FBM – for the large base sheet, uses up to 3 octaves
float fbm_lod(vec2 p, int octaves) {
    float v = 0.0;
    float a = 0.5;
    v += a * noise(p); p *= 2.1; a *= 0.5;
    if (octaves < 2) return v;
    v += a * noise(p); p *= 2.1; a *= 0.5;
    if (octaves < 3) return v;
    v += a * noise(p);
    return v;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_xz = world_pos.xz;

    // Vertex displacement remains cheap (2 noise samples)
    vec2 disp_uv = world_xz * 0.008 + TIME * 0.002;
    float disp = noise(disp_uv) * 0.6 + noise(disp_uv * 2.1) * 0.3;
    VERTEX.y += (disp - 0.5) * 6.0;
}

void fragment() {
    int lod_octaves = shell_layer < 1.0 ? 2 : (shell_layer < 2.0 ? 2 : 3);

    vec2 uv = world_xz * 0.006;

    float slow_time = TIME * 0.008;
    float mid_time  = TIME * 0.02;
    float fast_time = TIME * 0.05;

    vec2 uv_a = uv + vec2(slow_time, slow_time * 0.4);
    vec2 uv_b = uv + vec2(mid_time * 0.6, mid_time);
    vec2 uv_c = uv + vec2(-fast_time * 0.3, fast_time * 0.7);

    // Large base sheet – still LOD FBM, cheap
    float sheet_a = fbm_lod(uv_a * 0.3 + vec2(1.7, 9.2), lod_octaves);
    float sheet_b = fbm_lod(uv_b * 0.3 + vec2(31.1, 74.4), lod_octaves);
    float blend_factor = sin(TIME * 0.03) * 0.5 + 0.5;
    float large = mix(sheet_a, sheet_b, blend_factor);

    // Medium detail – back to 2-octave FBM (was single noise, now smoother)
    float detail = fbm2(uv_a * 0.9 + vec2(5.3, 2.8)) * 0.15;

    // Hole generator – restored to 2-octave FBM for organic holes
    float hole_time_1 = TIME * 0.0012;
    float hole_time_2 = TIME * 0.0007;
    float hole_time_3 = TIME * 0.0025;

    vec2 uv_hole_1 = uv_c * 0.4 + vec2(hole_time_1 * 0.7, hole_time_1 * 0.3);
    vec2 uv_hole_2 = uv_c * 0.55 + vec2(-hole_time_2 * 0.5, hole_time_2 * 0.8);
    vec2 uv_hole_3 = uv_c * 0.7 + vec2(hole_time_3 * 0.4, -hole_time_3 * 0.6);

    float hole_layer_1 = fbm2(uv_hole_1 + vec2(13.7, 42.1));
    float hole_layer_2 = fbm2(uv_hole_2 + vec2(87.3, 25.9));
    float hole_layer_3 = fbm2(uv_hole_3 + vec2(41.2, 63.8));

    float hole_combined = (hole_layer_1 * 0.5 + hole_layer_2 * 0.3 + hole_layer_3 * 0.2);
    float hole_activation = sin(TIME * 0.008) * 0.3 + 0.7;
    float hole_noise = hole_combined * hole_activation;
    float hole_threshold_base = 0.45 + sin(TIME * 0.015) * 0.08;
    float hole_threshold = mix(0.35, 0.65, hole_threshold_base);
    float holes = smoothstep(hole_threshold - 0.08, hole_threshold + 0.08, hole_noise);

    vec2 uv_breakup = world_xz * 0.003 + TIME * 0.0004;
    float breakup_mask = fbm2(uv_breakup);   // 2-octave FBM for breakup
    holes = mix(holes, 1.0, breakup_mask * 0.6);

    // Erosion – single noise is enough (kept cheap)
    float erosion = noise(uv_b * 1.5 + mid_time) * bottom_erosion;

    float shape = large * 0.82 + detail * 0.15 - erosion;

    float cov_t = clamp((cloud_coverage - 0.6) / 0.4, 0.0, 1.0);
    float threshold = mix(0.12, 0.05, cov_t);
    float cloud = smoothstep(threshold, threshold + edge_softness, shape);

    float hole_strength = mix(0.75, 0.15, cov_t);
    float hole_influence = hole_strength * (0.6 + 0.4 * sin(TIME * 0.01));
    cloud *= mix(holes, 1.0, 1.0 - hole_influence);

    // ── Color & Lighting ──────────────────────────────────────────────
    vec3 bottom_color = vec3(0.28, 0.30, 0.35);
    vec3 top_color    = vec3(0.55, 0.57, 0.62);
    float depth_shade = smoothstep(0.2, 0.9, cloud);
    vec3 base_color = mix(top_color, bottom_color, depth_shade);

    // Color variation – single noise (enough)
    float color_var = noise(uv_a * 0.6 + vec2(7.1, 3.3));
    base_color = mix(base_color * 0.90, base_color * 1.04, color_var);

    vec3 safe_sun = length(sun_dir) > 0.001 ? normalize(sun_dir) : vec3(0.0, 1.0, 0.0);
    float sun_height = safe_sun.y;
    float day_t = smoothstep(-0.1, 0.15, sun_height);
    float night_factor = 1.0 - day_t;

    float moon_above = clamp(moon_dir.y, 0.0, 1.0);
    float moonlight = moon_above * 0.035;

    float brightness = mix(
        min(sun_energy * 0.85, 1.0),
        0.012 + moonlight,
        night_factor
    );
    brightness *= light_multiplier;
    base_color *= brightness;

    vec3 night_tint = vec3(0.55, 0.62, 0.80);
    base_color = mix(base_color, base_color * night_tint, night_factor);

    float sunset = smoothstep(-0.05, 0.2, sun_height) * (1.0 - smoothstep(0.2, 0.5, sun_height));
    base_color = mix(base_color, base_color * vec3(1.15, 0.85, 0.65), sunset * 0.3);

    float sun_dot = clamp(sun_dir.y, 0.0, 1.0);
    float layer_t = shell_layer / 3.0;
    base_color += sun_dot * light_brightness * layer_t;

    base_color = mix(base_color, vec3(0.10, 0.11, 0.13), precipitation * storm_darkness);

    float lightning = clamp(light_multiplier - 1.0, 0.0, 2.0);
    base_color = mix(base_color, vec3(0.85, 0.88, 0.95), lightning * cloud * 0.5);

    // Bottom unevenness – restored to 2-octave FBM for realistic underside
    vec2 belly_wind = vec2(TIME * 0.004, TIME * 0.001);
    vec2 uv_streak = vec2(world_xz.x * 0.002, world_xz.y * 0.006) + belly_wind;
    float streak_a = fbm2(uv_streak);
    float streak_b = fbm2(uv_streak * 1.3 + vec2(42.1, 17.3));
    float streak_blend = sin(TIME * 0.006) * 0.5 + 0.5;
    float streak = mix(streak_a, streak_b, streak_blend);

    vec2 uv_wave = world_xz * 0.001 + vec2(TIME * 0.002, TIME * 0.0005);
    float wave = fbm2(uv_wave * vec2(1.0, 0.2));

    float bottom_detail = streak * 0.65 + wave * 0.35;
    bottom_detail = smoothstep(0.35, 0.75, bottom_detail);
    float bottom_shadow = bottom_detail * mix(0.5, 0.1, layer_t);
    base_color *= (1.0 - bottom_shadow);

    // Alpha
    float coverage_fade = clamp(cloud_coverage / coverage_fade_range, 0.0, 1.0);
    coverage_fade = smoothstep(0.0, 1.0, coverage_fade);
    float alpha = cloud * 0.98 * coverage_fade;

    float dist = length(world_xz);
    float radial_fade = 1.0 - smoothstep(1000.0, 1500.0, dist);
    alpha *= radial_fade;

    ALBEDO = base_color;
    ALPHA = alpha;
}