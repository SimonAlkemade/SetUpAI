extends SceneTree
## Boots the demo, lets it run against whatever server is up, and saves a
## screenshot. Needs a real renderer (not --headless):
##   godot --path godot --script res://tests/demo_smoke.gd -- /tmp/shot.png
## Exits 1 if no restyled frame arrived (start the server first, echo is fine).

var _t := 0.0
var _city: Node
var _frames := 0
var _hooked := false


func _init() -> void:
	_city = load("res://demo/city.tscn").instantiate()
	root.add_child(_city)


func _process(delta: float) -> bool:
	_t += delta
	if not _hooked and _city.renderer != null:
		_city.renderer.client.frame_received.connect(func(_i: int, _img: Image) -> void: _frames += 1)
		_hooked = true
	if _t < 4.0:
		return false
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "user://demo_smoke.png"
	root.get_texture().get_image().save_png(path)
	var got := _frames
	var r: DiffusionRenderer = _city.renderer
	print("demo: %d restyled frames in 4 s (%d sent, %d process frames), screenshot %s" % [
		got, r._next_id - 1, Engine.get_process_frames(), path])
	quit(0 if got > 0 else 1)
	return false
