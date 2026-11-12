# QuadCAN-C5 harness and swappable vehicle cables

The logger has **one** harness connector, J1: a Molex Micro-Fit 3.0, 2 × 7, right-angle (43045-1400).
Every vehicle cable plugs in there and carries power, ground and up to four CAN pairs. Two cable-ID
pins tell the firmware which cable is attached, so it picks sensible bitrates without a config file.

Mating parts: housing **Molex 43025-1400**, crimp terminals **Molex 43030-0007** (20–24 AWG),
crimper Molex 63819-0000 or a generic Micro-Fit crimper.

## J1 pinout (looking into the board connector)

| Pin | Signal | Pin | Signal |
|---|---|---|---|
| 1 | **VIN** 9–36 V (permanent battery) | 8 | **GND** |
| 2 | **GND** | 9 | **IGN** (optional switched +12/24 V) |
| 3 | CAN1_H | 10 | CAN1_L |
| 4 | CAN2_H | 11 | CAN2_L |
| 5 | CAN3_H | 12 | CAN3_L |
| 6 | CAN4_H | 13 | CAN4_L |
| 7 | CABLE_ID0 | 14 | CABLE_ID1 |

CANx_H and CANx_L sit directly above each other (3/10, 4/11, 5/12, 6/13), so each twisted pair
lands in one column. Keep the pairs twisted right up to the housing.

### Cable ID

ID pins are pulled up on the board. A cable identifies itself by tying ID pins to GND
(pin 2 or 8) **inside the plug**:

| ID1 (14) | ID0 (7) | Cable | Default config |
|---|---|---|---|
| open | open | none / bench | all channels 500 k, listen-only |
| open | **GND** | OBD-II | CAN1 500 k, listen-only |
| **GND** | open | J1939 (Deutsch 9-pin) | CAN1 + CAN2 250 k, listen-only |
| **GND** | **GND** | custom | whatever `/sd/quadcan.cfg` says |

`/sd/quadcan.cfg` always overrides the defaults (see the firmware README).

## Cable A: OBD-II (J1962 male)

| J1962 pin | Signal | → J1 pin |
|---|---|---|
| 16 | +12 V permanent | 1 |
| 4 | chassis ground | 2 |
| 5 | signal ground | 8 |
| 6 | CAN-H (ISO 15765, diagnostic) | 3 (CAN1_H) |
| 14 | CAN-L | 10 (CAN1_L) |
| 3 / 11 | 2nd CAN on some makes (e.g. Ford MS-CAN), *optional* | 4 / 11 (CAN2) |
| — | jumper inside the plug | 7 → 8 (ID0 to GND) |

Add **pigtails** for CAN2–CAN4 (twisted pairs, ~1 m, ending in a small locking connector such as
JST-SM or Deutsch DT-2) so you can tap buses elsewhere in the car without changing the cable.
An optional pigtail from J1 pin 9 to a switched-ignition fuse tap lets the logger know the key is on.
It wakes on CAN1 activity anyway, so this is a nice-to-have.

### Note for VW MQB (your Jetta)

On MQB cars the OBD port's pins 6/14 are the **diagnostic CAN behind the gateway (J533)**. It
carries almost no broadcast traffic: you get answers to diagnostic requests (UDS/OBD PIDs) and
little else. So:

* **OBD only:** set `can1_listen=0` and fit the CAN1 **TX_EN** jumper, then poll PIDs/UDS from
  the firmware or the phone (`SEND` command). This is what the Jetta Recorder app does over the OBDLink.
* **Raw powertrain / comfort / infotainment traffic:** tap the buses *behind* the gateway with
  the CAN2–CAN4 pigtails. The cleanest way is a T-harness at the gateway connector instead of
  splicing. Wire colours and pin positions vary by model year, so check the wiring diagram for
  your car before connecting anything. Leave those channels **listen-only with no TX jumper**.
* Leave all **TERM** jumpers off. The car's buses are already terminated.

## Cable B: heavy-duty J1939 (Deutsch HD10-9-1939, 9-pin)

| Deutsch pin | Signal | → J1 pin |
|---|---|---|
| A | battery ground | 2 and 8 |
| B | battery + (12 or 24 V, unswitched) | 1 |
| C | J1939 CAN-H (primary) | 3 (CAN1_H) |
| D | J1939 CAN-L (primary) | 10 (CAN1_L) |
| E | CAN shield | GND (pin 8) at the logger end only |
| H | 2nd J1939 CAN-H (green "Type 2" connectors) | 4 (CAN2_H) |
| J | 2nd J1939 CAN-L | 11 (CAN2_L) |
| F / G | J1708 (not used) | — |
| — | jumper inside the plug | 14 → 8 (ID1 to GND) |

* Input protection and the 60 V buck handle **24 V** trucks directly.
* Newer trucks may run J1939 at **500 kbit/s** (J1939-14). If CAN1 shows nothing but errors,
  set `can1=500000` (and `can2=500000`) in `quadcan.cfg`.
* The diagnostic port is normally already terminated. TERM jumpers stay off.

## Jumper rules (inside the lid window)

* **TERMn**: fit only when the logger is physically at the *end* of a bus, e.g. on a
  two-node bench setup. Never fit it when tapping a vehicle.
* **TX_ENn**: no jumper means that channel's transceiver input is held recessive by its internal
  pull-up, so the channel **cannot transmit**, whatever the firmware does. Fit it only on a channel
  you poll (usually CAN1 on OBD-II), *and* set `can<n>_listen=0`.
