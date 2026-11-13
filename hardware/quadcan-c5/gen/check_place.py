"""Report courtyard overlaps and parts outside the board."""
import sys, pcbnew
b = pcbnew.LoadBoard(sys.argv[1])
eb = b.GetBoardEdgesBoundingBox()
items = []
for fp in b.GetFootprints():
    fp.BuildCourtyardCaches()
    for side, lay in (("F", pcbnew.F_CrtYd), ("B", pcbnew.B_CrtYd)):
        c = fp.GetCourtyard(lay)
        if c.OutlineCount():
            items.append((fp.GetReference(), side, c))
bad = 0
for i in range(len(items)):
    r1, s1, c1 = items[i]
    bb = c1.BBox()
    if r1[0] != "H" and r1 not in ("U3", "J1", "J2", "J3", "J4") and not eb.Contains(bb):
        print("OUTSIDE", r1); bad += 1
    for j in range(i + 1, len(items)):
        r2, s2, c2 = items[j]
        if s1 != s2:
            continue
        if c1.Collide(c2.Outline(0), 0) if hasattr(c1, "Collide") else c1.BBox().Intersects(c2.BBox()):
            x = pcbnew.SHAPE_POLY_SET(c1); x.BooleanIntersection(c2)
            if x.Area() > 0.05 * 1e12:
                print(f"OVERLAP {r1} {r2} {x.Area()/1e12:.2f}mm2"); bad += 1
print("issues:", bad)

sys.exit(1 if bad else 0)
