"""Place footprints from design.PARTS onto a 4-layer board.

Run with KiCad's python:  /usr/bin/python3 gen/gen_pcb.py [out.kicad_pcb]
Stack-up: F.Cu signals | In1.Cu GND plane | In2.Cu signals + power | B.Cu signals + GND fill
"""
import os
import sys

import pcbnew

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from design import PARTS, PROJECT, TITLE, REV  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
KI = os.path.normpath(os.path.join(HERE, "..", "kicad"))
FPLIB = "/usr/share/kicad/footprints"
BOARD_W, BOARD_H = 110.0, 85.0
OX, OY = 100.0, 100.0
mm = pcbnew.FromMM

# ref: (x, y, rotation_deg, side)   board-local mm, y down
PLACE = {
    # ---- harness, left edge: pins x 10.5/13.5; CAN4..CAN1 at y 37..46, IGN 49, VIN 52
    "J1": (10.5, 52.0, 90, "F"),
    "R13": (5.5, 27.5, 90, "F"), "R14": (7.5, 27.5, 90, "F"),
    "R15": (13.0, 26.0, 0, "F"), "R16": (13.0, 28.0, 0, "F"),
    # ---- MCP2518FD + shared clock
    "U10": (51.0, 20.0, 0, "F"), "U9": (51.0, 36.0, 0, "F"),
    "Y1": (51.0, 28.0, 0, "F"), "C40": (47.5, 28.0, 90, "F"), "R55": (55.0, 28.0, 90, "F"),
    "C34": (51.0, 13.6, 0, "F"), "R54": (55.0, 13.6, 0, "F"),
    "C33": (51.0, 42.4, 0, "F"), "R53": (55.0, 42.4, 0, "F"),
    "R21": (45.3, 31.5, 90, "F"), "R22": (45.3, 24.5, 90, "F"),
    # ---- MCU (antenna on the top edge) + USB-C on the top edge
    "U3": (72.0, 13.75, 0, "F"),
    "C14": (59.6, 8.5, 180, "F"), "C13": (59.4, 10.4, 180, "F"),
    "R17": (59.6, 12.3, 0, "F"), "C15": (59.6, 14.0, 180, "F"),
    "J2": (50.0, 4.4, 180, "F"), "U4": (58.5, 5.5, 90, "F"),
    "R23": (52.0, 11.0, 0, "F"), "R24": (47.5, 11.0, 180, "F"),
    "D4": (39.0, 5.5, 90, "F"),
    "SW1": (88.0, 5.0, 0, "F"), "SW2": (88.0, 11.0, 0, "F"),
    "R18": (82.0, 30.0, 0, 'F'), "R19": (82.0, 32.5, 0, 'F'),
    # ---- IO expander, LEDs, mark button, Qwiic, LTE
    "U11": (72.0, 42.0, 0, 'F'), "C43": (72.0, 36.3, 0, 'F'),
    "D30": (100.5, 20.0, 0, "F"), "R70": (104.0, 20.0, 0, "F"),
    "D31": (100.5, 22.5, 0, "F"), "R71": (104.0, 22.5, 0, "F"),
    "D32": (100.5, 25.0, 0, "F"), "R72": (104.0, 25.0, 0, "F"),
    "SW3": (105.0, 30.5, 0, "F"), "R73": (100.0, 30.5, 90, "F"),
    "J6": (106.5, 13.0, 90, "F"),
    "J5": (107.5, 56.0, 180, "F"),
    # ---- RTC (CR1220 holder on the back)
    "U12": (92.0, 36.0, 0, "F"), "Y2": (92.0, 41.5, 0, "F"), "C44": (96.8, 36.0, 90, "F"),
    "BT1": (93.0, 50.0, 0, "B"),
    # ---- sense (next to the harness)
    "R8": (19.0, 52.5, 0, "F"), "R9": (19.0, 54.5, 0, "F"), "C12": (19.0, 56.5, 0, "F"),
    "R10": (23.0, 52.5, 0, "F"), "R11": (23.0, 54.5, 0, "F"), "Q1": (27.0, 53.5, 0, "F"),
    "R12": (27.0, 57.0, 0, "F"),
    # ---- power, bottom-left
    "F1": (5.0, 64.0, 270, "F"), "D1": (10.0, 65.0, 90, "F"), "D2": (15.0, 64.0, 90, "F"),
    "C2": (20.0, 64.0, 90, "F"), "C3": (23.5, 64.0, 90, "F"),
    "U1": (32.0, 67.0, 0, "F"), "C4": (34.0, 62.0, 0, "F"),
    "R1": (26.8, 70.0, 90, "F"), "R2": (26.8, 74.0, 90, "F"), "R3": (29.5, 74.0, 90, "F"),
    "R4": (32.2, 74.0, 90, "F"), "C8": (29.5, 79.5, 0, "F"), "C7": (33.0, 79.5, 0, "F"),
    "R5": (37.5, 72.0, 0, "F"), "R6": (37.5, 74.5, 0, "F"),
    "L1": (43.0, 66.0, 0, "F"), "D3": (41.0, 78.0, 0, "F"),
    "C5": (50.0, 63.0, 90, "F"), "C6": (50.0, 69.0, 90, "F"),
    "D5": (55.0, 61.0, 0, "F"), "R7": (55.0, 64.5, 0, "F"), "D6": (55.0, 68.0, 0, "F"),
    "U2": (52.5, 77.5, 0, "F"), "C10": (46.5, 82.5, 0, "F"), "C11": (58.5, 82.5, 0, "F"),
    "C9": (16.0, 78.0, 0, "F"), "C1": (4.5, 77.5, 0, "F"),
    # ---- microSD, bottom edge
    "J3": (70.0, 71.0, 0, "F"),
    "R60": (63.0, 59.0, 90, "F"), "R61": (65.0, 59.0, 90, "F"), "R62": (67.0, 59.0, 90, "F"),
    "R63": (69.0, 59.0, 90, "F"), "R20": (61.0, 59.0, 90, "F"),
    "C41": (76.0, 59.5, 90, "F"), "C42": (78.5, 59.5, 90, "F"),
    "Q3": (72.5, 54.5, 0, "F"), "R64": (76.5, 54.5, 90, "F"),
    "R65": (63.0, 54.8, 90, "F"), "R66": (65.0, 54.8, 90, "F"),
    # ---- wake diodes
    "D40": (47.0, 46.0, 0, "F"), "D41": (31.5, 55.0, 0, "F"), "R67": (35.0, 55.0, 90, "F"),
    # ---- GPS, bottom-right
    "U13": (95.0, 71.5, 0, "F"), "J4": (106.0, 70.0, 0, "F"), "L2": (104.0, 65.5, 90, "F"),
    "R83": (101.5, 60.5, 0, "F"), "C47": (106.5, 63.5, 90, "F"),
    "Q2": (90.0, 59.0, 0, "F"), "R80": (93.5, 59.0, 90, "F"),
    "C45": (84.0, 62.0, 90, "F"), "C46": (86.0, 62.0, 90, "F"),
    "R81": (82.0, 58.0, 90, "F"), "R82": (84.0, 58.0, 90, "F"),
    "D33": (98.0, 82.5, 0, "F"), "R84": (101.5, 82.5, 0, "F"),
    # ---- mounting holes
    "H1": (3.5, 3.5, 0, "F"), "H2": (106.5, 81.5, 0, "F"),
    "H3": (58.0, 50.0, 0, "F"), "H4": (106.5, 3.5, 0, "F"),
}
# ---- CAN rows (CAN4 at the top so the order matches the harness connector)
for n in range(1, 5):
    Y = 17.0 + 10.0 * (4 - n)
    PLACE[f"D{10 + n}"] = (17.5, Y + 1.8, 0, "F")         # ESD
    PLACE[f"R{30 + n}"] = (17.3, Y - 2.3, 0, "F")         # 120R
    PLACE[f"JP{n}"] = (21.6, Y - 2.3, 90, "F")            # TERM jumper
    PLACE[f"U{4 + n}"] = (30.5, Y + 0.3, 180, "F")        # transceiver (bus pins face left)
    PLACE[f"C{21 + 2 * n}"] = (30.5, Y - 4.0, 0, "F")     # VIO decoupling
    PLACE[f"C{20 + 2 * n}"] = (36.5, Y + 0.9, 90, "F")    # VCC decoupling
    PLACE[f"JP{n + 4}"] = (39.5, Y + 2.2, 90, "F")        # TX enable jumper
    PLACE[f"D{20 + n}"] = (39.5, Y - 2.5, 0, "F")         # RX LED
    PLACE[f"R{40 + n}"] = (43.0, Y - 2.5, 0, "F")

