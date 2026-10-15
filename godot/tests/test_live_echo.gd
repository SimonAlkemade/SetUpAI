extends SceneTree
## Against a running `python server/diffuse_server.py --backend echo`:
##   godot --headless --path godot --script res://tests/test_live_echo.gd
## Sends one frame through DiffusionClient and checks it comes back inverted.

var client := DiffusionClient.new()
var _ok := false
var _stats := false
var _t := 0.0


func _init() -> void:
	client.frame_received.connect(func(id: int, img: Image) -> void:
		var c := img.get_pixel(8, 8)
		var ok := id == 5 and absf(c.r - 0.8) < 0.05 and absf(c.g - 0.4) < 0.05
		print("echo frame: %s (id %d, %s)" % ["ok" if ok else "WRONG", id, c])
		_ok = ok)
	client.stats_received.connect(func(s: Dictionary) -> void:
		print("echo stats: ", s)
		_stats = int(s.get("id", -1)) == 5)
	client.connected.connect(func() -> void:
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		img.fill(Color(0.2, 0.6, 0.9))
		client.send_frame(5, img.save_jpg_to_buffer(0.95)))


func _process(delta: float) -> bool:
	client.poll(delta)
	_t += delta
	if _ok and _stats:
		quit(0)
	elif _t > 10.0:
		printerr("echo: timed out (frame ok=%s, stats=%s)" % [_ok, _stats])
		quit(1)
	return false
