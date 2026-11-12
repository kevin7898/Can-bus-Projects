"""QuadCAN-C5 - single source of truth for the schematic and the PCB.

Four-channel CAN-FD logger:
  * ESP32-C5-WROOM-1-N8R8 (Wi-Fi 6 dual band, Wi-Fi Aware, 2x native CAN-FD)
  * 2x MCP2518FD SPI CAN-FD controllers for channels 3 and 4
  * 4x TCAN1044AV-Q1 transceivers (5 V bus side, 3.3 V logic, standby with bus wake)
  * microSD logging, PCF8523 RTC + CR1220, optional u-blox NEO-M9N (25 Hz) GPS
  * 9-36 V input (12 V cars, 24 V trucks), TI TPS54360 60 V buck, supercap hold-up
  * Molex Micro-Fit 2x7 harness connector -> swappable OBD-II / J1939 cables

gen_sch.py and gen_pcb.py both read PARTS, so the netlist cannot drift.
Edit this file, then run gen/build.sh.
"""

PROJECT = "quadcan-c5"
TITLE = "QuadCAN-C5: 4-channel CAN-FD logger"
REV = "1.0"


def P(ref, lib_id, fp, value, mpn, pins, block, note="", dnp=False):
    return dict(ref=ref, lib_id=lib_id, fp=fp, value=value, mpn=mpn,
                pins=pins, block=block, note=note, dnp=dnp)


R0603 = "Resistor_SMD:R_0603_1608Metric"
R1206 = "Resistor_SMD:R_1206_3216Metric"
C0603 = "Capacitor_SMD:C_0603_1608Metric"
C0805 = "Capacitor_SMD:C_0805_2012Metric"
C1206 = "Capacitor_SMD:C_1206_3216Metric"
C1210 = "Capacitor_SMD:C_1210_3225Metric"
LED0603 = "LED_SMD:LED_0603_1608Metric"
SOD123 = "Diode_SMD:D_SOD-123"
SMA = "Diode_SMD:D_SMA"
SMB = "Diode_SMD:D_SMB"
SOT23 = "Package_TO_SOT_SMD:SOT-23"


def R(ref, val, a, b, block, fp=R0603, mpn="", note=""):
    return P(ref, "Device:R", fp, val, mpn or f"{val} {fp.split('_')[-2]} 1%", {"1": a, "2": b}, block, note)


def C(ref, val, a, b, block, fp=C0603, mpn="", note=""):
    return P(ref, "Device:C", fp, val, mpn or f"{val} {fp.split('_')[-2]} X7R/X5R", {"1": a, "2": b}, block, note)


def LED(ref, color, k, a, block):
    return P(ref, "Device:LED", LED0603, color, f"0603 LED {color}", {"1": k, "2": a}, block)


PARTS = []
add = PARTS.append

# ------------------------------------------------------------------ harness
add(P("J1", "Connector_Generic:Conn_02x07_Odd_Even",
      "Connector_Molex:Molex_Micro-Fit_3.0_43045-1400_2x07_P3.00mm_Horizontal",
      "HARNESS", "Molex 43045-1400 (mates 43025-1400 + 43030 crimps)",
      {"1": "VIN_RAW", "2": "GND", "3": "CAN1_H", "4": "CAN2_H", "5": "CAN3_H",
       "6": "CAN4_H", "7": "CABLE_ID0_RAW", "8": "GND", "9": "IGN_RAW",
       "10": "CAN1_L", "11": "CAN2_L", "12": "CAN3_L", "13": "CAN4_L",
       "14": "CABLE_ID1_RAW"}, "power",
      "Harness: 1 VIN, 2/8 GND, 3-6 CAN1-4 H, 10-13 CAN1-4 L, 9 IGN, 7/14 cable ID"))

# ------------------------------------------------------------------ input protection + 5 V buck
add(P("F1", "Device:Fuse", "Fuse:Fuse_Littelfuse-NANO2-451_453", "2A",
      "Littelfuse 0453002.MR (Nano2 2A 125V)", {"1": "VIN_RAW", "2": "VIN_F"}, "power"))
