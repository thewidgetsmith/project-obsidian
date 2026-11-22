# Spec Delta

## Purpose

Battery voltage, current and status flags measured on the ATmega and sent to
the XIAO at 10 Hz for the HUD and for safety decisions.

## ADDED Requirements

### Requirement: Sampling

Every `CONFIG_TELEMETRY_PERIOD_MS` (100 ms) the ATmega SHALL read 8 samples
each of the voltage and current ADC channels, interleaved, and average each
channel.

#### Scenario: Averaging

- **WHEN** the voltage channel returns 500 for all 8 reads
- **THEN** the averaged raw voltage is 500

### Requirement: Conversion

Conversion SHALL be pure 32-bit integer functions of the averaged raw value
and config constants, ordered so no intermediate overflows:
`voltage_mv = (raw × ADC_REF_MV / 1024) × VDIV_RATIO_X1000 / 1000` and
`current_ma = (raw − CURRENT_OFFSET_RAW) × 78125 / (16 × CURRENT_MV_PER_A)`.
Positive current means load draw.

#### Scenario: Voltage

- **GIVEN** ADC_REF_MV 5000 and VDIV_RATIO_X1000 3000
- **WHEN** raw 512 is converted
- **THEN** voltage_mv is 7500

#### Scenario: Current

- **GIVEN** CURRENT_OFFSET_RAW 512 and CURRENT_MV_PER_A 100
- **WHEN** raw 612 and raw 412 are converted
- **THEN** current_ma is 4882 and −4882

#### Scenario: HIL: Calibration

- **WHEN** telemetry is compared with a multimeter at the pack
- **THEN** reported voltage is within ±5 % (after calibrating the config constants)

### Requirement: Status flags

Flags SHALL be: MOTORS_ENABLED when the shift-register outputs are enabled;
LINK_TIMEOUT when the motion timeout is active; OVERVOLTAGE when voltage >
`CONFIG_BATT_OVERVOLT_MV` (13000); UNDERVOLTAGE when voltage <
`CONFIG_BATT_UNDERVOLT_MV` (10500); OVERCURRENT when current >
`CONFIG_BATT_OVERCURRENT_MA` (10000). Bits 5–7 SHALL be 0.

#### Scenario: Undervoltage and timeout

- **WHEN** flags are computed for 10000 mV, 0 mA, motors enabled, link timed out
- **THEN** the flags byte is 0x0B

#### Scenario: Boundaries

- **WHEN** flags are computed for exactly 13000 mV and 10000 mA
- **THEN** neither OVERVOLTAGE nor OVERCURRENT is set

### Requirement: Telemetry stream

The ATmega SHALL send one `TELEMETRY` frame per period on its own schedule,
independent of downlink traffic, the first one `CONFIG_TELEMETRY_PERIOD_MS`
after init.

#### Scenario: 10 Hz

- **GIVEN** telemetry was initialized at t = 0
- **WHEN** it is polled every 1 ms until t = 350 ms
- **THEN** exactly three TELEMETRY frames were sent, at 100, 200 and 300 ms

#### Scenario: HIL: Telemetry rate

- **WHEN** the XIAO log is watched for 10 s with the link up
- **THEN** about 100 TELEMETRY frames are logged
