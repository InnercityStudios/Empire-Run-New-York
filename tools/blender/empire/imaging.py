"""Image utilities for procedural texture generation (numpy only, no bpy).

All generated textures are tileable unless stated otherwise. Arrays are float
HxWxC in 0..1, row 0 at the top of the image.
"""
import os
import struct
import zlib

import numpy as np


def write_png(path, arr):
    """Write a float (0..1) or uint8 HxWxC array as an 8-bit PNG."""
    if arr.ndim == 2:
        arr = arr[:, :, None]
    if arr.dtype != np.uint8:
        arr = (np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    h, w, c = arr.shape
    color_type = {1: 0, 3: 2, 4: 6}[c]
    raw = np.concatenate([np.zeros((h, 1), np.uint8), arr.reshape(h, w * c)], axis=1).tobytes()

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(h, w, cells_y, cells_x, rng):
    """Tileable smooth value noise in 0..1."""
    g = rng.random((cells_y, cells_x))
    y = np.arange(h) / h * cells_y
    x = np.arange(w) / w * cells_x
    y0 = np.floor(y).astype(int)
    x0 = np.floor(x).astype(int)
    fy = y - y0
    fx = x - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % cells_y
    x1 = (x0 + 1) % cells_x
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    fx = fx[None, :]
    fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(h, w, base_cells, octaves, rng, gain=0.5):
    """Tileable fractal noise normalised to 0..1."""
    total = np.zeros((h, w))
    amp = 1.0
    norm = 0.0
    cells = base_cells
    for _ in range(octaves):
        total += value_noise(h, w, cells, cells, rng) * amp
        norm += amp
        amp *= gain
        cells *= 2
    return total / norm


def height_to_normal(height, strength):
    """Tangent-space normal map (OpenGL convention, +Y up) from a height field."""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength
    n = np.dstack([-dx, dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def rgb(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def lerp(a, b, t):
    return a + (b - a) * t


def draw_rect(img, x0, y0, x1, y1, color, alpha=1.0):
    """Blend a solid rect into img (pixel coords, clipped)."""
    h, w = img.shape[:2]
    x0, x1 = max(0, int(x0)), min(w, int(x1))
    y0, y1 = max(0, int(y0)), min(h, int(y1))
    if x1 <= x0 or y1 <= y0:
        return
    img[y0:y1, x0:x1, :3] = img[y0:y1, x0:x1, :3] * (1 - alpha) + np.asarray(color)[:3] * alpha