add(P("D1", "Device:D_Zener", SMB, "SMBJ36A", "SMBJ36A 600W TVS (36V standoff)",
      {"1": "VIN_F", "2": "GND"}, "power", "TVS: load dump / jump start; reverse polarity blows F1 via D1"))
add(P("D2", "Device:D_Schottky", SMA, "B360A", "Diodes B360A-13-F 60V 3A",
      {"1": "VIN", "2": "VIN_F"}, "power", "Reverse polarity block"))
add(P("C1", "Device:C_Polarized", "Capacitor_THT:CP_Radial_D8.0mm_P3.50mm", "47uF 63V",
      "47uF 63V low-ESR electrolytic, 8mm", {"1": "VIN", "2": "GND"}, "power"))
add(C("C2", "2.2uF 100V", "VIN", "GND", "power", C1210))
add(C("C3", "2.2uF 100V", "VIN", "GND", "power", C1210))
add(P("U1", "Regulator_Switching:TPS54360DDA", "Package_SO:TI_SO-PowerPAD-8_ThermalVias",
      "TPS54360DDA", "TI TPS54360DDAR (60V 3.5A buck)",
      {"1": "BUCK_BOOT", "2": "VIN", "3": "BUCK_EN", "4": "BUCK_RT", "5": "BUCK_FB",
       "6": "BUCK_COMP", "7": "GND", "8": "BUCK_SW", "9": "GND"}, "power",
      "Values from TI TPS54360 datasheet 5V design example (Fig. 34)"))
add(R("R1", "523k", "VIN", "BUCK_EN", "power"))
add(R("R2", "84.5k", "BUCK_EN", "GND", "power", note="UVLO: start 8V, stop 6.25V"))
add(R("R3", "162k", "BUCK_RT", "GND", "power", note="fsw ~600 kHz"))
add(C("C4", "100nF", "BUCK_BOOT", "BUCK_SW", "power"))
add(P("D3", "Device:D_Schottky", SMA, "B360A", "Diodes B360A-13-F 60V 3A",
      {"1": "BUCK_SW", "2": "GND"}, "power", "Catch diode"))
add(P("L1", "Device:L", "Inductor_SMD:L_Bourns_SRP7028A_7.3x6.6mm", "8.2uH",
      "Bourns SRP7028A-8R2M", {"1": "BUCK_SW", "2": "+5V"}, "power"))
add(C("C5", "47uF 10V", "+5V", "GND", "power", C1210))
add(C("C6", "47uF 10V", "+5V", "GND", "power", C1210))
add(R("R4", "13.0k", "BUCK_COMP", "BUCK_CZ", "power"))
add(C("C7", "6.8nF", "BUCK_CZ", "GND", "power"))
add(C("C8", "39pF", "BUCK_COMP", "GND", "power", mpn="39pF 0603 C0G"))
add(R("R5", "53.6k", "+5V", "BUCK_FB", "power"))
add(R("R6", "10.2k", "BUCK_FB", "GND", "power"))

# ------------------------------------------------------------------ USB power, hold-up, 3.3 V
add(P("D4", "Device:D_Schottky", SOD123, "B5819W", "B5819W 40V 1A",
      {"1": "+5V", "2": "VBUS"}, "power", "USB can power the whole board for bench work"))
add(P("D5", "Device:D_Schottky", SOD123, "B5819W", "B5819W 40V 1A",
      {"1": "+5V_SYS", "2": "+5V"}, "power", "Isolates hold-up rail from buck/transceivers"))
add(R("R7", "47R", "+5V_SYS", "SCAP", "power", R1206, note="Supercap charge limit (~100 mA)"))
add(P("D6", "Device:D_Schottky", SOD123, "B5819W", "B5819W 40V 1A",
      {"1": "+5V_SYS", "2": "SCAP"}, "power", "Supercap discharge path"))
add(P("C9", "Device:C_Polarized", "Capacitor_THT:CP_Radial_D13.0mm_P5.00mm", "0.47F 5.5V",
      "Eaton KR-5R5V474-R supercap", {"1": "SCAP", "2": "GND"}, "power",
      "~4 s hold-up at 0.5 W: lets firmware close log files on power loss"))
