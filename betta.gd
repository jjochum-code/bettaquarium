extends Node3D
## A single betta: procedural mesh, shader-driven swimming and a small
## cruise / hover / dart / feed state machine.

const BettaMesh := preload("res://betta_mesh.gd")
const BettaMorphs := preload("res://betta_morphs.gd")
const Food := preload("res://food.gd")
const BODY_SHADER := preload("res://shaders/betta.gdshader")
const EYE_SHADER := preload("res://shaders/eye.gdshader")

enum State { CRUISE, HOVER, DART, FEED }
## Approach, pause briefly to aim, lunge with the mouth opening, chew.
enum Feed { APPROACH, AIM, STRIKE, CHEW }

## Tip of the snout, in fish space.
const MOUTH := Vector3(0.0, 0.045, -0.5)
## Mouth-to-pellet distance from which a lined-up fish strikes.
const STRIKE_DIST := 0.32
## Roughly the mouth's own width: as far as the suction of an opening mouth reaches.
const CAPTURE_DIST := 0.07
const STRIKE_SPEED := 1.3
const CHEW_TIME := 0.9
## A pellet has to be in the water this long before the fish notices it.
const NOTICE_TIME := 0.3

const EYE_RADIUS := 0.028
## How far an eye can turn away from its resting direction, in radians.
const EYE_RANGE := 0.25

const MAX_DELTA := 0.05
## Speed at which the swimming animation reaches full intensity.
const FULL_PACE_SPEED := 1.2


## Steering tuning for the current state, see _steering().
class Steering:
	var speed := 0.45
	var accel := 2.0
	var decel := 0.9
	var turn_rate := 0.9
	var turn_gain := 1.5
	## How quickly the turn rate follows its target.
	var turn_ease := 1.6
	## Speed factor during a full about-turn.
	var tight_turn_speed := 0.5
	var pitch_rate := 0.7
	var max_pitch := 0.75
	## Amplitude of the rising and falling path towards the target.
	var wander := 0.3


## Damped spring the fin tips hang on, so they overshoot and swing.
class Spring:
	var value := Vector3.ZERO
	var _velocity := Vector3.ZERO
	var _stiffness: float
	var _damping: float

	func _init(stiffness: float, damping: float) -> void:
		_stiffness = stiffness
		_damping = damping

	func update(target: Vector3, delta: float) -> Vector3:
		_velocity += ((target - value) * _stiffness - _velocity * _damping) * delta
		value += _velocity * delta
		return value


## Swimming volume (half extents around the origin), set by the scene.
var _bounds := Vector3(2.6, 1.1, 1.3)

var _mat := ShaderMaterial.new()
var _body: MeshInstance3D
var _eyes: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _palette := 0

var _state := State.CRUISE
var _state_time := 0.0
var _target := Vector3.ZERO
var _feed := Feed.APPROACH
var _feed_time := 0.0
var _aim_time := 0.0
## A fast strike can carry the mouth past the pellet within one frame, so
## capture is tested along the path since the last frame.
var _prev_mouth := Vector3.ZERO

var _time := 0.0
var _yaw := PI * 0.5
var _pitch := 0.0
var _yaw_vel := 0.0
var _pitch_vel := 0.0
var _speed := 0.0

var _swim_phase := 0.0
var _pect_phase := 0.0
var _fin_drag := Spring.new(30.0, 6.5)
## Long fins: slower, softer and swinging further.
var _fin_drag_slow := Spring.new(7.0, 1.8)
var _mouth_open := 0.0
var _gill_open := 0.0
var _eye_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _eye_next_glance: Array[float] = [0.0, 0.0]


func _ready() -> void:
	_rng.randomize()
	_mat.shader = BODY_SHADER

	_body = MeshInstance3D.new()
	_body.material_override = _mat
	# The vertex shader moves the fins well outside the static bounding box.
	_body.extra_cull_margin = 1.0
	add_child(_body)
	_add_eyes()
	_apply_preset()

	_pick_target()
	_state_time = 6.0


## The fish is not teleported: if it ends up outside, it swims back in.
func set_bounds(half_extents: Vector3) -> void:
	_bounds = half_extents
	_target = _target.clamp(-_bounds, _bounds)


func next_palette() -> void:
	_palette = (_palette + 1) % BettaMorphs.PRESETS.size()
	_apply_preset()


func randomize_look() -> void:
	var look := BettaMorphs.random_look(_rng)
	_apply_look(look.colors, look.fins, look.mesh)


