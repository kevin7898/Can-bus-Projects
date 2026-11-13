"""Composite KiCad layer rasters into realistic bare-board images (cropped exactly to the outline)."""
import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

R = sys.argv[1]
PPMM = 20
BW, BH = 110.0, 85.0

def load(name):
    return np.array(Image.open(f"{R}/{name}.png").convert("L")) < 128   # True = ink

edge = load("Edge.Cuts")
ys, xs = np.nonzero(edge)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
crop = (slice(y0, y1 + 1), slice(x0, x1 + 1))
W, H = x1 - x0 + 1, y1 - y0 + 1
sx, sy = W / BW, H / BH

# board region = flood fill of the outline interior
img = Image.fromarray(np.where(edge[crop], 0, 255).astype(np.uint8)).copy()
ImageDraw.floodfill(img, (W // 2, H // 2), 128)
board = np.array(img) == 128
board |= edge[crop]

data = json.load(open(f"{R}/board.json"))

def render(side):
    cu = load(f"{side}.Cu")[crop]
    mask_open = load(f"{side}.Mask")[crop]
    silk = load(f"{side}.SilkS")[crop] & ~edge[crop]
    out = np.zeros((H, W, 3), np.float32)
    bg = np.array([28, 30, 34], np.float32)            # backdrop
    fr4 = np.array([176, 150, 92], np.float32)
    mask_bare = np.array([22, 84, 46], np.float32)     # LPI green over laminate
    mask_cu = np.array([44, 122, 70], np.float32)      # green over copper (lighter)
    gold = np.array([222, 186, 96], np.float32)        # ENIG
    white = np.array([238, 238, 230], np.float32)
    out[:] = bg
    out[board & ~cu] = mask_bare
    out[board & cu] = mask_cu
    out[board & mask_open & cu] = gold
    out[board & mask_open & ~cu] = fr4
    out[board & silk & ~mask_open] = white
    im = Image.fromarray(out.astype(np.uint8))
    d = ImageDraw.Draw(im)
    for x, y, r, npth in data["holes"]:
        cx, cy, rr = x * sx, y * sy, r * sx
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(12, 12, 14) if not npth else (28, 30, 34))
    # board edge: thin FR4 rim
    rim = board & ~np.array(Image.fromarray(board.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(5))).astype(bool)
    arr = np.array(im)
    arr[rim] = (150, 128, 80)
    im = Image.fromarray(arr)
    if side == "B":
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im

for side in ("F", "B"):
    im = render(side)
    im.save(f"{R}/bare_{side}.png")
    print(side, im.size)
