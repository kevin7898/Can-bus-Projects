"""Dump board geometry for the router (run with KiCad's python).

usage: /usr/bin/python3 export_geom.py board.kicad_pcb geom.json
"""
import json
import sys

import pcbnew

LAYERS = {pcbnew.F_Cu: "F", pcbnew.In1_Cu: "In1", pcbnew.In2_Cu: "In2", pcbnew.B_Cu: "B"}


def poly_pts(sps):
    out = []
    for i in range(sps.OutlineCount()):
        ol = sps.Outline(i)
        out.append([(pcbnew.ToMM(ol.CPoint(j).x), pcbnew.ToMM(ol.CPoint(j).y)) for j in range(ol.PointCount())])
    return out


def main(src, dst):
    b = pcbnew.LoadBoard(src)
    bb = b.GetBoardEdgesBoundingBox()
    g = {"bbox": [pcbnew.ToMM(bb.GetLeft()), pcbnew.ToMM(bb.GetTop()),
                  pcbnew.ToMM(bb.GetRight()), pcbnew.ToMM(bb.GetBottom())],
         "pads": [], "holes": [], "keepouts": []}
    for fp in b.GetFootprints():
        for pad in fp.Pads():
            layers = [v for k, v in LAYERS.items() if pad.IsOnLayer(k)]
            if not layers:
                continue
            polys = {}
            for k, v in LAYERS.items():
                if pad.IsOnLayer(k):
                    sps = pad.GetEffectivePolygon()
                    polys[v] = poly_pts(sps)
            pos = pad.GetPosition()
            g["pads"].append({
                "ref": fp.GetReference(), "pad": pad.GetNumber(), "net": pad.GetNetname(),
                "x": pcbnew.ToMM(pos.x), "y": pcbnew.ToMM(pos.y), "layers": layers,
                "smd": pad.GetAttribute() == pcbnew.PAD_ATTRIB_SMD,
                "poly": polys[layers[0]],
            })
            if pad.GetDrillSize().x > 0:
                g["holes"].append({"x": pcbnew.ToMM(pos.x), "y": pcbnew.ToMM(pos.y),
                                   "d": pcbnew.ToMM(max(pad.GetDrillSize().x, pad.GetDrillSize().y)),
                                   "npth": pad.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH})
        for z in fp.Zones():
            if z.GetIsRuleArea():
                g["keepouts"].append(poly_pts(z.Outline()))
    for z in b.Zones():
        if z.GetIsRuleArea():
            g["keepouts"].append(poly_pts(z.Outline()))
    json.dump(g, open(dst, "w"))
    print(f"exported {len(g['pads'])} pads, {len(g['holes'])} holes, {len(g['keepouts'])} keepouts")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
