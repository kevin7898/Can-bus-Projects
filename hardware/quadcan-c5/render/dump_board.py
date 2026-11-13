"""Dump drill holes and footprint boxes for the renderer (run with KiCad's python)."""
import json, sys
import pcbnew
b = pcbnew.LoadBoard(sys.argv[1])
mm = pcbnew.ToMM
holes = []
for fp in b.GetFootprints():
    for pad in fp.Pads():
        d = pad.GetDrillSize()
        if d.x > 0:
            holes.append((mm(pad.GetPosition().x) - 100, mm(pad.GetPosition().y) - 100, mm(max(d.x, d.y)) / 2,
                          pad.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH))
for t in b.GetTracks():
    if t.GetClass() == "PCB_VIA":
        holes.append((mm(t.GetPosition().x) - 100, mm(t.GetPosition().y) - 100, mm(t.GetDrillValue()) / 2, False))
fps = []
for fp in b.GetFootprints():
    side = "B" if fp.IsFlipped() else "F"
    cy = fp.GetCourtyard(pcbnew.B_CrtYd if side == "B" else pcbnew.F_CrtYd)
    bb = cy.BBox() if cy.OutlineCount() else fp.GetBoundingBox(False, False)
    fps.append(dict(ref=fp.GetReference(), fp=fp.GetFPID().GetLibItemName().wx_str(), side=side,
                    x=mm(fp.GetPosition().x) - 100, y=mm(fp.GetPosition().y) - 100, rot=fp.GetOrientationDegrees(),
                    bb=[mm(bb.GetLeft()) - 100, mm(bb.GetTop()) - 100, mm(bb.GetRight()) - 100, mm(bb.GetBottom()) - 100],
                    value=fp.GetValue()))
json.dump({"holes": holes, "fps": fps}, open(sys.argv[2], "w"))
