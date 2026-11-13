#!/usr/bin/env bash
# Renders of the routed board: realistic bare-board images (from KiCad's own layer plots) and
# 3D views with simplified part bodies (three.js, headless Chromium via Playwright).
#   needs: kicad-cli, python3 (numpy, pillow), node + playwright, `npm install three@0.169.0` in $WORK
# usage: render/render.sh [workdir]     -> docs/renders/*.png
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
PCB="$ROOT/kicad/quadcan-c5.kicad_pcb"
WORK="${1:-$(mktemp -d)}"
OUT="$ROOT/docs/renders"
mkdir -p "$WORK/layers" "$OUT"
for L in Edge.Cuts F.Cu B.Cu F.Mask B.Mask F.SilkS B.SilkS; do
  kicad-cli pcb export svg --exclude-drawing-sheet --page-size-mode 2 --black-and-white -l "$L,Edge.Cuts" -o "$WORK/layers/$L.svg" "$PCB" >/dev/null
  (cd "$WORK" && node "$HERE/raster.js" "layers/$L.svg" "layers/$L.png" 20 >/dev/null)
done
/usr/bin/python3 "$HERE/dump_board.py" "$PCB" "$WORK/layers/board.json" 2>/dev/null
python3 "$HERE/composite.py" "$WORK/layers"
cp "$WORK/layers/bare_F.png" "$OUT/board-top-bare.png"; cp "$WORK/layers/bare_B.png" "$OUT/board-bottom-bare.png"
[ -d "$WORK/node_modules/three" ] || (cd "$WORK" && npm init -y >/dev/null && npm install three@0.169.0 --silent)
cp "$HERE/scene.html" "$WORK/index.html"
cp "$WORK/layers/bare_F.png" "$WORK/layers/bare_B.png" "$WORK/layers/board.json" "$ROOT"/enclosure/*.stl "$WORK/"
(cd "$WORK" && python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 & echo $! > "$WORK/http.pid")
sleep 1
for v in iso top can logic bottom case closed; do (cd "$WORK" && node "$HERE/shot.js" "$OUT" "$v" 2400 1500); done
kill "$(cat "$WORK/http.pid")" 2>/dev/null || true
