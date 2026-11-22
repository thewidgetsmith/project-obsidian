# Adafruit Motor Shield v1

Drives the four Mecanum wheel motors and the camera gimbal servo. It plugs
onto the [ATmega328P board](atmega328p-arduino.md).

Reference: [github.com/adafruit/Adafruit_Motor-Shield-v1](https://github.com/adafruit/Adafruit_Motor-Shield-v1)
(hardware). Pin numbers and shift-register bits are confirmed against the
`AFMotor.h` / `AFMotor.cpp` sources in
[Adafruit-Motor-Shield-library](https://github.com/adafruit/Adafruit-Motor-Shield-library).
That library is reference only; the firmware drives the shield through `hal::`
(no third-party dependency).

## Components

| Part | Role |
| --- | --- |
| 2× L293D | Dual H-bridges; 4 DC motor channels (M1–M4), 0.6 A continuous per channel (1.2 A peak) |
| 74HC595 | Shift register that holds the eight H-bridge direction inputs |
| 2× servo headers | SERVO_1 (D10), SERVO_2 (D9); powered from the Arduino's 5 V |

## Connected Hardware

| Output | Load |
| --- | --- |
| M1–M4 | Four DC gear motors, one per Mecanum wheel. The wheel-to-channel mapping (FL/FR/RL/RR) depends on the wiring; it is recorded here once roadmap item 010 (Basic Movement) defines it. |
| SERVO_2 (D9) | SG90 micro servo, camera gimbal tilt |
| SERVO_1 (D10) | Unused |

The SG90 plugs into **SERVO_2 (D9)**, as confirmed by the owner. SERVO_1 (D10)
stays free.

## Arduino Pins Used

| Pin | Function |
| --- | --- |
| D11 (OC2A) | M1 speed (PWM) |
| D3 (OC2B) | M2 speed (PWM) |
| D6 (OC0A) | M3 speed (PWM) |
| D5 (OC0B) | M4 speed (PWM) |
| D4 | 74HC595 shift clock (SHCP) |
| D12 | 74HC595 latch (STCP) |
| D8 | 74HC595 serial data (DS) |
| D7 | 74HC595 output enable (OE, **active-low**) |
| D9 / D10 | Servo signals |

Each motor has its own PWM pin, so all four wheels get independent speed
control, which Mecanum kinematics requires. The PWM pin drives the L293D
channel's enable input.

## Direction Control (74HC595)

Each motor uses two shift-register outputs, A and B:

| Motor | A bit | B bit |
| --- | --- | --- |
| M1 | 2 | 3 |
| M2 | 1 | 4 |
| M3 | 5 | 7 |
| M4 | 0 | 6 |

| A | B | Result |
| --- | --- | --- |
| 1 | 0 | Forward |
| 0 | 1 | Backward |
| 0 | 0 | Release (coast) |

Speed comes from PWM duty on the motor's pin (0–255). "Forward" means the
motor's wiring polarity; roadmap item 010 decides which direction each wheel counts as
forward.

To update the directions, shift out all 8 bits **MSB first** (bit 7 first) on
D8 with a clock pulse on D4 per bit, then pulse D12 (latch). The firmware
keeps a shadow byte, because the 595 can't be read back.

## Safe Initialization Order

1. Set D7 (OE) HIGH: shift-register outputs off.
2. Set all four PWM pins to output, duty 0.
3. Shift out `0x00` and latch: every motor released.
4. Set D7 LOW: outputs enabled, with all motors still stopped.

Stopping (`motor_stop()`, the motion-timeout failsafe) means PWM 0 on all
channels plus a `0x00` latch. D7 can stay LOW.

## Power

- **Motors:** use the shield's external motor supply (EXT_PWR terminal),
  4.5–25 V. Remove the PWR jumper if the Arduino has its own supply, so the
  motors don't share it.
- **Servo:** the headers take 5 V from the Arduino's regulator. An SG90 can
  draw several hundred mA at stall and brown out the ATmega. A separate 5 V
  rail, or a large capacitor across the servo header, avoids resets.