add(P("U2", "Regulator_Linear:AP7361C-33E", "Package_TO_SOT_SMD:SOT-223-3_TabPin2",
      "AP7361C-33E", "Diodes AP7361C-33E-13 (1A LDO)",
      {"1": "+5V_SYS", "2": "GND", "3": "+3V3"}, "power"))
add(C("C10", "10uF", "+5V_SYS", "GND", "power", C0805))
add(C("C11", "22uF", "+3V3", "GND", "power", C0805))

# ------------------------------------------------------------------ sense inputs
add(R("R8", "1M", "VIN", "VIN_SENSE", "sense"))
add(R("R9", "100k", "VIN_SENSE", "GND", "sense", note="VIN/11 -> ADC; 36V = 3.27V"))
add(C("C12", "100nF", "VIN_SENSE", "GND", "sense"))
add(R("R10", "100k", "IGN_RAW", "IGN_B", "sense"))
add(R("R11", "10k", "IGN_B", "GND", "sense"))
add(P("Q1", "Transistor_BJT:MMBT3904", SOT23, "MMBT3904", "MMBT3904",
      {"1": "IGN_B", "2": "GND", "3": "IGN_N"}, "sense", "IGN > ~6.5V pulls IGN_N low (6-60V safe)"))
add(R("R12", "100k", "+3V3", "IGN_N", "sense"))
add(R("R13", "1k", "CABLE_ID0_RAW", "CABLE_ID0", "sense"))
add(R("R14", "100k", "+3V3", "CABLE_ID0", "sense"))
add(R("R15", "1k", "CABLE_ID1_RAW", "CABLE_ID1", "sense"))
add(R("R16", "100k", "+3V3", "CABLE_ID1", "sense", note="Cable grounds ID0/ID1 to identify itself"))

# ------------------------------------------------------------------ MCU
add(P("U3", "QuadCAN:ESP32-C5-WROOM-1", "QuadCAN:ESP32-C5-WROOM-1",
      "ESP32-C5-WROOM-1-N8R8", "Espressif ESP32-C5-WROOM-1-N8R8 (8MB flash, 8MB PSRAM)",
      {"1": "GND", "2": "+3V3", "3": "EN",
       # left edge (faces the CAN section): SPI on IOMUX pins, CAN1/CAN2, MCP chip selects
       "4": "SPI_MISO", "5": "CAN1_RXD", "6": "CAN1_TXD_MCU", "7": "CAN2_RXD", "8": "SPI_SCK",
       "9": "SPI_MOSI", "10": "CAN2_TXD_MCU", "11": "CAN3_CS", "12": "CAN4_CS",
       "13": "USB_DN", "14": "USB_DP",
       # right edge (faces I2C / GPS / LTE / SD)
       "15": "I2C_SCL", "16": "I2C_SDA", "17": "VIN_SENSE", "18": "ESP_GPS_RX", "21": "ESP_GPS_TX",
       "23": "SD_CS", "24": "ESP_LTE_RX", "25": "ESP_LTE_TX", "26": "CAN4_INT", "27": "CAN3_INT",
       "28": "GND", "29": "GND"},
      "mcu", "GPIO map: 2 MISO, 3 CAN1_RX (LP wake), 0 CAN1_TX, 1 CAN2_RX, 6 SCK, 7 MOSI, 8 CAN2_TX, "
             "9 CS3, 10 CS4, 28 SCL+BOOT, 5 SDA, 4 VIN_SENSE (ADC), 27 GPS_RX, 23 GPS_TX, 24 SD_CS, "
             "12/11 LTE, 25 INT4, 26 INT3"))
add(C("C13", "22uF", "+3V3", "GND", "mcu", C0805))
add(C("C14", "100nF", "+3V3", "GND", "mcu"))
add(R("R17", "10k", "+3V3", "EN", "mcu"))
add(C("C15", "1uF", "EN", "GND", "mcu"))
add(P("SW1", "Switch:SW_Push", "Button_Switch_SMD:SW_SPST_PTS810", "RESET", "C&K PTS810 SJM 250 SMTR LFS",
      {"1": "EN", "2": "GND"}, "mcu"))
