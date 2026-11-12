"""Grid A* autorouter with rip-up-and-reroute, for the QuadCAN-C5 board.

Reads geom.json (export_geom.py) and writes routes.json (apply_routes.py adds it to the board).
Routing layers are F.Cu, In2.Cu and B.Cu. In1.Cu is a solid GND plane: every SMD GND pad gets a
short stub to a via, and through-hole GND pads reach the plane directly.

Algorithm
  1. Route every net sequentially (critical/wide nets first, then short-to-long). Each connection
     is a greedy A* search on a 0.1 mm grid with clearance-inflated obstacles. Fine-pitch pads get
     reserved escape lanes.
  2. Repair loop: for every connection that failed, route it again ignoring other signal tracks
     (pads still block) to find its ideal path. Rip up the nets in the way, route the failed net,
     then re-route the ripped nets. Keep the result only if the total failure count does not grow.

usage: python3 route.py geom.json routes.json
"""
import copy
import heapq
import json
import math
import os
import random
import sys
import time
from array import array

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_erosion, distance_transform_edt

GRID = 0.1
HW = float(os.environ.get("ROUTE_HW", "2.5"))  # heuristic weight (greedy A*)
LAYERS = ["F", "In2", "B", "In1"]     # In1 = GND plane: last-resort only
CLR = 0.17            # copper clearance enforced (board netclass is 0.15 mm)
EDGE_CLR = 0.35
VIA_D, VIA_DRILL = 0.6, 0.3
VIA_COST = 12.0
LAYER_COST = [1.0, 1.15, 1.05, 4.0]
SIG_W = 0.2
WIDE = {"VIN_RAW": 1.0, "VIN_F": 1.0, "VIN": 0.8, "BUCK_SW": 1.0, "+5V": 0.6, "+5V_SYS": 0.5,
        "SCAP": 0.5, "+3V3": 0.4, "VBUS": 0.5, "GPS_3V3": 0.4, "GND": 0.4,
        "CAN1_H": 0.3, "CAN1_L": 0.3, "CAN2_H": 0.3, "CAN2_L": 0.3,
        "CAN3_H": 0.3, "CAN3_L": 0.3, "CAN4_H": 0.3, "CAN4_L": 0.3, "GPS_RF": 0.3}
FIRST = ["BUCK_SW", "BUCK_BOOT", "BUCK_FB", "BUCK_COMP", "BUCK_CZ", "BUCK_EN", "BUCK_RT",
         "VIN_RAW", "VIN_F", "VIN", "+5V", "+5V_SYS", "SCAP", "VBUS", "USB_DP", "USB_DN",
         "GPS_RF", "GPS_BIAS", "GPS_VCC_RF", "CLK40", "RTC_XI", "RTC_XO", "SPI_SCK", "SPI_MOSI", "SPI_MISO"]
STATS = {"limit": 0, "exhausted": 0}


