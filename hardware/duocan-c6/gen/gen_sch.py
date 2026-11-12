"""Generate kicad/duocan-c6.kicad_sch from design.PARTS.

Each pin gets a short wire stub ending in a net label, so the schematic is
connection-accurate and every part reads as its own block.
"""
import copy, math, os, uuid
from kiutils.schematic import Schematic
from kiutils.symbol import SymbolLib
from kiutils.items.common import Position, Property, Effects, Font, Justify, PageSettings, TitleBlock
from kiutils.items.schitems import (SchematicSymbol, LocalLabel, Connection,
                                    SymbolProjectInstance, SymbolProjectPath, Text)
from design import PARTS

HERE = os.path.dirname(os.path.abspath(__file__))
KI = os.path.normpath(os.path.join(HERE, "..", "kicad"))
SYSLIB = "/usr/share/kicad/symbols"
PROJECT = "duocan-c6"
STUB = 2.54
SCALE = 1.5


def S(v):
    return round(v * SCALE / 2.54) * 2.54

_libs = {}


def lib_symbol(lib_id):
    lib, name = lib_id.split(":")
    if lib not in _libs:
        path = os.path.join(KI, "DuoCAN.kicad_sym") if lib == "DuoCAN" else os.path.join(SYSLIB, lib + ".kicad_sym")
        _libs[lib] = SymbolLib.from_file(path)
    for s in _libs[lib].symbols:
        if s.entryName == name:
            if s.extends:
                raise RuntimeError(f"{lib_id} extends {s.extends}; pick a base symbol")
            s = copy.deepcopy(s)
            s.libraryNickname = lib
            return s
    raise KeyError(lib_id)


def eff(size=1.27, hide=False, justify=None):
    e = Effects(font=Font(width=size, height=size), hide=hide)
    if justify:
        e.justify = Justify(horizontally=justify)
    return e


def all_pins(sym):
    for unit in sym.units:
        for p in unit.pins:
            yield p


def r(v):
    return round(v / 1.27) * 1.27


def main():
    sch = Schematic.create_new()
    sch.version = 20230121
    sch.generator = "eeschema"
    sch.uuid = str(uuid.uuid4())
    sch.paper = PageSettings(paperSize="A3")
    sch.titleBlock = TitleBlock(title="DuoCAN-C6: dual CAN shield for XIAO ESP32-C6",
                                date="2026-11-12", revision="1.0",
                                comments={1: "Generated from gen/design.py - edit that, then re-run gen/build.sh",
                                          2: "Both transceivers boot SILENT (listen-only) via S-pin pull-ups"})
    root_path = "/" + sch.uuid
    seen = set()
    points = {}

    def place(lib_id, ref, value, at, fp="", extra=None, pins_to_nets=None):
        sym = lib_symbol(lib_id)
        if lib_id not in seen:
            seen.add(lib_id)
            ls = copy.deepcopy(sym)
            ls.libraryNickname = lib_id.split(":")[0]
            sch.libSymbols.append(ls)
        x, y = S(at[0]), S(at[1])
        s = SchematicSymbol()
        s.libraryNickname, s.entryName = lib_id.split(":")
        s.position = Position(X=x, Y=y, angle=0)
        s.unit = 1
        s.inBom = sym.inBom if sym.inBom is not None else True
        s.onBoard = sym.onBoard if sym.onBoard is not None else True
        s.uuid = str(uuid.uuid4())
        is_power = ref.startswith("#")
        props = [("Reference", ref, (x, y - 6.35), is_power),
                 ("Value", value, (x, y + 6.35), False),
                 ("Footprint", fp, (x, y), True),
                 ("Datasheet", "", (x, y), True)]
        for k, v in (extra or {}).items():
            props.append((k, v, (x, y), True))
        for i, (k, v, (px, py), hide) in enumerate(props):
            s.properties.append(Property(key=k, value=v, id=i, position=Position(X=px, Y=py, angle=0), effects=eff(hide=hide)))
        s.pins = {p.number: str(uuid.uuid4()) for p in all_pins(sym)}
        s.instances = [SymbolProjectInstance(name=PROJECT, paths=[SymbolProjectPath(sheetInstancePath=root_path, reference=ref, unit=1)])]
        sch.schematicSymbols.append(s)
        # wire stubs + labels
        for p in all_pins(sym):
            net = (pins_to_nets or {}).get(p.number)
            if net is None:
                continue
            a = math.radians(p.position.angle or 0)
            tipx, tipy = x + p.position.X, y - p.position.Y
            ox, oy = -math.cos(a), math.sin(a)
            ex, ey = r(tipx + ox * STUB), r(tipy + oy * STUB)
            tipx, tipy = r(tipx), r(tipy)
            for pt in ((tipx, tipy), (ex, ey)):
                k = (round(pt[0], 2), round(pt[1], 2))
                if points.setdefault(k, net) != net:
                    raise RuntimeError(f'{ref}.{p.number} ({net}) collides with {points[k]} at {k}')
            w = Connection(type="wire", points=[Position(X=tipx, Y=tipy), Position(X=ex, Y=ey)], uuid=str(uuid.uuid4()))
            sch.graphicalItems.append(w)
            ang = {(-1, 0): 180, (1, 0): 0, (0, 1): 270, (0, -1): 90}[(round(ox), round(oy))]
            just = "right" if ang in (180, 270) else "left"
            sch.labels.append(LocalLabel(text=net, position=Position(X=ex, Y=ey, angle=ang),
                                         effects=eff(justify=just), uuid=str(uuid.uuid4())))

    for p in PARTS:
        place(p["lib_id"], p["ref"], p["value"], p["sch"], fp=p["fp"],
              extra={"MPN": p["mpn"]} if p["mpn"] else None, pins_to_nets=p["pins"])
        if p["note"]:
            x, y = S(p["sch"][0]), S(p["sch"][1])
            sch.texts.append(Text(text=p["note"], position=Position(X=x - 12.7, Y=y + 12.7, angle=0),
                                  effects=eff(size=1.0, justify="left"), uuid=str(uuid.uuid4())))

    # PWR_FLAGs so ERC knows these nets are driven
    for i, net in enumerate(["VBAT_IN", "GND", "VIN_PROT", "+5V", "+3V3"]):
        place("power:PWR_FLAG", f"#FLG0{i+1}", "PWR_FLAG", (25.4 + i * 15.24, 160.02), pins_to_nets={"1": net})

    for i, (t, at) in enumerate([
        ("POWER: 12V in -> PTC -> TVS -> reverse diode -> Traco TSR-1 5V buck -> XIAO 5V pin", (12.7, 20.32)),
        ("CAN TRANSCEIVERS (x2): TJA1051T/3, VCC=5V, VIO=3V3 from XIAO, S-pin pull-up = silent at boot", (12.7, 81.28)),
        ("MCU: Seeed XIAO ESP32-C6 (two on-chip TWAI controllers) on sockets", (190.5, 20.32)),
        ("INDICATORS / EXPANSION", (180.34, 81.28)),
    ]):
        sch.texts.append(Text(text=t, position=Position(X=S(at[0]), Y=S(at[1]), angle=0),
                              effects=eff(size=2.0, justify="left"), uuid=str(uuid.uuid4())))

    sch.sheetInstances = []
    from kiutils.items.schitems import HierarchicalSheetInstance
    sch.sheetInstances.append(HierarchicalSheetInstance(instancePath="/", page="1"))
    out = os.path.join(KI, PROJECT + ".kicad_sch")
    sch.to_file(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
