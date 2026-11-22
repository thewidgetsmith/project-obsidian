# XIAO ESP32-S3 Sense: Pin Map

This is the single source of truth for XIAO GPIO use. Specs and changes
link here instead of restating pins. `firmware/xiao/include/config.h` must
agree with this page; see [Firmware Assignments](#firmware-assignments-configh).

Source: the Sense pin map in the
[Seeed getting-started wiki](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/#hardware-overview),
confirmed by the project owner. Nothing is wired yet, so assignments can still
change. Change them here first, then in `config.h`.

## Reserved by On-Board Hardware

Do not assign these GPIOs to anything else.

| Function | GPIOs |
| --- | --- |
| Camera (Sense board; OV2640, OV3660 or OV5640) | 10–18, 38, 39, 40, 47, 48 |
| microSD (Sense board, SPI) | 21 (CS), 7 (SCK), 8 (MISO), 9 (MOSI) |
| User LED (active-low) | 21, **shared with SD CS** |
| PDM microphone (Sense board) | 41 (data), 42 (clock) |
| Native USB (USB-C: flashing, logs) | 19 (D−), 20 (D+) |
| Octal PSRAM (in-package, ESP32-S3R8) | 33–37 (not broken out) |

**LED/SD conflict:** GPIO21 is both the user LED and the SD card's chip
select, so the LED can't signal status while the card is mounted. Status
indication belongs in the web UI or on an external LED on a free pin.

**PSRAM:** the R8 variant's octal PSRAM uses GPIO33–37 internally. They
don't appear in Seeed's tables because they aren't routed to any pad. This
is an inference from the Espressif datasheet's rule for octal-PSRAM
variants; it has no practical effect because the pins are unreachable.

## Header Pins

| Header | GPIO | Status |
| --- | --- | --- |
| D0 | 1 | Free |
| D1 | 2 | Free |
| D2 | 3 | Free (strapping pin, see below) |
| D3 | 4 | Free |
| D4 | 5 | Free (default I2C SDA) |
| D5 | 6 | Free (default I2C SCL) |
| D6 | 43 | **UART link TX → ATmega D0** (UART0 TX by default) |
| D7 | 44 | **UART link RX ← ATmega D1** (UART0 RX by default) |
| D8 | 7 | microSD (SCK) |
| D9 | 8 | microSD (MISO) |
| D10 | 9 | microSD (MOSI) |

The Sense board also routes D11 = GPIO42 and D12 = GPIO41 through the B2B
connector. Those are the microphone lines and aren't available.

That leaves **six free GPIOs: 1, 2, 3, 4, 5, 6.** The MAX98357A speaker
takes 1, 2 and 4, and I2C takes 5 and 6. **GPIO3 (D2) is the only
unallocated pin.** Reach for I2C devices before using it.

## Strapping Pins

GPIO 0, 3, 45 and 46 are sampled at reset. GPIO3 selects the JTAG signal
source, and only when the related eFuses are burned (they aren't by default),
so it's usable as plain I/O. Still, avoid a strong pull on it during reset.
Don't attach anything that pulls 45 or 46 during reset.

## UART Link

- **Pins:** GPIO43 (TX) and GPIO44 (RX), header D6/D7. The USB-C connector uses
  the native USB peripheral (GPIO19/20), not UART0, so the link does not
  interfere with flashing or USB logging.
- **Peripheral:** `UART_NUM_1`, routed to 43/44 through the GPIO matrix. This
  keeps UART0 out of ESP-IDF's console paths. Pin routing at 115200 baud has
  no timing cost.
- **Console:** `sdkconfig` has `CONFIG_ESP_CONSOLE_NONE=y` with the secondary
  console on USB-Serial-JTAG. Application logs therefore go to USB, never onto
  the link.
- **Boot noise:** with `CONFIG_BOOT_ROM_LOG_ALWAYS_ON=y`, the ROM prints its
  boot banner on GPIO43 at every reset. The ATmega's parser discards it
  (resync on `0x7E`), so this is harmless. The only way to silence it,
  `CONFIG_BOOT_ROM_LOG_ALWAYS_OFF`, burns an eFuse and is permanent. Not
  recommended.

## ATmega Side of the Link

The ATmega328P's only hardware UART, D0/D1, is also its USB-serial upload
port. With the XIAO wired to D0, the XIAO's TX and the USB-serial adapter's TX
both drive the ATmega's RX:
- **Uploads fail** while the XIAO is powered and connected. Disconnect XIAO TX
  (or add a jumper or switch) before `pio run -t upload`.
- **ATmega logs** do not use this UART; they go to a separate debug port on D2
  (see the ATmega pin map).

## Firmware Assignments (`config.h`)

`firmware/xiao/include/config.h` matches this table. The earlier conflicts
(UART on camera lines, SD on camera/mic lines, mic on strapping pins) are
resolved.

| Function | Macro(s) | GPIO(s) |
| --- | --- | --- |
| UART link | `CONFIG_UART_TX_PIN` / `RX_PIN` | 43 / 44 |
| Camera | `CONFIG_CAMERA_*_PIN` | PWDN/RESET −1 (not connected), XCLK 10, SIOD 40, SIOC 39, VSYNC 38, HREF 47, PCLK 13, D0–D7 = 15, 17, 18, 16, 14, 12, 11, 48 |
| microSD (SPI) | `CONFIG_SD_CS/SCLK/MISO/MOSI_PIN` | 21 / 7 / 8 / 9 |
| PDM microphone | `CONFIG_I2S_MIC_CLK_PIN` / `DATA_PIN` | 42 / 41 |
| Speaker (MAX98357A, I2S) | `CONFIG_I2S_SPK_BCLK/LRCLK/DATA_PIN` | 1 / 2 / 4 (provisional; roadmap item 021 may revise) |
| I2C | `CONFIG_I2C_SDA_PIN` / `SCL_PIN` | 5 / 6 |
| User LED (on-board) | `CONFIG_LED_PIN` | 21 (only while SD is unmounted) |
| Spare | — | 3 (D2) |

Camera data lines follow Seeed's Y2..Y9 = GPIO 15, 17, 18, 16, 14, 12, 11, 48.
