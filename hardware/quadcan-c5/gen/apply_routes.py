"""Add routes.json tracks/vias to a board, fill zones, run DRC (KiCad's python).

usage: /usr/bin/python3 apply_routes.py placed.kicad_pcb routes.json out.kicad_pcb drc.txt
"""
import json
import sys

import pcbnew

LAYER = {"F": pcbnew.F_Cu, "In2": pcbnew.In2_Cu, "B": pcbnew.B_Cu}
mm = pcbnew.FromMM


def main(src, routes, out, drc):
    b = pcbnew.LoadBoard(src)
    r = json.load(open(routes))
    nets = b.GetNetsByName()
    for t in r["tracks"]:
        net = nets[t["net"]]
        for (x1, y1), (x2, y2) in zip(t["pts"], t["pts"][1:]):
            tr = pcbnew.PCB_TRACK(b)
            tr.SetStart(pcbnew.VECTOR2I(mm(x1), mm(y1)))
            tr.SetEnd(pcbnew.VECTOR2I(mm(x2), mm(y2)))
            tr.SetWidth(mm(t["w"]))
            tr.SetLayer(LAYER[t["layer"]])
            tr.SetNet(net)
            b.Add(tr)
    for v in r["vias"]:
        via = pcbnew.PCB_VIA(b)
        via.SetPosition(pcbnew.VECTOR2I(mm(v["x"]), mm(v["y"])))
        via.SetDrill(mm(0.3))
        via.SetWidth(mm(0.6))
        via.SetNet(nets[v["net"]])
        b.Add(via)
    pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    pcbnew.SaveBoard(out, b)
    if drc:
        pcbnew.WriteDRCReport(b, drc, pcbnew.EDA_UNITS_MILLIMETRES, True)
    print("wrote", out)


if __name__ == "__main__":
    main(*sys.argv[1:4], sys.argv[4] if len(sys.argv) > 4 else None)
