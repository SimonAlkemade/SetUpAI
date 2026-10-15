extends SceneTree
## godot --headless --path godot --script res://tests/test_client_framing.gd

var _failed := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		printerr("FAIL: ", what)


func _init() -> void:
	var payload := PackedByteArray([0xFF, 0xD8, 1, 2, 3])
	var data := DiffusionClient.encode_frame(7, payload)
	check(data.slice(0, 4) == PackedByteArray([7, 0, 0, 0]), "id is uint32 little-endian")
	var f := DiffusionClient.decode_frame(data)
	check(f["id"] == 7 and f["payload"] == payload, "frame round trip")
	check(DiffusionClient.decode_frame(PackedByteArray([1, 2])).is_empty(), "short frame rejected")
	check(DiffusionClient.decode_frame(DiffusionClient.encode_frame(0xFFFFFFFF, payload))["id"] == 0xFFFFFFFF,
		"max id survives")

	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.9))
	var back := Image.new()
	check(back.load_jpg_from_buffer(img.save_jpg_to_buffer(0.9)) == OK, "jpeg decodes")
	check(back.get_size() == Vector2i(64, 32), "jpeg keeps size")
	check(back.get_pixel(10, 10).is_equal_approx(Color(0.2, 0.6, 0.9)) or
		(back.get_pixel(10, 10) - Color(0.2, 0.6, 0.9)).get_luminance() < 0.05, "jpeg keeps colour")

	print("framing: %s" % ("ok" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed else 0)