add(P("SW2", "Switch:SW_Push", "Button_Switch_SMD:SW_SPST_PTS810", "BOOT", "C&K PTS810 SJM 250 SMTR LFS",
      {"1": "I2C_SCL", "2": "GND"}, "mcu", "Hold BOOT while tapping RESET for download mode"))
add(R("R18", "4.7k", "+3V3", "I2C_SDA", "mcu"))
add(R("R19", "4.7k", "+3V3", "I2C_SCL", "mcu"))
add(R("R20", "10k", "+3V3", "SD_CS", "mcu"))
add(R("R21", "10k", "+3V3", "CAN3_CS", "mcu"))
add(R("R22", "10k", "+3V3", "CAN4_CS", "mcu"))

# ------------------------------------------------------------------ USB-C
add(P("J2", "Connector:USB_C_Receptacle_USB2.0_16P", "Connector_USB:USB_C_Receptacle_HRO_TYPE-C-31-M-12",
      "USB-C", "HRO TYPE-C-31-M-12",
      {"A1": "GND", "A12": "GND", "B1": "GND", "B12": "GND", "A4": "VBUS", "A9": "VBUS",
       "B4": "VBUS", "B9": "VBUS", "A5": "USB_CC1", "B5": "USB_CC2", "A6": "USB_DP",
       "B6": "USB_DP", "A7": "USB_DN", "B7": "USB_DN", "S1": "GND"}, "usb",
      "Native USB Serial/JTAG: flashing, console, config"))
add(R("R23", "5.1k", "USB_CC1", "GND", "usb"))
add(R("R24", "5.1k", "USB_CC2", "GND", "usb"))
add(P("U4", "Power_Protection:USBLC6-2SC6", "Package_TO_SOT_SMD:SOT-23-6", "USBLC6-2SC6",
      "ST USBLC6-2SC6", {"1": "USB_DP", "6": "USB_DP", "3": "USB_DN", "4": "USB_DN",
                         "2": "GND", "5": "VBUS"}, "usb"))

# ------------------------------------------------------------------ CAN channels
STB_SRC = {1: "CAN1_STB", 2: "CAN2_STB", 3: "CAN3_STB", 4: "CAN4_STB"}
for n in range(1, 5):
    u = 4 + n                     # U5..U8 transceivers
    blk = f"can{n}"
    add(P(f"U{u}", "QuadCAN:TCAN1044AV", "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm", "TCAN1044AV-Q1",
          "TI TCAN1044AVDRQ1 (alt: NXP TJA1044GT/3)",
          {"1": f"CAN{n}_TXD", "2": "GND", "3": "+5V", "4": f"CAN{n}_RXD", "5": "+3V3",
           "6": f"CAN{n}_L", "7": f"CAN{n}_H", "8": STB_SRC[n]}, blk,
          "STB has internal pull-up: transceiver boots in standby"))
    add(C(f"C{20 + 2 * n}", "100nF", "+5V", "GND", blk))
    add(C(f"C{21 + 2 * n}", "100nF", "+3V3", "GND", blk))
    add(P(f"D{10 + n}", "Power_Protection:NUP2105L", SOT23, "NUP2105L", "onsemi NUP2105LT1G",
          {"1": f"CAN{n}_H", "2": f"CAN{n}_L", "3": "GND"}, blk))
    add(R(f"R{30 + n}", "120R", f"CAN{n}_H", f"CAN{n}_TERM", blk, R1206))
    add(LED(f"D{20 + n}", "RX yellow", f"CAN{n}_RXD", f"LED_RX{n}_A", blk))
    add(R(f"R{40 + n}", "1k", "+3V3", f"LED_RX{n}_A", blk))

