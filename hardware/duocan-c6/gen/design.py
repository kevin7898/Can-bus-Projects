"""Single source of truth for the DuoCAN-C6 board.

Both the KiCad schematic (gen_sch.py) and the PCB (gen_pcb.py) are generated
from the PARTS table below, so the netlist cannot drift between them.

Each part:
  ref, lib_id (KiCad symbol), footprint, value, mpn/lcsc,
  pins {pin_number: net}, sch (x, y) in mm, pcb (x, y, rot_deg, side) in mm
PCB coordinates are board-local (origin = top-left board corner, y down).
"""

BOARD_W = 64.0
BOARD_H = 44.0

# Net classes: name -> (track width mm, clearance mm)
POWER_NETS = {"VBAT_IN": 0.8, "VBAT_F": 0.8, "VIN_PROT": 0.8,
              "+5V_REG": 0.6, "+5V": 0.6, "+3V3": 0.4}
SIGNAL_WIDTH = 0.25
CAN_WIDTH = 0.3

XIAO = "DuoCAN:XIAO_ESP32C6"


def P(ref, lib_id, fp, value, mpn, pins, sch, pcb, note=""):
    return dict(ref=ref, lib_id=lib_id, fp=fp, value=value, mpn=mpn,
                pins=pins, sch=sch, pcb=pcb, note=note)


R0805 = "Resistor_SMD:R_0805_2012Metric"
C0805 = "Capacitor_SMD:C_0805_2012Metric"
C1206 = "Capacitor_SMD:C_1206_3216Metric"
R1206 = "Resistor_SMD:R_1206_3216Metric"
L0805 = "LED_SMD:LED_0805_2012Metric"

