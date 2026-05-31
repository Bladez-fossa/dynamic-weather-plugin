shader_type canvas_item;

uniform float storm_weight : hint_range(0.0, 1.0) = 0.0;
uniform float sun_up : hint_range(0.0, 1.0) = 1.0;

// Mist layer parameters
uniform float layer1_scale : hint_range(1.0, 50.0) = 8.0;
uniform float layer1_speed = 0.3;
uniform float layer1_direction = 45.0; // degrees

uniform float layer2_scale = 5.0;
uniform float layer2_speed = 0.15;
uniform float layer2_direction = -30.0;

// Colours – you can also set these from the script
uniform vec3 day_fog_color : source_color = vec3(0.80, 0.82, 0.85);
uniform vec3 night_fog_color : source_color = vec3(0.15, 0.17, 0.25);

// Simple hash / pseudo‑random for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion – adds multiple octaves for cloud‑like detail
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    float time = TIME;

    // Move UVs in different directions
    float rad1 = radians(layer1_direction);
    vec2 uv1 = UV * layer1_scale + vec2(cos(rad1), sin(rad1)) * time * layer1_speed;

    float rad2 = radians(layer2_direction);
    vec2 uv2 = UV * layer2_scale + vec2(cos(rad2), sin(rad2)) * time * layer2_speed;

    // Generate mist density from two FBM layers
    float mist1 = fbm(uv1);
    float mist2 = fbm(uv2);
    float mist = (mist1 * 0.6 + mist2 * 0.4);

    // Make mist stronger near the bottom of the screen (optional)
    float edge_mask = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
    mist *= edge_mask;

    // Day/night fog colour
    vec3 fog_col = mix(night_fog_color, day_fog_color, sun_up);

    // Final alpha: mist shape modulated by storm weight
    float alpha = mist * storm_weight * 0.7;   // peak opacity 0.7

    COLOR = vec4(fog_col, alpha);
}