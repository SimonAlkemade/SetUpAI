"""Real-time img2img server for the Godot DiffusionRenderer.

    python diffuse_server.py                      # SD-Turbo on MPS/CUDA/CPU
    python diffuse_server.py --backend echo       # no model, inverts frames
"""
from __future__ import annotations

import argparse
import asyncio
import io
import json
import logging
import time

import websockets
from PIL import Image

from backends import Backend, DiffusionBackend, EchoBackend
from latest_slot import LatestSlot
from protocol import Config, pack_frame, parse_config, unpack_frame

log = logging.getLogger("diffuse")


def _encode_jpeg(image: Image.Image, quality: int) -> bytes:
    buf = io.BytesIO()
    image.save(buf, "JPEG", quality=quality)
    return buf.getvalue()


class Session:
    def __init__(self, ws, backend: Backend, lock: asyncio.Lock, default: Config, quality: int):
        self.ws = ws
        self.backend = backend
        self.lock = lock  # one inference at a time across all clients: one GPU
        self.config = default
        self.quality = quality
        self.slot = LatestSlot()

    async def receive(self) -> None:
        async for msg in self.ws:
            if isinstance(msg, (bytes, bytearray)):
                try:
                    self.slot.put(unpack_frame(msg))
                except ValueError as e:
                    log.warning("bad frame: %s", e)
                continue
            try:
                data = json.loads(msg)
            except json.JSONDecodeError:
                log.warning("bad json: %.80s", msg)
                continue
            if isinstance(data, dict) and data.get("type") == "config":
                self.config = parse_config(data, self.config)
                log.info("config %s", self.config)

    async def work(self) -> None:
        while True:
            frame_id, payload = await self.slot.get()
            config = self.config
            t0 = time.perf_counter()
            try:
                async with self.lock:
                    out = await asyncio.to_thread(self._run, payload, config)
            except Exception as e:  # a broken frame must not end the stream
                log.warning("frame %d failed: %s", frame_id, e)
                continue
            ms = (time.perf_counter() - t0) * 1000.0
            await self.ws.send(pack_frame(frame_id, out))
            await self.ws.send(json.dumps(
                {"type": "stats", "id": frame_id, "ms": round(ms, 1), "dropped": self.slot.dropped}
            ))

    def _run(self, payload: bytes, config: Config) -> bytes:
        image = Image.open(io.BytesIO(payload))
        return _encode_jpeg(self.backend.process(image, config), self.quality)


async def serve(backend: Backend, host: str, port: int, default: Config = Config(), quality: int = 85):
    lock = asyncio.Lock()

    async def handler(ws):
        log.info("client connected %s", ws.remote_address)
        session = Session(ws, backend, lock, default, quality)
        worker = asyncio.create_task(session.work())
        try:
            await session.receive()
        except websockets.ConnectionClosed:
            pass
        finally:
            worker.cancel()
            log.info("client gone")

    return await websockets.serve(handler, host, port, max_size=8 * 1024 * 1024, compression=None)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--backend", choices=["diffusion", "echo"], default="diffusion")
    ap.add_argument("--model", default="sd-turbo", help="sd-turbo, sdxs, or a Hugging Face img2img repo id")
    ap.add_argument("--device", default=None, help="mps / cuda / cpu (default: best available)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--quality", type=int, default=85, help="JPEG quality of replies")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")

    default = Config()
    if args.backend == "echo":
        backend: Backend = EchoBackend()
    else:
        log.info("loading %s ...", args.model)
        backend = DiffusionBackend(args.model, args.device)
        log.info("warming up on %s ...", backend.device)
        backend.warm_up(default)

    async def run():
        await serve(backend, args.host, args.port, default, args.quality)
        log.info("listening on ws://%s:%d", args.host, args.port)
        await asyncio.Future()

    asyncio.run(run())


if __name__ == "__main__":
    main()
