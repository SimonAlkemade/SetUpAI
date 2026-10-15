"""Measure ms/frame of the diffusion backend at a few sizes.

    python bench.py --model sd-turbo --sizes 256x256 320x192 384x256 --frames 20
"""
from __future__ import annotations

import argparse
import statistics
import time

from PIL import Image, ImageDraw

from backends import DiffusionBackend
from protocol import parse_config


def test_image(size):
    img = Image.new("RGB", size, (90, 110, 140))
    d = ImageDraw.Draw(img)
    w, h = size
    for i in range(8):
        x = i * w // 8
        d.rectangle([x + 4, h // 3 + (i * 17) % (h // 3), x + w // 10, h], fill=(150 + i * 10, 140, 120))
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="sd-turbo")
    ap.add_argument("--device", default=None)
    ap.add_argument("--sizes", nargs="+", default=["256x256", "320x192", "384x256", "512x320"])
    ap.add_argument("--frames", type=int, default=20)
    ap.add_argument("--strength", type=float, default=0.5)
    args = ap.parse_args()

    backend = DiffusionBackend(args.model, args.device)
    print(f"model={args.model} device={backend.device}")
    for s in args.sizes:
        w, h = (int(v) for v in s.split("x"))
        cfg = parse_config({"size": [w, h], "strength": args.strength})
        img = test_image(cfg.size)
        backend.warm_up(cfg, runs=2)
        times = []
        for _ in range(args.frames):
            t0 = time.perf_counter()
            backend.process(img, cfg)
            times.append((time.perf_counter() - t0) * 1000)
        med = statistics.median(times)
        print(f"{cfg.size[0]}x{cfg.size[1]}: median {med:6.1f} ms  ({1000 / med:4.1f} fps)  "
              f"min {min(times):6.1f}  max {max(times):6.1f}")


if __name__ == "__main__":
    main()
