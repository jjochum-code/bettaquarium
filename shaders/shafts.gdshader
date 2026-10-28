shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// One sheet of light beams. UV.x runs across the sheet, UV.y from the
// water surface (0) down to the floor (1).

uniform vec3 tint : source_color = vec3(0.5, 0.85, 1.0);
uniform float strength = 0.13;

varying float v_seed;

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}

void vertex() {
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Two noise bands drifting against each other make beams appear, wander and fade.
	float x = UV.x * 7.0 + v_seed * 53.0;
	float rays = noise1(x + TIME * 0.12) * noise1(x * 2.3 - TIME * 0.08 + 9.0);
	rays = smoothstep(0.15, 0.6, rays);
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	// Fades out before the sheet reaches the sand, so no seam shows there.
	float fall = pow(clamp(1.0 - UV.y / 0.85, 0.0, 1.0), 1.5);
	float shimmer = 0.75 + 0.25 * sin(TIME * 0.9 + v_seed * 20.0 + UV.x * 4.0);
	ALBEDO = tint;
	ALPHA = rays * edge * fall * shimmer * strength;
}
