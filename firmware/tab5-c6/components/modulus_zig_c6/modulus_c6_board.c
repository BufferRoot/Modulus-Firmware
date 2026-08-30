/*

 * Tab5 C6 field bring-up:

 * - Console UART0 (GPIO16/17): pull-ups when USB-TTL on COM18 is unplugged.

 * - USB-Serial-JTAG: disable auto chip-reset on cable detach (else C6 EN glitches

 *   while P4 keeps SDIO traffic — esp-hosted-mcu #127 / Tab5 field reports).

 */

#include "driver/gpio.h"

#include "soc/usb_serial_jtag_reg.h"



#define TAB5_C6_UART_TX_GPIO GPIO_NUM_16

#define TAB5_C6_UART_RX_GPIO GPIO_NUM_17



void modulus_c6_board_uart_pullups(void)

{

    gpio_set_pull_mode(TAB5_C6_UART_TX_GPIO, GPIO_PULLUP_ONLY);

    gpio_set_pull_mode(TAB5_C6_UART_RX_GPIO, GPIO_PULLUP_ONLY);

}



static void modulus_c6_board_disable_usb_uart_chip_reset(void)

{

    REG_SET_BIT(USB_SERIAL_JTAG_CHIP_RST_REG, USB_SERIAL_JTAG_USB_UART_CHIP_RST_DIS);

}



static void __attribute__((constructor)) modulus_c6_board_ctor(void)

{

    modulus_c6_board_uart_pullups();

    modulus_c6_board_disable_usb_uart_chip_reset();

}


