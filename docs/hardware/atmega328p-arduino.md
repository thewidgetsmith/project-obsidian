# ATmega328P Arduino Board: Pin Map

The motor controller is a standard ATmega328P development board with the
Arduino Uno R3 pin layout: 16 MHz, 5 V logic, 32 KB flash, 2 KB SRAM. The
[Adafruit Motor Shield v1](adafruit-motor-shield-v1.md) sits on top and uses
most of the digital pins.

This page and the shield page are the single source of truth for ATmega pin
use. `firmware/atmega/include/config.h` must agree with them.

## Pin Assignment

| Pin | Port | Peripheral | Used by | Notes |
| --- | --- | --- | --- | --- |
| D0 | PD0 | USART RXD | **UART link RX ← XIAO GPIO43** | Also the USB-serial upload port |
| D1 | PD1 | USART TXD | **UART link TX → XIAO GPIO44** | Also the USB-serial port |
| D2 | PD2 | INT0 | **Debug log TX → USB-serial adapter RX** | SoftwareSerial, 115200 8N1; see [Debug Log Port](#debug-log-port) |
| D3 | PD3 | OC2B (Timer2) | Shield: M2 PWM | |
| D4 | PD4 | — | Shield: 74HC595 clock (SHCP) | |
| D5 | PD5 | OC0B (Timer0) | Shield: M4 PWM | |
| D6 | PD6 | OC0A (Timer0) | Shield: M3 PWM | |
| D7 | PD7 | — | Shield: 74HC595 output enable (OE, active-low) | |
| D8 | PB0 | — | Shield: 74HC595 data (DS) | |
| D9 | PB1 | OC1A (Timer1) | Shield: SERVO_2 header, **SG90 gimbal** | See servo note on the shield page |
| D10 | PB2 | OC1B (Timer1), SS | Shield: SERVO_1 header (unused) | |
| D11 | PB3 | OC2A (Timer2), MOSI | Shield: M1 PWM | |
| D12 | PB4 | MISO | Shield: 74HC595 latch (STCP) | |
| D13 | PB5 | SCK | Free | On-board LED "L" |
| A0 | PC0 | ADC0 | Battery voltage divider | |
| A1 | PC1 | ADC1 | Battery current sensor | |
| A2 | PC2 | ADC2 | Free | Usable as digital I/O |
| A3 | PC3 | ADC3 | Debug log RX (reserved, unconnected) | SoftwareSerial needs an RX pin; firmware never listens on it |
| A4–A5 | PC4–PC5 | ADC4–5, SDA/SCL | Free | Reserve for I2C |

**Free for future features:** D13, A2, A4–A5. Every PWM-capable pin is used,
and INT0 (D2) now carries the debug log, so a wheel encoder would need a
pin-change interrupt instead.

## Timers

| Timer | Pins | Owner | Constraint |
| --- | --- | --- | --- |
| Timer0 (8-bit) | D5, D6 | Arduino `millis()`/`delay()`, and M3/M4 PWM | **Never change its prescaler or mode.** `hal::now_ms()` and every protocol timeout depend on it. `analogWrite()` on D5/D6 is safe (about 977 Hz). |
| Timer1 (16-bit) | D9, D10 | Servo (50 Hz) | Once the servo runs, D9/D10 can't be used for `analogWrite()`. |
| Timer2 (8-bit) | D3, D11 | M1/M2 PWM | Don't use `tone()`, which takes over Timer2. |

## UART Sharing

The only hardware UART (D0/D1) carries two things: the XIAO link and
firmware uploads through the board's USB-serial chip. Logs do **not** use it;
they go to the [debug log port](#debug-log-port).
- **Uploads:** disconnect the XIAO's TX wire (or use a jumper or switch on it)
  while uploading. Otherwise two transmitters drive D0.

## Debug Log Port

Logs leave on D2 through the Arduino core's bundled SoftwareSerial
(TX-only in practice; A3 is its unused RX pin), 115200 8N1. To read them,
wire a USB-to-TTL serial adapter (CH340, CP2102, FTDI…) to a second USB port
on the workstation:

| Adapter | Board |
| --- | --- |
| RX | D2 |
| GND | GND |
| TX, VCC | not connected |

The ATmega drives D2 at **5 V**: use an adapter with 5 V logic or a 5 V
jumper setting (most CH340/FTDI boards). Then
`pio device monitor -p /dev/ttyUSB1 -b 115200` (the port number depends on
plug-in order). Each logged byte blocks the main loop for about 87 µs, so
modules rate-limit their logs.

## Power

The board's 5 V regulator also powers the shield's logic and the servo
header. See the shield page for motor power and the SG90 brown-out risk.
