shader_type sky;

group_uniforms Directions;
uniform vec3 sun_dir; // towards the sun (from sky controller)
uniform vec3 moon_dir; // towards the moon (from sky controller)

// Sky gradients
group_uniforms SkyGradients;
uniform sampler2D sun_zenith_gradient : source_color, repeat_disable;
uniform sampler2D view_zenith_gradient : source_color, repeat_disable;
uniform sampler2D sun_view_gradient : source_color, repeat_disable;

// Sun
group_uniforms Sun;
uniform float sun_radius : hint_range(0,1) = 0.05;
uniform vec3 sun_color : source_color = vec3(1.0,1.0,1.0);

// Moon
group_uniforms Moon;
uniform float moon_radius : hint_range(0, 1) = 0.05;
uniform float moon_exposure : hint_range(-16,16) = 0;
uniform samplerCube moon_cubemap : source_color;
uniform mat3 moon_word_to_object;

// Stars
group_uniforms Stars;
uniform samplerCube star_cubemap: source_color;
uniform float star_exposure : hint_range(-16,16) = 0;
uniform float star_power : hint_range(1,5) = 1;
uniform float star_latitude : hint_range(-90, 90) = 0;
uniform float star_speed = 0.001;
uniform samplerCube star_constellation_cubemap : source_color;
uniform vec3 star_constellation_color : source_color = vec3(0.0,0.3,0.6);

// Weather
group_uniforms Weather;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float fog_density : hint_range(0.0, 1.0) = 0.0;
uniform float precipitation : hint_range(0.0, 1.0) = 0.0;
uniform float light_multiplier : hint_range(0.0, 3.0) = 1.0;
uniform float cirrus_weight : hint_range(0.0, 1.0) = 0.0;

// ── Helpers ────────────────────────────────────────────────────
float get_sun_mask(float sun_view_dot, float radius) {
	float step_radius = 1.0 - radius * radius;
	return step(step_radius, sun_view_dot);
}

float sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
	vec3 oc = -sphere_pos;
	float b = dot(oc, ray_dir);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) return -1.0;
	return -b - sqrt(h);
}

vec3 get_moon_texture(vec3 dir) {
	dir = moon_word_to_object * dir;
	dir.x = -dir.x;
	dir.z = -dir.z;
	return texture(moon_cubemap, dir).rgb;
}

mat3 rotation3d(vec3 axis, float angle) {
	axis = normalize(axis);
	float s = sin(angle);
	float c = cos(angle);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s),
		vec3(oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s),
		vec3(oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c)
	);
}

vec3 get_star_uvm(vec3 view_dir, float latitude, float local_sidereal_time) {
	float tilt = PI * (latitude - 90.0) / 180.0;
	mat3 tilt_rotation = rotation3d(vec3(-1.0, 0.0, 0.0), tilt);
	float spin = (0.75 - local_sidereal_time) * 2.0 * PI;
	mat3 spin_rotation = rotation3d(vec3(0.0, 1.0, 0.0), spin);
	return spin_rotation * tilt_rotation * view_dir;
}

// ── Noise for cirrus ────────────────────────────────────────────
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

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p *= 2.1;
		amplitude *= 0.5;
	}
	return value;
}

float get_cirrus(vec3 view_dir, float coverage, float wind) {
	if (view_dir.y < 0.01) return 0.0;
	float v_y = clamp(view_dir.y, 0.001, 1.0);
	vec2 uv = view_dir.xz / (v_y * 2.5);
	uv += TIME * wind * 0.005;

	vec2 stretch1 = vec2(uv.x * 0.3, uv.y * 2.0);
	vec2 stretch2 = vec2(uv.x * 0.8, uv.y * 4.0);
	float n1 = fbm(stretch1);
	float n2 = fbm(stretch2 + vec2(1.5, 2.0));
	float shape = mix(n1, n2, 0.5);

	shape = pow(shape + 0.08, 1.2);
	float threshold = mix(0.55, 0.15, coverage);
	float cloud = smoothstep(threshold, threshold + 0.5, shape);
	float horizon_fade = smoothstep(0.0, 0.2, view_dir.y);
	return clamp(cloud * horizon_fade, 0.0, 1.0);
}

