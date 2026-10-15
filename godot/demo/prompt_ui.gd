extends CanvasLayer
## Prompt box, presets, strength slider and live stats for the demo.

const PRESETS := {
	"Sci-fi": "a futuristic sci-fi city, neon lights, chrome towers, highly detailed",
	"Middle ages": "a medieval town, stone and timber houses, cobblestone street, highly detailed",
	"Cyberpunk": "a cyberpunk city at night, rain, neon signs, blade runner",
	"Ghibli": "a city street in the style of studio ghibli, watercolor, soft light",
}

var renderer: DiffusionRenderer
var _prompt: LineEdit
var _stats: Label
var _sent_at := {}


func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var row := HBoxContainer.new()
	box.add_child(row)
	var i := 1
	for name in PRESETS:
		var b := Button.new()
		b.text = "%d %s" % [i, name]
		b.pressed.connect(_use.bind(PRESETS[name]))
		row.add_child(b)
		i += 1
	var off := CheckButton.new()
	off.text = "Diffusion (Tab)"
	off.button_pressed = renderer.enabled
	off.toggled.connect(func(on: bool) -> void: renderer.enabled = on)
	row.add_child(off)

	_prompt = LineEdit.new()
	_prompt.text = renderer.prompt
	_prompt.custom_minimum_size.x = 640
	_prompt.text_submitted.connect(func(t: String) -> void:
		renderer.prompt = t
		_prompt.release_focus())
	box.add_child(_prompt)

	var srow := HBoxContainer.new()
	box.add_child(srow)
	var sl := Label.new()
	sl.text = "Strength"
	srow.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = renderer.strength
	slider.custom_minimum_size.x = 240
	slider.value_changed.connect(func(v: float) -> void: renderer.strength = v)
	srow.add_child(slider)

	_stats = Label.new()
	box.add_child(_stats)
	renderer.stats_updated.connect(_on_stats)


func _use(text: String) -> void:
	_prompt.text = text
	renderer.prompt = text


func _on_stats(s: Dictionary) -> void:
	var ms: float = s.get("ms", 0.0)
	_stats.text = "server %.0f ms/frame (%.1f fps)   dropped %d   %s" % [
		ms, 1000.0 / maxf(ms, 1.0), int(s.get("dropped", 0)),
		"connected" if renderer.client.is_open() else "offline"]


func _process(_delta: float) -> void:
	if not renderer.client.is_open():
		_stats.text = "offline: start server/diffuse_server.py"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.keycode - KEY_1
		if n >= 0 and n < PRESETS.size():
			_use(PRESETS.values()[n])
