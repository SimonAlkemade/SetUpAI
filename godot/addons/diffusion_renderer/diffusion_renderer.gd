class_name DiffusionRenderer
extends CanvasLayer
## Draws the scene, sends it to the diffusion server every `interval_ms`, and
## shows the restyled frame full-screen over it.
##
## The scene is rendered a second time into a small SubViewport at
## `resolution`, so the GPU->CPU readback and the JPEG are tiny. Its camera
## copies `source_camera` (default: the active camera) every frame.
##
## Fails open: with `enabled` off, or no frame from the server for
## `stale_after` seconds, the overlay hides and the plain scene shows.

signal stats_updated(stats: Dictionary)

@export var enabled := true:
	set(v):
		enabled = v
		if _overlay:
			_overlay.visible = false
@export var server_url := "ws://127.0.0.1:8765"
@export_multiline var prompt := "a futuristic sci-fi city, neon lights, highly detailed":
	set(v):
		prompt = v
		_push_config()
## How much the model may change the frame. Low keeps the geometry, high
## follows the prompt more.
@export_range(0.05, 1.0, 0.01) var strength := 0.5:
	set(v):
		strength = v
		_push_config()
@export var noise_seed := 42:
	set(v):
		noise_seed = v
		_push_config()
## Server-side EMA with the previous output; trades flicker for smear.
@export_range(0.0, 0.95, 0.01) var blend := 0.0:
	set(v):
		blend = v
		_push_config()
@export_range(10, 1000) var interval_ms := 50
## Snapped to multiples of 64 by the server.
@export var resolution := Vector2i(320, 192):
	set(v):
		resolution = v
		if _sub:
			_sub.size = v
		_push_config()
@export_range(0.0, 1.0, 0.01) var mix := 1.0:
	set(v):
		mix = v
		if _overlay:
			_overlay.modulate.a = v
@export var smooth_filter := true:
	set(v):
		smooth_filter = v
		if _overlay:
			_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if v else CanvasItem.TEXTURE_FILTER_NEAREST
@export var jpeg_quality := 0.8
## Frames sent but not yet answered. The server keeps only the newest anyway;
## this just stops us filling the socket while it is busy.
@export var max_in_flight := 2
@export var stale_after := 1.0
## While a restyled frame covers the whole screen (mix 1), stop drawing the
## full-resolution scene underneath it. The model and Godot share one GPU, so
## this hands the time to the model. It comes back the moment the overlay hides.
@export var skip_full_res := true
@export var source_camera: Camera3D

var client := DiffusionClient.new()
var last_stats := {}

var _sub: SubViewport
var _cam: Camera3D
var _overlay: TextureRect
var _tex: ImageTexture
var _next_id := 1
var _last_shown := 0
var _since_send := 0.0
var _since_frame := INF


func _ready() -> void:
	layer = 50
	_sub = SubViewport.new()
	_sub.size = resolution
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	_cam = Camera3D.new()
	_sub.add_child(_cam)

	_overlay = TextureRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)
	mix = mix
	smooth_filter = smooth_filter

	client.url = server_url
	client.frame_received.connect(_on_frame)
	client.stats_received.connect(func(s: Dictionary) -> void:
		last_stats = s
		stats_updated.emit(s))
	_push_config()


func _exit_tree() -> void:
	client.close()
	get_viewport().disable_3d = false


func _process(delta: float) -> void:
	_follow_camera()
	client.poll(delta)
	_since_frame += delta
	if _overlay.visible and _since_frame > stale_after:
		_overlay.visible = false
	get_viewport().disable_3d = skip_full_res and _overlay.visible and mix >= 0.999
	if not enabled:
		return
	_since_send += delta
	var interval := interval_ms / 1000.0
	if _since_send < interval:
		return
	# Keep the cadence, but never bank more than one tick on a slow frame.
	_since_send = minf(_since_send - interval, interval)
	if _next_id - 1 - _last_shown >= max_in_flight and _since_frame < stale_after:
		return
	var img := _sub.get_texture().get_image()
	if img == null or img.is_empty():
		return
	if client.send_frame(_next_id, img.save_jpg_to_buffer(jpeg_quality)):
		_next_id += 1


func _follow_camera() -> void:
	var src := source_camera if source_camera else get_viewport().get_camera_3d()
	if src == null or src == _cam:
		return
	_cam.global_transform = src.global_transform
	_cam.fov = src.fov
	_cam.near = src.near
	_cam.far = src.far
	_cam.cull_mask = src.cull_mask
	_cam.environment = src.environment
	_cam.current = true


func _on_frame(id: int, img: Image) -> void:
	if id <= _last_shown:
		return  # a late reply to an older frame
	_last_shown = id
	_since_frame = 0.0
	if _tex == null or _tex.get_size() != Vector2(img.get_size()):
		_tex = ImageTexture.create_from_image(img)
		_overlay.texture = _tex
	else:
		_tex.update(img)
	_overlay.visible = enabled


func _push_config() -> void:
	if client == null:
		return
	client.set_config({
		"prompt": prompt,
		"strength": strength,
		"seed": noise_seed,
		"blend": blend,
		"size": [resolution.x, resolution.y],
	})
