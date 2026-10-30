#!/usr/bin/env python3
"""Generates every sprite and icon used by the game.

All art is drawn procedurally here, so the project ships with no third-party
assets. The output is released under CC0 (see assets/LICENSE.md).

    python3 tools/generate_sprites.py

Writes PNGs to assets/sprites (world graphics) and assets/icons (32x32 item
icons). Requires Pillow (pip install pillow). Sprites face north; the game
rotates them for the other three directions.
"""
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SPR = os.path.join(ROOT, "assets", "sprites")
ICO = os.path.join(ROOT, "assets", "icons")
T = 32
OUTLINE = (24, 24, 30, 255)

METAL = (118, 124, 134, 255)
METAL_LIGHT = (168, 174, 184, 255)
METAL_DARK = (70, 74, 84, 255)
PIPE = (112, 118, 128, 255)


# --------------------------------------------------------------------------
# Drawing helpers
# --------------------------------------------------------------------------

def rgba(c):
    return tuple(c) if len(c) == 4 else tuple(c) + (255,)


def shade(c, f):
    """f > 0 lightens towards white, f < 0 darkens towards black."""
    r, g, b = c[:3]
    if f >= 0:
        r, g, b = (int(v + (255 - v) * f) for v in (r, g, b))
    else:
        r, g, b = (int(v * (1 + f)) for v in (r, g, b))
    return (r, g, b, c[3] if len(c) > 3 else 255)


def canvas(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def box(d, x0, y0, x1, y1, col, bevel=2, outline=OUTLINE):
    """Filled rectangle with a light top-left and dark bottom-right bevel."""
    col = rgba(col)
    d.rectangle([x0, y0, x1, y1], fill=col)
    hi, lo = shade(col, 0.3), shade(col, -0.35)
    for i in range(bevel):
        d.line([(x0 + 1 + i, y0 + 1 + i), (x1 - 1 - i, y0 + 1 + i)], fill=hi)
        d.line([(x0 + 1 + i, y0 + 1 + i), (x0 + 1 + i, y1 - 1 - i)], fill=hi)
        d.line([(x0 + 1 + i, y1 - 1 - i), (x1 - 1 - i, y1 - 1 - i)], fill=lo)
        d.line([(x1 - 1 - i, y0 + 1 + i), (x1 - 1 - i, y1 - 1 - i)], fill=lo)
    if outline:
        d.rectangle([x0, y0, x1, y1], outline=outline)


def disc(d, cx, cy, r, col, outline=OUTLINE):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgba(col), outline=outline)


def ring_shaded(d, cx, cy, r, col):
    """Disc with a highlight on the upper-left and shadow lower-right."""
    col = rgba(col)
    disc(d, cx, cy, r, shade(col, -0.3))
    disc(d, cx - 1, cy - 1, r - 2, col, outline=None)
    d.arc([cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2], 190, 280, fill=shade(col, 0.4), width=2)


def rivets(d, x0, y0, x1, y1, inset=3, col=(58, 60, 66, 255)):
    for x, y in ((x0 + inset, y0 + inset), (x1 - inset, y0 + inset),
                 (x0 + inset, y1 - inset), (x1 - inset, y1 - inset)):
        d.rectangle([x - 1, y - 1, x, y], fill=col)
        d.point((x - 1, y - 1), fill=shade(col, 0.5))


def speckle(img, rect, amount, seed, strength=0.08):
    """Adds subtle per-pixel noise to opaque pixels inside rect."""
    rnd = random.Random(seed)
    px = img.load()
    x0, y0, x1, y1 = rect
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = px[x, y]
            if c[3] == 0 or rnd.random() > amount:
                continue
            px[x, y] = shade(c, rnd.uniform(-strength, strength))


def with_shadow(img, offset=(2, 3), alpha=80):
    """Composites a soft drop shadow beneath the opaque pixels of img."""
    a = img.split()[3]
    shifted = Image.new("L", img.size, 0)
    shifted.paste(a, offset)
    mask = shifted.point(lambda v: alpha if v > 0 else 0)
    sh = Image.new("RGBA", img.size, (8, 12, 8, 0))
    sh.putalpha(mask)
    return Image.alpha_composite(sh, img)


