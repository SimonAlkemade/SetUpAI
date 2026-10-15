class_name DiffusionClient
extends RefCounted
## WebSocket link to server/diffuse_server.py. Call `poll()` every frame.
##
## Binary message: uint32 little-endian frame id, then JPEG bytes (both ways).
## Text message: JSON -- "config" from us, "stats" from the server.
## Reconnects on its own; while disconnected `send_frame` is a no-op, so the
## game never waits on the server.

signal frame_received(id: int, image: Image)
signal stats_received(stats: Dictionary)
signal connected
signal disconnected

const RECONNECT_MIN := 0.5
const RECONNECT_MAX := 5.0

var url := "ws://127.0.0.1:8765"
var _peer: WebSocketPeer
var _was_open := false
var _retry_in := 0.0
var _backoff := RECONNECT_MIN
var _config := {}


static func encode_frame(id: int, jpeg: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, id & 0xFFFFFFFF)
	out.append_array(jpeg)
	return out


## Returns {"id": int, "payload": PackedByteArray}, or {} if too short.
static func decode_frame(data: PackedByteArray) -> Dictionary:
	if data.size() < 4:
		return {}
	return {"id": data.decode_u32(0), "payload": data.slice(4)}


func is_open() -> bool:
	return _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


## Remembered and re-sent after every reconnect.
func set_config(config: Dictionary) -> void:
	_config = config.duplicate()
	_config["type"] = "config"
	if is_open():
		_peer.send_text(JSON.stringify(_config))


func send_frame(id: int, jpeg: PackedByteArray) -> bool:
	if not is_open():
		return false
	return _peer.send(encode_frame(id, jpeg)) == OK


func close() -> void:
	if _peer != null:
		_peer.close()


func poll(delta: float) -> void:
	if _peer == null:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_open()
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_backoff = RECONNECT_MIN
				if not _config.is_empty():
					_peer.send_text(JSON.stringify(_config))
				connected.emit()
			while _peer.get_available_packet_count() > 0:
				var pkt := _peer.get_packet()
				# was_string_packet() describes the packet get_packet() just returned.
				if _peer.was_string_packet():
					_on_text(pkt.get_string_from_utf8())
				else:
					_on_binary(pkt)
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				disconnected.emit()
			_was_open = false
			_peer = null
			_retry_in = _backoff
			_backoff = minf(_backoff * 2.0, RECONNECT_MAX)


func _open() -> void:
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 4 << 20
	_peer.outbound_buffer_size = 4 << 20
	if _peer.connect_to_url(url) != OK:
		_peer = null
		_retry_in = _backoff


func _on_text(text: String) -> void:
	var data = JSON.parse_string(text)
	if data is Dictionary and data.get("type", "") == "stats":
		stats_received.emit(data)


func _on_binary(pkt: PackedByteArray) -> void:
	var f := decode_frame(pkt)
	if f.is_empty():
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(f["payload"]) != OK:
		return
	frame_received.emit(int(f["id"]), img)
