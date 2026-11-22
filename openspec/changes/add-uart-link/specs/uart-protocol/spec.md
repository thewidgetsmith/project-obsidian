# Spec Delta

## Purpose

The wire protocol between the XIAO ESP32-S3 and the ATmega328P: one
header-only definition both boards compile, so framing, CRC and payload
layouts can never disagree.

## ADDED Requirements

### Requirement: Physical layer

The link SHALL run at 115200 baud, 8N1, no flow control, on the pins and
wiring in "UART Link" of `docs/hardware/xiao-esp32s3-sense.md` and "Pin
Assignment" of `docs/hardware/atmega328p-arduino.md`.

#### Scenario: HIL: Link wiring

- **WHEN** both boards are wired per the hardware pages and powered
- **THEN** frames sent by each board are received intact by the other

### Requirement: Single source of truth

All protocol constants, payload layouts, the CRC and the parser SHALL be
defined only in `firmware/shared/protocol.h`, which SHALL be header-only,
use only `<stdint.h>`, `<stddef.h>` and `<stdbool.h>`, and compile without
warnings as gnu++17 under both boards' flags and as C.

#### Scenario: Compiles as C

- **WHEN** a C translation unit in a host test build includes `protocol.h`
- **THEN** it compiles without warnings and its test passes

### Requirement: Frame format

A frame SHALL be `START(0x7E) LEN CMD PAYLOAD[LEN] CRC END(0x7E)`, with LEN
0..16 and a wire size of 5 + LEN bytes. CRC-8 SHALL cover CMD and PAYLOAD with
polynomial 0x07, initial value 0x00, no reflection and no final XOR.
Multi-byte fields SHALL be little-endian two's complement. No byte stuffing.

#### Scenario: CRC check value

- **WHEN** `protocol_crc8` runs over the ASCII bytes `123456789`
- **THEN** it returns 0xF4

#### Scenario: Round trip

- **WHEN** a frame is built for any command with LEN 0, 8 or 16 and fed byte by byte to a fresh parser
- **THEN** the parser reports one complete frame with the same CMD, LEN and payload

#### Scenario: Little-endian i16

- **WHEN** −2 is encoded as an i16 field
- **THEN** the bytes are `FE FF`

### Requirement: Parser recovery

The parser SHALL consume one byte at a time with a fixed 18-byte staging
buffer and no dynamic allocation. It SHALL silently discard a frame with a
bad CRC, a wrong END byte, LEN > 16, or a 10 ms gap mid-frame, and SHALL
resynchronize on the next 0x7E. No reply SHALL be sent for a discarded frame.

#### Scenario: Corrupted CRC

- **WHEN** a valid frame has one CRC bit flipped
- **THEN** the parser reports an error and no frame, then parses the next valid frame normally

#### Scenario: Wrong END

- **WHEN** a frame ends with 0x00 instead of 0x7E
- **THEN** the frame is discarded

#### Scenario: LEN too large

- **WHEN** a 0x7E is followed by LEN 17
- **THEN** the parser returns to waiting for START

#### Scenario: Truncated frame

- **WHEN** a frame stops mid-payload and no byte arrives for 10 ms
- **THEN** the partial frame is discarded and the next valid frame parses

#### Scenario: Garbage before a frame

- **WHEN** random non-0x7E bytes precede a valid frame
- **THEN** the valid frame parses

### Requirement: Command set

Downlink IDs SHALL be 0x00–0x3F and uplink IDs 0x40–0xFF, with
`PROTOCOL_VERSION` 0x01. The commands SHALL be HELLO 0x00 (down, u8
version), DRIVE 0x01 (down, i16 thrust, strafe, yaw, gimbal), STOP 0x02
(down, no payload), TELEMETRY 0x40 (up, u16 voltage_mv, i16 current_ma, u8
flags), HELLO_ACK 0x41 (up, u8 version, u8 status) and ACK 0x80 (up, u8 cmd,
u8 status). All other IDs are reserved.

#### Scenario: Drive payload layout

- **WHEN** DRIVE {thrust 1000, strafe −1000, yaw 0, gimbal 1} is encoded
- **THEN** the 8 payload bytes are `E8 03 18 FC 00 00 01 00`

### Requirement: Status codes

Status codes SHALL be OK 0x00, UNKNOWN_COMMAND 0x02, RANGE_ERROR 0x03 and
VERSION_MISMATCH 0x04.

#### Scenario: ACK payload

- **WHEN** an ACK for DRIVE with RANGE_ERROR is encoded
- **THEN** the payload bytes are `01 03`

### Requirement: Telemetry flags

Telemetry flag bits SHALL be MOTORS_ENABLED bit 0, LINK_TIMEOUT bit 1,
OVERVOLTAGE bit 2, UNDERVOLTAGE bit 3 and OVERCURRENT bit 4; bits 5–7 SHALL
always be 0.

#### Scenario: Telemetry payload layout

- **WHEN** TELEMETRY {11800 mV, −1500 mA, flags 0x03} is encoded
- **THEN** the 5 payload bytes are `18 2E 24 FA 03`

### Requirement: Drive field range

Every DRIVE field SHALL be in −1000..1000, where ±1000 is full scale.

#### Scenario: Range constants

- **WHEN** a test reads `PROTOCOL_DRIVE_MIN` and `PROTOCOL_DRIVE_MAX`
- **THEN** they are −1000 and 1000

### Requirement: Versioning

A change to an existing command's payload SHALL increment
`PROTOCOL_VERSION`. A new command in a reserved range SHALL NOT; a peer that
does not know it answers `UNKNOWN_COMMAND`.

#### Scenario: Unknown command from a newer peer

- **WHEN** the ATmega receives a valid frame with reserved ID 0x03
- **THEN** it replies `ACK {0x03, UNKNOWN_COMMAND}`
