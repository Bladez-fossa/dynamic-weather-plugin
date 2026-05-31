shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3  sun_dir;
uniform float precipitation      : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_coverage     : hint_range(0.0, 1.0) = 0.8;
uniform float layer_index        : hint_range(0.0, 3.0) = 0.0;
uniform float light_multiplier   : hint_range(0.0, 3.0) = 1.0;

uniform float storm_darkness     : hint_range(0.0, 1.0) = 0.65;
uniform float bottom_erosion     : hint_range(0.0, 0.5) = 0.22;
uniform float edge_softness      : hint_range(0.0, 0.5) = 0.30;
uniform float coverage_fade_range: hint_range(0.1, 1.0) = 0.65;
uniform float light_brightness   : hint_range(0.0, 1.0) = 0.10;

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

// Fix 2: fbm_lod kept for sheet sampling, full fbm removed
float fbm_lod(vec2 p, int octaves) {
    float value     = 0.0;
    float amplitude = 0.5;
    value += amplitude * noise(p); p *= 2.1; amplitude *= 0.5;
    if (octaves < 2) return value;
    value += amplitude * noise(p); p *= 2.1; amplitude *= 0.5;
    if (octaves < 3) return value;
    value += amplitude * noise(p); p *= 2.1; amplitude *= 0.5;
    if (octaves < 4) return value;
    value += amplitude * noise(p);
    return value;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_xz = world_pos.xz;

    float layer_t  = layer_index / 3.0;
    vec2  disp_uv  = world_xz * 0.04 + TIME * 0.004;

    // Fix 2: vertex displacement dropped from 4-octave fbm to 2 cheap noise samples —
    // displacement is large-scale so extra octaves bought nothing visible on Vega 8
    float disp = noise(disp_uv) * 0.6 + noise(disp_uv * 2.1) * 0.3;
    float strength = mix(20.0, 5.0, layer_t);
    VERTEX.y += (disp - 0.5) * strength;
}

void fragment() {
    float layer_t = layer_index / 3.0;

    // Fix 2: LOD octave budget tightened — bottom layer 2, mid 3, top 4
    int lod_octaves = layer_index < 1.0 ? 2 : (layer_index < 2.0 ? 3 : 4);

    float dist = length(world_xz);
    if (dist > 1500.0) discard;

    float wind_a = 0.006 - layer_t * 0.002;
    float wind_b = 0.004 - layer_t * 0.001;

    vec2 uv   = world_xz * 0.018;
    vec2 uv_a = uv + vec2(TIME * wind_a,        TIME * wind_a * 0.4);
    vec2 uv_b = uv + vec2(TIME * wind_b * 0.7,  TIME * wind_b);

    float sheet_a = fbm_lod(uv_a * 0.4 + vec2(1.7,  9.2),  lod_octaves);
    float sheet_b = fbm_lod(uv_b * 0.4 + vec2(31.1, 74.4), lod_octaves);
    float large   = mix(sheet_a, sheet_b, 0.45 + sin(TIME * 0.08) * 0.15);
    float medium  = fbm_lod(uv_a * 1.1 + vec2(5.3, 2.8),   lod_octaves);

    // Fix 2: erosion reduced to single noise() call — was fbm_lod(... 2 octaves),
    // the difference is invisible at cloud scale but saves one noise evaluation per fragment
    float erosion = 0.0;
    if (layer_t < 0.5) {
        erosion = noise(uv_b * 2.2 + TIME * 0.003) * (1.0 - layer_t * 2.0) * bottom_erosion;
    }

    float shape = large * 0.89 + medium * 0.2 - erosion;

    float cov_t    = clamp((cloud_coverage - 0.5) / 0.5, 0.0, 1.0);
    float threshold = mix(0.18, 0.04, cov_t);
    threshold -= layer_t * 0.05;
    float cloud = smoothstep(threshold, threshold + edge_softness, shape);

    // ── Color ──────────────────────────────────────────────────────────────
    vec3 dark_color  = vec3(0.06, 0.07, 0.09);
    vec3 light_color = vec3(0.30, 0.32, 0.36);
    vec3 base_color  = mix(dark_color, light_color, layer_t * 0.55);

    // Fix 2: color variation dropped from fbm() (4 octaves) to single noise() sample —
    // sub-pixel color variation needed zero octave detail
    float color_var = noise(uv_a * 0.8 + vec2(7.1, 3.3));
    base_color = mix(base_color * 0.85, base_color * 1.1, color_var);

    float sun_dot = clamp(sun_dir.y, 0.0, 1.0);
    base_color += sun_dot * light_brightness * layer_t;
    base_color  = mix(base_color, dark_color * 0.35, precipitation * storm_darkness);

    float lightning = clamp(light_multiplier - 1.0, 0.0, 2.0);
    base_color = mix(base_color, vec3(0.82, 0.86, 0.94), lightning * cloud * 0.6);

    // ── Alpha ──────────────────────────────────────────────────────────────
    float coverage_fade = clamp((cloud_coverage - 0.2) / coverage_fade_range, 0.0, 1.0);
    coverage_fade = smoothstep(0.0, 1.0, coverage_fade);
    float alpha = cloud * mix(0.99, 0.95, layer_t) * coverage_fade;

    float cloud_radius = 1400.0;
    float fade_start   = 700.0;
    float radial_fade  = 1.0 - smoothstep(fade_start, cloud_radius, dist);
    alpha *= radial_fade;

    if (layer_t < 0.35) {
        float base_fade = smoothstep(0.05, 0.45, cloud);
        alpha *= mix(base_fade, 1.0, layer_t * 2.5);
    }

    ALBEDO = base_color;
    ALPHA  = alpha;
}