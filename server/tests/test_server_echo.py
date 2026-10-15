import asyncio
import io
import json

import websockets
from PIL import Image

from backends import EchoBackend
from diffuse_server import serve
from protocol import pack_frame, unpack_frame


def jpeg(color, size=(64, 64)):
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, "JPEG", quality=95)
    return buf.getvalue()


async def start(backend=None):
    server = await serve(backend or EchoBackend(), "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    return server, f"ws://127.0.0.1:{port}"


async def recv_frame(ws):
    while True:
        msg = await asyncio.wait_for(ws.recv(), 5)
        if isinstance(msg, bytes):
            return unpack_frame(msg)


async def test_frame_is_processed_and_returned_with_its_id():
    server, url = await start()
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({"type": "config", "prompt": "x"}))
            await ws.send(pack_frame(42, jpeg((10, 200, 30))))
            fid, payload = await recv_frame(ws)
            assert fid == 42
            r, g, b = Image.open(io.BytesIO(payload)).convert("RGB").getpixel((32, 32))
            # EchoBackend inverts: (10,200,30) -> (245,55,225), give or take JPEG.
            assert abs(r - 245) < 8 and abs(g - 55) < 8 and abs(b - 225) < 8
    finally:
        server.close()
        await server.wait_closed()


async def test_stats_follow_each_frame():
    server, url = await start()
    try:
        async with websockets.connect(url) as ws:
            await ws.send(pack_frame(1, jpeg((0, 0, 0))))
            kinds = []
            for _ in range(2):
                msg = await asyncio.wait_for(ws.recv(), 5)
                kinds.append("bin" if isinstance(msg, bytes) else json.loads(msg)["type"])
            assert kinds == ["bin", "stats"]
    finally:
        server.close()
        await server.wait_closed()


class SlowEcho(EchoBackend):
    def process(self, image, config):
        import time

        time.sleep(0.2)
        return super().process(image, config)


async def test_slow_backend_drops_stale_frames():
    server, url = await start(SlowEcho())
    try:
        async with websockets.connect(url) as ws:
            for i in range(1, 11):
                await ws.send(pack_frame(i, jpeg((i * 20, 0, 0))))
            ids = []
            while not ids or ids[-1] != 10:
                fid, _ = await recv_frame(ws)
                ids.append(fid)
            # Never a backlog: the newest frame wins, most of the burst is skipped.
            assert ids == sorted(ids)
            assert len(ids) <= 3
    finally:
        server.close()
        await server.wait_closed()


async def test_bad_frame_does_not_kill_connection():
    server, url = await start()
    try:
        async with websockets.connect(url) as ws:
            await ws.send(pack_frame(1, b"not a jpeg"))
            await ws.send("{not json")
            await ws.send(pack_frame(2, jpeg((1, 2, 3))))
            fid, _ = await recv_frame(ws)
            assert fid == 2
    finally:
        server.close()
        await server.wait_closed()


async def test_config_reaches_backend():
    seen = []

    class Spy(EchoBackend):
        def process(self, image, config):
            seen.append(config.prompt)
            return image

    server, url = await start(Spy())
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({"type": "config", "prompt": "a medieval town"}))
            await ws.send(pack_frame(1, jpeg((0, 0, 0))))
            await recv_frame(ws)
            assert seen == ["a medieval town"]
    finally:
        server.close()
        await server.wait_closed()