PARTS = [
    # ---------------- Vehicle connector ----------------
    P("J1", "Connector_Generic:Conn_01x06",
      "Connector_Phoenix_MC:PhoenixContact_MCV_1,5_6-G-3.5_1x06_P3.50mm_Vertical",
      "VEHICLE", "Phoenix MCV 1,5/6-G-3,5 + MC 1,5/6-ST-3,5 plug",
      {"1": "VBAT_IN", "2": "GND", "3": "CAN1_H", "4": "CAN1_L",
       "5": "CAN2_H", "6": "CAN2_L"},
      (25.4, 63.5), (4.0, 7.0, 270, "F"),
      "Pluggable 3.5 mm terminal: 12V, GND, CAN1 H/L, CAN2 H/L"),

    # ---------------- Power input protection ----------------
    P("F1", "Device:Polyfuse", "Fuse:Fuse_1812_4532Metric", "500mA/30V PTC",
      "Littelfuse 1812L050/30DR", {"1": "VBAT_IN", "2": "VBAT_F"},
      (50.8, 38.1), (13.5, 4.5, 0, "F")),
    P("D1", "Device:D_Zener", "Diode_SMD:D_SMB", "SMBJ24A",
      "SMBJ24A (600W TVS, unidirectional)", {"1": "VBAT_F", "2": "GND"},
      (63.5, 45.72), (13.5, 9.0, 180, "F"),
      "Clamps load-dump / ignition spikes; conducts on reverse polarity and trips F1"),
    P("D2", "Device:D_Schottky", "Diode_SMD:D_SMA", "SS34",
      "SS34 40V 3A Schottky", {"1": "VIN_PROT", "2": "VBAT_F"},
      (73.66, 38.1), (20.5, 4.5, 180, "F"), "Reverse-polarity blocking"),
    P("C1", "Device:C", C1206, "10uF 50V", "X7R/X5R 1206 50V",
      {"1": "VIN_PROT", "2": "GND"}, (86.36, 45.72), (20.5, 9.0, 0, "F")),
    P("U1", "Regulator_Switching:TSR_1-2450",
      "Converter_DCDC:Converter_DCDC_TRACO_TSR-1_THT", "TSR 1-2450",
      "Traco TSR 1-2450 (4.75-36V in, 5V 1A)",
      {"1": "VIN_PROT", "2": "GND", "3": "+5V_REG"},
      (101.6, 38.1), (26.5, 8.0, 0, "F"),
      "Drop-in alt: RECOM R-78E5.0-1.0 (max 28V in)"),
    P("C2", "Device:C", C0805, "22uF 10V", "X5R 0805 10V",
      {"1": "+5V_REG", "2": "GND"}, (116.84, 45.72), (37.0, 9.0, 90, "F")),
    P("D3", "Device:D_Schottky", "Diode_SMD:D_SMA", "SS34",
      "SS34 40V 3A Schottky", {"1": "+5V", "2": "+5V_REG"},
      (127.0, 38.1), (40.0, 4.5, 180, "F"),
      "Stops the regulator back-feeding into USB and vice versa"),

    # ---------------- Battery voltage sense ----------------
    P("R1", "Device:R", R0805, "100k 1%", "0805 1%",
      {"1": "VIN_PROT", "2": "VSENSE"}, (152.4, 38.1), (33.5, 12.5, 90, "F")),
    P("R2", "Device:R", R0805, "15k 1%", "0805 1%",
      {"1": "VSENSE", "2": "GND"}, (152.4, 50.8), (33.5, 16.5, 90, "F")),
    P("C3", "Device:C", C0805, "100nF", "X7R 0805",
      {"1": "VSENSE", "2": "GND"}, (165.1, 50.8), (36.0, 16.5, 90, "F")),

    # ---------------- XIAO ESP32-C6 (socketed) ----------------
    P("U2", XIAO, "DuoCAN:XIAO_ESP32C6_Socket", "Seeed XIAO ESP32C6",
      "Seeed 113991254 + 2x 1x7 2.54mm female header",
      {"1": "VSENSE", "2": "CAN1_TX", "3": "CAN1_RX", "4": "CAN1_S",
       "5": "I2C_SDA", "6": "I2C_SCL", "7": "CAN2_TX",
       "8": "CAN2_RX", "9": "CAN2_S", "10": "LED_STAT", "11": "GPIO18",
       "12": "+3V3", "13": "GND", "14": "+5V"},
      (215.9, 50.8), (51.0, 22.0, 270, "F")),

    # ---------------- CAN channel 1 ----------------
    P("U3", "Interface_CAN_LIN:TJA1051T-3",
      "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm", "TJA1051T/3",
      "NXP TJA1051T/3,118 (LCSC C38695)",
      {"1": "CAN1_TX", "2": "GND", "3": "+5V", "4": "CAN1_RX", "5": "+3V3",
       "6": "CAN1_L", "7": "CAN1_H", "8": "CAN1_S"},
      (50.8, 101.6), (25.0, 20.5, 0, "F")),
    P("C4", "Device:C", C0805, "100nF", "X7R 0805",
      {"1": "+5V", "2": "GND"}, (30.48, 116.84), (25.0, 15.5, 90, "F")),
    P("C5", "Device:C", C0805, "100nF", "X7R 0805",
      {"1": "+3V3", "2": "GND"}, (35.56, 116.84), (30.0, 22.0, 0, "F")),
    P("R3", "Device:R", R0805, "10k", "0805",
      {"1": "+3V3", "2": "CAN1_S"}, (71.12, 88.9), (30.0, 18.0, 0, "F"),
      "Pull-up: transceiver is SILENT (listen-only) until firmware drives S low"),
    P("D4", "Power_Protection:NUP2105L", "Package_TO_SOT_SMD:SOT-23",
      "NUP2105L", "onsemi NUP2105LT1G CAN ESD",
      {"1": "CAN1_H", "2": "CAN1_L", "3": "GND"},
      (25.4, 101.6), (11.0, 19.0, 90, "F")),
    P("R4", "Device:R", R1206, "120R", "1206 1% 1/4W",
      {"1": "CAN1_H", "2": "CAN1_TERM"}, (25.4, 132.08), (16.5, 15.5, 0, "F"),
      "Bus termination, enabled by JP1"),
    P("JP1", "Connector_Generic:Conn_01x02",
      "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical",
      "TERM1", "2.54mm header + jumper cap",
      {"1": "CAN1_TERM", "2": "CAN1_L"}, (40.64, 132.08), (17.0, 22.0, 90, "F"),
      "Fit cap only when this board is a bus END (not when tapping a car)"),
    P("D5", "Device:LED", L0805, "RX1 yellow", "0805 LED",
      {"1": "CAN1_RX", "2": "LED_RX1_A"}, (71.12, 114.3), (31.0, 26.0, 0, "F")),
    P("R5", "Device:R", R0805, "1k", "0805",
      {"1": "+3V3", "2": "LED_RX1_A"}, (83.82, 114.3), (31.0, 28.5, 0, "F")),

    # ---------------- CAN channel 2 ----------------
    P("U4", "Interface_CAN_LIN:TJA1051T-3",
      "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm", "TJA1051T/3",
      "NXP TJA1051T/3,118 (LCSC C38695)",
      {"1": "CAN2_TX", "2": "GND", "3": "+5V", "4": "CAN2_RX", "5": "+3V3",
       "6": "CAN2_L", "7": "CAN2_H", "8": "CAN2_S"},
      (127.0, 101.6), (25.0, 34.0, 0, "F")),
    P("C6", "Device:C", C0805, "100nF", "X7R 0805",
      {"1": "+5V", "2": "GND"}, (106.68, 116.84), (20.0, 34.0, 90, "F")),
    P("C7", "Device:C", C0805, "100nF", "X7R 0805",
      {"1": "+3V3", "2": "GND"}, (111.76, 116.84), (30.0, 35.5, 0, "F")),
    P("R6", "Device:R", R0805, "10k", "0805",
      {"1": "+3V3", "2": "CAN2_S"}, (147.32, 88.9), (30.0, 31.5, 0, "F"),
      "Pull-up: transceiver is SILENT (listen-only) until firmware drives S low"),
    P("D6", "Power_Protection:NUP2105L", "Package_TO_SOT_SMD:SOT-23",
      "NUP2105L", "onsemi NUP2105LT1G CAN ESD",
      {"1": "CAN2_H", "2": "CAN2_L", "3": "GND"},
      (101.6, 101.6), (11.0, 27.0, 90, "F")),
    P("R7", "Device:R", R1206, "120R", "1206 1% 1/4W",
      {"1": "CAN2_H", "2": "CAN2_TERM"}, (101.6, 132.08), (16.5, 39.0, 0, "F"),
      "Bus termination, enabled by JP2"),
    P("JP2", "Connector_Generic:Conn_01x02",
      "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical",
      "TERM2", "2.54mm header + jumper cap",
      {"1": "CAN2_TERM", "2": "CAN2_L"}, (116.84, 132.08), (17.0, 30.0, 90, "F")),
    P("D7", "Device:LED", L0805, "RX2 yellow", "0805 LED",
      {"1": "CAN2_RX", "2": "LED_RX2_A"}, (147.32, 114.3), (31.0, 39.5, 0, "F")),
    P("R8", "Device:R", R0805, "1k", "0805",
      {"1": "+3V3", "2": "LED_RX2_A"}, (160.02, 114.3), (31.0, 42.0, 0, "F")),

    # ---------------- Indicators / expansion ----------------
    P("D8", "Device:LED", L0805, "PWR green", "0805 LED",
      {"1": "GND", "2": "LED_PWR_A"}, (193.04, 101.6), (44.0, 37.5, 0, "F")),
    P("R9", "Device:R", R0805, "2k2", "0805",
      {"1": "+3V3", "2": "LED_PWR_A"}, (205.74, 101.6), (44.0, 40.0, 0, "F")),
    P("D9", "Device:LED", L0805, "STAT blue", "0805 LED",
      {"1": "LED_STAT_K", "2": "LED_STAT"}, (193.04, 124.46), (50.0, 37.5, 0, "F")),
    P("R10", "Device:R", R0805, "1k", "0805",
      {"1": "LED_STAT_K", "2": "GND"}, (205.74, 124.46), (50.0, 40.0, 0, "F")),
    P("J2", "Connector_Generic_MountingPin:Conn_01x04_MountingPin",
      "Connector_JST:JST_SH_SM04B-SRSS-TB_1x04-1MP_P1.00mm_Horizontal",
      "QWIIC", "JST SM04B-SRSS-TB",
      {"1": "GND", "2": "+3V3", "3": "I2C_SDA", "4": "I2C_SCL", "MP": "GND"},
      (241.3, 101.6), (46.0, 4.0, 180, "F"), "Qwiic / STEMMA QT I2C port"),
    P("R11", "Device:R", R0805, "4k7", "0805",
      {"1": "+3V3", "2": "I2C_SDA"}, (228.6, 88.9), (40.0, 10.0, 90, "F")),
    P("R12", "Device:R", R0805, "4k7", "0805",
      {"1": "+3V3", "2": "I2C_SCL"}, (233.68, 88.9), (42.5, 10.0, 90, "F")),
    P("J3", "Connector_Generic:Conn_01x04",
      "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical",
      "AUX", "2.54mm 1x4 header",
      {"1": "+5V", "2": "+3V3", "3": "GPIO18", "4": "GND"},
      (241.3, 127.0), (58.0, 39.5, 90, "F"), "Spare GPIO18 + power"),

    # ---------------- Mechanical ----------------
    P("H1", "Mechanical:MountingHole", "MountingHole:MountingHole_3.2mm_M3",
      "M3", "", {}, (254.0, 38.1), (3.5, 3.5, 0, "F")),
    P("H2", "Mechanical:MountingHole", "MountingHole:MountingHole_3.2mm_M3",
      "M3", "", {}, (264.16, 38.1), (60.5, 3.5, 0, "F")),
    P("H3", "Mechanical:MountingHole", "MountingHole:MountingHole_3.2mm_M3",
      "M3", "", {}, (254.0, 50.8), (3.5, 40.5, 0, "F")),
    P("H4", "Mechanical:MountingHole", "MountingHole:MountingHole_3.2mm_M3",
      "M3", "", {}, (264.16, 50.8), (60.5, 40.5, 0, "F")),
]

# XIAO ESP32-C6 pinout (Seeed wiki): pad number -> (label, GPIO)
XIAO_PINS = {
    1: ("D0", "GPIO0 / ADC"), 2: ("D1", "GPIO1"), 3: ("D2", "GPIO2"),
    4: ("D3", "GPIO21"), 5: ("D4", "GPIO22 / SDA"), 6: ("D5", "GPIO23 / SCL"),
    7: ("D6", "GPIO16 / U0TX"), 8: ("D7", "GPIO17 / U0RX"),
    9: ("D8", "GPIO19"), 10: ("D9", "GPIO20"), 11: ("D10", "GPIO18"),
    12: ("3V3", ""), 13: ("GND", ""), 14: ("5V", ""),
}


def nets():
    out = {}
    for p in PARTS:
        for pin, n in p["pins"].items():
            out.setdefault(n, []).append((p["ref"], pin))
    return out


if __name__ == "__main__":
    for n, conns in sorted(nets().items()):
        print(f"{n:12s} {conns}")
