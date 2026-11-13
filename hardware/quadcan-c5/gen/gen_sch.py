"""Generate kicad/<project>.kicad_sch from design.PARTS.

Parts are auto-arranged block by block; every pin gets a short wire stub that ends in
a net label, so connectivity is exact and each block reads on its own.
"""
import copy
import math
import os
import uuid

from kiutils.items.common import Effects, Font, Justify, PageSettings, Position, Property, TitleBlock
from kiutils.items.schitems import (Connection, HierarchicalSheetInstance, LocalLabel, SchematicSymbol,
                                    SymbolProjectInstance, SymbolProjectPath, Text, NoConnect)
from kiutils.schematic import Schematic
from kiutils.symbol import SymbolLib

import design
from design import PARTS, PROJECT, PWR_FLAGS, BLOCK_TITLES

HERE = os.path.dirname(os.path.abspath(__file__))
KI = os.path.normpath(os.path.join(HERE, "..", "kicad"))
SYSLIB = "/usr/share/kicad/symbols"
G = 2.54
STUB = 2 * G
LABEL_ROOM = 24.0   # mm reserved for a net label beside a pin
_libs = {}


def snap(v):
    return round(v / G) * G


def _lib(lib):
    if lib not in _libs:
        path = os.path.join(KI, "QuadCAN.kicad_sym") if lib == "QuadCAN" else os.path.join(SYSLIB, lib + ".kicad_sym")
        _libs[lib] = SymbolLib.from_file(path)
    return _libs[lib]


def lib_symbol(lib_id):
    """Return a flattened (no 'extends') copy of a library symbol."""
    lib, name = lib_id.split(":")
    syms = {s.entryName: s for s in _lib(lib).symbols}
    s = copy.deepcopy(syms[name])
    if s.extends:
        base = copy.deepcopy(syms[s.extends])
        while base.extends:
            base = copy.deepcopy(syms[base.extends])
        base.entryName = name
        for u in base.units:
            u.entryName = name
        base.properties = s.properties
        base.extends = None
        s = base
    s.libraryNickname = lib
    if lib_id == "Interface_CAN_LIN:MCP2517FD-xSL":
        # Datasheet SDO is high-impedance when CS is high; KiCad calls it Output.
        for pin in pins_of(s):
            if pin.number == '12': pin.electricalType = 'tri_state'
    return s


def eff(size=1.27, hide=False, justify=None):
    e = Effects(font=Font(width=size, height=size), hide=hide)
    if justify:
        e.justify = Justify(horizontally=justify)
    return e


def pins_of(sym):
    for u in sym.units:
        for p in u.pins:
            yield p


def extent(sym):
    xs = [p.position.X for p in pins_of(sym)] or [0]
    ys = [p.position.Y for p in pins_of(sym)] or [0]
    side = any(abs(p.position.angle or 0) in (0, 180) for p in pins_of(sym))
    vert = any(abs(p.position.angle or 0) in (90, 270) for p in pins_of(sym))
    w = (max(xs) - min(xs)) + 2 * LABEL_ROOM if side else 30
    h = (max(ys) - min(ys)) + (2 * STUB + 8 if vert else 8)
    return max(w, 30), max(h, 16), (min(xs), max(xs), min(ys), max(ys))


