"""Place footprints from design.PARTS onto a fresh board (run with KiCad's python: /usr/bin/python3)."""
import os, sys
import pcbnew
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from design import PARTS, BOARD_W, BOARD_H, POWER_NETS, SIGNAL_WIDTH, CAN_WIDTH

HERE = os.path.dirname(os.path.abspath(__file__))
KI = os.path.normpath(os.path.join(HERE, "..", "kicad"))
FPLIB = "/usr/share/kicad/footprints"
OX, OY = 100.0, 100.0  # board origin on the KiCad canvas
mm = pcbnew.FromMM


def V(x, y):
    return pcbnew.VECTOR2I(mm(OX + x), mm(OY + y))


def load_fp(fpid):
    lib, name = fpid.split(":")
    path = os.path.join(KI, "DuoCAN.pretty") if lib == "DuoCAN" else os.path.join(FPLIB, lib + ".pretty")
    fp = pcbnew.FootprintLoad(path, name)
    if fp is None:
        raise KeyError(fpid)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def build(out):
    b = pcbnew.BOARD()
    b.SetCopperLayerCount(2)
    ds = b.GetDesignSettings()
    ds.m_TrackMinWidth = mm(0.2)
    ds.m_ViasMinSize = mm(0.6)
    ds.m_MinThroughDrill = mm(0.3)
    ds.m_CopperEdgeClearance = mm(0.4)
    ds.m_HoleClearance = mm(0.25)
    nc = ds.m_NetSettings.m_DefaultNetClass
    nc.SetClearance(mm(0.2)); nc.SetTrackWidth(mm(SIGNAL_WIDTH))
    nc.SetViaDiameter(mm(0.6)); nc.SetViaDrill(mm(0.3))

    # outline with 2mm corner radius
    r = 2.0
    segs = [((r, 0), (BOARD_W - r, 0)), ((BOARD_W, r), (BOARD_W, BOARD_H - r)),
            ((BOARD_W - r, BOARD_H), (r, BOARD_H)), ((0, BOARD_H - r), (0, r))]
    for a, c in segs:
        s = pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(V(*a)); s.SetEnd(V(*c)); s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(mm(0.1)); b.Add(s)
    for cx, cy, sx, sy in [(r, r, 0, r), (BOARD_W - r, r, BOARD_W - r, 0),
                           (BOARD_W - r, BOARD_H - r, BOARD_W, BOARD_H - r), (r, BOARD_H - r, r, BOARD_H)]:
        s = pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_ARC)
        s.SetCenter(V(cx, cy)); s.SetStart(V(sx, sy)); s.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(-90, pcbnew.DEGREES_T))
        s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(mm(0.1)); b.Add(s)

    netobjs = {}
    for p in PARTS:
        for n in p["pins"].values():
            if n not in netobjs:
                ni = pcbnew.NETINFO_ITEM(b, n); b.Add(ni); netobjs[n] = ni

    for p in PARTS:
        fp = load_fp(p["fp"])
        fp.SetReference(p["ref"]); fp.SetValue(p["value"])
        b.Add(fp)
        x, y, rot, side = p["pcb"]
        fp.SetPosition(V(x, y))
        fp.SetOrientationDegrees(rot)
        if side == "B":
            fp.Flip(fp.GetPosition(), False)
        for pad in fp.Pads():
            n = p["pins"].get(pad.GetNumber())
            if n:
                pad.SetNet(netobjs[n])
        fp.Reference().SetTextSize(pcbnew.VECTOR2I(mm(0.8), mm(0.8)))
        fp.Reference().SetTextThickness(mm(0.12))

    # silkscreen branding / labels
    def text(t, x, y, size=1.0, layer=pcbnew.F_SilkS, rot=0):
        tx = pcbnew.PCB_TEXT(b); tx.SetText(t); tx.SetPosition(V(x, y)); tx.SetLayer(layer)
        tx.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size))); tx.SetTextThickness(mm(size * 0.15))
        tx.SetTextAngleDegrees(rot)
        if layer == pcbnew.B_SilkS:
            tx.SetMirrored(True)
        b.Add(tx)
    text("DuoCAN-C6 v1.0", 32, 41.8, 1.0, pcbnew.B_SilkS)
    text("Dual CAN / XIAO ESP32-C6", 32, 39.8, 0.8, pcbnew.B_SilkS)
    text("Termination jumpers OFF when tapping a vehicle", 32, 37.6, 0.7, pcbnew.B_SilkS)
    for t, y in [("12V", 0), ("GND", 1), ("1H", 2), ("1L", 3), ("2H", 4), ("2L", 5)]:
        text(t, 1.0, 7.0 + y * 3.5, 0.7, pcbnew.B_SilkS, 90)
    pcbnew.SaveBoard(out, b)
    return b


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(KI, "duocan-c6-placed.kicad_pcb")
    build(out)
    print("wrote", out)
