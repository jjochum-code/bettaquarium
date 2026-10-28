extends SceneTree
## Prints the fish's eye positions on screen for every frame, to be matched
## against a movie of the same run (see sparkles.py).
## Usage: godot --path . -s tools/eye_track.gd -- [seed] [switch]
## Switches turn one thing off to find the cause of flashing pixels: noeyes,
## plaineyes, nofish, noglow, nodof, novolfog, nomsaa, nospec, noparticles.

const FRAMES := 120

var _main: Node
var _frame := 0


func _init() -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var args := OS.get_cmdline_user_args()
		_main._fish._rng.seed = int(args[0]) if args.size() > 0 else 1
		if args.size() > 1:
			_apply_switch(args[1])

	var fish: Node3D = _main._fish
	if _main.is_inside_tree() and fish != null and fish._eyes.size() == 2:
		var cam: Camera3D = _main._camera
		var e0 := cam.unproject_position(fish._eyes[0].global_position)
		var e1 := cam.unproject_position(fish._eyes[1].global_position)
		print("EYE %d %.1f %.1f %.1f %.1f" % [_frame, e0.x, e0.y, e1.x, e1.y])
		for i in 2:
			var q: Quaternion = fish._eyes[i].quaternion
			if not q.is_finite() or absf(q.length() - 1.0) > 0.01:
				print("BADQ frame %d eye %d %s" % [_frame, i, q])
	return _frame > FRAMES


func _apply_switch(switch: String) -> void:
	var fish: Node3D = _main._fish
	match switch:
		"noeyes":
			for eye: Node3D in fish._eyes:
				eye.visible = false
		"plaineyes":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.05, 0.04, 0.03)
			mat.roughness = 0.4
			for eye: MeshInstance3D in fish._eyes:
				eye.material_override = mat
		"nofish":
			fish._body.visible = false
		"noglow":
			_main._env.glow_enabled = false
		"nodof":
			_main._cam_attrs.dof_blur_far_enabled = false
			_main._cam_attrs.dof_blur_near_enabled = false
		"novolfog":
			_main._env.volumetric_fog_enabled = false
		"nomsaa":
			root.msaa_3d = Viewport.MSAA_DISABLED
		"nospec":
			for node in _main.get_children():
				if node is Light3D:
					node.light_specular = 0.0
		"noparticles":
			for node in _main.get_children():
				if node is GPUParticles3D:
					node.visible = false
		_:
			push_error("Unknown switch: %s" % switch)
