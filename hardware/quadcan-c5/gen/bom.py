"""BOM (grouped) and JLCPCB-style CPL from design.PARTS + KiCad's position export."""
import csv
import os
import sys

from design import PARTS

THT_HAND = {"J1", "J5", "BT1", "C1", "J7", "H1", "H2", "H3", "H4"} | {f"JP{n}" for n in range(1, 10)}


def main(pos_csv, out):
    groups = {}
    for p in PARTS:
        if p["ref"].startswith("H"):
            continue
        key = (p["value"], p["fp"].split(":")[1], p["mpn"])
        groups.setdefault(key, []).append(p["ref"])
    with open(os.path.join(out, "quadcan-c5-bom.csv"), "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["Qty", "Designator", "Value", "Footprint", "Manufacturer part / notes", "Assembly"])
        for (val, fp, mpn), refs in sorted(groups.items(), key=lambda kv: kv[1][0]):
            asm = "hand-solder (THT)" if set(refs) & THT_HAND else "SMT"
            if any(r == "U13" for r in refs):
                asm += " - optional GPS"
            w.writerow([len(refs), " ".join(sorted(refs)), val, fp, mpn, asm])
    # CPL in JLCPCB column naming
    with open(pos_csv) as f, open(os.path.join(out, "quadcan-c5-cpl.csv"), "w", newline="") as g:
        r = csv.DictReader(f)
        w = csv.writer(g, lineterminator="\n")
        w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
        for row in r:
            if row["Ref"] in THT_HAND:
                continue
            w.writerow([row["Ref"], row["PosX"] + "mm", row["PosY"] + "mm",
                        "Top" if row["Side"] == "top" else "Bottom", row["Rot"]])
    print("BOM groups:", len(groups))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
