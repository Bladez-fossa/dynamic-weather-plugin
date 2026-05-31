shader_type spatial;
render_mode blend_mix, depth_draw_never, unshaded, cull_disabled;

uniform vec4  snow_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float softness   : hint_range(0.0, 1.0) = 0.45;
uniform float arm_blend  : hint_range(0.0, 1.0) = 0.28;

varying vec4 v_particle_color;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		MODELVIEW_MATRIX[3]
	);
	v_particle_color = COLOR;
}

void fragment() {
	vec2  uv    = UV * 2.0 - 1.0;
	float dist  = length(uv);
	float angle = atan(uv.y, uv.x);

	float circle = 1.0 - smoothstep(softness, 1.0, dist);
	float star   = pow(abs(cos(3.0 * angle)), 3.5);
	float shape  = mix(circle, circle * star, arm_blend * circle);

	if (shape < 0.004) discard;

	ALBEDO = snow_color.rgb;
	ALPHA  = shape * v_particle_color.a * snow_color.a;
}