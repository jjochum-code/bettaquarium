shader_type spatial;
// Body and fins of the betta. All motion happens in deform().
// depth_draw_always: the translucent fins still write depth, so depth of field
// treats them as part of the fish.
render_mode cull_disabled, depth_draw_always;

#include "res://shaders/caustics.gdshaderinc"

// Vertex colour layout (see betta_mesh.gd):
//   r = flexibility (0 at fin base / body, 1 at fin tip)
//   g = part (0 body, 0.35 pectoral, 0.7 ventral, 1 median fins)
//   b = per-fin phase offset
// Fin UVs: x = ray coordinate (integer at each ray), y = base -> tip.
// CUSTOM0.xyz / CUSTOM1.xyz: surface tangents along the two mesh directions;
// CUSTOM1.w: how fast flexibility grows along the second tangent.

uniform float swim_phase = 0.0;
uniform float swim_amp = 0.04;
uniform float bend = 0.0;
uniform float bend_v = 0.0;
uniform vec3 drag = vec3(0.0);
// A slower, softer follower of the same motion: long fins swing out on it.
uniform vec3 drag_slow = vec3(0.0);
// 1 = tail fully spread; below 1 the rays fold together (fast swimming).
uniform float fin_spread = 1.0;
// 0..1: lower jaw dropped open / gill covers lifted (breathing, biting, chewing).
uniform float mouth_open = 0.0;
uniform float gill_open = 0.0;
uniform float pect_phase = 0.0;
uniform float pect_amp = 1.0;
uniform float fin_wave = 0.08;

uniform vec3 body_dark : source_color = vec3(0.01, 0.02, 0.10);
uniform vec3 iri_a : source_color = vec3(0.0, 0.75, 0.95);
uniform vec3 iri_b : source_color = vec3(0.45, 0.1, 0.9);
uniform vec3 fin_base : source_color = vec3(0.02, 0.07, 0.45);
uniform vec3 fin_mid : source_color = vec3(0.03, 0.4, 0.9);
uniform vec3 fin_edge : source_color = vec3(0.8, 0.03, 0.15);

// Colour patterns, see betta_morphs.gd.
uniform float iri_strength = 1.0;  // how metallic the scales are
uniform float marble = 0.0;  // koi / marble patches on body and fins
uniform vec3 marble_color : source_color = vec3(0.7, 0.04, 0.03);
uniform float marble_seed = 0.0;
uniform float butterfly = 0.0;  // sharp outer band on every fin
uniform float band_pos = 0.65;
uniform vec3 band_color : source_color = vec3(0.92, 0.9, 0.85);
uniform float band_opacity = 1.0;
uniform float fin_opacity = 1.0;

// Fin type details the mesh cannot carry.
uniform float crown = 0.0;  // crowntail: rays reach past a deeply cut membrane
uniform float ruffle = 0.0;  // rosetail: ruffled, overlapping fin edges
uniform float scallop = 1.0;  // depth of the scallops between rays

