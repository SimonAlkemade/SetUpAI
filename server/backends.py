"""Image-to-image backends. `process` runs in a worker thread, one at a time."""
from __future__ import annotations

import math
import os
from typing import Protocol

import numpy as np
from PIL import Image, ImageOps

from protocol import Config


class Backend(Protocol):
    def process(self, image: Image.Image, config: Config) -> Image.Image: ...


class EchoBackend:
    """No model: inverts the frame. For tests and for wiring Godot up on any machine."""

    def process(self, image: Image.Image, config: Config) -> Image.Image:
        return ImageOps.invert(image.convert("RGB"))


MODELS = {
    # name: (hub id, tiny VAE hub id or None)
    "sd-turbo": ("stabilityai/sd-turbo", "madebyollin/taesd"),
    "sdxs": ("IDKiro/sdxs-512-0.9", None),  # ships its own tiny VAE
}


def pick_device() -> str:
    import torch

    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def steps_for(strength: float) -> int:
    """img2img runs int(steps * strength) denoising steps; make that exactly 1."""
    return max(1, math.ceil(1.0 / strength - 1e-6))


class DiffusionBackend:
    """One-step distilled Stable Diffusion img2img (SD-Turbo by default)."""

    def __init__(self, model: str = "sd-turbo", device: str | None = None) -> None:
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        import torch
        from diffusers import AutoencoderTiny, AutoPipelineForImage2Image

        self.torch = torch
        self.device = device or pick_device()
        dtype = torch.float32 if self.device == "cpu" else torch.float16
        repo, tiny_vae = MODELS.get(model, (model, None))
        self.pipe = AutoPipelineForImage2Image.from_pretrained(
            repo, torch_dtype=dtype, safety_checker=None, requires_safety_checker=False
        )
        if tiny_vae:
            self.pipe.vae = AutoencoderTiny.from_pretrained(tiny_vae, torch_dtype=dtype)
        self.pipe.to(self.device)
        self.pipe.set_progress_bar_config(disable=True)
        self._prompt: str | None = None
        self._embeds = None
        self._previous: np.ndarray | None = None

    def _embeds_for(self, prompt: str):
        # The text encoder costs as much as a UNet step; run it once per prompt.
        if prompt != self._prompt:
            self._embeds, _ = self.pipe.encode_prompt(
                prompt, self.device, 1, do_classifier_free_guidance=False
            )
            self._prompt = prompt
        return self._embeds

    def process(self, image: Image.Image, config: Config) -> Image.Image:
        image = image.convert("RGB")
        if image.size != config.size:
            image = image.resize(config.size, Image.BILINEAR)
        # Same seed every frame -> same noise every frame -> far less flicker.
        generator = self.torch.Generator("cpu").manual_seed(config.seed)
        with self.torch.inference_mode():
            out = self.pipe(
                prompt_embeds=self._embeds_for(config.prompt),
                image=image,
                num_inference_steps=steps_for(config.strength),
                strength=config.strength,
                guidance_scale=0.0,
                generator=generator,
                width=config.size[0],
                height=config.size[1],
            ).images[0]
        if config.blend > 0.0:
            cur = np.asarray(out, dtype=np.float32)
            if self._previous is not None and self._previous.shape == cur.shape:
                cur = self._previous * config.blend + cur * (1.0 - config.blend)
            self._previous = cur
            out = Image.fromarray(cur.clip(0, 255).astype(np.uint8))
        else:
            self._previous = None
        return out

    def warm_up(self, config: Config, runs: int = 3) -> None:
        img = Image.new("RGB", config.size, (128, 128, 128))
        for _ in range(runs):
            self.process(img, config)
