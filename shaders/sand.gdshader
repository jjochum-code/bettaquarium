shader_type spatial;

#include "res://shaders/caustics.gdshaderinc"

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = noise(v_world.xz * 1.5) * 0.5 + noise(v_world.xz * 12.0) * 0.3 + noise(v_world.xz * 90.0) * 0.2;
	vec3 sand = mix(vec3(0.02, 0.02, 0.02), vec3(0.2, 0.17, 0.13), n);
	float c = caustics(v_world.xz * 0.35, TIME * 0.8);
	ALBEDO = sand;
	ROUGHNESS = 0.9;
	// Caustics only where the key light reaches.
	float lit = smoothstep(8.0, 2.0, distance(v_world.xz, vec2(0.5, -1.0)));
	EMISSION = sand * c * 2.0 * lit;
}
