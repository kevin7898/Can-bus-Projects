# Pre-order review checklist

Everything in `kicad/` is generated from `gen/design.py`. These checks pass automatically:

* the schematic netlist exported by `kicad-cli` matches `design.py` exactly (`gen/check_netlist.py`)
* no courtyard overlaps (`gen/check_place.py`)
* KiCad DRC on the routed board (`fab/drc.txt`)

Software can't judge everything below. Open `kicad/quadcan-c5.kicad_pro` in KiCad 7+ and spend
30 minutes on this list before spending money. A board spin costs far more than the review.

## Footprints made for this project

- [ ] **ESP32-C5-WROOM-1** (`kicad/QuadCAN.pretty`). Drawn from Espressif's datasheet v1.3,
      Fig. 11-1: pads 1.5 × 0.9 mm @ 1.27 mm, rows 17.5 mm apart, pad 1 centre 7.99 mm below
      the antenna edge, 3 × 3 thermal pad centred 9.83 mm from the left edge / 10.922 mm above the
      bottom edge. Print the copper layer 1:1 and lay a real module on it.
- [ ] Antenna keep-out: no copper on any layer under the top 6.5 mm of the module, and the module's
      antenna end sits flush with the board edge.

## Connector orientation (the classic generated-board mistake)

- [ ] **J1 Micro-Fit**: mating face points off the *left* edge; pin 1 (VIN) is the lowest pin of the column nearest the board edge (square pad).
- [ ] **J2 USB-C**: opening faces off the *top* edge.
- [ ] **J3 microSD**: card slot opens off the *bottom* edge.
- [ ] **J4 u.FL** clear of the GPS module body; **J6 Qwiic** opening faces the right edge.

## Electrical

- [ ] TVS **D1** cathode on VIN_F, reverse diode **D2** cathode toward the buck, catch diode
      **D3** cathode on SW. Check the silkscreen bars match.
- [ ] Buck loop: **C2/C3 → U1 VIN/GND → D3** as tight as possible. The router placed the
      SW node; inspect it and shorten by hand if needed. This is the noisiest node on the board.
- [ ] **U1 thermal pad** has vias to the In1 ground plane.
- [ ] Supercap **C9** polarity (+ on SCAP), bulk cap **C1** polarity (+ on VIN).
- [ ] USB D+/D− are routed as a pair, roughly equal length, over solid ground.
- [ ] Each CANx_H/L pair runs together from J1 → ESD → transceiver.
- [ ] GPS RF trace **L2 → J4 → U13 pin 11** is short and has ground on both sides.
      It isn't impedance-controlled; keep it under ~10 mm.

## Assembly notes

- [ ] U13 (GPS), its bias-T (R83, C47, L2), Q2/R80/C45/C46 and J4 are optional.
- [ ] Order MCP2518FD in **SOIC-14** (`MCP2518FDT-E/SL` or `-H/SL`), not the VDFN.
- [ ] TCAN1044**AV** (with V suffix = VIO pin). The non-V part has pin 5 NC and will not work.
- [ ] Crystal Y2 must be a **7 pF** load type (PCF8523 default CAP_SEL).
