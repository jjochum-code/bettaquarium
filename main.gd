extends Node3D
## Builds the whole scene in code: environment, lights, light shafts, drifting
## particles, the fish and a slowly drifting camera.
## Keys: F food, C next palette, 2 random look, Cmd+F / F11 fullscreen, Esc quit.

const Betta := preload("res://betta.gd")
const Food := preload("res://food.gd")

## Sand and plants. Off for now: the fish looks best against plain black.
const SHOW_FLOOR := false
const FLOOR_Y := -2.3

# The fish is drawn life-size: the camera distance follows the window size and
# the screen's pixel density, so a bigger window shows more water, not a bigger fish.
const FISH_LENGTH_CM := 4.3
const FISH_LENGTH_UNITS := 1.7
const FALLBACK_DPI := 160.0
const FOV := 36.0
const BASE_CAM_DIST := 4.6

var _fish: Betta
var _camera: Camera3D
var _cam_attrs: CameraAttributesPractical
var _cam_focus := Vector3.ZERO
var _cam_dist := BASE_CAM_DIST
var _env: Environment
var _key_light: SpotLight3D
## Half the visible width and height of the water at the fish's depth.
var _half_view := Vector2(3.0, 1.5)
var _time := 0.0


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_shafts()
	if SHOW_FLOOR:
		_build_floor()
		_build_plants()
	_build_particles()
	_fish = Betta.new()
	add_child(_fish)
	_build_camera()
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()


func _process(delta: float) -> void:
	_time += delta
	# Follow the fish only loosely, so it swims through the frame.
	_cam_focus = _cam_focus.lerp(_fish.position * Vector3(0.4, 0.4, 0.3), 1.0 - exp(-delta * 1.2))
	_camera.position = Vector3(sin(_time * 0.07) * 0.8, 0.3 + sin(_time * 0.05) * 0.2, _cam_dist)
	_camera.look_at(_cam_focus)

	var dist := _camera.position.distance_to(_fish.position)
	_cam_attrs.dof_blur_far_distance = dist + 1.5
	_cam_attrs.dof_blur_near_distance = maxf(dist - 2.0, 0.3)


func _fit_view() -> void:
	var size := get_viewport().get_visible_rect().size
	var dpi := float(DisplayServer.screen_get_dpi(get_window().current_screen))
	if dpi < 50.0 or dpi > 800.0:
		dpi = FALLBACK_DPI
	var px_per_unit := FISH_LENGTH_CM / 2.54 * dpi / FISH_LENGTH_UNITS
	var half_w := size.x / px_per_unit * 0.5
	var half_h := size.y / px_per_unit * 0.5
	_cam_dist = half_h / tan(deg_to_rad(FOV * 0.5))
	_half_view = Vector2(half_w, half_h)

	# The swimming volume is the visible area minus room for the fins.
	_fish.set_bounds(Vector3(maxf(half_w - 1.1, 0.3), maxf(half_h - 0.6, 0.15), 1.3))

	# Same look at any camera distance: the same fog on the fish, and a light
	# pool that still covers the whole width, as bright as before.
	_env.fog_density = 0.07 * BASE_CAM_DIST / _cam_dist
	var spread := maxf(1.0, half_w / 3.0)
	_key_light.position = Vector3(0.5, 9.0 * spread, -1.0)
	_key_light.spot_range = 16.0 * spread
	_key_light.light_energy = 7.0 * spread


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var modified := key.meta_pressed or key.ctrl_pressed
	match key.keycode:
		KEY_F11:
			_toggle_fullscreen()
		KEY_F:
			if modified:
				_toggle_fullscreen()
			else:
				_drop_food()
		KEY_C:
			_fish.next_palette()
		KEY_2:
			_fish.randomize_look()
		KEY_ESCAPE:
			get_tree().quit()


func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN


## Drops a pellet in from above, somewhere along the top of the view.
func _drop_food() -> void:
	var pellet := Food.new()
	var reach := maxf(_half_view.x - 0.8, 0.3)
	pellet.surface_y = _half_view.y - 0.1
	pellet.bottom_y = -_half_view.y - 0.5
	pellet.position = Vector3(randf_range(-reach, reach), _half_view.y + 0.4, randf_range(-0.6, 0.6))
	add_child(pellet)


