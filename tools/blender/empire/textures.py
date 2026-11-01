"""Procedural, tileable texture set for the 1970s New York world.

Run through tools/blender/build_textures.py. Deterministic: every texture uses
a fixed seed, so regenerating produces identical files.
"""
import os

import numpy as np

from .imaging import fbm, height_to_normal, lerp, rgb, smoothstep, value_noise, write_png, draw_rect


def _rng(seed):
    return np.random.default_rng(seed)


# ---------------------------------------------------------------------------
# Brick (2.4 m square tile: 32 courses, 11 bricks per course, running bond)
# ---------------------------------------------------------------------------
BRICK_COURSES = 32
BRICK_PER_ROW = 11


def _brick_layout(size):
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    ch = size / BRICK_COURSES
    bw = size / BRICK_PER_ROW
    row = np.floor(yy / ch).astype(int)
    u = xx / bw + (row % 2) * 0.5
    col = np.floor(u).astype(int) % BRICK_PER_ROW
    fu = u - np.floor(u)
    fv = yy / ch - row
    edge = np.minimum(np.minimum(fu, 1 - fu) * bw, np.minimum(fv, 1 - fv) * ch)
    return row, col, edge


def brick_albedo(size, base_hex, mortar_hex, seed, variation=0.16, soot=0.0):
    rng = _rng(seed)
    row, col, edge = _brick_layout(size)
    mortar = 1.0 - smoothstep(1.2, 2.6, edge)
    per = rng.random((BRICK_COURSES, BRICK_PER_ROW, 4))
    pick = per[row, col]
    base = rgb(base_hex)
    tone = 1.0 + (pick[..., 0:1] - 0.5) * 2 * variation
    hue = np.dstack([1 + (pick[..., 1] - 0.5) * 0.08, np.ones(row.shape), 1 - (pick[..., 1] - 0.5) * 0.08])
    brick = base[None, None, :] * tone * hue
    # Occasional over-fired (dark) and pale bricks
    dark = (pick[..., 2] > 0.93)[..., None]
    pale = (pick[..., 2] < 0.05)[..., None]
    brick = np.where(dark, brick * 0.62, brick)
    brick = np.where(pale, brick * 1.18, brick)
    grain = fbm(size, size, 64, 3, rng)[..., None]
    brick *= 0.88 + grain * 0.24
    speck = (rng.random((size, size)) > 0.985)[..., None]
    brick = np.where(speck, brick * 0.75, brick)
    mort = rgb(mortar_hex)[None, None, :] * (0.9 + fbm(size, size, 32, 2, rng)[..., None] * 0.2)
    out = lerp(brick, mort, mortar[..., None])
    if soot > 0:
        s = fbm(size, size, 4, 4, rng)[..., None]
        out *= 1.0 - soot * smoothstep(0.35, 0.8, s)
    return out


def brick_normal(size, seed):
    rng = _rng(seed)
    row, col, edge = _brick_layout(size)
    h = smoothstep(0.8, 3.5, edge)
    h = h * (0.85 + fbm(size, size, 48, 3, rng) * 0.3)
    return height_to_normal(h, 2.2)


# ---------------------------------------------------------------------------
# Generic surfaces
# ---------------------------------------------------------------------------
def stone(size, seed):
    rng = _rng(seed)
    n = fbm(size, size, 8, 6, rng)
    fine = fbm(size, size, 64, 2, rng)
    base = rgb("#bdb3a0")
    alb = base[None, None, :] * (0.82 + n[..., None] * 0.3) * (0.95 + fine[..., None] * 0.1)
    nrm = height_to_normal(n * 0.6 + fine * 0.4, 3.0)
    return alb, nrm


def roof(size, seed):
    rng = _rng(seed)
    n = fbm(size, size, 6, 5, rng)
    alb = np.ones((size, size, 3)) * rgb("#3a3836")[None, None, :]
    alb *= (0.75 + n[..., None] * 0.5)
    gravel = rng.random((size, size))
    alb = np.where((gravel > 0.92)[..., None], alb * 1.5, alb)
    alb = np.where((gravel < 0.05)[..., None], alb * 0.6, alb)
    # Tar seams every metre (tile covers 4 m)
    yy = np.arange(size)[:, None] / size * 4.0
    seam = (np.abs(yy - np.round(yy)) < 0.012)
    alb = np.where(seam[..., None] & np.ones((1, size, 1), bool), alb * 0.55, alb)
    # Water stains
    stain = smoothstep(0.62, 0.75, fbm(size, size, 3, 4, rng))
    alb = lerp(alb, alb * rgb("#7a7468")[None, None, :] * 1.6, stain[..., None] * 0.35)
    return alb


