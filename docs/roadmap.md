# Roadmap

Every feature planned for the rover, in the order it will be built. Each row
becomes one or more OpenSpec changes (`openspec/changes/`) when its turn
comes; the planner proposes them, and a feature may only depend on
lower-numbered ones. Numbers are kept from the original spec plan.

| # | Feature | OpenSpec change | Status |
| - | ------- | --------------- | ------ |
| 001 | Firmware Foundation XIAO | `add-xiao-foundation` | proposed |
| 002 | Firmware Foundation ATmega328P | `add-atmega-foundation` | proposed |
| 003 | Communication Protocol | `add-uart-link` | proposed |

### Foundation - 001 to 005
Set up both firmware projects, define the UART protocol, and achieve basic
end-to-end communication from smartphone to XIAO to ATmega328P and back.

| # | Feature | Target |
| - | ---- | ------ |
| 001 | Firmware Foundation XIAO | ESP32-S3 |
| 002 | Firmware Foundation ATmega328P | ATmega328P |
| 003 | Communication Protocol | Both MCUs |
| 004 | XIAO WiFi Web Server | ESP32-S3 |
| 005 | Basic Web Interface | ESP32-S3 (UI) |

### Rover Control UI - 006 to 009
Build the smartphone UI: live video feed background with overlaid virtual joysticks
that send proportional input back to the ESP32-S3 over WebSocket or HTTP.

| # | Feature | Target |
| - | ---- | ------ |
| 006 | Live Video Feed | ESP32-S3 (camera + server) |
| 007 | Joystick Control Overlay | ESP32-S3 (web UI) |
| 008 | Joystick Input Mapping | Both MCUs |
| 009 | Simple Heads-Up Display | ESP32-S3 (web UI) |

### Rover Movement - 010 to 012
Implement Mecanum wheel drive, yaw control, and camera gimbal tilt in response
to joystick input. Refines the UART communication protocol between the ESP32-S3
and ATmega328P.

| # | Feature | Target |
| - | ---- | ------ |
| 010 | Basic Movement | Both MCUs |
| 011 | Advanced Movement | Both MCUs |
| 012 | Camera Tilt Servo | ATmega328P + UI |

### Development Checkpoint - 013

### HUD Expansion - 014 to 020
Expands the on-screen HUD with feed effects, interactive controls (toggle/momentary
buttons for LEDs, intercom), and informational overlays (battery level).

| # | Feature | Target |
| - | ---- | ------ |
| 014 | Basic Feed Effects | ESP32-S3 (camera) |
| 015 | Advanced Feed Effects | ESP32-S3 (camera) |
| 016 | Intercom HUD Controls | ESP32-S3 (web UI) |
| 017 | HUD Toggle Controls | ESP32-S3 (web UI) |
| 018 | HUD Momentary Controls | ESP32-S3 (web UI) |
| 019 | HUD Information Display | ESP32-S3 (web UI) |
| 020 | HUD Battery Display | Both MCUs |

### Intercom Feature - 021 to 025
Implement two-way I2S audio: capture from the XIAO's built-in mic and stream to
smartphone, receive audio from smartphone and play through the MAX98357A amplifier
and speaker. Include sound effects playback from the microSD card.

| # | Feature | Target |
| - | ---- | ------ |
| 021 | Capture Rover Sound | ESP32-S3 (I2S mic) |
| 022 | Capture Smartphone Sound | ESP32-S3 (web UI) |
| 023 | Implement Intercom Controls | ESP32-S3 (web UI) |
| 024 | Sound Effects Playback | ESP32-S3 (SD + I2S) |
| 025 | Sound Effects HUD | ESP32-S3 (web UI) |

### Development Checkpoint - 026

### Future Features
Ideas for future features and enhancements.

- Infrared Laser Cannon - enables tank-like firing for battling other rovers
- Infrared Damage Detector - detects impacts from the laser cannon and applies damage
- HUD Expansion 2 - Expands the HUD to include damage and ammo indicators
- Camera feed AI detection - Detection and tracking of certain objects in the camera feed
- Obstacle Detection - Uses sensors around the rover to detect and avoid obstacles, shows on UI
- Autonomous Navigation - Edge detection, Obstacle avoidance, Path planning

---

## Development Checkpoints

A checkpoint adds no feature. It reviews the batch before it, while
that work is recent enough to remember and before more is built on top.

Each serves as an opportunity to review the code, evaluate the project
structure, fix known bugs, and ensure maintainability.