def rock(d, rnd, cx, cy, r, base, hi, lo):
    pts = []
    n = 7
    for i in range(n):
        a = 2 * math.pi * i / n + rnd.uniform(-0.25, 0.25)
        rr = r * rnd.uniform(0.75, 1.1)
        pts.append((cx + rr * math.cos(a), cy + rr * 0.85 * math.sin(a)))
    d.polygon(pts, fill=rgba(lo), outline=OUTLINE)
    inner = [(cx + (x - cx) * 0.78 - r * 0.12, cy + (y - cy) * 0.75 - r * 0.15) for x, y in pts]
    d.polygon(inner, fill=rgba(base))
    shine = [(cx + (x - cx) * 0.35 - r * 0.3, cy + (y - cy) * 0.3 - r * 0.35) for x, y in pts]
    d.polygon(shine, fill=rgba(hi))


def gear_shape(d, cx, cy, r_out, r_in, teeth, col, hole=3):
    pts = []
    steps = teeth * 4
    for i in range(steps):
        a = 2 * math.pi * i / steps
        r = r_out if (i % 4) in (1, 2) else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=rgba(col), outline=OUTLINE)
    d.ellipse([cx - r_in + 3, cy - r_in + 3, cx + r_in - 3, cy + r_in - 3], outline=shade(col, -0.3))
    if hole:
        disc(d, cx, cy, hole, (40, 40, 46))


def save(img, folder, name):
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, name + ".png"))