# MCP2518FD for CAN3/CAN4
for n, u in ((3, 9), (4, 10)):
    blk = f"can{n}"
    add(P(f"U{u}", "Interface_CAN_LIN:MCP2517FD-xSL", "Package_SO:SOIC-14_3.9x8.7mm_P1.27mm",
          "MCP2518FD", "Microchip MCP2518FDT-E/SL",
          {"1": f"CAN{n}_TXD_MCU", "2": f"CAN{n}_RXD", "4": f"CAN{n}_INT", "6": "CLK40",
           "7": "GND", "9": STB_SRC[n], "10": "SPI_SCK", "11": "SPI_MOSI",
           "12": "SPI_MISO", "13": f"CAN{n}_CS", "14": "+3V3"}, blk,
          "INT0/XSTBY drives transceiver STB"))
    add(C(f"C{30 + n}", "100nF", "+3V3", "GND", blk))
    add(R(f"R{50 + n}", "10k", "+3V3", f"CAN{n}_INT", blk))

add(P("Y1", "Oscillator:ASE-xxxMHz", "Oscillator:Oscillator_SMD_Abracon_ASE-4Pin_3.2x2.5mm",
      "40MHz", "Abracon ASE-40.000MHZ-LC-T (3.3V CMOS)",
      {"1": "OSC_EN", "2": "GND", "3": "CLK40", "4": "+3V3"}, "can3",
      "One clock for both MCP2518FD; expander can stop it in sleep"))
add(C("C40", "100nF", "+3V3", "GND", "can3"))
add(R("R55", "10k", "+3V3", "OSC_EN", "can3"))

for n in range(1, 5):
    add(P(f"JP{n}", "Connector_Generic:Conn_01x02", "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical",
          f"TERM{n}", "1x2 2.54mm header + jumper cap", {"1": f"CAN{n}_TERM", "2": f"CAN{n}_L"}, f"can{n}",
          "Fit ONLY when the logger is a bus end" if n == 1 else ""))
    add(P(f"JP{n + 4}", "Connector_Generic:Conn_01x02", "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical",
          f"TX_EN{n}", "1x2 2.54mm header + jumper cap", {"1": f"CAN{n}_TXD_MCU", "2": f"CAN{n}_TXD"}, f"can{n}",
          "TX ENABLE: no jumper = channel physically cannot transmit" if n == 1 else ""))

# ------------------------------------------------------------------ microSD
add(P("J3", "Connector:Micro_SD_Card_Det2", "Connector_Card:microSD_HC_Hirose_DM3AT-SF-PEJM5",
      "microSD", "Hirose DM3AT-SF-PEJM5",
      {"1": "SD_DAT2", "2": "SD_CS", "3": "SPI_MOSI", "4": "+3V3", "5": "SPI_SCK",
       "6": "GND", "7": "SPI_MISO", "8": "SD_DAT1", "9": "GND", "10": "SD_DET", "11": "GND"},
      "sd", "SPI mode, shares the bus with the MCP2518FDs"))
add(R("R60", "10k", "+3V3", "SD_DAT1", "sd"))
add(R("R61", "10k", "+3V3", "SD_DAT2", "sd"))
add(R("R62", "10k", "+3V3", "SPI_MISO", "sd"))
add(R("R63", "100k", "+3V3", "SD_DET", "sd"))
add(C("C41", "10uF", "+3V3", "GND", "sd", C0805))
add(C("C42", "100nF", "+3V3", "GND", "sd"))

# ------------------------------------------------------------------ IO expander, LEDs, button
add(P("U11", "Interface_Expansion:TCA9535PWR", "Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm",
      "TCA9535PWR", "TI TCA9535PWR (I2C 0x20)",
      {"2": "GND", "3": "GND", "21": "GND", "22": "I2C_SCL", "23": "I2C_SDA", "24": "+3V3",
       "12": "GND", "4": "CAN1_STB", "5": "CAN2_STB", "6": "LED_STAT_N", "7": "LED_SD_N",
       "8": "LED_LINK_N", "9": "OSC_EN", "10": "GPS_PWR_N", "11": "LTE_PWRKEY",
       "13": "IGN_N", "14": "CABLE_ID0", "15": "CABLE_ID1", "16": "SD_DET",
       "17": "GPS_RESET_N", "18": "LTE_STATUS", "19": "BTN_MARK_N"}, "io",
      "Powers up as inputs: STB lines float high = transceivers in standby"))
