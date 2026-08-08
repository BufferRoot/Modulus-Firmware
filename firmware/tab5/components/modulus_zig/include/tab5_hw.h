#pragma once

#include "driver/gpio.h"

/**
 * Tab5 hardware constants — single source (C++ BSP + M5 docs + pinmap.md).
 * Internal M-Bus: I2C0 @ G31 SDA / G32 SCL (CONFIG_BSP_I2C_NUM, BSP_I2C_NUM).
 * Port A Grove:   I2C1 @ G53 SDA / G54 SCL (BSP_EXT_I2C_NUM, EXT 5V rail).
 */

#define TAB5_I2C_SCL_GPIO 32
#define TAB5_I2C_SDA_GPIO 31

/* Port A HY2.0-4P Grove — I2C1 @ STD_GPIO53/54 (GPIO matrix, not dedicated I2C balls) */
#define TAB5_EXT_I2C_PORT     1
#define TAB5_EXT_I2C_SCL_GPIO GPIO_NUM_54
#define TAB5_EXT_I2C_SDA_GPIO GPIO_NUM_53

/* ExtPort1 GPIO_EXT (10-pin 5x2) */
#define TAB5_EXTPORT1_GPIO_0  GPIO_NUM_0
#define TAB5_EXTPORT1_GPIO_1  GPIO_NUM_1
#define TAB5_EXTPORT1_GPIO_49 GPIO_NUM_49
#define TAB5_EXTPORT1_GPIO_50 GPIO_NUM_50

/* M5-Bus rear 30-pin — pin 2 (GND on pin 1). Wired NC E-stop input. */
#define TAB5_MBUS_ESTOP_GPIO GPIO_NUM_16

/* COM.X STAMP — subset used by firmware docs */
#define TAB5_COMX_GPIO_5  GPIO_NUM_5
#define TAB5_COMX_GPIO_6  GPIO_NUM_6
#define TAB5_COMX_GPIO_18 GPIO_NUM_18
#define TAB5_COMX_GPIO_19 GPIO_NUM_19
#define TAB5_COMX_GPIO_33 GPIO_NUM_33
#define TAB5_COMX_GPIO_46 GPIO_NUM_46

#define TAB5_I2C_ADDR_ES8388    0x10
#define TAB5_I2C_ADDR_ES7210    0x40
#define TAB5_I2C_ADDR_GT911     0x14
#define TAB5_I2C_ADDR_ST7123    0x55
#define TAB5_I2C_ADDR_BMI270    0x68
#define TAB5_I2C_ADDR_RX8130    0x32
#define TAB5_I2C_ADDR_INA226    0x41
#define TAB5_I2C_ADDR_PI4IOE1   0x43
#define TAB5_I2C_ADDR_PI4IOE2   0x44
#define TAB5_I2C_ADDR_EXT_ENCODER 0x59 /* M5 Unit ExtEncoder on Port A Grove */

/* RS-485 SIT3088 — UART1, not I2C */
#define TAB5_RS485_UART         1
#define TAB5_RS485_TX_GPIO      20
#define TAB5_RS485_RX_GPIO      21
#define TAB5_RS485_DE_GPIO      34

/* NanoH2 Zigbee hub link — UART2 on M5BUS pins 16/15 (silkscreen TXD2/RXD2).
 * GPIO6 is shared with the COM.X STAMP pad net (xMOD_RX_GPIO6) — fine while
 * no STAMP module is fitted. UART0 = console, UART1 = RS-485. */
#define TAB5_ZB_UART            2
#define TAB5_ZB_UART_TX_GPIO    6  /* M5BUS pin 16 G14/TXD2 -> H2 Grove G2 (RX) */
#define TAB5_ZB_UART_RX_GPIO    7  /* M5BUS pin 15 G13/RXD2 <- H2 Grove G1 (TX) */

/* Port A alternate — TWAI/CAN transport shares G53/G54 with I2C1 (mutually exclusive) */
#define TAB5_PORT_A_CAN_TX_GPIO TAB5_EXT_I2C_SCL_GPIO
#define TAB5_PORT_A_CAN_RX_GPIO TAB5_EXT_I2C_SDA_GPIO

/* PI4IOE1 (0x43) outputs */
#define TAB5_E1_P0_RF_ANT       0 /* RF_PTH_L_INT_H_EXT: 0=int, 1=ext MMCX */
#define TAB5_E1_P1_SPK_EN       1
#define TAB5_E1_P2_EXT5V_EN     2
#define TAB5_E1_P4_LCD_RST      4
#define TAB5_E1_P5_TP_RST       5
#define TAB5_E1_P6_CAM_RST      6
#define TAB5_E1_P7_HP_DET       7 /* input: HIGH = jack inserted */

/* PI4IOE2 (0x44) — user + C++ BSP map */
#define TAB5_E2_P0_WLAN_PWR     0
#define TAB5_E2_P3_USB5V_EN     3
#define TAB5_E2_P4_PWROFF       4
#define TAB5_E2_P5_NCHG_QC      5
#define TAB5_E2_P6_CHG_STAT     6 /* input */
#define TAB5_E2_P7_CHG_EN       7

/*
 * PMS150G-U06 wake (PMIC E_TRG / PA6-CIN-):
 *   BMI270 INT1 + RX8130 INT — NOT connected to ESP GPIO (M5 Tab5 docs).
 *   See wakeup_shim.c for arm-before-sleep coordination.
 */

/* Port A / rear expansion — docs/hardware/tab5/interconnect.md */
#define TAB5_MBUS_I2C_SCL       TAB5_I2C_SCL_GPIO
#define TAB5_MBUS_I2C_SDA       TAB5_I2C_SDA_GPIO
