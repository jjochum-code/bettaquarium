extends Node3D
## A food pellet: drops in from above, floats at the surface for a moment,
## then sinks slowly. Fish find pellets through GROUP.

const GROUP := "food"
const RADIUS := 0.027
const DROP_SPEED := 1.6
const FLOAT_TIME := 2.0
const SINK_SPEED := 0.1

## Set by the scene before the pellet is added. Below bottom_y it is removed.
var surface_y := 1.0
var bottom_y := -2.0

## Seconds since the pellet hit the water.
var age := 0.0
## Current drift in units per second, so a fish can lead its strike.
var velocity := Vector3.ZERO

var _in_water := false
var _wobble := 0.0
var _mesh: MeshInstance3D
# Once eaten: the fish, and its mouth in the fish's own space.
var _eater: Node3D
var _mouth := Vector3.ZERO
var _taken_time := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_wobble = randf() * TAU
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 1.7
	sphere.radial_segments = 12
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.38, 0.12)
	mat.roughness = 0.45
	# A faint glow keeps the pellet readable against the dark water.
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.3, 0.1)
	mat.emission_energy_multiplier = 0.25
	sphere.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	add_child(_mesh)


## Pellets can only be taken once they are in the water.
func is_edible() -> bool:
	return _in_water


## Pushes the pellet through the water, e.g. with a fish's bow wave.
func nudge(offset: Vector3) -> void:
	if _in_water and _eater == null:
		position += offset


## Called once the mouth is close enough. The pellet is pulled the last
## millimetre into the mouth over the next few frames.
func engulf(eater: Node3D, mouth: Vector3) -> void:
	remove_from_group(GROUP)
	_eater = eater
	_mouth = mouth


func _process(delta: float) -> void:
	if _eater != null:
		_taken_time += delta
		if _taken_time < 0.05:
			position = position.lerp(_eater.to_global(_mouth), 1.0 - exp(-delta * 60.0))
		elif _mesh.visible:
			_mesh.visible = false
		elif _taken_time > 0.4:
			# A few crumbs escape through the gills while chewing.
			set_process(false)
			var side := 1.0 if randf() < 0.5 else -1.0
			position = _eater.to_global(Vector3(side * 0.07, 0.0, -0.3))
			_burst(3, Color(0.55, 0.25, 0.1), Vector3(0.0, -0.03, 0.0), 0.05, Vector3(side, 0.0, 0.3), 40.0)
			get_tree().create_timer(1.5).timeout.connect(queue_free)
		return
	if not _in_water:
		position.y -= DROP_SPEED * delta
		if position.y <= surface_y:
			position.y = surface_y
			_in_water = true
			# Air pulled under by the splash bubbles back up.
			var bubble := Color(0.8, 0.95, 1.0, 0.5)
			_burst(10, bubble, Vector3(0.0, 0.5, 0.0), 0.35, Vector3.DOWN, 50.0)
		return

	age += delta
	var before := position
	var sinking := smoothstep(FLOAT_TIME, FLOAT_TIME + 2.0, age)
	position.y -= sinking * SINK_SPEED * delta
	# Bob at the surface, then drift and tumble on the way down.
	position.y += sin(age * 2.0 + _wobble) * 0.02 * (1.0 - sinking) * delta
	position.x += sin(age * 0.7 + _wobble) * 0.03 * delta
	_mesh.rotation += Vector3(0.4, 0.7, 0.3) * maxf(sinking, 0.2) * delta
	velocity = (position - before) / delta
	if position.y < bottom_y:
		queue_free()


func _burst(count: int, color: Color, gravity: Vector3, speed: float,
		direction: Vector3, spread: float) -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	dot.radial_segments = 6
	dot.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.1
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = mat

	var particles := CPUParticles3D.new()
	particles.mesh = dot
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 1.2
	particles.explosiveness = 0.9
	particles.direction = direction
	particles.spread = spread
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.gravity = gravity
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.3
	add_child(particles)
	particles.emitting = true