## Eyes are spheres set into the head so a little over half shows. They turn
## in their sockets; the shader draws pupil, iris and cornea.
func _add_eyes() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = EYE_RADIUS
	mesh.height = EYE_RADIUS * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var t := 0.125
	var y := BettaMesh.center_y(t) + 0.022
	var x := BettaMesh.half_width(t) - EYE_RADIUS * 0.45
	for side: float in [1.0, -1.0]:
		var mat := ShaderMaterial.new()
		mat.shader = EYE_SHADER
		mat.set_shader_parameter("side", side)
		var eye := MeshInstance3D.new()
		eye.mesh = mesh
		eye.material_override = mat
		eye.position = Vector3(side * x, y, -0.5 + t)
		_body.add_child(eye)
		_eyes.append(eye)


func _apply_preset() -> void:
	var colors := BettaMorphs.with_defaults(BettaMorphs.PRESETS[_palette])
	_apply_look(colors, BettaMorphs.FIN_DEFAULTS, {})


func _apply_look(colors: Dictionary, fins: Dictionary, shape: Dictionary) -> void:
	for params: Dictionary in [colors, fins]:
		for key: String in params:
			_mat.set_shader_parameter(key, params[key])
	_body.mesh = BettaMesh.new(shape).build()

	# The iris picks up a hint of the body's sheen, and the socket blends into
	# the head instead of forming a black ring.
	var iris := Color(0.5, 0.38, 0.18).lerp(colors.iri_a, 0.4) * 0.8
	var rim: Color = colors.body_dark * 0.5
	for eye in _eyes:
		var mat := eye.material_override as ShaderMaterial
		mat.set_shader_parameter("iris_light", iris)
		mat.set_shader_parameter("rim_color", rim)


func _process(delta: float) -> void:
	delta = minf(delta, MAX_DELTA)
	if delta <= 0.0:
		return
	_time += delta
	_state_time -= delta

	var food := _nearest_food()
	if food != null and _state != State.FEED:
		_state = State.FEED
		_set_feed(Feed.APPROACH)
	var remaining := _update_target(food, delta)
	_steer(_steering(remaining), delta)
	_animate_swimming(delta)
	_update_mouth(remaining, delta)
	_update_eyes(food, delta)


## Updates the state machine and the target. Returns the distance still to
## cover, measured from the mouth while going for a pellet.
func _update_target(food: Food, delta: float) -> float:
	if _state == State.FEED:
		_update_feeding(food, delta)
		if _state == State.FEED and _feed != Feed.CHEW:
			var mouth := to_global(MOUTH)
			_target = food.position
			if _feed == Feed.STRIKE:
				# Lead the strike: aim where the sinking pellet will be on arrival.
				_target += food.velocity * food.position.distance_to(mouth) / STRIKE_SPEED
			return _target.distance_to(mouth)
	elif _state_time <= 0.0 or (_state != State.HOVER and position.distance_to(_target) < 0.7):
		_next_state()
	return position.distance_to(_target)


func _steering(remaining: float) -> Steering:
	var s := Steering.new()
	match _state:
		State.HOVER:
			s.speed = 0.02
		State.DART:
			s.speed = 1.5
			s.turn_rate = 1.4
		State.FEED:
			s.turn_rate = 2.2
			s.turn_gain = 3.0
			s.turn_ease = 4.0
			s.tight_turn_speed = 0.15
			s.max_pitch = 1.35
			s.pitch_rate = 1.2
			s.wander = 0.0
			s.decel = 2.5
			match _feed:
				Feed.APPROACH:
					# Brake into striking range rather than swimming into the pellet,
					# but never so slowly that a sinking pellet gets away.
					s.speed = clampf((remaining - 0.22) * 1.2, 0.15, 1.0)
				Feed.AIM:
					s.speed = 0.04
				Feed.STRIKE:
					s.speed = STRIKE_SPEED
					s.accel = 9.0
					s.pitch_rate = 2.0
				Feed.CHEW:
					s.speed = 0.0
	return s