add(C("C43", "100nF", "+3V3", "GND", "io"))
for i, (nm, col) in enumerate((("STAT", "green"), ("SD", "blue"), ("LINK", "blue"))):
    add(LED(f"D{30 + i}", col, f"LED_{nm}_N", f"LED_{nm}_A", "io"))
    add(R(f"R{70 + i}", "1k", "+3V3", f"LED_{nm}_A", "io"))
add(P("SW3", "Switch:SW_Push", "Button_Switch_SMD:SW_SPST_PTS810", "MARK", "C&K PTS810 SJM 250 SMTR LFS",
      {"1": "BTN_MARK_N", "2": "GND"}, "io", "Drops an event marker into the log"))
add(R("R73", "100k", "+3V3", "BTN_MARK_N", "io"))

# ------------------------------------------------------------------ RTC
add(P("U12", "Timer_RTC:PCF8523T", "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm", "PCF8523T",
      "NXP PCF8523T/1 (I2C 0x68)",
      {"1": "RTC_XI", "2": "RTC_XO", "3": "VBAT_RTC", "4": "GND", "5": "I2C_SDA",
       "6": "I2C_SCL", "8": "+3V3"}, "rtc"))
add(P("Y2", "Device:Crystal", "Crystal:Crystal_SMD_3215-2Pin_3.2x1.5mm", "32.768kHz",
      "Abracon ABS07-32.768KHZ-7-T (7pF)", {"1": "RTC_XI", "2": "RTC_XO"}, "rtc"))
add(P("BT1", "Device:Battery_Cell", "Battery:BatteryHolder_Keystone_3000_1x12mm", "CR1220",
      "Keystone 3000 + CR1220", {"1": "VBAT_RTC", "2": "GND"}, "rtc"))
add(C("C44", "100nF", "+3V3", "GND", "rtc"))

# ------------------------------------------------------------------ GPS (optional, DNP-able)
add(P("U13", "RF_GPS:NEO-M9N", "RF_GPS:ublox_NEO", "NEO-M9N",
      "u-blox NEO-M9N-00B (25 Hz)",
      {"3": "GPS_PPS", "7": "GND", "8": "GPS_RESET_N", "9": "GPS_VCC_RF", "10": "GND",
       "11": "GPS_RF", "12": "GND", "13": "GND", "20": "GPS_TXD", "21": "GPS_RXD",
       "22": "+3V3", "23": "GPS_3V3", "24": "GND"}, "gps",
      "Optional: leave U13 + bias-T unpopulated to rely on the phone's GPS"))
add(P("Q2", "Transistor_FET:AO3401A", SOT23, "AO3401A", "AOS AO3401A P-MOSFET",
      {"1": "GPS_PWR_N", "2": "+3V3", "3": "GPS_3V3"}, "gps", "GPS power switch"))
add(R("R80", "100k", "+3V3", "GPS_PWR_N", "gps"))
add(C("C45", "10uF", "GPS_3V3", "GND", "gps", C0805))
add(C("C46", "100nF", "GPS_3V3", "GND", "gps"))
add(R("R81", "1k", "ESP_GPS_TX", "GPS_RXD", "gps"))
add(R("R82", "1k", "GPS_TXD", "ESP_GPS_RX", "gps"))
add(R("R83", "22R", "GPS_VCC_RF", "GPS_BIAS", "gps", R1206,
      note="Bias-T per NEO-M9N integration manual; limits short-circuit current"))
add(C("C47", "100nF", "GPS_BIAS", "GND", "gps"))
add(P("L2", "Device:L", "Inductor_SMD:L_0603_1608Metric", "27nH", "Murata LQW18AN27NG00 (27nH)",
      {"1": "GPS_BIAS", "2": "GPS_RF"}, "gps"))
add(P("J4", "Connector:Conn_Coaxial", "Connector_Coaxial:U.FL_Hirose_U.FL-R-SMT-1_Vertical",
      "GPS ANT", "Hirose U.FL-R-SMT-1(10) - active antenna", {"1": "GPS_RF", "2": "GND"}, "gps"))
add(LED("D33", "GPS green", "GND", "LED_GPS_A", "gps"))
add(R("R84", "1k", "GPS_PPS", "LED_GPS_A", "gps", note="Blinks once per second with a fix"))

