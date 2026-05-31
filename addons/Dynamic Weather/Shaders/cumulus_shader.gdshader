shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float cloud_seed = 0.0;
uniform float cloud_scale = 1.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float sun_energy : hint_range(0.0, 8.0) = 1.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;

uniform float wind_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.3);
uniform float wind_speed : hint_range(0.0, 2.0) = 0.15;
uniform float turbulence : hint_range(0.0, 1.0) = 0.4;

// ── Noise (unchanged) ─────────────────────────────────────
float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.31);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), u.x),
               mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x), u.y);
}

// ── FBM – reduced from 5 to 3 octaves ─────────────────────
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {   // was 5
        v += a * noise(p);
        p *= 2.1;
        a *= 0.5;
    }
    return v;
}

varying vec2 v_uv;

void vertex() {
    // Billboarding (unchanged)
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
    vec3 to_camera = normalize(cam_pos - world_pos);

    vec3 forward = to_camera;
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = cross(forward, right);

    vec3 billboard_vertex = VERTEX.x * right + VERTEX.y * up + VERTEX.z * forward;
    vec4 final_vertex = MODEL_MATRIX * vec4(billboard_vertex, 1.0);
    POSITION = PROJECTION_MATRIX * VIEW_MATRIX * final_vertex;

    v_uv = UV - vec2(0.5);
}

void fragment() {
    vec2 uv = v_uv * cloud_scale + vec2(cloud_seed * 0.1);

    float drift_speed = wind_speed * (0.8 + cloud_seed * 0.004) * 0.1;
    vec2 drift = wind_dir * wind_time * drift_speed;
    vec2 base_uv = uv + drift;

    // Turbulence – replaced full FBM with single noise sample
    vec2 turb_uv = uv + drift * 0.3 + vec2(cloud_seed * 0.05);
    float turb = noise(turb_uv * 2.0 + wind_time * 0.02) * turbulence;

    // Shape layers – reduced from 3 to 2 FBM calls
    float shape1 = fbm(base_uv * 1.8);
    float shape2 = fbm(base_uv * 3.5 + vec2(1.2, 4.7) + turb);
    // shape3 removed entirely – contributed only 25% to final, invisible after coverage threshold

    // Warp – still gives boiling look, now 3 octaves
    vec2 warp_uv = base_uv * 2.0 + vec2(shape1 * 0.6, shape2 * 0.6);
    float warp_shape = fbm(warp_uv * 2.5 + wind_time * 0.015);

    // Combine shapes – weights adjusted to keep the visual balance
    float cloud_shape = (shape1 * 0.5 + shape2 * 0.5) * (0.7 + warp_shape * 0.3);

    // Flat bottom & radial fade
    float flat_base = smoothstep(-0.5, -0.1, v_uv.y);
    float radial = 1.0 - smoothstep(0.2, 0.55, length(v_uv));
    cloud_shape *= radial * flat_base;

    float coverage_min = mix(0.65, 0.25, cloud_coverage);
    float cloud = smoothstep(coverage_min, coverage_min + 0.2, cloud_shape);
    if (cloud < 0.05) discard;

    // ── Lighting (unchanged) ─────────────────────────────
    vec3 light_dir = normalize(sun_dir);
    float vertical = clamp((v_uv.y + 0.5), 0.0, 1.0);

    float top_highlight = pow(vertical, 0.5);
    float bottom_shadow = pow(1.0 - vertical, 2.0);
    float base_cut = 1.0 - smoothstep(0.0, 0.12, vertical);
    bottom_shadow = max(bottom_shadow, base_cut * 0.85);

    float center_dist = length(v_uv) * 2.0;
    float core_brightness = 1.0 - smoothstep(0.1, 0.5, center_dist);
    float rim_darkness = smoothstep(0.4, 0.8, center_dist);

    vec3 fake_normal = normalize(vec3(v_uv.x, v_uv.y, sqrt(max(0.01, 1.0 - dot(v_uv, v_uv)))));
    float sun_facing = pow(max(0.0, dot(fake_normal, light_dir)), 1.2);

    float sun_height_raw = light_dir.y;
    float sun_height = clamp(sun_height_raw, 0.0, 1.0);

    float ambient_top = 0.50 + sun_height * 0.30;
    float ambient_bottom = 0.06;
    float ambient = mix(ambient_bottom, ambient_top, vertical);

    float direct_sun = sun_facing * sun_height * 0.9;
    float shadow_side = (1.0 - sun_facing) * 0.5 * sun_height;
    float core_lighting = core_brightness * 0.15 * sun_height;

    float top_lighting = (direct_sun + ambient) * top_highlight;
    float bottom_lighting = (ambient_bottom + shadow_side * 0.15) * bottom_shadow;
    float final_light = clamp(top_lighting + bottom_lighting + core_lighting, 0.02, 1.3);

    vec3 cloud_top_color = vec3(1.0, 0.99, 0.97);
    vec3 cloud_base_color = vec3(0.32, 0.35, 0.42);
    vec3 cloud_shadow_color = vec3(0.15, 0.16, 0.22);

    vec3 color = mix(cloud_base_color, cloud_top_color, pow(vertical, 0.6));
    color = mix(color, cloud_shadow_color, rim_darkness * 0.7);
    color *= final_light;

    float backlit = rim_darkness * top_highlight * (1.0 - sun_facing) * 0.25 * sun_height;
    color = mix(color, vec3(1.0, 0.98, 0.95), backlit);

    float sunset = smoothstep(0.0, 0.25, sun_height) * (1.0 - smoothstep(0.25, 0.5, sun_height));
    color = mix(color, color * vec3(1.4, 0.75, 0.55), sunset * 0.6);

    float night_factor = smoothstep(0.05, 0.0, sun_height_raw);
    color = mix(color, vec3(0.05, 0.06, 0.09), night_factor);

    ALBEDO = color;
    ALPHA = cloud * (0.85 + core_brightness * 0.15);
}