"""Find broadcast CAN fields that track values the app polled.

Usage: python3 correlate.py <drive>.driveline [top_n]

For every polled label in obd_poll.csv, takes each broadcast ID (< 0x700), holds
its latest frame at each poll time, and scores u8 / u16 LE / u16 BE / 12-bit
slices by |Pearson r|.

Caveats:
- Slowly accumulating values (soot trigger, fuel used) correlate with any
  distance or time counter. Check deltas, not just r.
- r around 0.75 against torque or RPM fields means "tracks engine load",
  not "this is the sensor".
"""
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dlraw  # noqa: E402


def candidates(xs):
    c = {f"b{o}": xs[:, o] for o in range(8)}
    for o in range(7):
        le = xs[:, o] | (xs[:, o + 1] << 8)
        c[f"le{o}"] = le
        c[f"be{o}"] = (xs[:, o] << 8) | xs[:, o + 1]
        c[f"le{o}_lo12"] = le & 0xFFF
        c[f"le{o}_hi12"] = le >> 4
    return c


def main(drive, top=5):
    d = dlraw.load(os.path.join(drive, "frames.dlraw"))
    p = pd.read_csv(os.path.join(drive, "obd_poll.csv"), sep=";")
    p = p[p.kind == "value"]
    for lab, g in p.groupby("label"):
        pt = g.epoch.values.astype(float)
        pv = g.value.values.astype(float)
        if len(pv) < 50 or np.std(pv) == 0:
            print(f"{lab}: flat or too short ({len(pv)} samples)")
            continue
        best = []
        for cid, (t, x) in d.items():
            if cid >= 0x700 or len(t) < 100:
                continue
            idx = np.searchsorted(t, pt) - 1
            ok = idx >= 0
            if ok.sum() < 50:
                continue
            xs = x[idx[ok]].astype(np.int64)
            y = pv[ok]
            for name, v in candidates(xs).items():
                if np.std(v) == 0:
                    continue
                r = np.corrcoef(v, y)[0, 1]
                if np.isfinite(r):
                    best.append((abs(r), cid, name, r))
        best.sort(reverse=True)
        print(f"{lab}  n={len(pv)}  range {pv.min():.1f}..{pv.max():.1f}")
        for _a, cid, name, r in best[:top]:
            print(f"    0x{cid:03x} {name:10s} r={r:+.3f}")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 5)
