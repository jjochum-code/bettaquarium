extends RefCounted
## Builds a betta procedurally: a lofted body plus fin sheets. The fin type
## (halfmoon, veiltail, plakat, ...) is described by a shape dictionary, see
## DEFAULT_SHAPE and betta_morphs.gd.
## Fish space: nose at z = -0.5, tail root at z = +0.5, y up.
## The vertex colour, UV and custom channel layout is documented in shaders/betta.gdshader.

const PART_BODY := 0.0
const PART_PECTORAL := 0.35
const PART_VENTRAL := 0.7
const PART_MEDIAN := 1.0

const BODY_RINGS := 36
const BODY_SEGMENTS := 20
## The body runs on slightly past the tail root to close it off.
const T_CAP := 1.03
## Step for finite-difference tangents and normals.
const EPS := 0.002

# Body profile sampled at t = 0, 0.1, ... 1: height of the back above and of the
# belly below the centre line, and half width. The belly is fuller than the back.
const PROFILE_TOP := [0.0, 0.05, 0.092, 0.125, 0.135, 0.135, 0.125, 0.11, 0.092, 0.078, 0.068]
const PROFILE_BOTTOM := [0.0, 0.07, 0.115, 0.15, 0.165, 0.16, 0.14, 0.115, 0.092, 0.076, 0.066]
const PROFILE_WIDTH := [0.0, 0.058, 0.085, 0.095, 0.092, 0.082, 0.068, 0.052, 0.038, 0.027, 0.018]

## Halfmoon proportions. Lengths are in fish lengths (body = 1), angles in radians.
const DEFAULT_SHAPE := {
	"caudal_spread": 1.4,  # half the opening angle of the tail
	"caudal_length": 0.74,
	"caudal_profile": "halfmoon",  # halfmoon, flat, round, point or double
	"caudal_sag": 0.0,  # how far long rays droop, in ray lengths
	"caudal_asym": 0.0,  # > 0 makes the lower half of the tail longer
	"dorsal_start": 0.52,  # where along the back the dorsal fin begins
	"dorsal_scale": 1.0,
	"dorsal_sweep": 1.05,  # how far the rear rays lean back
	"dorsal_sag": 0.0,
	"anal_scale": 1.0,
	"anal_sag": 0.0,
	"ventral_scale": 1.0,
}

var _st := SurfaceTool.new()
var _vertex_count := 0
var _shape: Dictionary


func _init(shape: Dictionary = {}) -> void:
	_shape = DEFAULT_SHAPE.merged(shape, true)


func build() -> ArrayMesh:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Surface tangents, so the shader can rebuild normals after deforming.
	_st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	_st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	_add_body()
	_add_caudal()
	_add_dorsal()
	_add_anal()
	for side: float in [-1.0, 1.0]:
		_add_ventral(side)
		_add_pectoral(side)
	return _st.commit()


static func top_height(t: float) -> float:
	return _sample(PROFILE_TOP, t)


static func bottom_height(t: float) -> float:
	return _sample(PROFILE_BOTTOM, t)


## Bettas feed from the surface: the mouth sits high on the head, with an almost
## straight forehead above it and a chin that drops away steeply below.
static func center_y(t: float) -> float:
	return 0.045 * (1.0 - smoothstep(0.0, 0.3, t))


static func half_width(t: float) -> float:
	return _sample(PROFILE_WIDTH, t)


## Catmull-Rom through the profile samples, tapered to zero past the tail root.
static func _sample(arr: Array, t: float) -> float:
	var cap := 1.0
	if t > 1.0:
		cap = clampf(1.0 - (t - 1.0) / (T_CAP - 1.0), 0.0, 1.0)
	t = clampf(t, 0.0, 1.0)
	if t < 0.1:
		# Wedge-shaped snout with a blunt tip.
		var first: float = arr[1]
		return first * pow(t / 0.1, 0.5)
	var f := t * 10.0
	var i := mini(int(f), 9)
	var u := f - float(i)
	var p0: float = arr[maxi(i - 1, 0)]
	var p1: float = arr[i]
	var p2: float = arr[i + 1]
	var p3: float = arr[mini(i + 2, 10)]
	var v := 0.5 * (2.0 * p1 + (p2 - p0) * u
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u * u)
	return v * cap


static func _body_point(t: float, a: float) -> Vector3:
	var s := sin(a)
	var h := top_height(t) if s >= 0.0 else bottom_height(t)
	return Vector3(half_width(t) * cos(a), center_y(t) + h * s, -0.5 + t)


