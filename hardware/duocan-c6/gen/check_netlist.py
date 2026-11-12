"""Compare a KiCad-exported netlist (kicadsexpr) against design.PARTS."""
import re, sys
from design import nets

txt = open(sys.argv[1]).read()
got = {}
for m in re.finditer(r'\(net \(code "?\d+"?\) \(name "([^"]+)"\)(.*?)\)\s*(?=\(net |\)\s*\)\s*$)', txt, re.S):
    name = m.group(1).lstrip("/")
    nodes = set(re.findall(r'\(node \(ref "([^"]+)"\) \(pin "([^"]+)"\)', m.group(2)))
    nodes = {n for n in nodes if not n[0].startswith("#")}
    if name.startswith("unconnected-") or name.startswith("Net-("):
        if nodes:
            got.setdefault(name, set()).update(nodes)
        continue
    got.setdefault(name, set()).update(nodes)
want = {k: set(v) for k, v in nets().items()}
bad = 0
for n in sorted(set(want) | set(got)):
    if want.get(n, set()) != got.get(n, set()):
        bad += 1
        print("MISMATCH", n, "want-only", want.get(n, set()) - got.get(n, set()), "got-only", got.get(n, set()) - want.get(n, set()))
print(f"{len(want)} nets checked, {bad} mismatches")
sys.exit(1 if bad else 0)
