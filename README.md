# SetUpAI — real-time diffusion renderer for Godot 4

Godot draws the scene. Every 50 ms a small copy of the frame is sent to a local
Stable Diffusion server, restyled image-to-image with a text prompt, and shown
full-screen over the game. The geometry and camera come from Godot. The prompt
sets the world: *"a futuristic sci-fi city"* and *"a medieval town"* give the
same streets in two eras.

```
Godot                                         server/diffuse_server.py
 DiffusionRenderer                             ws://127.0.0.1:8765
  SubViewport @ 320x192 ── JPEG every 50 ms ─▶  newest-frame slot (older ones dropped)
  full-screen TextureRect ◀── restyled JPEG ──  SD-Turbo img2img, 1 step, tiny VAE
```

## Run it (macOS / Apple Silicon)

```bash
cd server
uv venv && source .venv/bin/activate
uv pip install -e ".[sd]"
python diffuse_server.py            # first run downloads SD-Turbo (~2.5 GB) and TAESD
```

Then open `godot/` in Godot 4.3+ and press Play. Use keys **1–4** for the presets,
type your own prompt in the box, press **Tab** to switch diffusion on and off, and
**Space** to pause the drive.

You can check the wiring without the model: `python diffuse_server.py --backend echo`
returns each frame with its colours inverted.

## How fast is it?

The real-time limit is the model, not Godot. Measure it on your machine:

```bash
python bench.py                     # ms/frame at 256x256, 320x192, 384x256, 512x320
```

The on-screen label shows the server's ms/frame and how many frames it skipped.
Godot sends every `interval_ms` (50) no matter what. The server only ever works
on the newest frame, so the picture never falls behind the camera. A slower
model means fewer restyled frames per second, not more lag.

Ways to make it faster, from most to least effective:

- **Lower `resolution`** on the DiffusionRenderer. Cost grows with pixel count;
  256×128 is roughly half the cost of 320×192.
- **`--model sdxs`**: a one-step model built for speed (experimental here).
- Keep `skip_full_res` on. While the restyled frame covers the screen, Godot
  stops drawing the full-resolution scene, so more of the shared GPU goes to the model.

## Use it in your own scene

Copy `godot/addons/diffusion_renderer/` into your project and add a
`DiffusionRenderer` node anywhere in the scene. It follows the active camera
(or `source_camera`, if set).

| property | default | |
|---|---|---|
| `prompt` | sci-fi city | the setting |
| `strength` | 0.5 | how far the model may move away from the render: low keeps the shapes, high follows the prompt |
| `noise_seed` | 42 | the same seed gives the same noise every frame, which reduces flicker |
| `blend` | 0 | blends each output with the previous one (less flicker, more smear) |
| `interval_ms` | 50 | how often a frame is sent |
| `resolution` | 320×192 | diffusion size, snapped to multiples of 64 |
| `mix` | 1 | cross-fade between the raw render and the restyled frame |
| `skip_full_res` | true | stop drawing the full-res scene while the restyled frame covers it |
| `enabled` | true | off → plain Godot |

If the server isn't running, or no frame has arrived for `stale_after` seconds,
the overlay hides and the raw scene shows. The client reconnects on its own.

## Protocol

WebSocket. Binary messages go both ways: a `uint32` little-endian frame id, then
JPEG bytes. Text messages are JSON: `{"type":"config","prompt",...}` from Godot,
and `{"type":"stats","id","ms","dropped"}` from the server after every frame.
The full definition is in `server/protocol.py`.

## Tests

```bash
cd server && pytest                  # protocol, slot, end-to-end over a real socket (echo backend)
godot --headless --path godot --script res://tests/test_client_framing.gd
# with `python server/diffuse_server.py --backend echo` running:
godot --headless --path godot --script res://tests/test_live_echo.gd
godot --path godot --script res://tests/demo_smoke.gd -- /tmp/shot.png
```
