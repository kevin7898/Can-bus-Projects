#!/usr/bin/env bash
# Fabrication outputs for JLCPCB / PCBWay: gerbers + drill (zipped), BOM and pick-and-place CSVs, PDFs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PCB="$HERE/../kicad/quadcan-c5.kicad_pcb"
SCH="$HERE/../kicad/quadcan-c5.kicad_sch"
OUT="$HERE/../fab"
mkdir -p "$OUT/gerbers"
rm -f "$OUT"/gerbers/*

kicad-cli pcb export gerbers -o "$OUT/gerbers/" \
  -l F.Cu,In1.Cu,In2.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts \
  --subtract-soldermask --no-x2 "$PCB" >/dev/null
kicad-cli pcb export drill -o "$OUT/gerbers/" --format excellon --excellon-separate-th \
  --generate-map --map-format gerberx2 "$PCB" >/dev/null
(cd "$OUT/gerbers" && rm -f ../quadcan-c5-gerbers.zip && zip -q ../quadcan-c5-gerbers.zip ./*)

kicad-cli pcb export pos -o "$OUT/quadcan-c5-pos-raw.csv" --format csv --units mm --side both "$PCB" >/dev/null
kicad-cli sch export pdf -o "$OUT/quadcan-c5-schematic.pdf" "$SCH" >/dev/null
kicad-cli pcb export pdf -o "$OUT/quadcan-c5-assembly-top.pdf" -l F.Fab,F.SilkS,Edge.Cuts "$PCB" >/dev/null
python3 "$HERE/bom.py" "$OUT/quadcan-c5-pos-raw.csv" "$OUT"
echo "fab outputs in $OUT"