varying float v_part;
varying vec3 v_world;
varying vec3 v_normal;
varying vec3 v_tangent;
varying vec3 v_rest;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Scales overlap like roof tiles: discs on a staggered grid (g.x runs head to
// tail), the one nearer the head on top, so only each rear crescent shows.
// offset: from the visible scale's centre, in scale radii.
// rnd: random value per scale.
// clear: 0 at the rim of the overlapping scale (in its shadow), 1 away from it.
const float SCALE_R = 0.75;

void scale_at(vec2 g, out vec2 offset, out float rnd, out float clear) {
	float best_i = 1e9;
	vec2 best_c = g;
	for (int di = -1; di <= 1; di++) {
		float i = floor(g.x) + float(di);
		float shift = mod(i, 2.0) * 0.5;
		for (int dj = -1; dj <= 1; dj++) {
			vec2 c = vec2(i + 0.5, floor(g.y - shift) + float(dj) + shift + 0.5);
			if (length(g - c) < SCALE_R && i < best_i) {
				best_i = i;
				best_c = c;
			}
		}
	}
	// Distance to the rim of the overlapping scales nearer the head.
	float edge = 1.0;
	for (int di = -1; di <= 0; di++) {
		float i = best_i + float(di) - 1.0;
		float shift = mod(i, 2.0) * 0.5;
		for (int dj = -1; dj <= 1; dj++) {
			vec2 c = vec2(i + 0.5, floor(g.y - shift) + float(dj) + shift + 0.5);
			edge = min(edge, length(g - c) - SCALE_R);
		}
	}
	offset = (g - best_c) / SCALE_R;
	rnd = fract(sin(dot(best_c, vec2(12.9898, 78.233))) * 43758.5453);
	clear = smoothstep(0.0, 0.18, edge);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float koi_mask(vec3 rest) {
	float n = noise3(rest * 5.0 + marble_seed) * 0.65 + noise3(rest * 13.0 + marble_seed) * 0.35;
	return marble * smoothstep(0.5, 0.58, n);
}

// Head features on the body UVs. around: sin(UV.y * TAU), -1 along the belly,
// 0 on the flanks, +1 along the back.
// Signed distance to the curved rear edge of the gill cover (negative in front).
float gill_distance(vec2 uv, float around) {
	return uv.x - (0.2 - 0.07 * around * around + 0.015 * around);
}

// Small upturned mouth: a gape that starts at the top of the snout tip and
// drops steeply to its corner. 0 on the gape line.
float mouth_gape(vec2 uv, float around) {
	return around - (0.45 - uv.x * 23.0);
}

// face.x: how much a body vertex belongs to the lower jaw, face.y: to a gill cover.
// t: time. seed: per-fin phase offset.
vec3 deform(vec3 rest, float flex, float part, float seed, float t, vec2 face) {
	vec3 p = rest;
	// The lower jaw drops, hinged at the corner of the mouth. The gill covers
	// lift away from the head, opening a slit at their rear edge.
	p.y -= mouth_open * face.x * 0.03;
	p.z += mouth_open * face.x * 0.006;
	p.x += sign(rest.x) * gill_open * face.y * 0.018;

	// r: distance of a fin point from the body.
	vec2 q = vec2(rest.y, rest.z - clamp(rest.z, -0.1, 0.47));
	float r = length(q);
	// path: how far the body wave has travelled to reach this point. On the body
	// that is z; on the median fins the wave continues out along the rays, so
	// long fins swing all the way to their tips, even where they hang down
	// (veiltail) or stand straight up (halfmoon edges).
	float path = rest.z;
	if (part > 0.9) {
		float attached = smoothstep(0.0, 0.3, flex);
		if (rest.z > 0.47) {
			// The tail opens and closes like a fan around the tail root.
			vec2 fan = vec2(rest.z - 0.47, rest.y);
			float spread = fin_spread + 0.04 * sin(t * 0.6 + seed * TAU);
			// The offset keeps atan(0, 0) from producing NaN at the tail root.
			float turn = (spread - 1.0) * atan(fan.y, fan.x + 1e-6) * attached;
			fan = vec2(fan.x * cos(turn) - fan.y * sin(turn), fan.x * sin(turn) + fan.y * cos(turn));
			p.z = fan.x + 0.47;
			p.y = fan.y;
		}
		path = clamp(rest.z, -0.1, 0.47) + r * attached;
		// Dorsal, tail and anal fin overlap. Deriving their flexibility from the
		// position makes overlapping parts move identically, so they slide over
		// each other instead of cutting through. Past 1 for long fins, which
		// bend and trail more.
		flex = min((r - 0.06) / 0.7, 1.8) * smoothstep(0.0, 0.15, flex);
		flex = max(flex, 0.0);
	}

	// Travelling body wave, starting right behind the eyes so the whole trunk
	// works, not just the tail. The head's counter-swing is done on the node.
	float s = max(path + 0.3, 0.0);
	float sw = max(path + 0.38, 0.0);
	float env = sw * sw * 0.85 + sw * 0.3;
	// Out on long fins the wave slows down and lags further behind.
	float lag = max(path - 0.5, 0.0);
	p.x += sin(swim_phase - path * 5.0 - lag * lag * 2.0) * swim_amp * env;
	// C-shaped bend while turning.
	p.x += bend * s * s * 0.6;
	// Same in the vertical when pitching up or down.
	p.y += bend_v * s * s * 0.6;

	// Fin ripples: a slow swell rolling out from the body, a sweep along the fin,
	// and a fine flutter at the margin.
	float f2 = flex * flex;
	float swell = sin(t * 2.2 - r * 9.0 + rest.y * 2.5 + seed * TAU);
	float sweep = sin(t * 1.3 + swim_phase * 0.5 - r * 5.0 - rest.z * 3.0);
	float flutter = sin(t * 3.7 - r * 18.0 + rest.y * 7.0) * flex;
	float ripple = swell * 0.55 + sweep * 0.35 + flutter * 0.25 * (1.0 + ruffle);
	p.x += pow(flex, 1.5) * ripple * fin_wave;
	// Long fins billow slowly as a whole, even when the fish is still.
	p.x += f2 * sin(t * 0.9 - r * 3.0 + seed * TAU) * 0.04;
	// Rosetail: the outer margin is gathered into ruffles.
	float around = atan(q.x, q.y + 1e-5) * 40.0 + rest.z * 60.0;
	p.x += ruffle * step(0.9, part) * pow(flex, 3.0) * sin(around) * 0.05;
	// The membrane also breathes slightly within its own plane.
	p.y += f2 * sin(t * 1.1 - r * 4.0 + rest.z * 2.0) * 0.015;
	// Outer parts of long fins hang on the slow spring: they swing out further
	// and settle later than the roots.
	p += f2 * mix(drag, drag_slow, clamp(flex - 0.4, 0.0, 1.0));

	if (part > 0.2 && part < 0.5) {
		// Pectoral fins paddle.
		float side = sign(rest.x);
		float flap = sin(pect_phase + side * 0.6 - flex * 1.5);
		p.z += flex * flap * 0.08 * pect_amp;
		p.x -= side * flex * (flap * 0.5 + 0.5) * 0.05 * pect_amp;
	}
	return p;
}

void vertex() {
	float flex = COLOR.r;
	float part = COLOR.g;
	float seed = COLOR.b;

	// Deform the vertex and two neighbours along the surface and take the normal
	// from those, so shading follows every ripple.
	vec3 tu = CUSTOM0.xyz;
	vec3 tv = CUSTOM1.xyz;
	float eu = 0.003 / max(length(tu), 1e-4);
	float ev = 0.003 / max(length(tv), 1e-4);
	vec2 face = vec2(0.0);
	if (part < 0.2) {
		float around = sin(UV.y * TAU);
		float gape = mouth_gape(UV, around);
		float gd = gill_distance(UV, around);
		face.x = (1.0 - smoothstep(0.0, 0.045, UV.x)) * smoothstep(0.0, -0.12, gape);
		face.y = smoothstep(-0.12, -0.005, gd) * (1.0 - step(0.0, gd)) * smoothstep(0.95, 0.5, abs(around));
	}
	vec3 p0 = deform(VERTEX, flex, part, seed, TIME, face);
	vec3 pu = deform(VERTEX + tu * eu, flex, part, seed, TIME, face);
	vec3 pv = deform(VERTEX + tv * ev, flex + CUSTOM1.w * ev, part, seed, TIME, face);
	vec3 n = cross(pu - p0, pv - p0);
	if (dot(n, n) < 1e-14) {
		n = NORMAL;
	} else {
		n = normalize(n);
		if (dot(n, NORMAL) < 0.0) {
			n = -n;
		}
	}

	v_rest = VERTEX;
	VERTEX = p0;
	v_part = part;
	v_world = (MODEL_MATRIX * vec4(p0, 1.0)).xyz;
	v_normal = (MODELVIEW_MATRIX * vec4(n, 0.0)).xyz;
	v_tangent = (MODELVIEW_MATRIX * vec4(pu - p0, 0.0)).xyz;
}

void fragment() {
	bool is_fin = v_part > 0.2;
	// Never normalize a zero vector: the glow turns a single NaN pixel into a flash.
	vec3 n = dot(v_normal, v_normal) > 1e-12 ? normalize(v_normal) : VIEW;
	// Fins are single sheets: always light the side facing the camera.
	if (is_fin && dot(n, VIEW) < 0.0) {
		n = -n;
	}

	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
	float shift = clamp(fres * 1.4 + 0.15 * sin(v_world.y * 6.0 + TIME * 0.3), 0.0, 1.0);
	vec3 iri = mix(iri_a, iri_b, shift);

	vec3 col;
	vec3 back = vec3(0.0);
	vec3 glow = vec3(0.0);
	float rough;
	float metal;
	float alpha = 1.0;

	if (is_fin) {
		float u = UV.x;
		float v = UV.y;

		// Fin rays fork twice on the way out, a rosetail's three times.
		float f = fract(u + 0.5) - 0.5;
		float split1 = 0.25 * smoothstep(0.3, 0.5, v);
		float split2 = 0.125 * smoothstep(0.6, 0.78, v);
		float split3 = 0.0625 * smoothstep(0.8, 0.92, v) * ruffle;
		float ray_dist = abs(abs(abs(abs(f) - split1) - split2) - split3);
		float width = mix(0.05, 0.025, v);
		float fw = fwidth(u);
		float ray = 1.0 - smoothstep(width - fw, width + fw, ray_dist);
		// Fade out sub-pixel detail instead of letting it shimmer.
		float detail = clamp(width / max(fw, 1e-5), 0.0, 1.0);
		ray *= detail;

		// Outer edge: shallow scallops between the rays, or for a crowntail a
		// deeply cut membrane with each main ray reaching past it as a tapering spike.
		float scallop_edge = 1.0 - 0.015 * scallop * (1.0 - pow(abs(cos(u * PI)), 2.0));
		float spike = mix(0.16, 0.03, clamp((v - 0.68) / 0.32, 0.0, 1.0));
		float crown_edge = 1.0 - 0.32 * smoothstep(spike, spike + 0.05, abs(f));
		float edge = mix(scallop_edge, crown_edge, crown);
		// Anti-aliased by its own screen-space gradient.
		float to_edge = edge - v;
		float cover = clamp(to_edge / max(fwidth(to_edge), 1e-5) + 0.5, 0.0, 1.0);
		if (cover <= 0.0) {
			discard;
		}

		// The membrane is pleated between the rays: tilt the normal across the fin.
		vec3 across = v_tangent - n * dot(v_tangent, n);
		across = dot(across, across) > 1e-12 ? normalize(across) : vec3(0.0);
		n = normalize(n - across * sin(TAU * u) * 0.2 * detail * (1.0 - v * 0.5));

		float wobble = sin(u * 2.3) * 0.04 + sin(u * 0.7 + 1.0) * 0.05;
		col = mix(fin_base, fin_mid, smoothstep(0.0, 0.5, v));
		col = mix(col, fin_edge, smoothstep(0.45, 0.85, v + wobble));
		col = mix(col, vec3(1.0, 0.85, 0.8), smoothstep(edge - 0.03, edge, v) * 0.15);
		// The membrane is thicker and darker near the body.
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.6, v));
		// Butterfly: a sharply separated outer band.
		float band = smoothstep(band_pos - 0.02, band_pos + 0.02, v + wobble * 0.5) * butterfly;
		col = mix(col, band_color, band);
		col = mix(col, marble_color, koi_mask(v_rest));
		col *= mix(1.0, 0.6, ray);
		// Streaks along the rays break up the flat colour bands.
		col *= 0.8 + 0.2 * sin(u * 5.7 + sin(u * 1.9) * 2.0 + v * 3.0);
		if (v_part < 0.5) {
			// Pectoral fins are nearly clear: a paler wash of the fin colour.
			col = mix(col, vec3(dot(col, vec3(0.333))), 0.3) * 1.1;
		}

		float fres_fin = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
		col += mix(iri_a, iri_b, fres_fin) * fres_fin * 0.25 * iri_strength;

		// The thin outer membrane lets light through; the rays stay solid.
		float thin = smoothstep(0.5, 1.0, v);
		float opacity = mix(0.96, 0.7, thin);
		opacity = mix(opacity, 1.0, ray * 0.8);
		if (v_part < 0.5) {
			opacity *= 0.55;
		}
		opacity *= fin_opacity * mix(1.0, band_opacity, band);
		alpha = opacity * cover;

		back = col * mix(1.0, 0.4, ray) * (0.7 + 0.5 * thin);
		glow = col * 0.03;
		rough = 0.5;
		metal = 0.0;
	} else {
		float sa = sin(UV.y * TAU);
		float gd = gill_distance(UV, sa);
		// 0 on the smooth head in front of the gill cover, 1 on the scaled body.
		float head = smoothstep(-0.01, 0.03, gd);
		float gill_line = (1.0 - smoothstep(0.0, 0.012, abs(gd))) * smoothstep(0.95, 0.6, abs(sa));
		float gape = mouth_gape(UV, sa);
		float snout = 1.0 - smoothstep(0.03, 0.04, UV.x);
		// The open mouth is a dark gap that widens with the jaw, framed by thick lips.
		float mouth = (1.0 - smoothstep(0.06 + 0.4 * mouth_open, 0.16 + 0.45 * mouth_open, abs(gape))) * snout;
		float lips = (1.0 - smoothstep(0.2, 0.5, abs(gape))) * snout;

		vec2 g = vec2(UV.x * 52.0, UV.y * 36.0);
		vec2 so;
		float srnd;
		float sclear;
		scale_at(g, so, srnd, sclear);
		float sr = length(so);
		// Each scale is brightest towards its free rear edge, with a thin dark rim
		// there and a soft shadow where the scale in front overlaps it.
		float scale = 0.5 + 0.5 * smoothstep(-0.4, 0.6, so.x);
		scale *= 1.0 - 0.55 * smoothstep(0.8, 0.97, sr);
		scale *= mix(0.45, 1.0, sclear);
		// Scales sit at slightly different angles and catch the light individually.
		scale *= 0.85 + 0.3 * srnd;
		// Below a few pixels per scale, fade to the average brightness.
		float scale_detail = clamp(0.35 / max(fwidth(g.x), 1e-4) - 0.5, 0.0, 1.0);
		scale = mix(0.62, scale, scale_detail);
		vec3 along = v_tangent - n * dot(v_tangent, n);
		if (dot(along, along) > 1e-12) {
			along = normalize(along);
			vec3 around_dir = cross(n, along);
			vec2 tilt = so + vec2(srnd - 0.5, fract(srnd * 7.3) - 0.5) * 0.6;
			n = normalize(n + (along * tilt.x + around_dir * tilt.y) * 0.25 * scale_detail * head);
		}
		float sheen = scale * head;
		vec3 scale_iri = mix(iri_a, iri_b, clamp(shift + (srnd - 0.5) * 0.35 + so.x * 0.15, 0.0, 1.0));
		col = mix(body_dark, scale_iri, clamp((sheen * 0.85 + 0.1) * iri_strength, 0.0, 1.0));
		col = mix(col, marble_color * (0.8 + 0.4 * sheen), koi_mask(v_rest));
		// The gill cover has a soft metallic sheen.
		col += iri * (1.0 - head) * smoothstep(-0.12, -0.02, gd) * 0.22;
		col = mix(col, fin_base, smoothstep(0.8, 1.0, UV.x) * 0.7);
		// Dark back, brighter flanks, slightly pale belly.
		col *= mix(0.45, 1.0, smoothstep(1.0, 0.15, sa));
		col += iri * 0.06 * smoothstep(-0.3, -1.0, sa);
		col += iri * 0.1 * lips;
		// Lifted gill covers reveal a glimpse of red gills.
		float slit = (1.0 - smoothstep(0.0, 0.008 + 0.008 * gill_open, abs(gd - 0.004))) * smoothstep(0.95, 0.6, abs(sa));
		col = mix(col, vec3(0.25, 0.02, 0.03), slit * smoothstep(0.2, 0.8, gill_open) * 0.7);
		col *= 1.0 - 0.75 * max(gill_line, mouth) - 0.1 * mouth * mouth_open;
		glow = iri * sheen * fres * 0.3 * iri_strength;
		// Not too glossy: sharp highlights on the scales glitter along the back.
		rough = mix(0.55, 0.38, sheen);
		metal = 0.3 * sheen;
	}

	// At the silhouette the interpolated normal can end up edge-on or facing
	// away; the lighting then divides by almost zero and the glow blows the
	// pixel up into a flash. Tilt such normals towards the viewer.
	float ndv = dot(n, VIEW);
	if (ndv < 0.05) {
		n = normalize(n + VIEW * (0.05 - ndv));
	}

	vec3 wn = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float c = caustics(v_world.xz * 0.35 + v_world.y * 0.1, TIME * 0.8);

	NORMAL = n;
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	// Less specular along the back, which faces the lamp above.
	SPECULAR = is_fin ? 0.6 : mix(0.6, 0.3, smoothstep(0.4, 1.0, sin(UV.y * TAU)));
	BACKLIGHT = back;
	ALPHA = alpha;
	EMISSION = glow + col * c * 0.9 * (0.35 + 0.65 * max(wn.y, 0.0));
}
