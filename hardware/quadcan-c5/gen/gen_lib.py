"""Project-local KiCad library: symbols + footprints that KiCad 7 does not ship.

ESP32-C5-WROOM-1 land pattern: Espressif ESP32-C5-WROOM-1/1U datasheet v1.3, Fig. 11-1
  module 18.0 x 27.5 mm, 28 castellated pads 1.5 x 0.9 mm @ 1.27 mm,
  pad rows 17.5 mm apart (centre-centre), pad 1 centre 7.99 mm below the antenna edge,
  thermal pad = 3x3 array of 1.3 mm squares @ 1.7 mm, centre 9.83 mm from the
  left module edge and 10.922 mm above the bottom edge. Antenna area: top 6.5 mm.
"""
import os
import uuid
from design import ESP32C5_PINS

HERE = os.path.dirname(os.path.abspath(__file__))
KI = os.path.normpath(os.path.join(HERE, "..", "kicad"))


def U():
    return str(uuid.uuid4())


def box_symbol(name, ref, left, right, fp, ds, width=15.24, top=None, bottom=None):
    """left/right: list of (number, name, etype) top->bottom (None = gap)."""
    rows = max(len(left), len(right))
    h = rows * 2.54
    y0 = (rows // 2) * 2.54
    ytop, ybot = y0 + 1.27, y0 - (rows - 1) * 2.54 - 1.27
    pins = []

    def pin(num, nm, et, x, y, ang):
        pins.append(f'      (pin {et} line (at {x:.2f} {y:.2f} {ang}) (length 2.54)\n'
                    f'        (name "{nm}" (effects (font (size 1.016 1.016))))\n'
                    f'        (number "{num}" (effects (font (size 1.016 1.016)))))')
    for i, p in enumerate(left):
        if p:
            pin(p[0], p[1], p[2], -width / 2 - 2.54, y0 - i * 2.54, 0)
    for i, p in enumerate(right):
        if p:
            pin(p[0], p[1], p[2], width / 2 + 2.54, y0 - i * 2.54, 180)
    return f'''  (symbol "{name}" (in_bom yes) (on_board yes)
    (property "Reference" "{ref}" (at 0 {ytop + 1.27:.2f} 0) (effects (font (size 1.27 1.27))))
    (property "Value" "{name}" (at 0 {ybot - 1.27:.2f} 0) (effects (font (size 1.27 1.27))))
    (property "Footprint" "{fp}" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "{ds}" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
    (symbol "{name}_0_1"
      (rectangle (start {-width / 2:.2f} {ytop:.2f}) (end {width / 2:.2f} {ybot:.2f}) (stroke (width 0.254) (type default)) (fill (type background)))
    )
    (symbol "{name}_1_1"
{chr(10).join(pins)}
    )
  )'''


def symbols():
    io = "bidirectional"
    esp_left = [(n, ESP32C5_PINS[n], {1: "power_in", 2: "power_in", 3: "input"}.get(n, io)) for n in range(1, 15)]
    esp_right = [(n, ESP32C5_PINS[n], "no_connect" if ESP32C5_PINS[n] in ("NC",) else
                  ("power_in" if n in (28, 29) else io)) for n in range(15, 30)]
    esp_right = list(reversed(esp_right[:14])) + [esp_right[14]]  # 28..15 top->bottom, then EPAD
    # NC/IO15 is the PSRAM chip select on N8R8 modules -> mark no_connect
    esp_right = [(n, nm, "no_connect" if n == 19 else et) for (n, nm, et) in esp_right]
    tcan_l = [("1", "TXD", "input"), ("4", "RXD", "output"), ("8", "STB", "input"),
              ("5", "VIO", "power_in")]
    tcan_r = [("3", "VCC", "power_in"), ("7", "CANH", "bidirectional"),
              ("6", "CANL", "bidirectional"), ("2", "GND", "power_in")]
    body = "\n".join([
        box_symbol("ESP32-C5-WROOM-1", "U", esp_left, esp_right, "QuadCAN:ESP32-C5-WROOM-1",
                   "https://documentation.espressif.com/esp32-c5-wroom-1_wroom-1u_datasheet_en.pdf", 20.32),
        box_symbol("TCAN1044AV", "U", tcan_l, tcan_r, "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm",
                   "https://www.ti.com/lit/ds/symlink/tcan1044a-q1.pdf", 12.7),
    ])
    return f"(kicad_symbol_lib (version 20220914) (generator quadcan_gen)\n{body}\n)\n"


def ln(x1, y1, x2, y2, layer, w):
    return (f'  (fp_line (start {x1:.3f} {y1:.3f}) (end {x2:.3f} {y2:.3f}) '
            f'(stroke (width {w}) (type solid)) (layer "{layer}") (tstamp {U()}))')


def rect(x1, y1, x2, y2, layer, w):
    return [ln(x1, y1, x2, y1, layer, w), ln(x2, y1, x2, y2, layer, w),
            ln(x2, y2, x1, y2, layer, w), ln(x1, y2, x1, y1, layer, w)]


def esp32c5_fp():
    # origin = module centre; module spans x -9..9, y -13.75..13.75 (antenna at -y)
    W, H = 18.0, 27.5
    top = -H / 2
    pads = []
    for n in range(1, 15):
        y = top + 7.99 + (n - 1) * 1.27
        pads.append(f'  (pad "{n}" smd rect (at -8.75 {y:.3f}) (size 1.5 0.9) (layers "F.Cu" "F.Paste" "F.Mask") (tstamp {U()}))')
    for n in range(15, 29):
        y = top + 7.99 + (28 - n) * 1.27
        pads.append(f'  (pad "{n}" smd rect (at 8.75 {y:.3f}) (size 1.5 0.9) (layers "F.Cu" "F.Paste" "F.Mask") (tstamp {U()}))')
    ex, ey = -W / 2 + 9.83, H / 2 - 10.922
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            pads.append(f'  (pad "29" smd rect (at {ex + i * 1.7:.3f} {ey + j * 1.7:.3f}) (size 1.3 1.3) (layers "F.Cu" "F.Paste" "F.Mask") (tstamp {U()}))')
    # thermal vias between the squares
    for i in (-0.5, 0.5):
        for j in (-0.5, 0.5):
            pads.append(f'  (pad "29" thru_hole circle (at {ex + i * 1.7:.3f} {ey + j * 1.7:.3f}) (size 0.6 0.6) (drill 0.3) (layers "*.Cu") (tstamp {U()}))')
    g = []
    g += rect(-W / 2, top, W / 2, H / 2, "F.Fab", 0.1)
    g += rect(-W / 2, top, W / 2, H / 2, "F.SilkS", 0.12)
    g.append(ln(-W / 2, top + 6.5, W / 2, top + 6.5, "F.SilkS", 0.12))
    g += rect(-W / 2 - 0.75, top - 0.25, W / 2 + 0.75, H / 2 + 0.25, "F.CrtYd", 0.05)
    # antenna keep-out: no copper on any layer under the antenna (extends past the board edge)
    ko = (f'  (zone (net 0) (net_name "") (layers "*.Cu") (tstamp {U()}) (name "ANT_KEEPOUT") (hatch edge 0.5)\n'
          f'    (connect_pads (clearance 0))\n    (min_thickness 0.25)\n'
          f'    (keepout (tracks not_allowed) (vias not_allowed) (pads not_allowed) (copperpour not_allowed) (footprints allowed))\n'
          f'    (fill (thermal_gap 0.5) (thermal_bridge_width 0.5))\n'
          f'    (polygon (pts (xy {-W / 2 - 1} {top - 6}) (xy {W / 2 + 1} {top - 6}) (xy {W / 2 + 1} {top + 6.5}) (xy {-W / 2 - 1} {top + 6.5})))\n  )')
    return f'''(footprint "ESP32-C5-WROOM-1" (version 20221018) (generator quadcan_gen)
  (layer "F.Cu")
  (descr "Espressif ESP32-C5-WROOM-1 module, land pattern per datasheet v1.3 Fig. 11-1")
  (tags "ESP32-C5 WROOM wifi6")
  (attr smd)
  (fp_text reference "REF**" (at 0 {top + 3:.2f}) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))) (tstamp {U()}))
  (fp_text value "ESP32-C5-WROOM-1" (at 0 {H / 2 + 1.5:.2f}) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))) (tstamp {U()}))
  (fp_text user "ANTENNA - keep clear" (at 0 {top + 4.5:.2f}) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))) (tstamp {U()}))
  (fp_circle (center -10.0 {top + 7.99:.3f}) (end -9.8 {top + 7.99:.3f}) (stroke (width 0.2) (type solid)) (fill solid) (layer "F.SilkS") (tstamp {U()}))
{chr(10).join(g)}
{chr(10).join(pads)}
{ko}
)
'''


if __name__ == "__main__":
    os.makedirs(os.path.join(KI, "QuadCAN.pretty"), exist_ok=True)
    open(os.path.join(KI, "QuadCAN.kicad_sym"), "w").write(symbols())
    open(os.path.join(KI, "QuadCAN.pretty", "ESP32-C5-WROOM-1.kicad_mod"), "w").write(esp32c5_fp())
    open(os.path.join(KI, "sym-lib-table"), "w").write(
        '(sym_lib_table\n  (lib (name "QuadCAN")(type "KiCad")(uri "${KIPRJMOD}/QuadCAN.kicad_sym")(options "")(descr "QuadCAN-C5 parts"))\n)\n')
    open(os.path.join(KI, "fp-lib-table"), "w").write(
        '(fp_lib_table\n  (lib (name "QuadCAN")(type "KiCad")(uri "${KIPRJMOD}/QuadCAN.pretty")(options "")(descr "QuadCAN-C5 footprints"))\n)\n')
    print("library written")
