"""Summarise a KiCad DRC report and verify the routed board's connectivity.

usage: /usr/bin/python3 check_pcb.py board.kicad_pcb drc.txt
"""
import collections
import re
import sys

import pcbnew


def main(pcb, drc):
    txt = open(drc).read()
    kinds = collections.Counter(re.findall(r"^\[(\w+)\]", txt, re.M))
    viol = re.search(r"Found (\d+) DRC violations", txt)
    unc = re.search(r"Found (\d+) unconnected pads", txt)
    print("DRC violations:", viol.group(1) if viol else "?", dict(kinds))
    print("unconnected pads:", unc.group(1) if unc else "?")
    b = pcbnew.LoadBoard(pcb)
    b.BuildConnectivity()
    conn = b.GetConnectivity()
    print("unrouted connections (connectivity):", conn.GetUnconnectedCount(True))
    print(f"tracks: {len(b.GetTracks())}")
    from design import PARTS
    expected = {p['ref']: p for p in PARTS}
    actual = {fp.GetReference(): fp for fp in b.GetFootprints()}
    mismatches = []
    if set(expected) != set(actual): mismatches.append("component sets differ")
    for ref, p in expected.items():
        if ref not in actual: continue
        pads = {}
        for pad in actual[ref].Pads():
            pads.setdefault(pad.GetNumber(), set()).add(pad.GetNetname())
        for pin, net in p['pins'].items():
            if pads.get(pin) != {net}: mismatches.append(f"{ref}.{pin}: {pads.get(pin)} != {net}")
        for pin, ns in pads.items():
            if pin not in p['pins'] and ns != {''}: mismatches.append(f"unexpected connection {ref}.{pin}: {ns}")
        if actual[ref].GetValue() != p['value']: mismatches.append(f"stale value: {ref}")
    print("PCB/source mismatches:", len(mismatches))
    for m in mismatches: print(m)
    errors = len(re.findall(r"Severity: error|; error\b", txt))
    sys.exit(1 if errors or conn.GetUnconnectedCount(True) or mismatches else 0)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