// ── Main sky ─────────────────────────────────────────────────────
void sky() {
	vec3 sun_dir_to_sun = sun_dir;
	vec3 view_dir = EYEDIR;

	// Star UVW
	vec3 star_uvw = get_star_uvm(view_dir, star_latitude, mod(TIME * star_speed, 1.0));
	vec3 star_output = texture(star_cubemap, star_uvw).rgb;
	star_output = pow(star_output, vec3(star_power));

	// Angular dots
	float sun_view_dot = dot(sun_dir_to_sun, view_dir);
	float sun_zenith_dot = sun_dir_to_sun.y;
	float view_zenith_dot = view_dir.y;

	float sun_view_dot01 = (sun_view_dot + 1.0) * 0.5;
	float sun_zenith_dot01 = (sun_zenith_dot + 1.0) * 0.5;

	// Sky gradients
	vec3 sun_zenith_color = texture(sun_zenith_gradient, vec2(sun_zenith_dot01, 0.5)).rgb;
	vec3 view_zenith_color = texture(view_zenith_gradient, vec2(sun_zenith_dot01, 0.5)).rgb;
	float vz_mask = pow(clamp(1.0 - view_zenith_dot, 0.0, 1.0), 4.0);

	vec3 sun_view_color = texture(sun_view_gradient, vec2(sun_zenith_dot01, 0.5)).rgb;
	float sv_mask = pow(clamp(sun_view_dot, 0.0, 1.0), 4.0);

	vec3 sky_output = sun_zenith_color + vz_mask * view_zenith_color + sv_mask * sun_view_color;

	// Sun disc
	float sun_mask = get_sun_mask(sun_view_dot, sun_radius);
	vec3 sun_output = sun_color * sun_mask;
	sun_output *= smoothstep(-0.05, 0.05, sun_dir_to_sun.y);

	// Moon (no extra rotation – moon_dir already rotates via the node)
	float moon_intersect = sphere_intersect(view_dir, moon_dir, moon_radius);
	float moon_mask = moon_intersect > -1.0 ? 1.0 : 0.0;
	vec3 moon_normal = normalize(view_dir * moon_intersect - moon_dir);
	float moon_ndotl = clamp(dot(moon_normal, sun_dir_to_sun), 0.0, 1.0);
	vec3 moon_texture = get_moon_texture(moon_normal);
	vec3 moon_output = moon_mask * moon_ndotl * exp2(moon_exposure) * moon_texture;

	// Stars – hide behind sun/moon
	float star_mask = (1.0 - sun_mask) * (1.0 - moon_mask);
	float star_strength = (1.0 - sun_view_dot01) * clamp(-sun_zenith_dot, 0.0, 1.0);

	vec3 constellation_output = texture(star_constellation_cubemap, star_uvw).rgb;
	constellation_output *= star_constellation_color * star_mask * star_strength;
	star_output *= star_mask * exp2(star_exposure) * star_strength;

	// Fog
	vec3 fog_color = sun_zenith_color;
	float fog_mask = fog_density * (1.0 - view_zenith_dot);
	sky_output = mix(sky_output, fog_color, clamp(fog_mask, 0.0, 1.0));

	// Cloud darkening
	sky_output *= mix(1.0, 0.15, cloud_coverage);
	sun_output  *= mix(1.0, 0.08, cloud_coverage);
	moon_output *= mix(1.0, 0.0,  cloud_coverage);
	star_output *= mix(1.0, 0.1,  cloud_coverage);

	// Cirrus
	float cirrus = cirrus_weight * get_cirrus(view_dir, cloud_coverage, 1.0);
	vec3 cirrus_base = vec3(0.95, 0.97, 1.0);
	vec3 cirrus_color = mix(cirrus_base, sun_zenith_color, 0.15);
	cirrus_color = mix(cirrus_color, sun_view_color * 1.2, sv_mask * 0.3);

	float sun_influence = clamp(sun_zenith_dot + 0.3, 0.0, 1.0);
	float moon_above = clamp(moon_dir.y, 0.0, 1.0);
	float moon_view_dot = dot(moon_dir, view_dir);
	float moon_influence = moon_above * clamp(moon_view_dot * 0.5 + 0.5, 0.0, 1.0) * 0.25;
	float total_light = clamp(sun_influence + moon_influence, 0.0, 1.0);
	cirrus_color = mix(cirrus_color * 0.05, cirrus_color, total_light);

	float sun_clear = 1.0 - smoothstep(0.0, 0.08, sun_mask);
	sky_output = mix(sky_output, cirrus_color, cirrus * 0.95 * sun_clear);

	// Final combine
	vec3 output = (sky_output + sun_output + moon_output + star_output) * light_multiplier;
	COLOR = output;
}