func _steer(s: Steering, delta: float) -> void:
	var to_target := _target - position
	var want_speed := s.speed
	var want_yaw_vel := sin(_time * 0.5) * 0.12
	var want_pitch := sin(_time * 0.4) * 0.12
	var chewing := _state == State.FEED and _feed == Feed.CHEW
	if _state != State.HOVER and not chewing and to_target.length() > 0.01:
		var dir := to_target.normalized()
		var yaw_err := wrapf(atan2(-dir.x, -dir.z) - _yaw, -PI, PI)
		want_yaw_vel = clampf(yaw_err * s.turn_gain, -s.turn_rate, s.turn_rate)
		# Ease off through tight turns instead of pivoting at full speed.
		want_speed *= lerpf(1.0, s.tight_turn_speed, clampf(absf(yaw_err) / 2.0, 0.0, 1.0))
		var wander := sin(_time * 0.55) * s.wander
		want_pitch = clampf(asin(clampf(dir.y, -1.0, 1.0)) + wander, -s.max_pitch, s.max_pitch)

		if _state == State.FEED and _feed == Feed.APPROACH:
			var from_mouth := _target - to_global(MOUTH)
			var lined_up := absf(yaw_err) < 0.5 and absf(want_pitch - _pitch) < 0.4
			if (-basis.z).angle_to(from_mouth) > 1.0 and to_target.length() < 0.6:
				# Overshot, the pellet is beside the head. Back off on the pectorals.
				want_speed = -0.2
			elif not lined_up:
				# Turn almost on the spot so the mouth does not circle the pellet.
				want_speed = 0.12

	# Turn rates are eased too, so a new target never snaps the body round.
	_yaw_vel = lerpf(_yaw_vel, want_yaw_vel, _damp(s.turn_ease, delta))
	_yaw += _yaw_vel * delta
	var want_pitch_vel := clampf((want_pitch - _pitch) * 2.0, -s.pitch_rate, s.pitch_rate)
	_pitch_vel = lerpf(_pitch_vel, want_pitch_vel, _damp(2.0, delta))
	_pitch += _pitch_vel * delta

	var accel := s.accel if want_speed > _speed else s.decel
	_speed = lerpf(_speed, want_speed, _damp(accel, delta))

	var roll := clampf(_yaw_vel * 0.12, -0.25, 0.25)
	basis = Basis.from_euler(Vector3(_pitch, _yaw, roll))
	position += -basis.z * _speed * delta
	position.y += sin(_time * 0.9) * 0.12 * delta


## Feeds the body wave, fin motion and head sway to the shader.
func _animate_swimming(delta: float) -> void:
	var pace := clampf(_speed / FULL_PACE_SPEED, 0.0, 1.0)
	_swim_phase += delta * lerpf(2.5, 13.0, pace)
	_pect_phase += delta * lerpf(9.0, 4.0, pace)

	var drag_target := Vector3(-_yaw_vel * 0.1, _pitch_vel * 0.1 - 0.05 * (1.0 - pace), _speed * 0.05)
	_mat.set_shader_parameter("drag", _fin_drag.update(drag_target, delta))
	_mat.set_shader_parameter("drag_slow", _fin_drag_slow.update(drag_target * 1.4, delta))

	# At rest the trunk keeps flexing slowly from side to side.
	var idle_flex := (sin(_time * 0.9) * 0.05 + sin(_time * 0.37) * 0.03) * (1.0 - pace)
	_mat.set_shader_parameter("swim_phase", _swim_phase)
	_mat.set_shader_parameter("swim_amp", lerpf(0.02, 0.075, pace) + absf(_yaw_vel) * 0.012)
	_mat.set_shader_parameter("bend", clampf(-_yaw_vel * 0.2 + idle_flex, -0.35, 0.35))
	_mat.set_shader_parameter("bend_v", clampf(_pitch_vel * 0.25, -0.3, 0.3))
	_mat.set_shader_parameter("pect_phase", _pect_phase)
	_mat.set_shader_parameter("pect_amp", lerpf(1.0, 0.35, pace))
	# Fins fold and pull taut at speed, and open up and billow when idling.
	_mat.set_shader_parameter("fin_spread", lerpf(1.0, 0.8, pace))
	_mat.set_shader_parameter("fin_wave", lerpf(0.095, 0.06, pace))

	# The head swings against the tail beat, continuing the body wave forwards.
	var sway := lerpf(0.015, 0.07, pace) + absf(_yaw_vel) * 0.01
	_body.rotation.y = -sin(_swim_phase + 2.5) * sway
	_body.position.x = sin(_swim_phase + 0.8) * sway * 0.25


func _update_feeding(food: Food, delta: float) -> void:
	_feed_time += delta
	if _feed == Feed.CHEW:
		if _feed_time > CHEW_TIME:
			_set_feed(Feed.APPROACH)
			if food == null:
				_hover(_rng.randf_range(1.5, 3.0))
		return
	if food == null:
		_hover(_rng.randf_range(1.5, 3.0))
		return

	var mouth := to_global(MOUTH)
	var from_mouth := food.position - mouth
	var dist := from_mouth.length()
	var off_axis := (-basis.z).angle_to(from_mouth)
	var swept := Geometry3D.get_closest_point_to_segment(food.position, _prev_mouth, mouth)
	_prev_mouth = mouth

	match _feed:
		Feed.APPROACH, Feed.AIM:
			if dist < 0.1 and off_axis < 1.0:
				# Right in front of the mouth: snap without a run-up.
				_set_feed(Feed.STRIKE)
			elif _feed == Feed.APPROACH and dist < STRIKE_DIST and off_axis < 0.45:
				_set_feed(Feed.AIM)
				_aim_time = _rng.randf_range(0.15, 0.5)
			elif _feed == Feed.AIM and off_axis > 0.6:
				_set_feed(Feed.APPROACH)
			elif _feed == Feed.AIM and _feed_time > _aim_time:
				_set_feed(Feed.STRIKE)
		Feed.STRIKE:
			if swept.distance_to(food.position) < CAPTURE_DIST:
				food.engulf(self, MOUTH)
				_set_feed(Feed.CHEW)
				return
			if off_axis > 1.5 or _feed_time > 0.6:
				_set_feed(Feed.APPROACH)

	if _feed != Feed.STRIKE and dist < 0.2:
		# The bow wave pushes the pellet away, which is why bettas strike
		# instead of just swimming onto their food.
		food.nudge(-basis.z * _speed * 0.35 * delta)