# ------------------------------------------------------------------ expansion
add(P("J5", "Connector_Generic:Conn_01x08", "Connector_PinHeader_2.54mm:PinHeader_1x08_P2.54mm_Vertical",
      "LTE", "1x8 2.54mm header",
      {"1": "VIN", "2": "GND", "3": "+3V3", "4": "ESP_LTE_TX", "5": "ESP_LTE_RX",
       "6": "LTE_PWRKEY", "7": "LTE_STATUS", "8": "GND"}, "exp",
      "LTE Cat-1 add-on (e.g. SIMCom A7670 carrier with its own regulator, fed from VIN)"))
add(P("J6", "Connector_Generic_MountingPin:Conn_01x04_MountingPin",
      "Connector_JST:JST_SH_SM04B-SRSS-TB_1x04-1MP_P1.00mm_Horizontal", "QWIIC", "JST SM04B-SRSS-TB",
      {"1": "GND", "2": "+3V3", "3": "I2C_SDA", "4": "I2C_SCL", "MP": "GND"}, "exp"))

for i in range(1, 5):
    add(P(f"H{i}", "Mechanical:MountingHole", "MountingHole:MountingHole_3.2mm_M3", "M3", "", {}, "mech"))

# PWR_FLAG nets (driven from off-sheet sources)
PWR_FLAGS = ["VIN_RAW", "GND", "VIN", "+5V", "+5V_SYS", "+3V3", "VBUS", "GPS_3V3", "VBAT_RTC", "SCAP"]

BLOCK_TITLES = {
    "power": "POWER: 9-36V -> fuse -> TVS -> reverse diode -> TPS54360 5V buck -> hold-up -> 3.3V LDO",
    "sense": "VIN / IGNITION / CABLE-ID SENSE",
    "mcu": "MCU: ESP32-C5-WROOM-1 (2x native CAN-FD, Wi-Fi 6 + Wi-Fi Aware)",
    "usb": "USB-C (native USB Serial/JTAG)",
    "can1": "CAN1 (native CAN-FD 0) - OBD gateway pins 6/14",
    "can2": "CAN2 (native CAN-FD 1)",
    "can3": "CAN3 (MCP2518FD #1) + shared 40MHz clock",
    "can4": "CAN4 (MCP2518FD #2)",
        "sd": "microSD (SPI)",
    "io": "IO EXPANDER, STATUS LEDS, MARK BUTTON",
    "rtc": "RTC + CR1220 backup",
    "gps": "GPS (optional) NEO-M9N 25Hz + active antenna bias-T",
    "exp": "EXPANSION: LTE header, Qwiic",
    "mech": "MECHANICAL",
}

# ESP32-C5 pin naming for the custom symbol: number -> (name, left/right)
ESP32C5_PINS = {
    1: "GND", 2: "3V3", 3: "EN", 4: "IO2", 5: "IO3", 6: "IO0", 7: "IO1", 8: "IO6",
    9: "IO7", 10: "IO8", 11: "IO9", 12: "IO10", 13: "IO13/USB_D-", 14: "IO14/USB_D+",
    15: "IO28", 16: "IO5", 17: "IO4", 18: "IO27", 19: "NC/IO15", 20: "NC", 21: "IO23",
    22: "NC", 23: "IO24", 24: "RX0/IO12", 25: "TX0/IO11", 26: "IO25", 27: "IO26",
    28: "GND", 29: "EPAD_GND",
}


def nets():
    out = {}
    for p in PARTS:
        for pin, n in p["pins"].items():
            out.setdefault(n, []).append((p["ref"], pin))
    return out


def check():
    refs = [p["ref"] for p in PARTS]
    dup = {r for r in refs if refs.count(r) > 1}
    assert not dup, f"duplicate refs {dup}"
    single = {n: c for n, c in nets().items() if len(c) < 2}
    return single


if __name__ == "__main__":
    for n, conns in sorted(nets().items()):
        print(f"{n:16s} {len(conns):3d} {conns if len(conns) < 6 else ''}")
    print("single-pin nets:", check())
    print(len(PARTS), "parts", len(nets()), "nets")