func _build_environment() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.25, 0.35)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.8
	# A specular hit can be hundreds of times brighter than its surroundings for
	# a frame. Uncapped, the glow turns it into a white disc.
	env.glow_hdr_luminance_cap = 2.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.fog_enabled = true
	# Fade to black with distance, not to a haze colour.
	env.fog_light_color = Color(0.0, 0.004, 0.006)
	env.fog_sun_scatter = 0.0
	env.fog_density = 0.07

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.3, 0.7, 0.75)
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 40.0

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08

	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70.0, 25.0, 0.0)
	sun.light_color = Color(0.8, 1.0, 0.95)
	sun.light_energy = 0.45
	sun.light_volumetric_fog_energy = 0.0
	sun.shadow_enabled = true
	sun.light_specular = 0.3
	add_child(sun)

	# Back light towards the camera, so the fins glow through.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 180.0, 0.0)
	rim.light_color = Color(0.5, 0.8, 1.0)
	rim.light_energy = 1.2
	rim.light_volumetric_fog_energy = 0.0
	rim.light_specular = 0.3
	add_child(rim)

	# A pool of light from straight above; everything outside it falls off into black.
	var key := SpotLight3D.new()
	_key_light = key
	key.position = Vector3(0.5, 9.0, -1.0)
	key.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	key.spot_range = 16.0
	key.spot_angle = 30.0
	key.spot_angle_attenuation = 0.6
	key.light_color = Color(0.75, 1.0, 0.92)
	key.light_energy = 7.0
	key.light_volumetric_fog_energy = 2.0
	key.shadow_enabled = true
	# Full-strength reflections of this lamp glint harshly off the back.
	key.light_specular = 0.25
	add_child(key)


## Light beams: additive sheets leaning with the sun, staggered in depth so the
## fish swims in front of some and behind others.
func _build_shafts() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/shafts.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 18:
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(2.0, 4.5), 14.0)
		quad.material = mat
		var sheet := MeshInstance3D.new()
		sheet.mesh = quad
		sheet.position = Vector3(rng.randf_range(-13.0, 13.0), 2.5, lerpf(-5.5, 1.6, float(i) / 17.0))
		sheet.rotation.z = -0.28 + rng.randf_range(-0.04, 0.04)
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sheet)


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sand.gdshader")
	plane.material = mat
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = plane
	floor_node.position.y = FLOOR_Y
	add_child(floor_node)


func _build_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var centers: Array[Vector3] = [
		# Out-of-focus framing in the foreground.
		Vector3(-4.3, FLOOR_Y, 1.8), Vector3(4.5, FLOOR_Y, 1.5),
	]
	while centers.size() < 26:
		var c := Vector3(rng.randf_range(-9.0, 9.0), FLOOR_Y, rng.randf_range(-7.0, -2.2))
		# Keep the middle of the stage open.
		if absf(c.x) > 2.2 or c.z < -4.0:
			centers.append(c)

	var transforms: Array[Transform3D] = []
	for c in centers:
		for blade in rng.randi_range(8, 16):
			var pos := c + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
			var rot := Basis(Vector3.UP, rng.randf() * TAU)
			transforms.append(Transform3D(rot.scaled(Vector3(1.0, rng.randf_range(1.6, 4.2), 1.0)), pos))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _make_blade()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/plant.gdshader")
	var plants := MultiMeshInstance3D.new()
	plants.multimesh = mm
	plants.material_override = mat
	plants.extra_cull_margin = 1.0
	add_child(plants)


func _make_blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	for i in segs + 1:
		var h := float(i) / segs
		var w := 0.07 * (1.0 - h * h * 0.8)
		for s: float in [0.0, 1.0]:
			st.set_uv(Vector2(s, h))
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3((s - 0.5) * 2.0 * w, h, 0.0))
	for i in segs:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 3)
	return st.commit()


func _build_particles() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var dot := GradientTexture2D.new()
	dot.gradient = gradient
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.7, 1.0, 0.9, 0.35)
	mat.albedo_texture = dot
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	quad.material = mat

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(14.0, 7.0, 5.0)
	process.gravity = Vector3(0.0, -0.01, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.scale_min = 0.4
	process.scale_max = 1.6
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.15
	process.turbulence_noise_scale = 2.0

	var motes := GPUParticles3D.new()
	motes.amount = 1400
	motes.lifetime = 24.0
	motes.preprocess = 24.0
	motes.visibility_aabb = AABB(Vector3(-16.0, -9.0, -8.0), Vector3(32.0, 18.0, 14.0))
	motes.process_material = process
	motes.draw_pass_1 = quad
	add_child(motes)


func _build_camera() -> void:
	_cam_attrs = CameraAttributesPractical.new()
	_cam_attrs.dof_blur_far_enabled = true
	_cam_attrs.dof_blur_far_transition = 5.0
	_cam_attrs.dof_blur_near_enabled = true
	_cam_attrs.dof_blur_near_transition = 1.0
	_cam_attrs.dof_blur_amount = 0.06

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.3, BASE_CAM_DIST)
	_camera.fov = FOV
	_camera.attributes = _cam_attrs
	add_child(_camera)
	_camera.make_current()
