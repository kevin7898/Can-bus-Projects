"""Autorouter for the QuadCAN-C5 board: direction-aware A* (C core) + rip-up-and-reroute.

Reads geom.json (export_geom.py) and writes routes.json (apply_routes.py adds it to the board).
Layers: F.Cu, In2.Cu and B.Cu carry signals. In1.Cu is a solid GND plane, used for a signal only
as a last resort. Every SMD GND pad gets a short stub to a via into the plane.

How it works
  1. Every connection is an A* search on a 0.1 mm grid (route_core.c). The search state includes
     the direction of travel, so bends cost extra: tracks come out as long straight runs joined by
     45-degree corners. Obstacles are inflated by track half-width + clearance, so anything the
     search finds is DRC-clean by construction.
  2. Nets are routed critical-first, then short-to-long.
  3. Repair: a connection that failed is routed "through" other nets' tracks to find where it
     wants to go. The nets in its way are ripped up, it is routed, and they are routed again.
     The change is kept only if the number of open connections does not grow.

usage: python3 route.py geom.json routes.json
"""
import copy
import ctypes
import json
import hashlib
import math
import os
import random
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

HERE = os.path.dirname(os.path.abspath(__file__))
GRID = 0.1
LAYERS = ["F", "In2", "B", "In1"]     # In1 = GND plane: last resort only
SIGNAL_LAYERS = (1, 1, 1, 0)
CLR = 0.25            # clearance enforced (board rule is 0.15 mm)
EDGE_CLR = 0.45
VIA_D, VIA_DRILL = 0.6, 0.3
VIA_COST = 14.0
TURN45, TURN90 = 0.6, 2.5
HW = float(os.environ.get("ROUTE_HW", "1.4"))
LAYER_COST = [1.0, 1.1, 1.05, 3.0]
LONG_COST = [1.5, 1.0, 1.25, 3.0]     # long signal nets prefer the inner layer
MAX_EXP = 60_000_000
GND_FIRST = os.environ.get("ROUTE_GND_FIRST", "1") == "1"
SIG_W = 0.2
WIDE = {"VIN_RAW": 1.0, "VIN_F": 1.0, "VIN": 0.8, "BUCK_SW": 1.0, "+5V": 0.6, "+5V_SYS": 0.5,
        "SCAP": 0.5, "+3V3": 0.4, "VBUS": 0.5, "GPS_3V3": 0.4, "SD_3V3": 0.4, "GND": 0.4,
        "CAN1_H": 0.3, "CAN1_L": 0.3, "CAN2_H": 0.3, "CAN2_L": 0.3,
        "CAN3_H": 0.3, "CAN3_L": 0.3, "CAN4_H": 0.3, "CAN4_L": 0.3, "GPS_RF": 0.3}
WIDE.update({"BAT_PACK":0.8,"BAT":0.8,"VSYS":0.8,"BOOST_SW":0.8,"VEH_5V":0.8,"CHG_IN":0.8,"USB_PWR":0.6})
FIRST = ["BOOST_SW", "BOOST_FB", "VSYS", "BAT", "CHG_IN", "BUCK_SW", "BUCK_BOOT", "BUCK_FB", "BUCK_COMP", "BUCK_CZ", "BUCK_EN", "BUCK_RT",
         "VIN_RAW", "VIN_F", "VIN", "+5V", "+5V_SYS", "SCAP", "VBUS", "USB_DP", "USB_DN",
         "GPS_RF", "GPS_BIAS", "GPS_VCC_RF", "CLK40", "RTC_XI", "RTC_XO",
         "CAN1_H", "CAN1_L", "CAN2_H", "CAN2_L", "CAN3_H", "CAN3_L", "CAN4_H", "CAN4_L",
         "SPI_SCK", "SPI_MOSI", "SPI_MISO"]
STATS = {"searches": 0, "blocked": 0, "budget": 0}

# ---------------------------------------------------------------------------------- C core
_so = os.path.join(HERE, "route_core.so")
_src = os.path.join(HERE, "route_core.c")
if not os.path.exists(_so) or os.path.getmtime(_so) < os.path.getmtime(_src):
    subprocess.check_call(["gcc", "-O2", "-shared", "-fPIC", "-o", _so, _src, "-lm"])
