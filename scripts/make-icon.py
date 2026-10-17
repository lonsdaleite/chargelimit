#!/usr/bin/env python3
"""Draws the Settings icon (green tile with a battery, like the stock Battery pane) into the Settings bundle."""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "layout/Library/PreferenceBundles/ChargeLimit.bundle"
GREEN = (52, 199, 89)
WHITE = (255, 255, 255)


def draw(size: int) -> Image.Image:
    s = 8  # supersampling
    n = size * s
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.225), fill=GREEN)
    # Horizontal battery: body outline, cap on the right, fill to 80%.
    left, right = int(n * 0.18), int(n * 0.76)
    top, bottom = int(n * 0.33), int(n * 0.67)
    stroke = max(int(n * 0.06), 1)
    d.rounded_rectangle((left, top, right, bottom), radius=int(n * 0.07), outline=WHITE, width=stroke)
    d.rounded_rectangle((right + stroke // 2, int(n * 0.43), int(n * 0.83), int(n * 0.57)), radius=int(n * 0.03), fill=WHITE)
    pad = stroke + int(n * 0.03)
    inner_right = left + pad + int((right - left - 2 * pad) * 0.8)
    d.rectangle((left + pad, top + pad, inner_right, bottom - pad), fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
    draw(29 * scale).save(OUT / f"ChargeLimit{suffix}.png")