static func _body_tangent_t(t: float, a: float) -> Vector3:
	return (_body_point(minf(t + EPS, T_CAP), a) - _body_point(maxf(t - EPS, 0.0), a)) / (2.0 * EPS)


static func _body_tangent_a(t: float, a: float) -> Vector3:
	return (_body_point(t, a + EPS) - _body_point(t, a - EPS)) / (2.0 * EPS)


static func _body_normal(t: float, a: float) -> Vector3:
	var n := _body_tangent_a(t, a).cross(_body_tangent_t(t, a))
	if n.length_squared() < 1e-14:
		return Vector3(0.0, 0.0, -1.0 if t < 0.5 else 1.0)
	n = n.normalized()
	if n.dot(Vector3(cos(a), sin(a), 0.0)) < 0.0:
		n = -n
	return n


func _add_body() -> void:
	# Rings bunch up towards the head, where the shape changes fastest.
	var ts: Array[float] = []
	for i in BODY_RINGS + 1:
		ts.append(pow(float(i) / BODY_RINGS, 1.5))
	ts.append(T_CAP)

	var start := _vertex_count
	for t in ts:
		for j in BODY_SEGMENTS + 1:
			var a := TAU * float(j) / BODY_SEGMENTS
			var tu := _body_tangent_t(t, a)
			var tv := _body_tangent_a(t, a)
			_st.set_custom(0, Color(tu.x, tu.y, tu.z, 0.0))
			_st.set_custom(1, Color(tv.x, tv.y, tv.z, 0.0))
			_st.set_color(Color(0.0, PART_BODY, 0.0, 1.0))
			_st.set_uv(Vector2(minf(t, 1.0), float(j) / BODY_SEGMENTS))
			_st.set_normal(_body_normal(t, a))
			_st.add_vertex(_body_point(t, a))
			_vertex_count += 1
	var row := BODY_SEGMENTS + 1
	for i in ts.size() - 1:
		for j in BODY_SEGMENTS:
			var a0 := start + i * row + j
			var b0 := a0 + row
			_quad(a0, a0 + 1, b0, b0 + 1)


## Adds a sheet spanned between a base polyline and a tip polyline. A sag bends
## the rays; it is scaled by each ray's length.
func _add_fin(bases: PackedVector3Array, tips: PackedVector3Array, nv: int,
		rays: float, part: float, phase: float, sag := Vector3.ZERO) -> void:
	var nu := bases.size() - 1
	var start := _vertex_count
	for i in nu + 1:
		var u := float(i) / nu
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, nu)
		var du := float(i1 - i0) / nu
		var ray_sag := sag * bases[i].distance_to(tips[i])
		for j in nv + 1:
			var v := float(j) / nv
			var tu := (_fin_point(bases, tips, i1, v, sag) - _fin_point(bases, tips, i0, v, sag)) / du
			var tv := tips[i] - bases[i] + ray_sag * 2.0 * v
			# w: flexibility grows along tv at the same rate as v.
			_st.set_custom(0, Color(tu.x, tu.y, tu.z, 0.0))
			_st.set_custom(1, Color(tv.x, tv.y, tv.z, 1.0))
			_st.set_color(Color(v, part, phase, 1.0))
			_st.set_uv(Vector2(u * rays, v))
			# Must be the sheet's true normal: the shader orients its rebuilt normal
			# by this one, and a rough guess flips it between neighbouring vertices.
			var n := tu.cross(tv)
			_st.set_normal(n.normalized() if n.length_squared() > 1e-12 else Vector3.RIGHT)
			_st.add_vertex(_fin_point(bases, tips, i, v, sag))
			_vertex_count += 1
	var row := nv + 1
	for i in nu:
		for j in nv:
			var a0 := start + i * row + j
			var b0 := a0 + row
			_quad(a0, a0 + 1, b0, b0 + 1)


func _fin_point(bases: PackedVector3Array, tips: PackedVector3Array, i: int,
		v: float, sag: Vector3) -> Vector3:
	return bases[i].lerp(tips[i], v) + sag * bases[i].distance_to(tips[i]) * v * v


func _quad(a0: int, a1: int, b0: int, b1: int) -> void:
	_st.add_index(a0)
	_st.add_index(b0)
	_st.add_index(a1)
	_st.add_index(a1)
	_st.add_index(b0)
	_st.add_index(b1)


