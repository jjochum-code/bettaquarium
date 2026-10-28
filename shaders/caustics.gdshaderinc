// Tileable animated water caustics (iterative turbulence pattern).
float caustics(vec2 uv, float t) {
	vec2 p = mod(uv * TAU, TAU) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 5; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		// Keep the divisors away from zero, or the glow turns single pixels into flashes.
		vec2 w = vec2(sin(i.x + tt), cos(i.y + tt));
		w = max(abs(w), vec2(1e-3)) * (step(vec2(0.0), w) * 2.0 - 1.0);
		c += 1.0 / max(length(vec2(p.x / (w.x / inten), p.y / (w.y / inten))), 1e-3);
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 1.5);
}