def asphalt(size, seed):
    """Worn city asphalt, 6 m tile."""
    rng = _rng(seed)
    large = fbm(size, size, 4, 5, rng)
    mid = fbm(size, size, 32, 3, rng)
    base = rgb("#4a4a4a")
    alb = base[None, None, :] * (0.78 + large[..., None] * 0.32) * (0.92 + mid[..., None] * 0.16)
    agg = rng.random((size, size))
    alb = np.where((agg > 0.975)[..., None], alb * 1.35, alb)
    alb = np.where((agg < 0.02)[..., None], alb * 0.7, alb)
    # Patch repairs (darker rectangles)
    for _ in range(4):
        x0, y0 = rng.integers(0, size, 2)
        w, h = rng.integers(size // 12, size // 4, 2)
        ys = (np.arange(y0, y0 + h) % size)[:, None]
        xs = (np.arange(x0, x0 + w) % size)[None, :]
        alb[ys, xs] *= 0.9
    # Oil drips
    oil = smoothstep(0.7, 0.85, fbm(size, size, 6, 4, rng))
    alb *= (1.0 - oil[..., None] * 0.2)
    height = large * 0.3 + mid * 0.4 + (agg > 0.975) * 0.3
    # Cracks: random walks
    crack = np.zeros((size, size))
    for _ in range(14):
        p = rng.random(2) * size
        ang = rng.random() * np.pi * 2
        for _ in range(int(rng.integers(60, 220))):
            ang += rng.normal(0, 0.35)
            p = (p + np.array([np.cos(ang), np.sin(ang)]) * 2.0) % size
            crack[int(p[1]), int(p[0])] = 1.0
    crack = np.maximum(crack, np.roll(crack, 1, 0) * 0.6)
    alb *= (1.0 - crack[..., None] * 0.45)
    height -= crack * 0.5
    return alb, height_to_normal(height, 4.0)


def sidewalk(size, seed):
    """Concrete flags, 3 m tile with 1.5 m slabs."""
    rng = _rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    slab = size / 2.0
    sx = np.floor(xx / slab).astype(int)
    sy = np.floor(yy / slab).astype(int)
    tones = rng.random((2, 2))
    tone = tones[sy, sx]
    fx = (xx % slab)
    fy = (yy % slab)
    edge = np.minimum(np.minimum(fx, slab - fx), np.minimum(fy, slab - fy))
    joint = 1.0 - smoothstep(1.5, 4.0, edge)
    n = fbm(size, size, 8, 5, rng)
    base = rgb("#a7a49c")
    alb = base[None, None, :] * (0.86 + tone[..., None] * 0.12) * (0.88 + n[..., None] * 0.24)
    alb = lerp(alb, rgb("#5e5b55")[None, None, :], joint[..., None] * 0.8)
    # Chewing gum and stains
    gum = rng.random((size, size)) > 0.9993
    gum = gum | np.roll(gum, 1, 0) | np.roll(gum, 1, 1)
    alb = np.where(gum[..., None], alb * 0.55, alb)
    stain = smoothstep(0.66, 0.8, fbm(size, size, 5, 4, rng))
    alb *= 1.0 - stain[..., None] * 0.25
    height = (1.0 - joint) * 0.7 + n * 0.3
    return alb, height_to_normal(height, 3.0)


def corrugated(size):
    yy = np.arange(size)[:, None] / size * 10.0  # 10 slats per metre tile
    ridge = 0.5 + 0.5 * np.cos(yy * np.pi * 2)
    h = np.repeat(ridge, size, axis=1)
    rng = _rng(77)
    alb = np.ones((size, size, 3)) * (0.78 + h[..., None] * 0.18)
    alb *= 0.9 + fbm(size, size, 4, 4, rng)[..., None] * 0.2
    return alb, height_to_normal(h, 4.0)


def wood(size, seed):
    rng = _rng(seed)
    planks = 8
    xx = np.arange(size)[None, :] / size * planks
    pid = np.floor(xx).astype(int)
    tones = rng.random(planks)
    t = np.repeat(tones[pid], size, axis=0)
    grain = value_noise(size, size, 128, 6, rng)
    base = rgb("#6b5a45")
    alb = base[None, None, :] * (0.75 + t[..., None] * 0.3) * (0.85 + grain[..., None] * 0.3)
    gap = np.abs(xx - np.round(xx)) < 0.03
    alb = np.where(np.repeat(gap, size, axis=0)[..., None], alb * 0.5, alb)
    return alb


def foliage(size, seed):
    """Leaf canopy: overlapping leaf clusters with sunlit tips and dark gaps."""
    rng = _rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    alb = np.ones((size, size, 3)) * rgb("#1f2d14")[None, None, :]
    palette = [rgb(c) for c in ("#3f5a22", "#56722c", "#6c8a35", "#4a6826", "#7f9c42")]
    for _ in range(2600):
        cx, cy = rng.random(2) * size
        r = 3 + rng.random() * 7
        col = palette[rng.integers(0, len(palette))] * (0.85 + rng.random() * 0.3)
        x0, x1 = int(cx - r), int(cx + r) + 1
        y0, y1 = int(cy - r), int(cy + r) + 1
        ys = np.arange(y0, y1) % size
        xs = np.arange(x0, x1) % size
        dy = (np.arange(y0, y1) - cy)[:, None]
        dx = (np.arange(x0, x1) - cx)[None, :]
        # Leaf: ellipse lit from the top-left
        m = (dx * dx / (r * r) + dy * dy / (r * r * 0.45)) < 1.0
        shade = (1.15 - (dx + dy) / (3 * r))[..., None]
        patch = alb[np.ix_(ys, xs)]
        alb[np.ix_(ys, xs)] = np.where(m[..., None], col[None, None, :] * shade, patch)
    return np.clip(alb, 0, 1)


# ---------------------------------------------------------------------------
# Atlases (non-tiling)
# ---------------------------------------------------------------------------
WINDOW_ATLAS_COLS = 4
WINDOW_ATLAS_ROWS = 2


def _window_cell(w, h, variant, rng):
    """One double-hung sash window, glass area only (frame is geometry)."""
    img = np.zeros((h, w, 3))
    emit = np.zeros((h, w, 3))
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    # Dark interior with vertical falloff
    interior = rgb("#14110f")[None, None, :] * (0.7 + 0.6 * (yy / h))[..., None]
    img[:] = interior
    if variant == 1:  # white lace curtains at the sides
        side = np.minimum(xx, w - xx) / w
        c = 1.0 - smoothstep(0.12, 0.3, side)
        folds = 0.85 + 0.15 * np.sin(xx * 0.25)
        img = lerp(img, rgb("#d9d2bf")[None, None, :] * folds[..., None], (c * 0.9)[..., None])
    elif variant == 2:  # venetian blinds on the top two thirds
        blind = (yy < h * 0.62)
        slat = 0.8 + 0.2 * np.sin(yy * 0.9)
        img = np.where(blind[..., None], rgb("#c2b89c")[None, None, :] * slat[..., None], img)
    elif variant == 3:  # warmly lit room
        glow = rgb("#a8743a")[None, None, :] * (0.55 + 0.45 * (1 - yy / h))[..., None]
        img = glow
        emit = rgb("#ffcf8a")[None, None, :] * np.ones((h, w, 1))
    elif variant == 4:  # roller shade half down
        img = np.where((yy < h * 0.45)[..., None], rgb("#d8c9a0")[None, None, :], img)
    elif variant == 5:  # red curtains drawn
        folds = 0.75 + 0.25 * np.sin(xx * 0.18 + rng.random() * 6)
        img = rgb("#6a1c18")[None, None, :] * folds[..., None]
    elif variant == 6:  # potted plant silhouette and lit lamp behind
        img = lerp(img, rgb("#4a3a25")[None, None, :], 0.5)
        plant = ((xx - w * 0.3) ** 2 / (w * 0.18) ** 2 + (yy - h * 0.86) ** 2 / (h * 0.09) ** 2) < 1
        img = np.where(plant[..., None], rgb("#1c2a14")[None, None, :], img)
        emit = rgb("#ffd9a0")[None, None, :] * 0.35 * np.ones((h, w, 1))
    elif variant == 7:  # grimy, dusty glass
        img = lerp(img, rgb("#6b675d")[None, None, :], 0.45)
    # Sky reflection streak (diagonal)
    if variant not in (3,):
        diag = (xx / w + yy / h * 0.6)
        refl = smoothstep(0.35, 0.55, diag) * (1 - smoothstep(0.6, 0.9, diag))
        img = lerp(img, rgb("#8fa3b2")[None, None, :], (refl * 0.28)[..., None])
    # Meeting rail and upper sash bottom rail
    rail_y = h * 0.5
    sash = rgb("#d9d3c4")
    draw_rect(img, 0, rail_y - h * 0.025, w, rail_y + h * 0.025, sash)
    draw_rect(emit, 0, rail_y - h * 0.025, w, rail_y + h * 0.025, (0, 0, 0))
    # Sash stiles
    for x0, x1 in ((0, w * 0.045), (w * 0.955, w)):
        draw_rect(img, x0, 0, x1, h, sash)
        draw_rect(emit, x0, 0, x1, h, (0, 0, 0))
    draw_rect(img, 0, 0, w, h * 0.03, sash)
    draw_rect(img, 0, h * 0.97, w, h, sash)
    img *= 0.92 + fbm(h, w, 8, 3, rng)[..., None] * 0.16
    return img, emit


def window_atlas(size, seed):
    rng = _rng(seed)
    cw = size // WINDOW_ATLAS_COLS
    chh = size // WINDOW_ATLAS_ROWS
    alb = np.zeros((size, size, 3))
    emi = np.zeros((size, size, 3))
    for v in range(WINDOW_ATLAS_COLS * WINDOW_ATLAS_ROWS):
        cx, cy = v % WINDOW_ATLAS_COLS, v // WINDOW_ATLAS_COLS
        a, e = _window_cell(cw, chh, v, rng)
        alb[cy * chh:(cy + 1) * chh, cx * cw:(cx + 1) * cw] = a
        emi[cy * chh:(cy + 1) * chh, cx * cw:(cx + 1) * cw] = e
    return alb, emi


SHOP_ATLAS_COLS = 2
SHOP_ATLAS_ROWS = 2


def _shop_cell(w, h, variant, rng):
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    warm = rgb("#5a3d22")
    img = warm[None, None, :] * (0.55 + 0.45 * (1 - yy / h))[..., None]
    if variant == 0:  # deli / grocery: shelves of goods
        for s in range(3):
            y = h * (0.25 + s * 0.22)
            draw_rect(img, 0, y, w, y + h * 0.03, rgb("#2a1c10"))
            x = 0
            while x < w:
                bw = rng.integers(6, 16)
                col = rgb(["#b33a2a", "#e0c070", "#3a6a3a", "#d8d0c0", "#2a4a7a"][rng.integers(0, 5)])
                draw_rect(img, x, y - h * 0.09, x + bw - 2, y, col * (0.7 + rng.random() * 0.3))
                x += bw
    elif variant == 1:  # restaurant: tables with checked cloths, warm light
        img = rgb("#8a5a2e")[None, None, :] * (0.6 + 0.4 * (1 - yy / h))[..., None]
        for t in range(4):
            cx = w * (0.12 + t * 0.25)
            for i in range(10):
                for j in range(3):
                    col = rgb("#c43a2a") if (i + j) % 2 else rgb("#efe6d2")
                    draw_rect(img, cx - 25 + i * 5, h * 0.62 + j * 5, cx - 20 + i * 5, h * 0.62 + j * 5 + 5, col)
            draw_rect(img, cx - 2, h * 0.77, cx + 2, h, rgb("#2a1a10"))
    elif variant == 2:  # barber / cafe: white tiles, mirrors
        img = rgb("#d8d6cc")[None, None, :] * np.ones((h, w, 1))
        tile = (np.floor(xx / 8) + np.floor(yy / 8)) % 2
        img *= (0.92 + tile * 0.06)[..., None]
        for m in range(3):
            draw_rect(img, w * (0.1 + m * 0.3), h * 0.15, w * (0.28 + m * 0.3), h * 0.55, rgb("#8fa3b2"))
    else:  # closed / dim store with gate shadow
        img = rgb("#1a1714")[None, None, :] * np.ones((h, w, 1))
        bars = (xx % 10) < 2
        img = np.where(bars[..., None], rgb("#3d3a35")[None, None, :], img)
    diag = (xx / w + yy / h * 0.5)
    refl = smoothstep(0.3, 0.5, diag) * (1 - smoothstep(0.55, 0.8, diag))
    img = lerp(img, rgb("#a9b7c0")[None, None, :], (refl * 0.25)[..., None])
    return img


def shop_atlas(w, h, seed):
    rng = _rng(seed)
    cw, chh = w // SHOP_ATLAS_COLS, h // SHOP_ATLAS_ROWS
    out = np.zeros((h, w, 3))
    for v in range(SHOP_ATLAS_COLS * SHOP_ATLAS_ROWS):
        cx, cy = v % SHOP_ATLAS_COLS, v // SHOP_ATLAS_COLS
        out[cy * chh:(cy + 1) * chh, cx * cw:(cx + 1) * cw] = _shop_cell(cw, chh, v, rng)
    return out


AWNING_SCHEMES = [("#a8231c", "#ece4d0"), ("#24543a", "#ece4d0"), ("#1f2d4a", "#e4d8b8"), ("#5a1a1a", "#c9a24a")]


def awning_atlas(size):
    """Four horizontal bands, each a vertical-stripe colour scheme. 2 m across."""
    out = np.zeros((size, size, 3))
    band = size // len(AWNING_SCHEMES)
    xx = np.arange(size) / size * 8.0  # 8 stripes of 0.25 m
    stripe = (np.floor(xx) % 2).astype(bool)
    for i, (a, b) in enumerate(AWNING_SCHEMES):
        row = np.where(stripe[:, None], rgb(b)[None, :], rgb(a)[None, :])
        out[i * band:(i + 1) * band] = row[None, :, :]
    rng = _rng(5)
    out *= 0.9 + fbm(size, size, 16, 3, rng)[..., None] * 0.15
    return out


def build_all(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    p = lambda n: os.path.join(out_dir, n)
    write_png(p("brick_red_albedo.png"), brick_albedo(1024, "#8e3b2a", "#9d968a", 11))
    write_png(p("brick_brown_albedo.png"), brick_albedo(1024, "#6b4430", "#8f877a", 12))
    write_png(p("brick_tan_albedo.png"), brick_albedo(1024, "#b08a62", "#a89f90", 13, variation=0.12))
    write_png(p("brick_dark_albedo.png"), brick_albedo(1024, "#53261d", "#6e675e", 14, soot=0.35))
    write_png(p("brick_painted_albedo.png"), brick_albedo(1024, "#e8e2d4", "#d4cdbd", 15, variation=0.04, soot=0.2))
    write_png(p("brick_normal.png"), brick_normal(1024, 16))
    a, n = stone(512, 21)
    write_png(p("stone_albedo.png"), a)
    write_png(p("stone_normal.png"), n)
    write_png(p("roof_albedo.png"), roof(512, 31))
    a, n = asphalt(1024, 41)
    write_png(p("asphalt_albedo.png"), a)
    write_png(p("asphalt_normal.png"), n)
    a, n = sidewalk(1024, 51)
    write_png(p("sidewalk_albedo.png"), a)
    write_png(p("sidewalk_normal.png"), n)
    a, e = window_atlas(1024, 61)
    write_png(p("window_atlas.png"), a)
    write_png(p("window_emission.png"), e)
    write_png(p("shop_atlas.png"), shop_atlas(1024, 512, 71))
    write_png(p("awning_atlas.png"), awning_atlas(256))
    a, n = corrugated(256)
    write_png(p("corrugated_albedo.png"), a)
    write_png(p("corrugated_normal.png"), n)
    write_png(p("wood_albedo.png"), wood(256, 81))
    write_png(p("foliage_albedo.png"), foliage(512, 91))
    write_png(p("grime_noise.png"), grime(512, 101))
    for i, kind in enumerate(("tar", "silver", "gravel")):
        a, n = roof_variant(512, 110 + i, kind)
        write_png(p("roof_%s_albedo.png" % kind), a)
        write_png(p("roof_%s_normal.png" % kind), n)
    palette_textures(out_dir)


def roof_variant(size, seed, kind):
    """Roof membranes (4 m tile): 'tar' dark rolled asphalt, 'silver'
    aluminium-coated (1970s 'tar beach'), 'gravel' ballasted. Returns albedo
    and a normal map with seams, blisters and ponding."""
    rng = _rng(seed)
    yy = np.arange(size)[:, None] / size * 4.0
    seam = (np.abs(yy - np.round(yy)) < 0.01).astype(float) * np.ones((1, size))
    big = fbm(size, size, 3, 5, rng)
    mid = fbm(size, size, 16, 4, rng)
    fine = rng.random((size, size))
    pond = smoothstep(0.6, 0.78, fbm(size, size, 2, 4, rng))
    if kind == "silver":
        base = rgb("#908f88")
        alb = base[None, None, :] * (0.8 + big[..., None] * 0.28) * (0.93 + mid[..., None] * 0.12)
        alb = lerp(alb, rgb("#6a6359")[None, None, :], (pond * 0.6)[..., None])
        flake = smoothstep(0.7, 0.86, fbm(size, size, 6, 4, rng))
        alb = lerp(alb, rgb("#4a4741")[None, None, :], (flake * 0.35)[..., None])
        height = mid * 0.4 + seam * 0.6 + flake * -0.3
    elif kind == "gravel":
        base = rgb("#8f8a80")
        grit = (fine > 0.5).astype(float) * 0.12 + (fine > 0.92) * 0.25 - (fine < 0.08) * 0.25
        alb = base[None, None, :] * (0.8 + big[..., None] * 0.25 + grit[..., None])
        alb = lerp(alb, rgb("#55524b")[None, None, :], (pond * 0.45)[..., None])
        height = fine * 0.7 + mid * 0.3
        seam = seam * 0.0
    else:
        base = rgb("#3e3c39")
        alb = base[None, None, :] * (0.72 + big[..., None] * 0.45) * (0.9 + mid[..., None] * 0.2)
        alb = np.where((fine > 0.94)[..., None], alb * 1.45, alb)
        alb = lerp(alb, rgb("#77705f")[None, None, :], (pond * 0.35)[..., None])
        blister = smoothstep(0.7, 0.8, fbm(size, size, 24, 2, rng))
        height = mid * 0.5 + blister * 0.5 + seam * 0.8
    alb = np.where((seam > 0.5)[..., None], alb * 0.7, alb)
    return alb, height_to_normal(height, 3.0)


def grime(size, seed):
    """World-space weathering mask (tileable): R blotches, G vertical rain
    streaks, B fine speckle. Sampled by the world shader at several scales."""
    rng = _rng(seed)
    blot = smoothstep(0.35, 0.75, fbm(size, size, 4, 5, rng))
    streak = value_noise(size, size, 6, 48, rng) * 0.6 + value_noise(size, size, 12, 96, rng) * 0.4
    streak = smoothstep(0.45, 0.85, streak)
    speck = fbm(size, size, 64, 3, rng)
    return np.dstack([blot, streak, speck])


def palette_textures(out_dir):
    """Pack untextured materials into swatch atlases (see materials.py)."""
    from . import materials as matlib

    n = matlib.PALETTE_GRID
    px = matlib.PALETTE_SWATCH_PX
    size = n * px
    alb = np.zeros((size, size, 3))
    orm = np.zeros((size, size, 3))
    emi = np.zeros((size, size, 3))
    for i, name in enumerate(matlib.palette_names()):
        m = matlib.get(name)
        col, row = i % n, i // n
        ys, xs = slice(row * px, (row + 1) * px), slice(col * px, (col + 1) * px)
        alb[ys, xs] = rgb("#ffffff") if m.get("tint") else rgb(m.get("color", "#ffffff"))
        orm[ys, xs] = (1.0 if m.get("tint") else 0.0, m.get("roughness", 0.8), m.get("metallic", 0.0))
        if m.get("emission"):
            emi[ys, xs] = rgb(m["emission"]) * min(1.0, m.get("emission_energy", 1.0) / matlib.PALETTE_EMISSION_SCALE)
    write_png(os.path.join(out_dir, "palette_albedo.png"), alb)
    write_png(os.path.join(out_dir, "palette_orm.png"), orm)
    write_png(os.path.join(out_dir, "palette_emission.png"), emi)