def main():
    sch = Schematic.create_new()
    sch.version = 20230121
    sch.generator = "eeschema"
    sch.uuid = str(uuid.uuid4())
    sch.paper = PageSettings(paperSize="A0")
    sch.titleBlock = TitleBlock(title=design.TITLE, date="2026-11-13", revision=design.REV,
                                comments={1: "Generated from gen/design.py - edit that, then run gen/build.sh",
                                          2: "All transceivers boot in STANDBY; TX needs firmware + a TX_EN jumper"})
    root = "/" + sch.uuid
    seen, points = set(), {}

    def place(p, x, y):
        sym = lib_symbol(p["lib_id"])
        if p["lib_id"] not in seen:
            seen.add(p["lib_id"])
            sch.libSymbols.append(copy.deepcopy(sym))
        s = SchematicSymbol()
        s.libraryNickname, s.entryName = p["lib_id"].split(":")
        s.position = Position(X=x, Y=y, angle=0)
        s.unit = 1
        s.inBom = not p["ref"].startswith("#")
        s.onBoard = not p["ref"].startswith("#")
        s.dnp = p.get("dnp", False)
        s.uuid = str(uuid.uuid4())
        _, _, (x0, x1, y0, y1) = extent(sym)
        props = [("Reference", p["ref"], (x + x1 + 1.27, y - y1 - 1.27), p["ref"].startswith("#")),
                 ("Value", p["value"], (x + x1 + 1.27, y - y0 + 2.54), False),
                 ("Footprint", p.get("fp", ""), (x, y), True),
                 ("Datasheet", "", (x, y), True)]
        if p.get("mpn"):
            props.append(("MPN", p["mpn"], (x, y), True))
        for i, (k, v, (px, py), hide) in enumerate(props):
            s.properties.append(Property(key=k, value=v, id=i, position=Position(X=px, Y=py, angle=0),
                                         effects=eff(hide=hide, justify="left")))
        s.pins = {pp.number: str(uuid.uuid4()) for pp in pins_of(sym)}
        s.instances = [SymbolProjectInstance(name=PROJECT, paths=[
            SymbolProjectPath(sheetInstancePath=root, reference=p["ref"], unit=1)])]
        sch.schematicSymbols.append(s)
        for pp in pins_of(sym):
            net = p["pins"].get(pp.number)
            if net is None:
                if pp.number not in design.NC_PINS.get(p['ref'], set()):
                    raise RuntimeError(f"Unreviewed unused pin {p['ref']}.{pp.number}")
                sch.noConnects.append(NoConnect(position=Position(X=x+pp.position.X, Y=y-pp.position.Y), uuid=str(uuid.uuid4())))
                continue
            a = math.radians(pp.position.angle or 0)
            tx, ty = round(x + pp.position.X, 3), round(y - pp.position.Y, 3)
            ox, oy = -round(math.cos(a)), round(math.sin(a))
            ex, ey = round(tx + ox * STUB, 3), round(ty + oy * STUB, 3)
            for pt in ((tx, ty), (ex, ey)):
                k = (round(pt[0], 2), round(pt[1], 2))
                if points.setdefault(k, net) != net:
                    raise RuntimeError(f"{p['ref']}.{pp.number} ({net}) collides with {points[k]} at {k}")
            sch.graphicalItems.append(Connection(type="wire", points=[Position(X=tx, Y=ty), Position(X=ex, Y=ey)],
                                                 uuid=str(uuid.uuid4())))
            ang = {(-1, 0): 180, (1, 0): 0, (0, 1): 0, (0, -1): 0}[(ox, oy)]
            sch.labels.append(LocalLabel(text=net, position=Position(X=ex, Y=ey, angle=ang),
                                         effects=eff(justify="right" if ang in (180, 270) else "left"),
                                         uuid=str(uuid.uuid4())))

    # ---- shelf-pack blocks onto the sheet
    blocks = []
    for p in PARTS:
        for b in blocks:
            if b[0] == p["block"]:
                b[1].append(p)
                break
        else:
            blocks.append((p["block"], [p]))
    flags = [dict(ref=f"#FLG{i + 1:02d}", lib_id="power:PWR_FLAG", value="PWR_FLAG", fp="", mpn="",
                  pins={"1": n}, block="flags", note="") for i, n in enumerate(PWR_FLAGS)]
    blocks.append(("flags", flags))

    SHEET_W, MARGIN, BLOCK_W = 1160.0, 20.32, 270.0
    bx, by, row_h = MARGIN, MARGIN, 0.0
    for name, parts in blocks:
        # lay out the block in its own coordinates first
        cx, cy, line_h, cells = 0.0, 0.0, 0.0, []
        for p in parts:
            w, h, _ = extent(lib_symbol(p["lib_id"]))
            if cx + w > BLOCK_W and cx > 0:
                cx, cy, line_h = 0.0, cy + line_h, 0.0
            cells.append((p, cx + w / 2, cy + h / 2))
            cx += w
            line_h = max(line_h, h)
        notes = [f"{p['ref']}: {p['note']}" for p in parts if p.get("note")]
        bw = BLOCK_W
        bh = cy + line_h + 12 + 3.2 * len(notes)
        if bx + bw > SHEET_W:
            bx, by, row_h = MARGIN, by + row_h + 10, 0.0
        sch.texts.append(Text(text=BLOCK_TITLES.get(name, name.upper()),
                              position=Position(X=snap(bx), Y=snap(by), angle=0),
                              effects=eff(size=2.2, justify="left"), uuid=str(uuid.uuid4())))
        for p, px, py in cells:
            _, _, (x0, x1, y0, y1) = extent(lib_symbol(p["lib_id"]))
            place(p, snap(bx + px - (x0 + x1) / 2), snap(by + 10 + py + (y0 + y1) / 2))
        ny = by + 10 + cy + line_h + 4
        for t in notes:
            sch.texts.append(Text(text=t, position=Position(X=snap(bx), Y=ny, angle=0),
                                  effects=eff(size=1.4, justify="left"), uuid=str(uuid.uuid4())))
            ny += 3.2
        bx += bw + 12
        row_h = max(row_h, bh)

    ymax = max(s.position.Y for s in sch.schematicSymbols)
    print("lowest symbol at y =", round(ymax), "mm (A0 sheet is 841 mm tall)")
    sch.sheetInstances = [HierarchicalSheetInstance(instancePath="/", page="1")]
    out = os.path.join(KI, PROJECT + ".kicad_sch")
    sch.to_file(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
