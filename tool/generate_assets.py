"""Generates the game's sound effects and app icon.

Run from the project root:  python3 tool/generate_assets.py
Needs numpy and Pillow. Then run:
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create
"""

import math
import os
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RATE = 44100
SOUNDS = "assets/sounds"
IMAGES = "assets/images"


# ---------------------------------------------------------------- sounds

def _t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def _env(n, attack=0.004, decay=8.0):
    t = np.arange(n) / RATE
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t * decay)


def _bell(freq, seconds, decay=7.0, gain=1.0):
    t = _t(seconds)
    tone = (np.sin(2 * math.pi * freq * t)
            + 0.45 * np.sin(2 * math.pi * freq * 2.0 * t)
            + 0.18 * np.sin(2 * math.pi * freq * 3.01 * t))
    return gain * tone * _env(len(t), decay=decay)


def _mix(*parts):
    """Each part is (start_seconds, samples)."""
    end = max(int(s * RATE) + len(x) for s, x in parts)
    out = np.zeros(end)
    for s, x in parts:
        i = int(s * RATE)
        out[i:i + len(x)] += x
    return out


def _write(name, samples, volume=0.8):
    peak = np.max(np.abs(samples)) or 1.0
    data = (samples / peak * volume * 32767).astype(np.int16)
    with wave.open(os.path.join(SOUNDS, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


def make_sounds():
    os.makedirs(SOUNDS, exist_ok=True)
    rng = np.random.default_rng(7)

    # Picking a piece up: a short soft blip.
    t = _t(0.06)
    _write("pick", np.sin(2 * math.pi * (700 + 500 * t / t[-1]) * t)
           * _env(len(t), decay=60), 0.45)

    # Putting a piece down: a woody "thock".
    t = _t(0.12)
    body = np.sin(2 * math.pi * 190 * t) * _env(len(t), 0.002, 38)
    click = rng.normal(0, 1, len(t)) * _env(len(t), 0.001, 140) * 0.35
    _write("place", body + click, 0.7)

    # Dropping somewhere it does not fit: two quick falling tones.
    _write("fail", _mix((0, _bell(420, 0.08, 30)), (0.07, _bell(310, 0.12, 25))), 0.4)

    # Line clears, one pitch higher per combo step (pentatonic).
    steps = [0, 2, 4, 7, 9, 12]
    for i, s in enumerate(steps, start=1):
        root = 523.25 * 2 ** (s / 12)
        chord = _mix(
            (0.00, _bell(root, 0.5, 6)),
            (0.04, _bell(root * 1.25, 0.45, 6, 0.7)),
            (0.08, _bell(root * 1.5, 0.45, 6, 0.6)),
        )
        sparkle = rng.normal(0, 1, len(chord)) * _env(len(chord), 0.002, 20) * 0.08
        _write(f"clear_{i}", chord + sparkle, 0.75)

    # Ice breaking: a bright crack with a glassy ring.
    t = _t(0.25)
    crack = np.diff(rng.normal(0, 1, len(t)), prepend=0) * _env(len(t), 0.001, 45)
    ring = _mix((0, _bell(2093.0, 0.25, 18, 0.5)), (0.03, _bell(2637.0, 0.22, 20, 0.4)))
    n = min(len(crack), len(ring))
    _write("ice", crack[:n] * 0.6 + ring[:n], 0.7)

    # Big multi-line clear: a fast rising arpeggio.
    notes = [659.25, 783.99, 987.77, 1318.5]
    _write("praise", _mix(*[(i * 0.06, _bell(f, 0.4, 7)) for i, f in enumerate(notes)]), 0.7)

    # Board completely cleared.
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98]
    _write("all_clear", _mix(*[(i * 0.07, _bell(f, 0.6, 5)) for i, f in enumerate(notes)]), 0.75)

    # Game over: slow falling notes.
    notes = [392.0, 329.63, 261.63]
    _write("game_over", _mix(*[(i * 0.22, _bell(f, 0.7, 4)) for i, f in enumerate(notes)]), 0.6)

    # New best score: a little fanfare.
    notes = [523.25, 659.25, 783.99, 1046.5]
    parts = [(i * 0.11, _bell(f, 0.5, 5)) for i, f in enumerate(notes)]
    parts.append((0.44, _bell(1046.5, 0.9, 3) + _bell(1318.5, 0.9, 3, 0.6)))
    _write("best", _mix(*parts), 0.7)


# ---------------------------------------------------------------- icon

# Neon Night theme colours (lib/ui/theme.dart).
COLORS = {
    "red": (255, 79, 129),
    "orange": (255, 155, 61),
    "yellow": (255, 224, 74),
    "green": (110, 240, 107),
    "cyan": (46, 230, 230),
    "blue": (79, 139, 255),
    "purple": (181, 101, 255),
}


def _shade(rgb, f):
    if f >= 0:
        return tuple(int(c + (255 - c) * f) for c in rgb)
    return tuple(int(c * (1 + f)) for c in rgb)


def _block(draw, x, y, s, rgb):
    """Same bevelled look as paintBlock in lib/ui/palette.dart."""
    r = s * 0.16
    draw.rounded_rectangle([x, y, x + s, y + s], r, fill=_shade(rgb, -0.32))
    draw.rounded_rectangle([x, y, x + s, y + s * 0.92], r, fill=_shade(rgb, 0.35))
    i = s * 0.12
    draw.rounded_rectangle([x + i, y + i, x + s - i, y + s - i * 1.25], r * 0.6, fill=rgb)
    draw.rounded_rectangle([x + i * 1.5, y + i * 1.3, x + s - i * 1.5, y + i * 2.3],
                           i * 0.5, fill=_shade(rgb, 0.45))


def _blocks(size, area):
    """Draws the icon's pieces into a transparent image. [area] is the fraction
    of the image the pieces may cover."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    layout = [  # (row, col, colour) on a 3x3 grid
        (0, 0, "red"), (0, 1, "red"), (1, 0, "red"),
        (0, 2, "yellow"),
        (1, 1, "cyan"), (1, 2, "cyan"), (2, 2, "cyan"),
        (2, 0, "green"), (2, 1, "green"),
    ]
    cell = size * area / 3
    off = (size - cell * 3) / 2
    gap = cell * 0.05
    for r, c, name in layout:
        _block(draw, off + c * cell + gap, off + r * cell + gap, cell - 2 * gap, COLORS[name])

    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 30, 140), mask=img.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.015))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(shadow, (0, int(size * 0.012)))
    out.alpha_composite(img)
    return out


def _background(size):
    top, bottom = np.array([92, 44, 190]), np.array([22, 10, 64])
    t = np.linspace(0, 1, size)[:, None, None]
    grad = (top * (1 - t) + bottom * t).astype(np.uint8)
    grad = np.repeat(grad, size, axis=1)
    return Image.fromarray(grad, "RGB").convert("RGBA")


def make_icons():
    os.makedirs(IMAGES, exist_ok=True)
    size = 1024

    full = _background(size)
    full.alpha_composite(_blocks(size, 0.72))
    full.convert("RGB").save(os.path.join(IMAGES, "icon.png"))

    # Android adaptive icon: keep the pieces inside the 66% safe zone.
    _blocks(size, 0.5).save(os.path.join(IMAGES, "icon_foreground.png"))

    # Splash logo (Android 12+ shows it inside a circle).
    _blocks(size, 0.55).save(os.path.join(IMAGES, "splash.png"))


if __name__ == "__main__":
    make_sounds()
    make_icons()
    print("done")