# net classes: name -> width
WIDE = {"VIN_RAW": 1.0, "VIN_F": 1.0, "VIN": 1.0, "BUCK_SW": 1.0, "+5V": 0.8, "+5V_SYS": 0.6,
        "SCAP": 0.6, "+3V3": 0.5, "VBUS": 0.6, "GPS_3V3": 0.4, "GND": 0.5}
CAN_PAIRS = [f"CAN{n}_{s}" for n in range(1, 5) for s in "HL"]


def V(x, y):
    return pcbnew.VECTOR2I(mm(OX + x), mm(OY + y))


def load_fp(fpid):
    lib, name = fpid.split(":")
    path = os.path.join(KI, "QuadCAN.pretty") if lib == "QuadCAN" else os.path.join(FPLIB, lib + ".pretty")
    fp = pcbnew.FootprintLoad(path, name)
    if fp is None:
        raise KeyError(fpid)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def outline(b):
    """Rounded-rectangle outline: four lines + four 90-degree arcs (start / mid / end)."""
    r = 3.0
    W, H = BOARD_W, BOARD_H
    segs = [((r, 0), (W - r, 0)), ((W, r), (W, H - r)), ((W - r, H), (r, H)), ((0, H - r), (0, r))]
    for a, c in segs:
        s = pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(V(*a)); s.SetEnd(V(*c)); s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(mm(0.1)); b.Add(s)
    k = r * (1 - 0.70710678)
    arcs = [((W - r, 0), (W - k, k), (W, r)), ((W, H - r), (W - k, H - k), (W - r, H)),
            ((r, H), (k, H - k), (0, H - r)), ((0, r), (k, k), (r, 0))]
    for st, mid, en in arcs:
        s = pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_ARC)
        s.SetArcGeometry(V(*st), V(*mid), V(*en))
        s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(mm(0.1)); b.Add(s)