def fit_icon(img, size=30):
    """Scales a sprite down to a centered 32x32 icon."""
    w, h = img.size
    s = min(size / w, size / h, 1.0)
    small = img.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    out = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    out.paste(small, ((T - small.width) // 2, (T - small.height) // 2), small)
    return out


# --------------------------------------------------------------------------
# Terrain
# --------------------------------------------------------------------------

def grass_tile(seed):
    rnd = random.Random(seed)
    img, d = canvas(T, T)
    base = (84, 116, 56)
    d.rectangle([0, 0, T - 1, T - 1], fill=rgba(base))
    px = img.load()
    for y in range(T):
        for x in range(T):
            px[x, y] = shade(base, rnd.uniform(-0.07, 0.06))
    for _ in range(14):
        x, y = rnd.randrange(T), rnd.randrange(1, T)
        c = shade(base, rnd.choice([-0.22, 0.18, 0.12]))
        d.point((x, y), fill=c)
        d.point((x, y - 1), fill=c)
    for _ in range(rnd.randint(0, 2)):
        x, y = rnd.randrange(2, T - 2), rnd.randrange(2, T - 2)
        d.point((x, y), fill=rgba(rnd.choice([(214, 196, 90), (200, 210, 230), (190, 120, 160)])))
    return img


def water_tile(seed, base):
    rnd = random.Random(seed)
    img, d = canvas(T, T)
    px = img.load()
    for y in range(T):
        for x in range(T):
            px[x, y] = shade(base, rnd.uniform(-0.03, 0.03))
    for _ in range(5):
        x, y = rnd.randrange(T), rnd.randrange(T)
        ln = rnd.randint(3, 7)
        for i in range(ln):
            px[(x + i) % T, y] = shade(base, 0.22)
    return img


def sand_tile(seed):
    rnd = random.Random(seed)
    img, d = canvas(T, T)
    base = (186, 170, 116)
    px = img.load()
    for y in range(T):
        for x in range(T):
            px[x, y] = shade(base, rnd.uniform(-0.06, 0.05))
    for _ in range(6):
        x, y = rnd.randrange(1, T - 1), rnd.randrange(1, T - 1)
        d.point((x, y), fill=shade(base, -0.3))
        d.point((x + 1, y), fill=shade(base, 0.25))
    return img


def make_terrain():
    atlas = Image.new("RGBA", (T * 8, T), (0, 0, 0, 0))
    for i in range(4):
        atlas.paste(grass_tile(100 + i), (i * T, 0))
    atlas.paste(water_tile(7, (48, 98, 152)), (4 * T, 0))
    atlas.paste(water_tile(8, (36, 78, 134)), (5 * T, 0))
    atlas.paste(sand_tile(9), (6 * T, 0))
    atlas.paste(grass_tile(110), (7 * T, 0))
    save(atlas, SPR, "terrain")


ORES = {
    "iron_ore": ((128, 146, 172), (196, 210, 228), (72, 84, 104), None),
    "copper_ore": ((192, 106, 58), (236, 164, 100), (112, 58, 34), (64, 168, 146)),
    "coal": ((46, 46, 50), (118, 118, 130), (20, 20, 24), None),
    "stone": ((168, 156, 132), (216, 206, 182), (108, 98, 82), None),
}


def ore_tile(name, seed):
    base, hi, lo, fleck = ORES[name]
    rnd = random.Random(seed)
    img, d = canvas(T, T)
    # Translucent stain so neighbouring ore tiles read as one patch.
    px = img.load()
    for y in range(T):
        for x in range(T):
            px[x, y] = lo[:3] + (int(rnd.uniform(28, 46)),)
    for _ in range(rnd.randint(8, 10)):
        cx, cy = rnd.uniform(5, 27), rnd.uniform(5, 27)
        rock(d, rnd, cx, cy, rnd.uniform(3.4, 5.4), base, hi, lo)
    for _ in range(5):
        d.point((rnd.randrange(2, 30), rnd.randrange(2, 30)), fill=rgba(lo))
    if fleck:
        px = img.load()
        for _ in range(8):
            x, y = rnd.randrange(T), rnd.randrange(T)
            if px[x, y][3] and px[x, y][:3] != OUTLINE[:3]:
                px[x, y] = rgba(fleck)
    return img


def make_ores():
    atlas = Image.new("RGBA", (T * 3, T * 4), (0, 0, 0, 0))
    for row, name in enumerate(["iron_ore", "copper_ore", "coal", "stone"]):
        for v in range(3):
            atlas.paste(ore_tile(name, row * 31 + v * 7 + 3), (v * T, row * T))
    save(atlas, SPR, "ores")


# --------------------------------------------------------------------------
# Item icons
# --------------------------------------------------------------------------

def ore_icon(name, seed):
    base, hi, lo, fleck = ORES[name]
    rnd = random.Random(seed)
    img, d = canvas(T, T)
    for cx, cy, r in ((11, 19, 8), (21, 20, 7.5), (16, 11, 7)):
        rock(d, rnd, cx, cy, r, base, hi, lo)
    if fleck:
        px = img.load()
        for _ in range(10):
            x, y = rnd.randrange(T), rnd.randrange(T)
            if px[x, y][3] and px[x, y][:3] != OUTLINE[:3]:
                px[x, y] = rgba(fleck)
    return img


def plate_icon(col):
    img, d = canvas(T, T)
    for off in (6, 0):
        y = 9 + off
        pts = [(4, y + 4), (18, y), (28, y + 4), (14, y + 8)]
        d.polygon(pts, fill=rgba(col), outline=OUTLINE)
        d.polygon([(4, y + 4), (14, y + 8), (14, y + 11), (4, y + 7)], fill=shade(col, -0.3), outline=OUTLINE)
        d.polygon([(14, y + 8), (28, y + 4), (28, y + 7), (14, y + 11)], fill=shade(col, -0.15), outline=OUTLINE)
        d.line([(9, y + 3), (17, y + 1)], fill=shade(col, 0.45))
    return img


def brick_icon():
    img, d = canvas(T, T)
    col = (176, 150, 118)
    box(d, 4, 9, 27, 24, col)
    mortar = shade(col, -0.35)
    d.line([(5, 16), (26, 16)], fill=mortar)
    d.line([(12, 10), (12, 16)], fill=mortar)
    d.line([(20, 16), (20, 23)], fill=mortar)
    speckle(img, (5, 10, 26, 23), 0.35, 4, 0.1)
    return img


def gear_icon():
    img, d = canvas(T, T)
    gear_shape(d, 16, 16, 13, 10, 8, (150, 156, 166), hole=4)
    d.arc([8, 8, 24, 24], 200, 290, fill=(210, 214, 222, 255), width=2)
    return img


def wire_icon():
    img, d = canvas(T, T)
    wood = (150, 108, 66)
    cu = (206, 116, 58)
    box(d, 9, 9, 22, 23, cu, bevel=1)
    for y in range(11, 23, 2):
        d.line([(10, y), (21, y)], fill=shade(cu, -0.25))
    box(d, 6, 6, 25, 9, wood, bevel=1)
    box(d, 6, 23, 25, 26, wood, bevel=1)
    d.line([(22, 14), (27, 12), (29, 16)], fill=rgba(cu), width=2)
    return img


def circuit_icon():
    img, d = canvas(T, T)
    green = (48, 138, 70)
    box(d, 3, 6, 28, 25, green)
    trace = (120, 200, 120, 255)
    d.line([(6, 10), (12, 10), (12, 14)], fill=trace)
    d.line([(6, 21), (11, 21), (11, 18)], fill=trace)
    d.line([(20, 12), (25, 12), (25, 9)], fill=trace)
    d.line([(20, 18), (25, 18), (25, 22)], fill=trace)
    box(d, 11, 11, 20, 20, (36, 36, 42), bevel=1)
    for y in (13, 16, 18):
        d.point((10, y), fill=(220, 180, 60, 255))
        d.point((21, y), fill=(220, 180, 60, 255))
    for x in range(6, 26, 3):
        d.point((x, 24), fill=(230, 190, 70, 255))
    return img


# --------------------------------------------------------------------------
# Buildings (all drawn facing north)
# --------------------------------------------------------------------------

def belt_frames():
    """8 animation frames of a straight belt moving north."""
    strip = Image.new("RGBA", (T * 8, T), (0, 0, 0, 0))
    rail = (126, 128, 138)
    surface = (56, 56, 62)
    ridge = (94, 94, 102)
    for f in range(8):
        img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        px = img.load()
        for y in range(T):
            for x in range(2, 30):
                if x in (2, 29):
                    c = OUTLINE
                elif x <= 5 or x >= 26:
                    c = rgba(rail)
                    if x in (3, 26):
                        c = shade(rail, 0.3)
                    if x in (5, 28):
                        c = shade(rail, -0.3)
                    if (y + f * 2) % 8 == 0:
                        c = shade(rail, -0.45)
                    if x in (4, 27) and (y + f * 2) % 8 == 4:
                        c = rgba((214, 172, 52))
                else:
                    dx = abs(x - 15.5)
                    v = (y + f * 2 - dx * 0.7) % 16
                    c = rgba(surface)
                    if v < 3:
                        c = rgba(ridge) if v >= 1 else shade(ridge, 0.25)
                    if x in (6, 25):
                        c = shade(c, -0.3)
                px[x, y] = c
        strip.paste(img, (f * T, 0))
    return strip


def belt_curve(strip, from_left):
    """Warps the straight frames around a quarter circle (enter side -> exit north)."""
    out = Image.new("RGBA", strip.size, (0, 0, 0, 0))
    src = strip.load()
    dst = out.load()
    for f in range(8):
        for py in range(T):
            for px_ in range(T):
                # Corner of the turn: top-left when entering from the west.
                lx = px_ + 0.5 if from_left else T - (px_ + 0.5)
                ly = py + 0.5
                r = math.hypot(lx, ly)
                if r < 2 or r >= 30:
                    continue
                theta = math.atan2(ly, lx)  # pi/2 at entry edge, 0 at exit
                ys = min(T - 1, max(0, int(T * theta / (math.pi / 2))))
                xs = int(r)
                if not from_left:
                    xs = T - 1 - xs
                dst[f * T + px_, py] = src[f * T + xs, ys]
    return out


def inserter_base():
    img, d = canvas(T, T)
    box(d, 6, 7, 25, 26, (92, 96, 106))
    rivets(d, 6, 7, 25, 26, inset=2)
    disc(d, 16, 16, 7, (214, 170, 48))
    disc(d, 16, 16, 4, (120, 96, 30), outline=None)
    disc(d, 16, 16, 2, (50, 50, 56), outline=None)
    return with_shadow(img)


def inserter_icon():
    img = inserter_base()
    d = ImageDraw.Draw(img)
    d.line([(16, 16), (21, 9), (25, 4)], fill=(214, 170, 48, 255), width=3)
    disc(d, 25, 4, 2, (60, 60, 66))
    return img


def burner_drill():
    img, d = canvas(64, 64)
    box(d, 10, 0, 22, 10, (150, 136, 112))  # output chute (front-left tile)
    d.rectangle([13, 0, 19, 4], fill=(40, 36, 32, 255))
    box(d, 3, 6, 59, 59, (114, 100, 86))
    speckle(img, (4, 7, 58, 58), 0.4, 11, 0.06)
    rivets(d, 3, 6, 59, 59)
    ring_shaded(d, 32, 34, 14, (88, 82, 76))
    disc(d, 32, 34, 9, (50, 46, 44))
    # Fire box
    box(d, 42, 45, 55, 56, (54, 46, 42), bevel=1)
    for x in (45, 49, 53):
        d.line([(x, 48), (x, 54)], fill=(214, 110, 40, 255))
    d.rectangle([8, 46, 20, 49], fill=(70, 60, 52, 255))
    return with_shadow(img)


def electric_drill():
    img, d = canvas(96, 96)
    box(d, 40, 0, 55, 12, (126, 140, 156))  # output chute (front center)
    d.rectangle([44, 0, 51, 5], fill=(34, 38, 44, 255))
    box(d, 4, 8, 90, 90, (80, 98, 120))
    speckle(img, (5, 9, 89, 89), 0.4, 12, 0.05)
    for x, y in ((6, 10), (74, 10), (6, 74), (74, 74)):
        box(d, x, y, x + 14, y + 14, (60, 72, 88), bevel=1)
        disc(d, x + 7, y + 7, 3, (40, 44, 52))
    ring_shaded(d, 48, 50, 22, (104, 116, 132))
    disc(d, 48, 50, 15, (40, 44, 50))
    box(d, 24, 80, 70, 86, (52, 60, 72), bevel=1)
    for x in range(28, 68, 6):
        d.line([(x, 81), (x + 3, 85)], fill=(220, 180, 50, 255))
    disc(d, 82, 48, 3, (90, 220, 255))
    return with_shadow(img)


def furnace():
    img, d = canvas(64, 64)
    stone = (150, 138, 118)
    d.rounded_rectangle([3, 4, 59, 59], radius=10, fill=rgba(stone), outline=OUTLINE)
    mortar = shade(stone, -0.28)
    for i, y in enumerate(range(12, 58, 7)):
        d.line([(6, y), (56, y)], fill=mortar)
        for x in range(8 + (i % 2) * 6, 56, 12):
            d.line([(x, y - 6), (x, y)], fill=mortar)
    speckle(img, (4, 5, 58, 58), 0.5, 13, 0.1)
    d.arc([5, 6, 57, 57], 180, 270, fill=shade(stone, 0.3), width=2)
    # Top opening (crucible)
    d.ellipse([18, 9, 44, 31], fill=(34, 28, 26, 255), outline=OUTLINE)
    d.ellipse([22, 13, 40, 27], fill=(56, 40, 32, 255))
    # Fire box arch
    d.rounded_rectangle([22, 38, 40, 56], radius=6, fill=(30, 24, 22, 255), outline=OUTLINE)
    d.line([(24, 52), (38, 52)], fill=(90, 70, 60, 255))
    return with_shadow(img)


def assembler():
    img, d = canvas(96, 96)
    box(d, 4, 4, 90, 90, (112, 118, 100))
    speckle(img, (5, 5, 89, 89), 0.4, 14, 0.05)
    rivets(d, 4, 4, 90, 90, inset=4)
    box(d, 18, 18, 76, 76, (78, 82, 70), bevel=2)
    for x in range(22, 74, 6):
        d.line([(x, 8), (x, 14)], fill=(64, 68, 58, 255))
        d.line([(x, 80), (x, 86)], fill=(64, 68, 58, 255))
    for i in range(0, 50, 8):
        d.polygon([(23 + i, 77), (27 + i, 77), (31 + i, 73), (27 + i, 73)], fill=(220, 180, 50, 255))
    disc(d, 47, 47, 20, (58, 60, 56))
    disc(d, 47, 47, 16, (36, 38, 36), outline=None)
    disc(d, 84, 12, 3, (120, 230, 120))
    return with_shadow(img)


def chest():
    img, d = canvas(T, T)
    col = (134, 128, 118)
    box(d, 4, 6, 27, 27, col)
    d.line([(5, 12), (26, 12)], fill=shade(col, -0.4))
    d.line([(5, 21), (26, 21)], fill=shade(col, -0.25))
    box(d, 13, 10, 18, 15, (220, 176, 60), bevel=1)
    rivets(d, 4, 6, 27, 27, inset=2)
    return with_shadow(img)


def pipe_atlas():
    atlas = Image.new("RGBA", (T * 16, T), (0, 0, 0, 0))
    for mask in range(16):
        img, d = canvas(T, T)
        if mask & 1:
            box(d, 11, 0, 20, 14, PIPE, bevel=1)
            d.line([(11, 2), (20, 2)], fill=METAL_DARK)
        if mask & 2:
            box(d, 17, 11, 31, 20, PIPE, bevel=1)
            d.line([(29, 11), (29, 20)], fill=METAL_DARK)
        if mask & 4:
            box(d, 11, 17, 20, 31, PIPE, bevel=1)
            d.line([(11, 29), (20, 29)], fill=METAL_DARK)
        if mask & 8:
            box(d, 0, 11, 14, 20, PIPE, bevel=1)
            d.line([(2, 11), (2, 20)], fill=METAL_DARK)
        box(d, 9, 9, 22, 22, shade(PIPE, 0.08), bevel=2)
        disc(d, 15, 15, 2, METAL_DARK, outline=None)
        atlas.paste(with_shadow(img, (1, 2), 70), (mask * T, 0))
    return atlas


def pump():
    img, d = canvas(T, T)
    box(d, 12, 0, 19, 10, PIPE, bevel=1)
    box(d, 5, 8, 26, 28, (70, 104, 140))
    rivets(d, 5, 8, 26, 28, inset=2)
    disc(d, 15, 18, 6, (200, 72, 52))
    disc(d, 15, 18, 2, (60, 30, 24), outline=None)
    d.rectangle([7, 25, 24, 27], fill=(40, 60, 84, 255))
    return with_shadow(img)


def boiler():
    img, d = canvas(96, 64)
    box(d, 0, 41, 9, 54, PIPE, bevel=1)   # water in/out (left)
    box(d, 86, 41, 95, 54, PIPE, bevel=1)  # water in/out (right)
    box(d, 40, 0, 55, 12, PIPE, bevel=1)   # steam out (front)
    body = (132, 112, 98)
    d.rounded_rectangle([6, 8, 89, 58], radius=12, fill=rgba(body), outline=OUTLINE)
    d.rounded_rectangle([9, 11, 86, 22], radius=6, fill=shade(body, 0.22))
    for x in (24, 47, 70):
        d.line([(x, 9), (x, 57)], fill=shade(body, -0.35), width=2)
    speckle(img, (7, 9, 88, 57), 0.4, 15, 0.06)
    box(d, 37, 38, 58, 56, (46, 40, 38), bevel=1)
    for x in range(40, 57, 4):
        d.line([(x, 42), (x, 53)], fill=(80, 66, 60, 255))
    disc(d, 16, 32, 4, (230, 230, 230))
    d.line([(16, 32), (18, 30)], fill=(200, 40, 40, 255))
    return with_shadow(img)


def steam_engine():
    img, d = canvas(96, 96)
    box(d, 40, 0, 55, 10, PIPE, bevel=1)
    box(d, 40, 85, 55, 95, PIPE, bevel=1)
    body = (98, 114, 100)
    box(d, 8, 8, 87, 87, body)
    speckle(img, (9, 9, 86, 86), 0.4, 16, 0.05)
    rivets(d, 8, 8, 87, 87, inset=4)
    box(d, 12, 28, 26, 68, (78, 90, 80), bevel=1)   # piston housing
    d.rectangle([16, 34, 22, 62], fill=(60, 66, 62, 255))
    d.line([(24, 48), (34, 48)], fill=METAL_LIGHT, width=3)
    ring_shaded(d, 52, 48, 26, (84, 86, 92))
    disc(d, 52, 48, 21, (46, 48, 52))
    disc(d, 52, 48, 5, (150, 150, 158))
    box(d, 68, 12, 84, 22, (180, 140, 50), bevel=1)
    return with_shadow(img)


def pole():
    img, d = canvas(T, 56)
    d.ellipse([8, 49, 24, 55], fill=(0, 0, 0, 70))
    wood = (124, 88, 54)
    box(d, 14, 8, 18, 53, wood, bevel=1)
    box(d, 4, 9, 27, 13, shade(wood, -0.1), bevel=1)
    for x in (7, 24):
        disc(d, x, 8, 2, (210, 220, 200))
    d.line([(15, 14), (8, 22)], fill=shade(wood, -0.2), width=2)
    return img


def player():
    img, d = canvas(T, T)
    d.ellipse([7, 20, 25, 30], fill=(0, 0, 0, 70))
    box(d, 11, 18, 20, 27, (92, 92, 100), bevel=1)  # backpack
    d.ellipse([6, 10, 25, 23], fill=(216, 126, 44, 255), outline=OUTLINE)
    d.ellipse([7, 6, 12, 13], fill=(196, 110, 36, 255), outline=OUTLINE)   # left arm
    d.ellipse([19, 6, 24, 13], fill=(196, 110, 36, 255), outline=OUTLINE)  # right arm
    disc(d, 15, 14, 6, (226, 226, 216))
    d.rectangle([12, 9, 18, 11], fill=(40, 70, 100, 255))
    return img


def status_icon(kind):
    img, d = canvas(16, 16)
    disc(d, 8, 8, 7, (190, 40, 36))
    if kind == "no_power":
        d.polygon([(9, 2), (4, 9), (8, 9), (6, 14), (12, 6), (8, 6)], fill=(255, 220, 60, 255))
    elif kind == "no_fuel":
        d.polygon([(8, 2), (12, 8), (11, 12), (8, 14), (5, 12), (4, 8)], fill=(255, 160, 40, 255))
        d.polygon([(8, 7), (10, 10), (8, 13), (6, 10)], fill=(255, 230, 90, 255))
    elif kind == "no_input":
        d.rectangle([7, 3, 9, 10], fill=(255, 255, 255, 255))
        d.rectangle([7, 12, 9, 13], fill=(255, 255, 255, 255))
    return img


# --------------------------------------------------------------------------

def main():
    random.seed(1)
    make_terrain()
    make_ores()

    for i, name in enumerate(ORES):
        save(ore_icon(name, 50 + i), ICO, name)
    save(plate_icon((168, 176, 188)), ICO, "iron_plate")
    save(plate_icon((210, 124, 72)), ICO, "copper_plate")
    save(brick_icon(), ICO, "stone_brick")
    save(gear_icon(), ICO, "iron_gear")
    save(wire_icon(), ICO, "copper_wire")
    save(circuit_icon(), ICO, "circuit")

    strip = belt_frames()
    save(strip, SPR, "belt_straight")
    save(belt_curve(strip, True), SPR, "belt_curve_left")
    save(belt_curve(strip, False), SPR, "belt_curve_right")
    save(fit_icon(strip.crop((0, 0, T, T))), ICO, "belt")

    pipes = pipe_atlas()
    save(pipes, SPR, "pipe")
    save(pipes.crop((10 * T, 0, 11 * T, T)), ICO, "pipe")

    save(inserter_base(), SPR, "inserter")
    save(inserter_icon(), ICO, "inserter")

    sprites = {
        "burner_drill": burner_drill(),
        "electric_drill": electric_drill(),
        "furnace": furnace(),
        "assembler": assembler(),
        "chest": chest(),
        "pump": pump(),
        "boiler": boiler(),
        "steam_engine": steam_engine(),
        "pole": pole(),
        "player": player(),
    }
    for name, img in sprites.items():
        save(img, SPR, name)
        if name != "player":
            save(fit_icon(img), ICO, name)

    for kind in ("no_power", "no_fuel", "no_input"):
        save(status_icon(kind), SPR, "status_" + kind)
    print("Sprites written to", SPR, "and", ICO)


if __name__ == "__main__":
    main()