func _set_feed(phase: Feed) -> void:
	_feed = phase
	_feed_time = 0.0


## Independent saccades around the fish while idle; both eyes on the pellet
## while feeding.
func _update_eyes(food: Food, delta: float) -> void:
	for i in _eyes.size():
		var eye := _eyes[i]
		var side := 1.0 if i == 0 else -1.0
		if food != null and _state == State.FEED:
			_eye_targets[i] = food.position
		else:
			_eye_next_glance[i] -= delta
			if _eye_next_glance[i] <= 0.0:
				_eye_next_glance[i] = _rng.randf_range(0.6, 2.5)
				var glance := Vector3(side * _rng.randf_range(0.2, 1.2), _rng.randf_range(-0.4, 0.4),
						_rng.randf_range(-1.5, -0.3))
				_eye_targets[i] = to_global(glance)

		var rest := Vector3(side, 0.0, 0.0)
		var look := (_body.to_local(_eye_targets[i]) - eye.position).normalized()
		var angle := rest.angle_to(look)
		if angle > EYE_RANGE:
			look = rest.slerp(look, EYE_RANGE / angle)
		var want := Quaternion(rest, look) if angle > 0.001 else Quaternion.IDENTITY
		eye.quaternion = eye.quaternion.slerp(want, _damp(8.0, delta))


## Slow breathing, a wide-open mouth at the end of a strike, and a few quick
## chewing movements with flared gills after it.
func _update_mouth(remaining: float, delta: float) -> void:
	var breath := 0.5 + 0.5 * sin(_time * 5.0)
	var want_mouth := 0.06 * breath
	var want_gill := 0.15 * breath
	if _state == State.FEED:
		match _feed:
			Feed.STRIKE:
				want_mouth = 1.0 if remaining < 0.15 else 0.3
			Feed.CHEW:
				var chomp := maxf(sin(_feed_time / CHEW_TIME * 3.0 * TAU), 0.0)
				want_mouth = 0.3 * chomp
				want_gill = 0.3 + 0.4 * chomp
	_mouth_open = lerpf(_mouth_open, want_mouth, _damp(25.0, delta))
	_gill_open = lerpf(_gill_open, want_gill, _damp(12.0, delta))
	_mat.set_shader_parameter("mouth_open", _mouth_open)
	_mat.set_shader_parameter("gill_open", _gill_open)


func _nearest_food() -> Food:
	var best: Food = null
	var best_dist := INF
	var mouth := to_global(MOUTH)
	for pellet: Food in get_tree().get_nodes_in_group(Food.GROUP):
		if not pellet.is_edible() or pellet.age < NOTICE_TIME:
			continue
		var dist := mouth.distance_to(pellet.position)
		if dist < best_dist:
			best = pellet
			best_dist = dist
	return best


func _next_state() -> void:
	var r := _rng.randf()
	if _state != State.HOVER and r < 0.35:
		_hover(_rng.randf_range(1.5, 4.5))
	elif r < 0.47:
		_state = State.DART
		_state_time = _rng.randf_range(0.6, 1.2)
		# Roughly straight ahead; a dart never starts with a spin.
		var ahead := (-basis.z * _rng.randf_range(1.5, 2.5)).rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
		_target = (position + ahead).clamp(-_bounds, _bounds)
	else:
		_state = State.CRUISE
		_state_time = _rng.randf_range(5.0, 10.0)
		_pick_target()


func _hover(duration: float) -> void:
	_state = State.HOVER
	_state_time = duration


func _pick_target() -> void:
	for attempt in 8:
		var y := _rng.randf_range(-_bounds.y, _bounds.y)
		# Usually head for the other half of the water column.
		if _rng.randf() < 0.65:
			y = (-1.0 if position.y > 0.0 else 1.0) * _rng.randf_range(0.3, 1.0) * _bounds.y
		_target = Vector3(_rng.randf_range(-_bounds.x, _bounds.x), y, _rng.randf_range(-_bounds.z, _bounds.z))
		# Prefer long sideways runs, which show the fish in profile.
		if absf(_target.x - position.x) > minf(1.5, _bounds.x):
			return


## Frame-rate independent smoothing factor for lerp().
static func _damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