def zone(b, net, layer, pts, prio=0, clearance=0.3):
    z = pcbnew.ZONE(b)
    z.SetLayer(layer)
    z.SetNet(net)
    z.SetAssignedPriority(prio)
    z.SetLocalClearance(mm(clearance))
    z.SetMinThickness(mm(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetThermalReliefGap(mm(0.3))
    z.SetThermalReliefSpokeWidth(mm(0.5))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    ol = z.Outline()
    ol.NewOutline()
    for x, y in pts:
        ol.Append(mm(OX + x), mm(OY + y))
    b.Add(z)
    return z


def build(out):
    b = pcbnew.BOARD()
    b.SetCopperLayerCount(4)
    ds = b.GetDesignSettings()
    ds.SetBoardThickness(mm(1.6))
    ds.m_TrackMinWidth = mm(0.15)
    ds.m_ViasMinSize = mm(0.5)
    ds.m_MinThroughDrill = mm(0.3)
    ds.m_CopperEdgeClearance = mm(0.3)
    ds.m_HoleClearance = mm(0.25)
    ds.m_HoleToHoleMin = mm(0.25)
    ds.m_MinClearance = mm(0.12)
    ds.m_SolderMaskMinWidth = mm(0)
    ds.m_MinResolvedSpokes = 1
    nset = ds.m_NetSettings
    dflt = nset.m_DefaultNetClass
    dflt.SetClearance(mm(0.15)); dflt.SetTrackWidth(mm(0.2))
    dflt.SetViaDiameter(mm(0.6)); dflt.SetViaDrill(mm(0.3))
    outline(b)

    netobjs = {}
    for p in PARTS:
        for n in p["pins"].values():
            if n not in netobjs:
                ni = pcbnew.NETINFO_ITEM(b, n); b.Add(ni); netobjs[n] = ni

    missing = [p["ref"] for p in PARTS if p["ref"] not in PLACE]
    if missing:
        raise SystemExit(f"no placement for {missing}")
    for p in PARTS:
        fp = load_fp(p["fp"])
        fp.SetReference(p["ref"]); fp.SetValue(p["value"])
        b.Add(fp)
        x, y, rot, side = PLACE[p["ref"]]
        fp.SetPosition(V(x, y))
        if side == "B":
            fp.Flip(fp.GetPosition(), False)
        fp.SetOrientationDegrees(rot)
        for pad in fp.Pads():
            n = p["pins"].get(pad.GetNumber())
            if n:
                pad.SetNet(netobjs[n])
        for t in (fp.Reference(),):
            t.SetTextSize(pcbnew.VECTOR2I(mm(0.8), mm(0.8)))
            t.SetTextThickness(mm(0.12))
        fp.Value().SetVisible(False)
        fp.SetField("MPN", p["mpn"]) if hasattr(fp, "SetField") else None

    gnd = netobjs["GND"]
    full = [(0.2, 0.2), (BOARD_W - 0.2, 0.2), (BOARD_W - 0.2, BOARD_H - 0.2), (0.2, BOARD_H - 0.2)]
    zone(b, gnd, pcbnew.In1_Cu, full)
    zone(b, gnd, pcbnew.B_Cu, full)
    zone(b, gnd, pcbnew.F_Cu, full)
    zone(b, gnd, pcbnew.In2_Cu, full)

    def text(t, x, y, size=1.0, layer=pcbnew.F_SilkS, rot=0):
        tx = pcbnew.PCB_TEXT(b); tx.SetText(t); tx.SetPosition(V(x, y)); tx.SetLayer(layer)
        tx.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size))); tx.SetTextThickness(mm(size * 0.15))
        tx.SetTextAngleDegrees(rot)
        if layer == pcbnew.B_SilkS:
            tx.SetMirrored(True)
        b.Add(tx)
    text(f"QuadCAN-C5 v{REV}", 55, 47.0, 1.2, pcbnew.B_SilkS)
    text("4x CAN-FD logger - ESP32-C5", 55, 49.0, 0.8, pcbnew.B_SilkS)
    text("TERM: bus end only", 22.0, 10.2, 0.8)
    text("TX: no jumper = listen-only", 42.0, 10.2, 0.8)
    for n in range(1, 5):
        text(f"CAN{n}", 24.5, 17.0 + 10.0 * (4 - n) + 4.2, 0.8)
    pcbnew.SaveBoard(out, b)
    return b


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(KI, PROJECT + ".kicad_pcb")
    build(out)
    print("wrote", out)
