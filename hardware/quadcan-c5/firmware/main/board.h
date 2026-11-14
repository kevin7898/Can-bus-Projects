// QuadCAN-C5 board pin map - must match hardware/quadcan-c5/gen/design.py (U3 pin table)
#pragma once
#include "driver/gpio.h"

// ---- CAN channels -------------------------------------------------------
// CAN1/CAN2: ESP32-C5 on-chip CAN-FD controllers (TWAI0/TWAI1)
#define PIN_CAN1_TX        GPIO_NUM_0
#define PIN_CAN1_RX        GPIO_NUM_3    // LP GPIO -> deep-sleep wake on bus activity
#define PIN_CAN2_TX        GPIO_NUM_8
#define PIN_CAN2_RX        GPIO_NUM_1
// CAN3/CAN4: MCP2518FD on SPI2 (shared with microSD)
#define PIN_SPI_MISO       GPIO_NUM_2    // IOMUX FSPIQ
#define PIN_SPI_SCK        GPIO_NUM_6    // IOMUX FSPICLK
#define PIN_SPI_MOSI       GPIO_NUM_7    // IOMUX FSPID
#define PIN_CAN3_CS        GPIO_NUM_9
#define PIN_CAN4_CS        GPIO_NUM_10
#define PIN_MCP_INT        GPIO_NUM_23   // U19 AND of independent active-low MCP interrupts
#define PIN_SD_CS          GPIO_NUM_24

// ---- I2C: TCA9535 expander (0x20), PCF8523 RTC (0x68), Qwiic ------------
#define PIN_I2C_SDA        GPIO_NUM_25
#define PIN_I2C_SCL        GPIO_NUM_28   // also the BOOT strap / BOOT button
#define I2C_ADDR_EXPANDER  0x20
#define I2C_ADDR_POWER     0x21
#define I2C_ADDR_BAT_ADC   0x48
#define I2C_ADDR_RTC       0x68

// ---- deep-sleep wake inputs (all LP GPIOs, all active low) ----------------
// CAN1/CAN2: the transceiver in standby pulls RXD low on bus activity (PIN_CAN1_RX / PIN_CAN2_RX).
// WAKE_N:    diode-OR of CAN3_RXD, CAN4_RXD and the ignition input.
#define PIN_WAKE_N         GPIO_NUM_5
#define WAKE_PIN_MASK      ((1ULL << PIN_CAN1_RX) | (1ULL << PIN_CAN2_RX) | (1ULL << PIN_WAKE_N))

// ---- analog --------------------------------------------------------------
#define PIN_VIN_SENSE      GPIO_NUM_4    // ADC1_CH3, VIN / 11
#define VIN_DIVIDER        11.0f
#define VIN_DIODE_DROP_V   0.45f         // D2 reverse-polarity diode sits before the divider

// ---- UARTs ---------------------------------------------------------------
#define PIN_GPS_TX         GPIO_NUM_27   // boot strap -> U20 -> NEO-M9N RXD
#define PIN_GPS_RX         GPIO_NUM_26   // NEO-M9N TXD -> ESP
#define PIN_LTE_TX         GPIO_NUM_11   // U0TXD -> LTE module RXD
#define PIN_LTE_RX         GPIO_NUM_12   // U0RXD <- LTE module TXD

// ---- TCA9535 expander bit numbers (port0 = 0..7, port1 = 8..15) ---------
enum {
    XP_CAN1_STB = 0, XP_CAN2_STB, XP_LED_STAT_N, XP_LED_SD_N, XP_LED_LINK_N, XP_OSC_EN,
    XP_GPS_PWR_N, XP_LTE_PWRKEY,
    XP_IGN_N = 8, XP_CABLE_ID0, XP_CABLE_ID1, XP_SD_DET, XP_GPS_RESET_N, XP_LTE_STATUS,
    XP_BTN_MARK_N, XP_SD_PWR_N,
};
// Pins the firmware drives. Everything else stays an input, which is also the reset state:
// STB lines float high (transceivers in standby), GPS and SD card power off, oscillator enabled.
#define XP_OUTPUT_MASK  ((1u << XP_CAN1_STB) | (1u << XP_CAN2_STB) | (1u << XP_LED_STAT_N) | \
                         (1u << XP_LED_SD_N) | (1u << XP_LED_LINK_N) | (1u << XP_OSC_EN) |   \
                         (1u << XP_GPS_PWR_N) | (1u << XP_LTE_PWRKEY) | (1u << XP_SD_PWR_N))

// Cable identification (cable grounds ID0/ID1; open = 1)
typedef enum {
    CABLE_NONE = 3,        // ID1=1 ID0=1 : nothing / bench
    CABLE_OBD2 = 2,        // ID1=1 ID0=0 : OBD-II (CAN1 = pins 6/14)
    CABLE_J1939 = 1,       // ID1=0 ID0=1 : Deutsch 9-pin (CAN1 = C/D, CAN2 = H/J)
    CABLE_CUSTOM = 0,      // both grounded: user cable, config from SD
} cable_id_t;

#define NUM_CAN 4