func _add_caudal() -> void:
	var bases := PackedVector3Array()
	var tips := PackedVector3Array()
	var spread: float = _shape.caudal_spread
	var nu := 96
	for i in nu + 1:
		var u := float(i) / nu
		var ang := lerpf(-spread, spread, u)
		var base := Vector3(0.0, lerpf(-0.06, 0.06, u), 0.47)
		bases.append(base)
		tips.append(base + Vector3(0.0, sin(ang), cos(ang)) * _caudal_length(u))
	_add_fin(bases, tips, 32, 30.0, PART_MEDIAN, 0.0, Vector3(0.0, -float(_shape.caudal_sag), 0.0))


## Ray length across the tail, from u = 0 at the bottom edge to 1 at the top.
func _caudal_length(u: float) -> float:
	var x := 2.0 * u - 1.0
	var shape := 1.0
	match _shape.caudal_profile:
		"halfmoon":  # full D shape
			shape = 0.9 + 0.1 * sin(u * PI)
		"flat":  # delta: nearly straight outer edge
			shape = 0.94 + 0.06 * sin(u * PI)
		"round":
			shape = 1.0 - 0.35 * x * x
		"point":  # spade: tapers to a central point
			shape = 0.45 + 0.55 * pow(1.0 - absf(x), 1.6)
		"double":  # double tail: two lobes with a deep notch between them
			shape = 0.95 - 0.8 * exp(-pow(x / 0.16, 2.0))
	var asym: float = _shape.caudal_asym
	return float(_shape.caudal_length) * shape * (1.0 - asym * x)


func _add_dorsal() -> void:
	var bases := PackedVector3Array()
	var tips := PackedVector3Array()
	var start: float = _shape.dorsal_start
	var scale: float = _shape.dorsal_scale
	var nu := 48
	for i in nu + 1:
		var u := float(i) / nu
		var t := lerpf(start, 0.96, u)
		# Slightly off the midplane so it never z-fights with the tail.
		var base := Vector3(0.006, top_height(t) * 0.92, -0.5 + t)
		var ang := lerpf(0.35, _shape.dorsal_sweep, u)
		var length := lerpf(0.22, 0.6, smoothstep(0.0, 0.7, u)) * scale
		bases.append(base)
		tips.append(base + Vector3(0.0, cos(ang), sin(ang)) * length)
	var sag: float = _shape.dorsal_sag
	_add_fin(bases, tips, 26, 18.0, PART_MEDIAN, 0.0, Vector3(0.0, -sag, sag * 0.5))


func _add_anal() -> void:
	var bases := PackedVector3Array()
	var tips := PackedVector3Array()
	var scale: float = _shape.anal_scale
	var nu := 60
	for i in nu + 1:
		var u := float(i) / nu
		var t := lerpf(0.4, 0.97, u)
		var base := Vector3(-0.006, -bottom_height(t) * 0.92, -0.5 + t)
		var ang := lerpf(0.25, 1.1, u)
		var length := lerpf(0.25, 0.62, smoothstep(0.0, 0.8, u)) * scale
		bases.append(base)
		tips.append(base + Vector3(0.0, -cos(ang), sin(ang)) * length)
	var sag: float = _shape.anal_sag
	_add_fin(bases, tips, 26, 22.0, PART_MEDIAN, 0.0, Vector3(0.0, -sag * 0.3, sag))


func _add_ventral(side: float) -> void:
	var bases := PackedVector3Array()
	var tips := PackedVector3Array()
	var scale: float = _shape.ventral_scale
	var nu := 8
	for i in nu + 1:
		var u := float(i) / nu
		var t := lerpf(0.27, 0.33, u)
		var base := Vector3(side * 0.025, -bottom_height(t) * 0.9, -0.5 + t)
		var ang := lerpf(0.15, 0.5, u)
		var dir := Vector3(side * 0.25, -cos(ang), sin(ang)).normalized()
		bases.append(base)
		tips.append(base + dir * lerpf(0.5, 0.2, u) * scale)
	_add_fin(bases, tips, 20, 3.0, PART_VENTRAL, 0.3 + side * 0.1)


func _add_pectoral(side: float) -> void:
	var bases := PackedVector3Array()
	var tips := PackedVector3Array()
	var nu := 16
	var t := 0.24
	for i in nu + 1:
		var u := float(i) / nu
		var phi := lerpf(-0.9, 0.9, u)
		var base := Vector3(side * half_width(t) * 0.95, lerpf(-0.025, 0.025, u) - 0.01, -0.5 + t)
		var dir := Vector3(side * 0.75, sin(phi) * 0.7, 0.55).normalized()
		bases.append(base)
		tips.append(base + dir * 0.2 * (0.8 + 0.2 * cos(phi)))
	_add_fin(bases, tips, 12, 8.0, PART_PECTORAL, 0.6)
