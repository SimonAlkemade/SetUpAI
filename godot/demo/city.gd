extends Node3D
## A plain box city for the diffusion renderer to restyle: blocks, streets, a
## sun and a camera that drives down the avenues. Everything is built here so
## the scene file stays one node.
##
## Keys: Space pause the drive, Tab toggle diffusion, 1-4 presets.

const BLOCKS := 9
const BLOCK := 24.0
const STREET := 10.0
const SPEED := 6.0

var _cam: Camera3D
var _t := 0.0
var _driving := true
var renderer: DiffusionRenderer


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_environment()
	_ground()
	var mats: Array[StandardMaterial3D] = []
	for c in [Color(0.75, 0.72, 0.68), Color(0.55, 0.58, 0.62), Color(0.68, 0.55, 0.45), Color(0.85, 0.85, 0.82)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		mats.append(m)
	var pitch := BLOCK + STREET
	var half := (BLOCKS - 1) * pitch * 0.5
	for bx in BLOCKS:
		for bz in BLOCKS:
			var origin := Vector3(bx * pitch - half, 0, bz * pitch - half)
			for i in rng.randi_range(2, 5):
				var size := Vector3(rng.randf_range(6, 11), rng.randf_range(6, 45), rng.randf_range(6, 11))
				var p := origin + Vector3(rng.randf_range(-BLOCK, BLOCK - size.x * 2) * 0.5 + size.x * 0.5 - BLOCK * 0.25,
					size.y * 0.5, rng.randf_range(-BLOCK, BLOCK - size.z * 2) * 0.5 + size.z * 0.5 - BLOCK * 0.25)
				_box(p, size, mats[rng.randi() % mats.size()])

	_cam = Camera3D.new()
	_cam.fov = 70
	_cam.far = 600
	add_child(_cam)
	_cam.current = true

	renderer = DiffusionRenderer.new()
	add_child(renderer)
	var ui := preload("res://demo/prompt_ui.gd").new()
	ui.renderer = renderer
	add_child(ui)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2000, 2000)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.25, 0.27)
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)


func _process(delta: float) -> void:
	if _driving:
		_t += delta
	# Down one avenue and back along the next, looking a little to the side.
	var pitch := BLOCK + STREET
	var lane := pitch * 0.5
	var z := fmod(_t * SPEED, BLOCKS * pitch) - BLOCKS * pitch * 0.5
	_cam.position = Vector3(lane, 2.2, z)
	_cam.rotation = Vector3(deg_to_rad(4), PI + sin(_t * 0.25) * 0.5, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_driving = not _driving
			KEY_TAB:
				renderer.enabled = not renderer.enabled