_lib = ctypes.CDLL(_so)
_u8 = np.ctypeslib.ndpointer(np.uint8, flags="C_CONTIGUOUS")
_f32 = np.ctypeslib.ndpointer(np.float32, flags="C_CONTIGUOUS")
_i32 = np.ctypeslib.ndpointer(np.int32, flags="C_CONTIGUOUS")
_lib.route_astar.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int, _u8, _u8, _u8, _f32, _i32, ctypes.c_int,
                             _f32, _u8, ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float,
                             ctypes.c_long, _i32, ctypes.c_int]
_lib.route_astar.restype = ctypes.c_int
_out = np.zeros(3 * 60000, np.int32)


def astar(G, free, vfree, sources, target, heur, layers_ok=SIGNAL_LAYERS, lcost=None, max_exp=MAX_EXP):
    """free/target: (L, H, W) uint8. Returns [(layer, y, x), ...] from a source cell to the tree, or None."""
    STATS["searches"] += 1
    src = np.ascontiguousarray(np.array(sources, np.int32).reshape(-1, 3))
    n = _lib.route_astar(G.W, G.H, len(LAYERS), free, vfree, target, heur, src, len(src),
                         np.array(lcost or LAYER_COST, np.float32), np.array(layers_ok, np.uint8),
                         VIA_COST, TURN45, TURN90, HW, max_exp, _out, len(_out) // 3)
    if n < 0:
        STATS["blocked" if n == -1 else "budget"] += 1
        return None
    return [tuple(int(v) for v in _out[3 * i:3 * i + 3]) for i in range(n)]


# ---------------------------------------------------------------------------------- grid
class Grid:
    def __init__(self, g, pads_by_net):
        x0, y0, x1, y1 = g["bbox"]
        self.x0, self.y0 = x0, y0
        self.W = int(math.ceil((x1 - x0) / GRID)) + 1
        self.H = int(math.ceil((y1 - y0) / GRID)) + 1
        self.netid = {"": -1}
        for n in pads_by_net:
            self.nid(n)
        self.netmap = [np.zeros((self.H, self.W), np.int32) for _ in LAYERS]
        self.drillcnt = np.zeros((self.H, self.W), np.int16)
        self._edge(x0, y0, x1, y1)
        for p in g["pads"]:
            nid = self.netid[p["net"]] if p["net"] else -1
            for lyr in p["layers"]:
                if lyr in LAYERS:
                    self.poly(LAYERS.index(lyr), p["poly"], nid)
        for h in g["holes"]:
            self.drill(h["x"], h["y"], h["d"] / 2, +1)
            if h["npth"]:
                for li in range(len(LAYERS)):
                    self.circle(li, h["x"], h["y"], h["d"] / 2 + 0.15, -1)
        for ko in g["keepouts"]:
            for li in range(len(LAYERS)):
                self.poly(li, ko, -1)
        self.padmap = [nm.copy() for nm in self.netmap]   # copper that can never be ripped up
        self.edge_dist = distance_transform_edt(self.netmap[0] != -1) * GRID
        self._corridors(pads_by_net)

    def nid(self, name):
        if name not in self.netid:
            self.netid[name] = len(self.netid)
        return self.netid[name]

    def c(self, x, y):
        return (x - self.x0) / GRID, (y - self.y0) / GRID

    def mm(self, cx, cy):
        return round(self.x0 + cx * GRID, 4), round(self.y0 + cy * GRID, 4)

    def _mask(self, pts_cells, pad, draw_fn):
        xs = [p[0] for p in pts_cells]; ys = [p[1] for p in pts_cells]
        bx0 = max(0, int(math.floor(min(xs) - pad)) - 1); by0 = max(0, int(math.floor(min(ys) - pad)) - 1)
        bx1 = min(self.W, int(math.ceil(max(xs) + pad)) + 2); by1 = min(self.H, int(math.ceil(max(ys) + pad)) + 2)
        if bx1 <= bx0 or by1 <= by0:
            return None, None
        img = Image.new("L", (bx1 - bx0, by1 - by0), 0)
        draw_fn(ImageDraw.Draw(img), bx0, by0)
        return (slice(by0, by1), slice(bx0, bx1)), np.array(img) != 0

    def poly(self, li, polys, val):
        for pts in polys:
            cells = [self.c(x, y) for x, y in pts]
            sl, m = self._mask(cells, 0, lambda d, ox, oy: d.polygon([(x - ox, y - oy) for x, y in cells], fill=1, outline=1))
            if sl is not None:
                self.netmap[li][sl][m] = val

    def circle(self, li, x, y, r, val):
        cx, cy = self.c(x, y)
        rr = r / GRID
        sl, m = self._mask([(cx, cy)], rr, lambda d, ox, oy: d.ellipse([cx - rr - ox, cy - rr - oy, cx + rr - ox, cy + rr - oy], fill=1))
        if sl is not None:
            self.netmap[li][sl][m] = val

    def segment_mask(self, a, b, w):
        """Cells covered by a round-ended segment. Drawn as an exact polygon + end caps (PIL's wide
        lines are lopsided for even pixel widths, which would eat into the clearance on one side)."""
        (ax, ay), (bx, by) = self.c(*a), self.c(*b)
        rr = w / 2 / GRID
        ln = math.hypot(bx - ax, by - ay)

        def f(d, ox, oy):
            if ln > 1e-6:
                nx, ny = -(by - ay) / ln * rr, (bx - ax) / ln * rr
                d.polygon([(ax + nx - ox, ay + ny - oy), (bx + nx - ox, by + ny - oy),
                           (bx - nx - ox, by - ny - oy), (ax - nx - ox, ay - ny - oy)], fill=1, outline=1)
            for cx, cy in ((ax, ay), (bx, by)):
                d.ellipse([cx - rr - ox, cy - rr - oy, cx + rr - ox, cy + rr - oy], fill=1, outline=1)
        return self._mask([(ax, ay), (bx, by)], rr, f)

    def drill(self, x, y, r, delta):
        cx, cy = self.c(x, y)
        rr = r / GRID
        sl, m = self._mask([(cx, cy)], rr, lambda d, ox, oy: d.ellipse([cx - rr - ox, cy - rr - oy, cx + rr - ox, cy + rr - oy], fill=1))
        if sl is not None:
            self.drillcnt[sl][m] += delta

    def _edge(self, x0, y0, x1, y1):
        img = Image.new("L", (self.W, self.H), 1)
        a, b = self.c(x0 + 0.05, y0 + 0.05), self.c(x1 - 0.05, y1 - 0.05)
        ImageDraw.Draw(img).rounded_rectangle([a[0], a[1], b[0], b[1]], radius=3.0 / GRID, fill=0)
        m = np.array(img) != 0
        for nm in self.netmap:
            nm[m] = -1

    def _corridors(self, pads_by_net):
        """Escape lanes for fine-pitch pads: the pad centre line extended 0.9 mm past both ends.
        Usable by the pad's own net, treated as copper by every other net."""
        self.corridor = [np.zeros((self.H, self.W), np.int32) for _ in LAYERS]
        for net, pads in pads_by_net.items():
            nid = self.netid[net]
            for p in pads:
                xs = [x for pts in p["poly"] for x, _ in pts]; ys = [y for pts in p["poly"] for _, y in pts]
                wx, wy = max(xs) - min(xs), max(ys) - min(ys)
                if min(wx, wy) > 0.7 or abs(wx - wy) < 0.2:
                    continue
                if wy > wx:
                    a, b = (p["x"], min(ys) - 0.9), (p["x"], max(ys) + 0.9)
                else:
                    a, b = (min(xs) - 0.9, p["y"]), (max(xs) + 0.9, p["y"])
                (ax, ay), (bx, by) = self.c(*a), self.c(*b)
                sl, m = self._mask([(ax, ay), (bx, by)], 1, lambda d, ox, oy: d.line([ax - ox, ay - oy, bx - ox, by - oy], fill=1, width=1))
                for lyr in p["layers"]:
                    if lyr in LAYERS and sl is not None:
                        li = LAYERS.index(lyr)
                        cor = self.corridor[li][sl]
                        cor[m & (cor == 0) & (self.padmap[li][sl] == 0)] = nid

    def free_maps(self, nid, w, ghost=False):
        """Cells where a track centre (free) / via centre (vfree) of this net may sit.
        ghost=True ignores other nets' tracks (pads, keep-outs and lanes still block)."""
        need = w / 2 + CLR + GRID * 0.6
        vneed = VIA_D / 2 + CLR + GRID * 0.6 + 0.04
        free = np.zeros((len(LAYERS), self.H, self.W), np.uint8)
        vfree = np.ones((self.H, self.W), bool)
        for li in range(len(LAYERS)):
            nm = self.padmap[li] if ghost else self.netmap[li]
            cor = self.corridor[li]
            foreign = ((nm != 0) & (nm != nid)) | ((cor != 0) & (cor != nid) & (nm == 0))
            dist = distance_transform_edt(~foreign) * GRID
            f = (dist > need) & (self.edge_dist > w / 2 + EDGE_CLR)
            f |= (nm == nid)
            # Reserved lanes cannot override clearance to real foreign pads/tracks.
            free[li] = f
            vfree &= (dist > vneed) & (self.edge_dist > VIA_D / 2 + EDGE_CLR)
        if not ghost:
            vfree &= distance_transform_edt(self.drillcnt == 0) * GRID > VIA_DRILL / 2 + 0.25 + GRID
        return free, np.ascontiguousarray(vfree.astype(np.uint8))


def split_runs(path):
    """cell path -> [(layer, [corner points])], [via cells]"""
    runs, vias = [], []
    cur = [path[0]]
    for a in path[1:]:
        if a[0] != cur[-1][0]:
            runs.append(cur)
            vias.append((a[1], a[2]))
            cur = [a]
        else:
            cur.append(a)
    runs.append(cur)
    out = []
    for run in runs:
        pts = [run[0]]
        for i in range(1, len(run) - 1):
            p0, p1, p2 = run[i - 1], run[i], run[i + 1]
            if (p1[1] - p0[1], p1[2] - p0[2]) != (p2[1] - p1[1], p2[2] - p1[2]):
                pts.append(p1)
        if len(run) > 1:
            pts.append(run[-1])
        out.append((run[0][0], [(p[2], p[1]) for p in pts]))
    return out, vias


def point_in_pad(p, x, y):
    for pts in p["poly"]:
        inside = False
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % n]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
                inside = not inside
        if inside:
            return True
    return False


