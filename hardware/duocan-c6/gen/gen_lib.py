"""Generate the project-local KiCad library (XIAO ESP32-C6 symbol + socket footprint)."""
import os, uuid
from design import XIAO_PINS

HERE = os.path.dirname(os.path.abspath(__file__))
KI = os.path.join(HERE, "..", "kicad")


def sym():
    pins = []
    for n in range(1, 15):
        name, gpio = XIAO_PINS[n]
        label = f"{name} {gpio}".strip() if gpio else name
        label = label.replace(" ", "_").replace("/", "")
        if n <= 7:
            x, y, ang = -15.24, 7.62 - (n - 1) * 2.54, 0
        else:
            x, y, ang = 15.24, -7.62 + (n - 8) * 2.54, 180
        etype = {12: "power_out", 13: "power_in", 14: "power_in"}.get(n, "bidirectional")
        pins.append(
            f'      (pin {etype} line (at {x} {y:.2f} {ang}) (length 2.54)\n'
            f'        (name "{label}" (effects (font (size 1.016 1.016))))\n'
            f'        (number "{n}" (effects (font (size 1.016 1.016)))))')
    return f'''(kicad_symbol_lib (version 20220914) (generator duocan_gen)
  (symbol "XIAO_ESP32C6" (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 11.43 0) (effects (font (size 1.27 1.27))))
    (property "Value" "XIAO_ESP32C6" (at 0 -11.43 0) (effects (font (size 1.27 1.27))))
    (property "Footprint" "DuoCAN:XIAO_ESP32C6_Socket" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "https://wiki.seeedstudio.com/xiao_esp32c6_getting_started/" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
    (symbol "XIAO_ESP32C6_0_1"
      (rectangle (start -12.7 10.16) (end 12.7 -10.16) (stroke (width 0.254) (type default)) (fill (type background)))
    )
    (symbol "XIAO_ESP32C6_1_1"
{chr(10).join(pins)}
    )
  )
)
'''


def fp():
    pads, lines = [], []
    for n in range(1, 15):
        if n <= 7:
            x, y = -7.62, -7.62 + (n - 1) * 2.54
        else:
            x, y = 7.62, 7.62 - (n - 8) * 2.54
        shape = "rect" if n == 1 else "oval"
        pads.append(f'  (pad "{n}" thru_hole {shape} (at {x} {y:.2f}) (size 1.7 1.7) (drill 1) (layers "*.Cu" "*.Mask") (tstamp {uuid.uuid4()}))')

    def ln(x1, y1, x2, y2, layer, w):
        return f'  (fp_line (start {x1} {y1}) (end {x2} {y2}) (stroke (width {w}) (type solid)) (layer "{layer}") (tstamp {uuid.uuid4()}))'
    # XIAO body 17.8 x 21 mm; USB-C at -y end, overhangs ~1.2mm
    bx, by0, by1 = 8.9, -11.7, 9.3
    for (a, b, c, d) in [(-bx, by0, bx, by0), (bx, by0, bx, by1), (bx, by1, -bx, by1), (-bx, by1, -bx, by0)]:
        lines.append(ln(a, b, c, d, "F.SilkS", 0.12))
        lines.append(ln(a, b, c, d, "F.Fab", 0.1))
    # USB-C outline
    for (a, b, c, d) in [(-4.5, by0 - 1.5, 4.5, by0 - 1.5), (4.5, by0 - 1.5, 4.5, by0), (-4.5, by0, -4.5, by0 - 1.5)]:
        lines.append(ln(a, b, c, d, "F.Fab", 0.1))
    cy0, cy1, cx = by0 - 1.75, by1 + 0.25, bx + 0.25
    for (a, b, c, d) in [(-cx, cy0, cx, cy0), (cx, cy0, cx, cy1), (cx, cy1, -cx, cy1), (-cx, cy1, -cx, cy0)]:
        lines.append(ln(a, b, c, d, "F.CrtYd", 0.05))
    return f'''(footprint "XIAO_ESP32C6_Socket" (version 20221018) (generator duocan_gen)
  (layer "F.Cu")
  (descr "Seeed XIAO ESP32C6 on two 1x7 2.54mm female headers, rows 15.24mm apart, USB-C toward -Y")
  (attr through_hole)
  (fp_text reference "REF**" (at 0 -4) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))) (tstamp {uuid.uuid4()}))
  (fp_text value "XIAO_ESP32C6" (at 0 4) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))) (tstamp {uuid.uuid4()}))
  (fp_text user "USB-C" (at 0 -10) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))) (tstamp {uuid.uuid4()}))
{chr(10).join(lines)}
{chr(10).join(pads)}
)
'''


if __name__ == "__main__":
    os.makedirs(os.path.join(KI, "DuoCAN.pretty"), exist_ok=True)
    open(os.path.join(KI, "DuoCAN.kicad_sym"), "w").write(sym())
    open(os.path.join(KI, "DuoCAN.pretty", "XIAO_ESP32C6_Socket.kicad_mod"), "w").write(fp())
    open(os.path.join(KI, "sym-lib-table"), "w").write(
        '(sym_lib_table\n  (lib (name "DuoCAN")(type "KiCad")(uri "${KIPRJMOD}/DuoCAN.kicad_sym")(options "")(descr "DuoCAN-C6 project parts"))\n)\n')
    open(os.path.join(KI, "fp-lib-table"), "w").write(
        '(fp_lib_table\n  (lib (name "DuoCAN")(type "KiCad")(uri "${KIPRJMOD}/DuoCAN.pretty")(options "")(descr "DuoCAN-C6 project footprints"))\n)\n')
    print("library written")
