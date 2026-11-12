#!/usr/bin/env bash
# Regenerate everything from gen/design.py.
#   needs: KiCad 7 (kicad-cli + pcbnew python at /usr/bin/python3),
#          python3 with kiutils, numpy, scipy, pillow (for the schematic + router)
# usage: gen/build.sh            (full run, ~10-20 min because of the router)
#        SKIP_ROUTE=1 gen/build.sh   (reuse kicad/routes.json)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KI="$HERE/../kicad"
OUT="$HERE/../fab"
WORK="${WORK:-$(mktemp -d)}"
KPY=/usr/bin/python3
cd "$HERE"

python3 gen_lib.py
python3 gen_sch.py
kicad-cli sch export netlist -o "$WORK/sch.net" "$KI/quadcan-c5.kicad_sch" >/dev/null
python3 check_netlist.py "$WORK/sch.net"

$KPY gen_pcb.py "$WORK/placed.kicad_pcb"
$KPY check_place.py "$WORK/placed.kicad_pcb"
$KPY export_geom.py "$WORK/placed.kicad_pcb" "$WORK/geom.json"
if [ -z "${SKIP_ROUTE:-}" ]; then
  python3 route.py "$WORK/geom.json" "$KI/routes.json"
fi
$KPY apply_routes.py "$WORK/placed.kicad_pcb" "$KI/routes.json" "$KI/quadcan-c5.kicad_pcb" "$OUT/drc.txt"
$KPY check_pcb.py "$KI/quadcan-c5.kicad_pcb" "$OUT/drc.txt"
./fab.sh
