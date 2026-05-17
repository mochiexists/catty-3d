#!/usr/bin/env python3
"""Generate the Catty 3D DMG background images.

Produces dmg-assets/background.png (540x380) and background@2x.png
(1080x760). Layout matches the create-dmg coordinates in
.github/workflows/release-direct.yml — DO NOT draw any app or
Applications icon here; create-dmg renders those on top.

  icon-size     : 100
  Catty 3D.app  : (130, 190)  → icon center ≈ (180, 240)
  Applications  : (410, 190)  → icon center ≈ (460, 240)

Palette pulled from the app icon: deep indigo-violet space ground,
magenta wireframe rat tone, cream cat-fur warm white. Mirrors
catty3d.com.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO_ROOT / "dmg-assets"
WIDTH, HEIGHT = 540, 380

# Palette (RGB)
SPACE_0 = (4, 3, 10)        # near-black
SPACE_1 = (10, 8, 32)       # deep indigo
SPACE_2 = (26, 14, 46)      # violet undertone
MAGENTA = (217, 70, 239)    # the rat wireframe
MAGENTA_DIM = (140, 40, 160)
VIOLET = (124, 58, 237)
CREAM = (245, 230, 200)
CREAM_DIM = (180, 165, 140)
STAR = (255, 255, 255)


def load_font(filename: str, size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        f"/System/Library/Fonts/Supplemental/{filename}",
        f"/Library/Fonts/{filename}",
        f"/System/Library/Fonts/{filename}",
        f"/System/Library/Fonts/HelveticaNeue.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def gradient_bg(scale: int) -> Image.Image:
    """Vertical violet→indigo→black gradient with two radial glow washes."""
    w, h = WIDTH * scale, HEIGHT * scale
    img = Image.new("RGB", (w, h), SPACE_0)
    px = img.load()
    for y in range(h):
        t = y / h
        # Smooth piecewise gradient: violet at top, indigo middle, black bottom.
        if t < 0.5:
            k = t / 0.5
            r = int(SPACE_2[0] * (1 - k) + SPACE_1[0] * k)
            g = int(SPACE_2[1] * (1 - k) + SPACE_1[1] * k)
            b = int(SPACE_2[2] * (1 - k) + SPACE_1[2] * k)
        else:
            k = (t - 0.5) / 0.5
            r = int(SPACE_1[0] * (1 - k) + SPACE_0[0] * k)
            g = int(SPACE_1[1] * (1 - k) + SPACE_0[1] * k)
            b = int(SPACE_1[2] * (1 - k) + SPACE_0[2] * k)
        for x in range(w):
            px[x, y] = (r, g, b)

    # Add radial glow washes (magenta from top-left, violet from bottom-right).
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    cx, cy = int(0.18 * w), int(0.05 * h)
    r = int(0.55 * w)
    for i in range(40):
        a = int(38 * (1 - i / 40))
        od.ellipse((cx - r + i * 3, cy - r + i * 3, cx + r - i * 3, cy + r - i * 3),
                   fill=(*MAGENTA, a))
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=40 * scale / 2))

    cx2, cy2 = int(0.85 * w), int(0.85 * h)
    r2 = int(0.45 * w)
    overlay2 = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od2 = ImageDraw.Draw(overlay2)
    for i in range(30):
        a = int(28 * (1 - i / 30))
        od2.ellipse((cx2 - r2 + i * 3, cy2 - r2 + i * 3, cx2 + r2 - i * 3, cy2 + r2 - i * 3),
                    fill=(*VIOLET, a))
    overlay2 = overlay2.filter(ImageFilter.GaussianBlur(radius=40 * scale / 2))

    img = Image.alpha_composite(img.convert("RGBA"), overlay)
    img = Image.alpha_composite(img, overlay2)
    return img.convert("RGB")


def draw_stars(img: Image.Image, scale: int, n: int = 90) -> None:
    """Sprinkle small stars + a few warm-cream brights."""
    import random
    rng = random.Random(7)  # deterministic
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    for _ in range(n):
        x = rng.random() * w
        y = rng.random() * h
        r = rng.uniform(0.5, 2.0) * scale
        bright = rng.random() < 0.18
        col = CREAM if bright else STAR
        alpha = int(rng.uniform(110, 220))
        d.ellipse((x - r, y - r, x + r, y + r), fill=(*col, alpha))
        if bright:
            halo = r * 3
            d.ellipse((x - halo, y - halo, x + halo, y + halo),
                      fill=(*col, 30))


def draw_arrow(img: Image.Image, scale: int) -> None:
    """Magenta hand-drawn-feeling arrow from app slot → Applications slot."""
    d = ImageDraw.Draw(img, "RGBA")
    # Source: app icon center ≈ (180, 240); target: Applications ≈ (460, 240).
    # Arc slightly upward through the middle.
    sx, sy = 220 * scale, 230 * scale
    ex, ey = 420 * scale, 230 * scale
    # Quadratic bezier midpoint
    mx, my = (sx + ex) // 2, (sy + ey) // 2 - 36 * scale
    # Draw segmented dotted-ish arc by sampling t
    width = max(2, int(2.2 * scale))
    last = None
    for i in range(0, 41):
        t = i / 40
        x = (1 - t) ** 2 * sx + 2 * (1 - t) * t * mx + t ** 2 * ex
        y = (1 - t) ** 2 * sy + 2 * (1 - t) * t * my + t ** 2 * ey
        if last is not None and i % 2 == 0:
            d.line([last, (x, y)], fill=(*MAGENTA, 220), width=width)
        last = (x, y)
    # Arrowhead at end
    head = 14 * scale
    angle = math.atan2(ey - my, ex - mx)
    ax1 = ex - head * math.cos(angle - 0.5)
    ay1 = ey - head * math.sin(angle - 0.5)
    ax2 = ex - head * math.cos(angle + 0.5)
    ay2 = ey - head * math.sin(angle + 0.5)
    d.polygon([(ex, ey), (ax1, ay1), (ax2, ay2)], fill=(*MAGENTA, 240))


def draw_text(img: Image.Image, scale: int) -> None:
    """Headline + tagline above the icon row."""
    d = ImageDraw.Draw(img, "RGBA")
    title = load_font("Cormorant-Garamond.ttc", 36 * scale) if False else \
        load_font("Times.ttc", 36 * scale)
    body = load_font("HelveticaNeue.ttc", 12 * scale)

    headline = "Catty 3D"
    tagline = "Drag Catty into Applications to install · catty3d.com"

    # Centre headline at y ≈ 80
    bbox = d.textbbox((0, 0), headline, font=title)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (WIDTH * scale - tw) // 2
    ty = 60 * scale
    # Subtle magenta glow
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.text((tx, ty), headline, font=title, fill=(*MAGENTA, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=6 * scale))
    img.paste(glow, (0, 0), glow)
    d.text((tx, ty), headline, font=title, fill=(*CREAM, 235))

    # Tagline below
    bbox = d.textbbox((0, 0), tagline, font=body)
    tw = bbox[2] - bbox[0]
    tx = (WIDTH * scale - tw) // 2
    ty2 = ty + th + 10 * scale
    d.text((tx, ty2), tagline, font=body, fill=(*CREAM_DIM, 220))


def render(scale: int) -> Image.Image:
    img = gradient_bg(scale)
    draw_stars(img, scale)
    draw_arrow(img, scale)
    draw_text(img, scale)
    return img


def main() -> None:
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    img1 = render(1)
    img1.save(ASSETS_DIR / "background.png", "PNG", optimize=True)
    img2 = render(2)
    img2.save(ASSETS_DIR / "background@2x.png", "PNG", optimize=True)
    print(f"wrote {ASSETS_DIR}/background.png ({WIDTH}x{HEIGHT})")
    print(f"wrote {ASSETS_DIR}/background@2x.png ({WIDTH*2}x{HEIGHT*2})")


if __name__ == "__main__":
    main()