# ======================================================================================= grid
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
                    self.circle(li, h["x"], h["y"], h["d"] / 2, -1)
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
        return self.x0 + cx * GRID, self.y0 + cy * GRID

    # -- rasterising on a local patch (fast)
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

    def circle(self, li, x, y, r, val, target=None):
        cx, cy = self.c(x, y)
        rr = r / GRID
        sl, m = self._mask([(cx, cy)], rr, lambda d, ox, oy: d.ellipse([cx - rr - ox, cy - rr - oy, cx + rr - ox, cy + rr - oy], fill=1))
        if sl is None:
            return
        tgt = self.netmap[li] if target is None else target
        tgt[sl][m] = val

    def segment_mask(self, a, b, w):
        (ax, ay), (bx, by) = self.c(*a), self.c(*b)
        rr = w / 2 / GRID

        def f(d, ox, oy):
            d.line([ax - ox, ay - oy, bx - ox, by - oy], fill=1, width=max(1, int(round(w / GRID))))
            for cx, cy in ((ax, ay), (bx, by)):
                d.ellipse([cx - rr - ox, cy - rr - oy, cx + rr - ox, cy + rr - oy], fill=1)
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
        The lane is usable by its own net and treated as copper by everyone else."""
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
                        cor[m & (self.padmap[li][sl] == nid)] = nid

    # -- free space for one net
    def free_maps(self, nid, w, ghost=False):
        """ghost=True: only pads/keep-outs/lanes block (used to find who is in the way)."""
        need = w / 2 + CLR + GRID * 0.6
        vneed = VIA_D / 2 + CLR + GRID * 0.6 + 0.04
        free, vfree = [], np.ones((self.H, self.W), bool)
        for li in range(len(LAYERS)):
            nm = self.padmap[li] if ghost else self.netmap[li]
            cor = self.corridor[li]
            foreign = ((nm != 0) & (nm != nid)) | ((cor != 0) & (cor != nid) & (nm == 0))
            dist = distance_transform_edt(~foreign) * GRID
            f = (dist > need) & (self.edge_dist > w / 2 + EDGE_CLR)
            f |= (nm == nid)
            # own escape lane: may hug foreign *pads*, but keeps full clearance to foreign tracks
            if (cor == nid).any():
                trk = foreign & (self.padmap[li] == 0) & (cor == 0)
                lane_ok = distance_transform_edt(~trk) * GRID > need
                f |= (cor == nid) & ~((nm != 0) & (nm != nid)) & lane_ok
            free.append(f)
            vfree &= (dist > vneed) & (self.edge_dist > VIA_D / 2 + EDGE_CLR)
        if not ghost:
            vfree &= distance_transform_edt(self.drillcnt == 0) * GRID > VIA_DRILL / 2 + 0.25 + GRID
        return free, vfree


# ======================================================================================= search
def astar(G, free, vfree, sources, target_mask, heur, max_exp, layers_ok=(0, 1, 2), lcost=None):
    W, H = G.W, G.H
    N = W * H
    nL = len(LAYERS)
    fr = [bytearray(free[li].astype(np.uint8).tobytes()) if li in layers_ok else bytearray(N) for li in range(nL)]
    vf = bytearray(vfree.astype(np.uint8).tobytes())
    tg = [bytearray(target_mask[li].astype(np.uint8).tobytes()) for li in range(nL)]
    hm = heur.ravel().tolist() if heur is not None else None
    gsc = array("f", [1e30]) * (N * nL)
    prev = array("i", [-1]) * (N * nL)
    lc_all = lcost or LAYER_COST
    pq = []
    for li, cy, cx in sources:
        s = li * N + cy * W + cx
        gsc[s] = 0.0
        heapq.heappush(pq, (0.0, s))
    dirs = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
            (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
    exp = 0
    while pq:
        f, s = heapq.heappop(pq)
        li, r = divmod(s, N)
        g0 = gsc[s]
        if f > g0 + (HW * hm[r] if hm else 0.0) + 1e-3:
            continue                       # stale entry
        if tg[li][r]:
            path = []
            while s != -1:
                path.append(s)
                s = prev[s]
            path.reverse()
            return [(p // N, (p % N) // W, (p % N) % W) for p in path]
        exp += 1
        if exp > max_exp:
            STATS["limit"] += 1
            return None
        cy, cx = divmod(r, W)
        lc = lc_all[li]
        frl = fr[li]
        for dx, dy, cst in dirs:
            nx, ny = cx + dx, cy + dy
            if nx < 0 or ny < 0 or nx >= W or ny >= H:
                continue
            nr = ny * W + nx
            if not frl[nr]:
                continue
            if dx and dy and not (frl[cy * W + nx] and frl[ny * W + cx]):
                continue
            ns = li * N + nr
            ng = g0 + cst * lc
            if ng < gsc[ns]:
                gsc[ns] = ng
                prev[ns] = s
                heapq.heappush(pq, (ng + (HW * hm[nr] if hm else 0.0), ns))
        if vf[r]:
            for l2 in layers_ok:
                if l2 == li or not fr[l2][r]:
                    continue
                ns = l2 * N + r
                ng = g0 + VIA_COST
                if ng < gsc[ns]:
                    gsc[ns] = ng
                    prev[ns] = s
                    heapq.heappush(pq, (ng + (HW * hm[r] if hm else 0.0), ns))
    STATS["exhausted"] += 1
    return None


def los_smooth(pts, freel):
    if len(pts) <= 2:
        return pts
    H, W = freel.shape

    def clear(a, b):
        n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2) + 1
        for k in range(n + 1):
            x = a[0] + (b[0] - a[0]) * k / n
            y = a[1] + (b[1] - a[1]) * k / n
            for xx, yy in ((math.floor(x), math.floor(y)), (math.ceil(x), math.ceil(y)),
                           (math.floor(x), math.ceil(y)), (math.ceil(x), math.floor(y))):
                if not (0 <= xx < W and 0 <= yy < H) or not freel[yy, xx]:
                    return False
        return True
    out = [pts[0]]
    i = 0
    while i < len(pts) - 1:
        j = len(pts) - 1
        while j > i + 1 and not clear(pts[i], pts[j]):
            j -= 1
        out.append(pts[j])
        i = j
    return out


def split_runs(path):
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
            p0, p1, p2 = pts[-1], run[i], run[i + 1]
            d1 = (p1[1] - p0[1], p1[2] - p0[2]); d2 = (p2[1] - p1[1], p2[2] - p1[2])
            if d1[0] * d2[1] - d1[1] * d2[0] != 0 or (d1[0] * d2[0] + d1[1] * d2[1]) < 0:
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


# ======================================================================================= router
class Router:
    def __init__(self, g, pads_by_net, order):
        self.g = g
        self.pbn = pads_by_net
        self.order = order
        self.G = Grid(g, pads_by_net)
        self.geom = {}            # net -> {"tracks": [...], "vias": [...], "raster": [(li, sl, mask)]}
        self.failed = {}          # net -> [(ref, pad)]
        self._cells = {}
        self.allow_plane = False

    # -- pad helpers
    def pad_cells(self, p, li):
        key = (p["ref"], p["pad"], round(p["x"], 3), round(p["y"], 3), li)
        if key not in self._cells:
            G = self.G
            nid = G.netid[p["net"]]
            cx, cy = G.c(p["x"], p["y"])
            cx, cy = int(round(cx)), int(round(cy))
            cells = []
            for dy in range(-12, 13):
                for dx in range(-12, 13):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < G.W and 0 <= y < G.H and G.padmap[li][y, x] == nid and point_in_pad(p, *G.mm(x, y)):
                        cells.append((li, y, x))
            self._cells[key] = cells
        return self._cells[key]

    def width(self, net):
        return min([WIDE.get(net, SIG_W)] + [max(0.2, pad_minor(p)) for p in self.pbn[net]])

    # -- commit / rip-up
    def _draw(self, net, li, a, b, w):
        sl, m = self.G.segment_mask(a, b, w)
        if sl is not None:
            nm = self.G.netmap[li][sl]
            m = m & (nm == 0)
            nm[m] = self.G.netid[net]
            self.geom[net]["raster"].append((li, sl, m))

    def commit(self, net, w, path, pad_from, free):
        G = self.G
        nid = G.netid[net]
        rec = self.geom.setdefault(net, {"tracks": [], "vias": [], "raster": []})
        runs, vcells = split_runs(path)
        runs = [(li, los_smooth(pts, binary_erosion(free[li], iterations=2))) for li, pts in runs]
        for li, pts in runs:
            mmpts = [G.mm(x, y) for x, y in pts]
            if len(mmpts) >= 2:
                rec["tracks"].append({"net": net, "layer": LAYERS[li], "w": w, "pts": mmpts})
                for a, b in zip(mmpts, mmpts[1:]):
                    self._draw(net, li, a, b, w + 0.1)
        for cy, cx in vcells:
            self.add_via(net, *G.mm(cx, cy))
        li = path[0][0]
        if LAYERS[li] in pad_from["layers"]:
            a = (pad_from["x"], pad_from["y"]); b = G.mm(path[0][2], path[0][1])
            if math.hypot(a[0] - b[0], a[1] - b[1]) > 1e-3:
                ws = min(w, pad_minor(pad_from))
                rec["tracks"].append({"net": net, "layer": LAYERS[li], "w": ws, "pts": [a, b]})
                self._draw(net, li, a, b, ws + 0.1)

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

    # -- routing one net
    def route_net(self, net):
        G = self.G
        nid = G.netid[net]
        pads = self.pbn[net]
        w = self.width(net)
        xs = [p["x"] for p in pads]; ys = [p["y"] for p in pads]
        long_net = (max(xs) - min(xs)) + (max(ys) - min(ys)) > 35 and net not in WIDE
        lcost = [1.6, 1.0, 1.3, 4.0] if long_net else None
        free, vfree = G.free_maps(nid, w)
        cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
        pads = sorted(pads, key=lambda p: (p["x"] - cx) ** 2 + (p["y"] - cy) ** 2)
        tree = [np.zeros((G.H, G.W), bool) for _ in LAYERS]
        tree_pads = [pads[0]]
        for lyr in pads[0]["layers"]:
            if lyr in LAYERS:
                for li, y, x in self.pad_cells(pads[0], LAYERS.index(lyr)):
                    tree[li][y, x] = True
        todo, failed = pads[1:], []
        while todo:
            todo.sort(key=lambda p: min((p["x"] - q["x"]) ** 2 + (p["y"] - q["y"]) ** 2 for q in tree_pads))
            p = todo.pop(0)
            srcs = [c for lyr in p["layers"] if lyr in LAYERS for c in self.pad_cells(p, LAYERS.index(lyr))]
            if any(tree[li][y, x] for li, y, x in srcs):
                tree_pads.append(p)
                continue
            anyt = np.logical_or.reduce(tree)
            heur = distance_transform_edt(~anyt)
            path, wc = None, w
            for wc in sorted({w, min(w, 0.5), min(w, 0.25)}, reverse=True):
                if wc != w:
                    free, vfree = G.free_maps(nid, wc)
                path = astar(G, free, vfree, srcs, tree, heur, max_exp=600000, lcost=lcost)
                if path is not None:
                    break
            if path is None and self.allow_plane:
                free, vfree = G.free_maps(nid, min(w, 0.25))
                wc = min(w, 0.25)
                path = astar(G, free, vfree, srcs, tree, heur, max_exp=600000, layers_ok=(0, 1, 2, 3), lcost=lcost)
            if path is None:
                failed.append((p["ref"], p["pad"]))
                free, vfree = G.free_maps(nid, w)
                continue
            self.commit(net, wc, path, p, free)
            for li, y, x in path:
                tree[li][y, x] = True
            tree_pads.append(p)
            free, vfree = G.free_maps(nid, w)
        if failed:
            self.failed[net] = failed
        else:
            self.failed.pop(net, None)
        return failed

    def ghost_blockers(self, net):
        """Route the net ignoring other signal tracks; return the nets whose copper is in the way."""
        G = self.G
        nid = G.netid[net]
        w = self.width(net)
        free, vfree = G.free_maps(nid, w, ghost=True)
        pads = self.pbn[net]
        blockers = set()
        tree = [np.zeros((G.H, G.W), bool) for _ in LAYERS]
        for lyr in pads[0]["layers"]:
            if lyr in LAYERS:
                for li, y, x in self.pad_cells(pads[0], LAYERS.index(lyr)):
                    tree[li][y, x] = True
        for p in pads[1:]:
            srcs = [c for lyr in p["layers"] if lyr in LAYERS for c in self.pad_cells(p, LAYERS.index(lyr))]
            heur = distance_transform_edt(~np.logical_or.reduce(tree))
            path = astar(G, free, vfree, srcs, tree, heur, max_exp=600000)
            if path is None:
                continue
            for li, y, x in path:
                tree[li][y, x] = True
            r = int(math.ceil((w / 2 + CLR + 0.5) / GRID))
            for li, y, x in path[::3]:
                win = G.netmap[li][max(0, y - r):y + r + 1, max(0, x - r):x + r + 1]
                pw = G.padmap[li][max(0, y - r):y + r + 1, max(0, x - r):x + r + 1]
                ids = np.unique(win[(win > 0) & (win != nid) & (pw != win)])
                blockers.update(int(i) for i in ids)
        inv = {v: k for k, v in G.netid.items()}
        return [inv[i] for i in blockers if inv.get(i) and inv[i] != "GND"]

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

    # -- GND stubs
    def gnd_stubs(self):
        G = self.G
        gid = G.netid["GND"]
        w = WIDE["GND"]
        free, vfree = G.free_maps(gid, w)
        bad = []
        for p in self.pbn["GND"]:
            if not p["smd"] or p["layers"][0] not in LAYERS:
                continue
            li = LAYERS.index(p["layers"][0])
            srcs = self.pad_cells(p, li)
            tgt = [np.zeros((G.H, G.W), bool) for _ in LAYERS]
            tgt[li] = vfree & (G.netmap[li] == 0)
            path = astar(G, free, vfree, srcs, tgt, None, max_exp=40000, layers_ok=(li,)) if srcs else None
            if path is None:
                bad.append(("GND", p["ref"], p["pad"]))
                continue
            self.commit("GND", min(w, pad_minor(p)), path, p, free)
            vx, vy = G.mm(path[-1][2], path[-1][1])
            self.add_via("GND", vx, vy)
            free, vfree = G.free_maps(gid, w)
        return bad

    def stitch(self, pitch=3.0):
        """GND stitching vias on a grid wherever a via fits clear of everything, so every
        F.Cu / B.Cu / In2.Cu GND pour fragment is tied to the In1 plane."""
        G = self.G
        gid = G.netid["GND"]
        _, vfree = G.free_maps(gid, 0.3)
        empty = np.logical_and.reduce([(nm == 0) | (nm == gid) for nm in G.netmap])
        step = int(pitch / GRID)
        n = 0
        for y in range(step // 2, G.H, step):
            for x in range(step // 2, G.W, step):
                # search a small neighbourhood for a legal spot
                done = False
                for dy in range(-6, 7, 2):
                    for dx in range(-6, 7, 2):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < G.H and 0 <= xx < G.W and vfree[yy, xx] and empty[yy, xx]:
                            self.add_via("GND", *G.mm(xx, yy))
                            n += 1
                            done = True
                            break
                    if done:
                        break
        return n

    def run(self, t0, repair_rounds=8):
        for net in self.order:
            self.route_net(net)
        print(f"initial: {self.nfail()} failed connections in {len(self.failed)} nets  ({time.time() - t0:.0f}s)", flush=True)
        stale = 0
        for rnd in range(repair_rounds):
            if not self.failed:
                break
            improved = False
            for net in list(self.failed):
                if net not in self.failed:
                    continue
                before = self.nfail()
                snap = self.snapshot()
                blockers = self.ghost_blockers(net)
                random.shuffle(blockers)
                blockers = blockers[:6]
                for b in blockers:
                    self.rip(b)
                    self.failed.pop(b, None)
                self.rip(net)
                self.route_net(net)
                for b in blockers:
                    self.route_net(b)
                after = self.nfail()
                if after > before or (after == before and net in self.failed):
                    self.restore(snap)
                else:
                    improved = improved or after < before
                    print(f"  repair {net}: ripped {blockers} -> {after} failed", flush=True)
            print(f"round {rnd + 1}: {self.nfail()} failed  ({time.time() - t0:.0f}s)", flush=True)
            stale = 0 if improved else stale + 1
            if stale >= 2:
                break
        if self.failed:
            # last resort: let the remaining connections borrow the In1 ground plane
            self.allow_plane = True
            for net in list(self.failed):
                self.rip(net)
                self.route_net(net)
            print(f"plane fallback: {self.nfail()} failed  ({time.time() - t0:.0f}s)", flush=True)
        gnd_bad = self.gnd_stubs()
        n_stitch = self.stitch()
        print(f"stitching vias: {n_stitch}", flush=True)
        tracks = [t for r in self.geom.values() for t in r["tracks"]]
        vias = [v for r in self.geom.values() for v in r["vias"]]
        failed = [(n, *rp) for n, lst in self.failed.items() for rp in lst] + gnd_bad
        return tracks, vias, failed


def main(src, dst):
    t0 = time.time()
    random.seed(1)
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
    json.dump({"tracks": tracks, "vias": vias, "failed": failed}, open(dst, "w"))
    print(f"done in {time.time() - t0:.0f}s: {len(tracks)} tracks, {len(vias)} vias, {len(failed)} failed {STATS}")
    for f in failed:
        print("FAILED", f)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
