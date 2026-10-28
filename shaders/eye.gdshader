shader_type spatial;

// Fish eye on a sphere looking out along its local (side, 0, 0) axis; rotating
// the node turns the eye. Pupil and iris sit behind a bulging cornea, so they
// shift against the surface with the view angle like behind a real lens.

uniform float side = 1.0;
uniform vec3 iris_light : source_color = vec3(0.5, 0.38, 0.18);
uniform vec3 iris_dark : source_color = vec3(0.05, 0.035, 0.02);
uniform vec3 rim_color : source_color = vec3(0.015, 0.02, 0.04);
uniform float pupil_size = 0.5;  // radius as a fraction of the iris
uniform float iris_angle = 1.0;  // angular radius of the iris, radians
uniform float lens_depth = 0.35;

varying vec3 v_local;

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.1);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 d = normalize(v_local);
	vec3 axis = vec3(side, 0.0, 0.0);

	// Refraction through the cornea: look at the iris from slightly inside.
	vec3 view_obj = normalize((inverse(MODEL_MATRIX) * (INV_VIEW_MATRIX * vec4(VIEW, 0.0))).xyz);
	vec3 di = normalize(d - view_obj * lens_depth * (1.0 - dot(d, axis) * 0.5));

	float ang = acos(clamp(dot(di, axis), -1.0, 1.0));
	float rr = ang / iris_angle;  // 0 at the centre of the pupil, 1 at the edge of the iris
	// The offset keeps atan(0, 0) defined at the centre of the pupil.
	float around = atan(di.z, di.y + 1e-6);

	// Iris: fine radial fibres, darker towards the pupil and the outer edge.
	// At life size the eye is only ~15 px wide, so the fibres fade out before
	// they turn into sparkle. That also hides the seam where the angle wraps.
	float fibre_detail = clamp(0.5 / max(fwidth(around) * 46.0, 1e-4), 0.0, 1.0);
	float fibres = 0.65 + (0.2 * sin(around * 46.0 + sin(around * 7.0) * 2.0)
			+ 0.2 * (hash(floor(around * 30.0)) - 0.5)) * fibre_detail;
	vec3 iris = mix(iris_dark, iris_light, smoothstep(pupil_size, 0.75, rr) * fibres);
	iris = mix(iris, iris_dark, smoothstep(0.8, 1.0, rr));

	float pupil = 1.0 - smoothstep(pupil_size - 0.04, pupil_size + 0.01, rr);
	vec3 col = mix(iris, vec3(0.003), pupil);
	// Beyond the iris the eyeball disappears into the dark socket.
	col = mix(col, rim_color, smoothstep(1.0, 1.1, rr));

	// Edge-on normals at the rim make single pixels blow up to white. Tilt them
	// towards the viewer.
	vec3 n = NORMAL;
	float ndv = dot(n, VIEW);
	if (ndv < 0.1) {
		n = normalize(n + VIEW * (0.1 - ndv));
	}
	NORMAL = n;

	ALBEDO = col;
	METALLIC = 0.35 * (1.0 - pupil) * (1.0 - smoothstep(1.0, 1.1, rr));
	ROUGHNESS = 0.35;
	// Broad, faint sheen of the water surface above, so the eye looks wet. A
	// sharper highlight would be sub-pixel and pop on and off.
	vec3 sky = normalize((VIEW_MATRIX * vec4(0.2, 1.0, 0.4, 0.0)).xyz);
	// facing^12 by multiplication: pow() returns garbage on rim pixels on Metal.
	float facing = clamp(dot(reflect(-VIEW, NORMAL), sky), 0.0, 1.0);
	float f2 = facing * facing;
	float f4 = f2 * f2;
	float glint = f4 * f4 * f4;
	EMISSION = vec3(0.6, 0.7, 0.75) * glint * 0.15;
}

// Plain diffuse plus a broad, faint highlight, both capped: on a sphere this
// small, the patch facing the lamp above is a single pixel that would flash.
void light() {
	DIFFUSE_LIGHT += min(clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI, vec3(1.0));
	vec3 half_sum = VIEW + LIGHT;
	if (dot(half_sum, half_sum) > 1e-6) {
		float spec = pow(max(dot(NORMAL, normalize(half_sum)), 0.0), 30.0);
		SPECULAR_LIGHT += min(ATTENUATION * LIGHT_COLOR * spec * 0.02, vec3(0.08));
	}
}
