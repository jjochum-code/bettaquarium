shader_type spatial;
render_mode cull_disabled;

// Ribbon blade: UV.x across the blade, UV.y from root (0) to tip (1).

varying float v_tone;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = origin.x * 1.3 + origin.z * 1.7;
	float h = UV.y;
	v_tone = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float sway = sin(TIME * 0.6 + ph + h * 2.5) * 0.25 + sin(TIME * 1.1 + ph * 2.0 + h * 5.0) * 0.08;
	VERTEX.x += sway * h * h;
	VERTEX.z += cos(TIME * 0.5 + ph) * 0.12 * h * h;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	float rib = 1.0 - smoothstep(0.0, 0.12, abs(UV.x - 0.5));
	vec3 tip = mix(vec3(0.03, 0.22, 0.06), vec3(0.12, 0.3, 0.03), v_tone);
	vec3 col = mix(vec3(0.004, 0.03, 0.012), tip, UV.y * UV.y);
	col *= mix(1.0, 0.6, rib);
	NORMAL = n;
	ALBEDO = col;
	ROUGHNESS = 0.5;
	BACKLIGHT = col * 0.7;
}
