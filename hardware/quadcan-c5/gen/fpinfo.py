import os, sys, pcbnew
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from design import PARTS
KI = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "kicad"))
seen = {}
for p in PARTS:
    lib, name = p["fp"].split(":")
    path = os.path.join(KI, "QuadCAN.pretty") if lib == "QuadCAN" else f"/usr/share/kicad/footprints/{lib}.pretty"
    if p["fp"] in seen:
        seen[p["fp"]][1].append(p["ref"]); continue
    fp = pcbnew.FootprintLoad(path, name)
    bb = fp.GetCourtyard(pcbnew.F_CrtYd).BBox() if fp.GetCourtyard(pcbnew.F_CrtYd).OutlineCount() else fp.GetBoundingBox(False, False)
    seen[p["fp"]] = ((round(pcbnew.ToMM(bb.GetLeft()),2), round(pcbnew.ToMM(bb.GetTop()),2), round(pcbnew.ToMM(bb.GetRight()),2), round(pcbnew.ToMM(bb.GetBottom()),2)), [p["ref"]])
for k, (bb, refs) in seen.items():
    print(f"{k.split(':')[1][:48]:48s} {bb} {' '.join(refs)}")
