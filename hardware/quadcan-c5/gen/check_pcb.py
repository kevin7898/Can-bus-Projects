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


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
