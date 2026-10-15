"""Wire format shared with the Godot client (addons/diffusion_renderer).

Binary message: uint32 little-endian frame id, then JPEG bytes. Same in both
directions, so the client can match a reply to the frame it sent and drop
replies that arrive after a newer one.

Text message: JSON. Client -> server {"type": "config", ...}; server -> client
{"type": "stats", ...}.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, replace

_HEADER = struct.Struct("<I")


def pack_frame(frame_id: int, payload: bytes) -> bytes:
    return _HEADER.pack(frame_id & 0xFFFFFFFF) + payload


def unpack_frame(data: bytes) -> tuple[int, bytes]:
    if len(data) < _HEADER.size:
        raise ValueError(f"frame too short: {len(data)} bytes")
    return _HEADER.unpack_from(data)[0], bytes(data[_HEADER.size:])


@dataclass(frozen=True)
class Config:
    prompt: str = "a futuristic sci-fi city, neon lights, highly detailed"
    strength: float = 0.5
    seed: int = 42
    # EMA with the previous output, 0 = off. Trades flicker for smear.
    blend: float = 0.0
    size: tuple[int, int] = (320, 192)


def _snap(v: int) -> int:
    return max(64, int(round(v / 64)) * 64)


def parse_config(msg: dict, base: Config | None = None) -> Config:
    """Merge the keys present in `msg` onto `base`; unknown keys are ignored."""
    cfg = base or Config()
    changes: dict = {}
    if "prompt" in msg:
        changes["prompt"] = str(msg["prompt"])
    if "strength" in msg:
        changes["strength"] = min(1.0, max(0.05, float(msg["strength"])))
    if "seed" in msg:
        changes["seed"] = int(msg["seed"])
    if "blend" in msg:
        changes["blend"] = min(0.95, max(0.0, float(msg["blend"])))
    if "size" in msg:
        w, h = msg["size"]
        changes["size"] = (_snap(int(w)), _snap(int(h)))
    return replace(cfg, **changes)