def pad_minor(p):
    xs = [x for pts in p["poly"] for x, _ in pts]; ys = [y for pts in p["poly"] for _, y in pts]
    return max(0.15, min(max(xs) - min(xs), max(ys) - min(ys)) * 0.9)


# ---------------------------------------------------------------------------------- router
class Router:
    def __init__(self, g, pads_by_net, order):
        self.pbn = pads_by_net
        self.order = order
        self.G = Grid(g, pads_by_net)
        self.geom = {}            # net -> {"tracks", "vias", "raster"}
        self.failed = {}          # net -> [(ref, pad)]
        self._cells = {}
        self.allow_plane = False

    def pad_cells(self, p, li):
        key = (p["ref"], p["pad"], round(p["x"], 3), round(p["y"], 3), li)
        if key not in self._cells:
            G = self.G
            nid = G.netid[p["net"]]
            cx, cy = G.c(p["x"], p["y"])
            cx, cy = int(round(cx)), int(round(cy))
            cells = []
            for dy in range(-14, 15):
                for dx in range(-14, 15):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < G.W and 0 <= y < G.H and G.padmap[li][y, x] == nid and point_in_pad(p, *G.mm(x, y)):
                        cells.append((li, y, x))
            self._cells[key] = cells
        return self._cells[key]

    def sources(self, p):
        return [c for lyr in p["layers"] if lyr in LAYERS for c in self.pad_cells(p, LAYERS.index(lyr))]

    def width(self, net):
        return min([WIDE.get(net, SIG_W)] + [max(0.2, pad_minor(p)) for p in self.pbn[net]])

    def _draw(self, net, li, a, b, w):
        sl, m = self.G.segment_mask(a, b, w)
        if sl is not None:
            nm = self.G.netmap[li][sl]
            m = m & (nm == 0)
            nm[m] = self.G.netid[net]
            self.geom[net]["raster"].append((li, sl, m))

    def commit(self, net, w, path, pad_from):
        G = self.G
        rec = self.geom.setdefault(net, {"tracks": [], "vias": [], "raster": []})
        runs, vcells = split_runs(path)
        for li, pts in runs:
            mmpts = [G.mm(x, y) for x, y in pts]
            if len(mmpts) >= 2:
                rec["tracks"].append({"net": net, "layer": LAYERS[li], "w": w, "pts": mmpts})
                for a, b in zip(mmpts, mmpts[1:]):
                    self._draw(net, li, a, b, w + 0.1)
        for cy, cx in vcells:
            self.add_via(net, *G.mm(cx, cy))
        li = path[0][0]
        if pad_from is not None and LAYERS[li] in pad_from["layers"]:
            a = (pad_from["x"], pad_from["y"]); b = G.mm(path[0][2], path[0][1])
            if math.hypot(a[0] - b[0], a[1] - b[1]) > 1e-3:
                ws = min(w, pad_minor(pad_from))
                rec["tracks"].append({"net": net, "layer": LAYERS[li], "w": ws, "pts": [a, b]})

    def add_via(self, net, x, y):
        rec = self.geom.setdefault(net, {"tracks": [], "vias": [], "raster": []})
        rec["vias"].append({"net": net, "x": x, "y": y})
        self.G.drill(x, y, VIA_DRILL / 2, +1)
        for li in range(len(LAYERS)):
            self._draw(net, li, (x, y), (x, y), VIA_D + 0.1)

    def rip(self, net):
        rec = self.geom.pop(net, None)
        if not rec:
            return
        for li, sl, m in rec["raster"]:
            self.G.netmap[li][sl][m] = 0
        for v in rec["vias"]:
            self.G.drill(v["x"], v["y"], VIA_DRILL / 2, -1)

    def _tree(self, pad):
        G = self.G
        tree = np.zeros((len(LAYERS), G.H, G.W), np.uint8)
        for li, y, x in self.sources(pad):
            tree[li, y, x] = 1
        return tree

    def route_net(self, net):
        G = self.G
        nid = G.netid[net]
        pads = self.pbn[net]
        w = self.width(net)
        xs = [p["x"] for p in pads]; ys = [p["y"] for p in pads]
        long_net = (max(xs) - min(xs)) + (max(ys) - min(ys)) > 35 and net not in WIDE
        lcost = LONG_COST if long_net else LAYER_COST
        cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
        pads = sorted(pads, key=lambda p: (p["x"] - cx) ** 2 + (p["y"] - cy) ** 2)
        tree = self._tree(pads[0])
        tree_pads = [pads[0]]
        todo, failed = pads[1:], []
        free, vfree = G.free_maps(nid, w)
        while todo:
            todo.sort(key=lambda p: min((p["x"] - q["x"]) ** 2 + (p["y"] - q["y"]) ** 2 for q in tree_pads))
            p = todo.pop(0)
            srcs = self.sources(p)
            if any(tree[li, y, x] for li, y, x in srcs):
                tree_pads.append(p)
                continue
            heur = distance_transform_edt(tree.max(axis=0) == 0).astype(np.float32)
            path, wc, dirty = None, w, False
            for wc in sorted({w, min(w, 0.5), min(w, 0.25)}, reverse=True):
                if wc != w:
                    free, vfree = G.free_maps(nid, wc)
                    dirty = True
                path = astar(G, free, vfree, srcs, tree, heur, lcost=lcost)
                if path is None and self.allow_plane:
                    path = astar(G, free, vfree, srcs, tree, heur, layers_ok=(1, 1, 1, 1), lcost=lcost)
                if path is not None:
                    break
            if path is None:
                failed.append((p["ref"], p["pad"]))
                if dirty:
                    free, vfree = G.free_maps(nid, w)
                continue
            self.commit(net, wc, path, p)
            for li, y, x in path:
                tree[li, y, x] = 1
            tree_pads.append(p)
            free, vfree = G.free_maps(nid, w)
        if failed:
            self.failed[net] = failed
        else:
            self.failed.pop(net, None)
        return failed

    def ghost_blockers(self, net):
        """Nets whose tracks sit on this net's ideal (pads-only) path."""
        G = self.G
        nid = G.netid[net]
        w = self.width(net)
        free, vfree = G.free_maps(nid, min(w, 0.25), ghost=True)
        pads = self.pbn[net]
        blockers = {}
        tree = self._tree(pads[0])
        r = int(math.ceil((w / 2 + CLR + 0.3) / GRID))
        for p in pads[1:]:
            heur = distance_transform_edt(tree.max(axis=0) == 0).astype(np.float32)
            path = astar(G, free, vfree, self.sources(p), tree, heur)
            if path is None:
                continue
            for li, y, x in path:
                tree[li, y, x] = 1
            for li, y, x in path[::2]:
                win = G.netmap[li][max(0, y - r):y + r + 1, max(0, x - r):x + r + 1]
                pw = G.padmap[li][max(0, y - r):y + r + 1, max(0, x - r):x + r + 1]
                for i in np.unique(win[(win > 0) & (win != nid) & (pw != win)]):
                    blockers[int(i)] = blockers.get(int(i), 0) + 1
        inv = {v: k for k, v in G.netid.items()}
        names = [inv[i] for i, _ in sorted(blockers.items(), key=lambda kv: -kv[1]) if inv.get(i) and inv[i] != "GND"]
        return names

    def nfail(self):
        return sum(len(v) for v in self.failed.values())

    def snapshot(self):
        return ([nm.copy() for nm in self.G.netmap], self.G.drillcnt.copy(), copy.deepcopy(self.geom), copy.deepcopy(self.failed))

    def restore(self, s):
        nms, dc, geom, failed = s
        self.G.netmap = [nm.copy() for nm in nms]
        self.G.drillcnt = dc.copy()
        self.geom = copy.deepcopy(geom)
        self.failed = copy.deepcopy(failed)

    def gnd_stubs(self):
        """Short stub + via into the In1 plane for every SMD GND pad."""
        G = self.G
        gid = G.netid["GND"]
        w = WIDE["GND"]
        bad = []
        zero = np.zeros((G.H, G.W), np.float32)
        plated = {(q['ref'],q['pad']) for q in self.pbn['GND'] if not q['smd']}
        for p in self.pbn["GND"]:
            if (p['ref'],p['pad']) in plated: continue  # exposed pad already has plane vias
            if not p["smd"] or p["layers"][0] not in LAYERS:
                continue
            li = LAYERS.index(p["layers"][0])
            srcs = self.pad_cells(p, li)
            path = None
            for wc in (min(w, max(0.2, pad_minor(p))), 0.25):
                free, vfree = G.free_maps(gid, wc)
                tgt = np.zeros((len(LAYERS), G.H, G.W), np.uint8)
                tgt[li] = vfree & (G.netmap[li] == 0)
                ok = [0, 0, 0, 0]; ok[li] = 1
                path = astar(G, free, vfree, srcs, tgt, zero, layers_ok=tuple(ok), max_exp=3_000_000) if srcs else None
                if path is not None:
                    break
            if path is None:
                bad.append(("GND", p["ref"], p["pad"]))
                continue
            self.commit("GND", wc, path, p)
            self.add_via("GND", *G.mm(path[-1][2], path[-1][1]))
        return bad

    def stitch(self, pitch=4.0):
        """GND stitching vias on a regular grid wherever one fits, tying the pours to the plane."""
        G = self.G
        gid = G.netid["GND"]
        step = int(pitch / GRID)
        n = 0
        _, vfree = G.free_maps(gid, 0.3)
        empty = np.logical_and.reduce([(nm == 0) for nm in G.netmap])
        for y in range(step // 2, G.H, step):
            for x in range(step // 2, G.W, step):
                if vfree[y, x] and empty[max(0, y - 5):y + 6, max(0, x - 5):x + 6].all():
                    self.add_via("GND", *G.mm(x, y))
                    n += 1
        return n

    def repair(self, t0, rounds, k):
        stale = 0
        for rnd in range(rounds):
            if not self.failed:
                return
            improved = False
            for net in list(self.failed):
                if net not in self.failed:
                    continue
                before = self.nfail()
                snap = self.snapshot()
                cand = self.ghost_blockers(net)
                blockers = cand[:k] if rnd % 2 == 0 else random.sample(cand, min(k, len(cand)))
                for b in blockers:
                    self.rip(b)
                    self.failed.pop(b, None)
                self.rip(net)
                self.route_net(net)
                for b in sorted(blockers, key=lambda n: self.order.index(n) if n in self.order else 999):
                    self.route_net(b)
                after = self.nfail()
                if after > before or (after == before and net in self.failed):
                    self.restore(snap)
                else:
                    improved = improved or after < before
                    print(f"  repair {net}: ripped {len(blockers)} nets -> {after} open", flush=True)
            print(f"round {rnd + 1}: {self.nfail()} open  ({time.time() - t0:.0f}s)", flush=True)
            stale = 0 if improved else stale + 1
            if stale >= 3:
                return

    def run(self, t0):
        gnd_bad = []
        if GND_FIRST:
            gnd_bad = self.gnd_stubs()
            print(f"GND stubs first: {len(gnd_bad)} failed  ({time.time() - t0:.0f}s)", flush=True)
        for net in self.order:
            self.route_net(net)
        print(f"initial: {self.nfail()} open connections in {len(self.failed)} nets  ({time.time() - t0:.0f}s) {STATS}", flush=True)
        self.repair(t0, rounds=12, k=5)
        if self.failed:
            self.allow_plane = True      # last resort: borrow the In1 plane
            for net in list(self.failed):
                self.rip(net)
                self.route_net(net)
            print(f"plane fallback: {self.nfail()} open  ({time.time() - t0:.0f}s)", flush=True)
            self.repair(t0, rounds=4, k=8)
        if not GND_FIRST:
            gnd_bad = self.gnd_stubs()
        print(f"GND stubs: {len(gnd_bad)} failed; stitching vias: {self.stitch()}", flush=True)
        tracks = [t for r in self.geom.values() for t in r["tracks"]]
        vias = [v for r in self.geom.values() for v in r["vias"]]
        failed = [(n, *rp) for n, lst in self.failed.items() for rp in lst] + gnd_bad
        return tracks, vias, failed


def seg_dist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    u = 0 if L2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - ax - u * dx, py - ay - u * dy)


def via_clearance_check(tracks, vias):
    """Exact via-to-foreign-track gaps on the outer and In2 layers (vias span every layer)."""
    worst = []
    for v in vias:
        for t in tracks:
            if t["net"] == v["net"]:
                continue
            for a, b in zip(t["pts"], t["pts"][1:]):
                if min(a[0], b[0]) - 1.2 > v["x"] or max(a[0], b[0]) + 1.2 < v["x"] or \
                   min(a[1], b[1]) - 1.2 > v["y"] or max(a[1], b[1]) + 1.2 < v["y"]:
                    continue
                gap = seg_dist((v["x"], v["y"]), a, b) - VIA_D / 2 - t["w"] / 2
                if gap < 0.15:
                    worst.append((round(gap, 3), v["net"], t["net"], round(v["x"], 2), round(v["y"], 2)))
    return sorted(worst)


def main(src, dst):
    t0 = time.time()
    random.seed(int(os.environ.get("ROUTE_SEED", "1")))
    g = json.load(open(src))
    pads_by_net = {}
    for p in g["pads"]:
        if p["net"]:
            pads_by_net.setdefault(p["net"], []).append(p)
    nets = [n for n in pads_by_net if n != "GND" and len(pads_by_net[n]) > 1]

    def span(n):
        xs = [p["x"] for p in pads_by_net[n]]; ys = [p["y"] for p in pads_by_net[n]]
        return (max(xs) - min(xs)) + (max(ys) - min(ys))
    order = [n for n in FIRST if n in nets] + sorted([n for n in nets if n not in FIRST], key=span)
    tracks, vias, failed = Router(g, pads_by_net, order).run(t0)
    json.dump({"geometry_sha256": hashlib.sha256(open(src,"rb").read()).hexdigest(), "tracks": tracks, "vias": vias, "failed": failed}, open(dst, "w"))
    inner = sum(1 for t in tracks if t["layer"] == "In1")
    print(f"done in {time.time() - t0:.0f}s: {len(tracks)} tracks, {len(vias)} vias, {len(failed)} failed, "
          f"{inner} tracks on the In1 plane {STATS}")
    bad = via_clearance_check(tracks, vias)
    print(f"via clearance check: {len(bad)} below 0.15 mm", bad[:5])
    for f in failed:
        print("FAILED", f)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
