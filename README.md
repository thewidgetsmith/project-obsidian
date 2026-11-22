# Project Obsidian

## Overview

Project Obsidian is a firmware project for a small robotic rover, built around
the [Seeed Studio XIAO ESP32-S3 Sense](https://www.seeedstudio.com/XIAO-ESP32-S3-Sense-p-5639.html)
microcontroller. The rover is operated wirelessly via a smartphone running a
companion web interface that combines a real-time video feed with on-screen dual
virtual joysticks for intuitive control.

## Concept

The operator's smartphone connects directly to the rover's Wi-Fi access point (or joins its network). A web page streamed from the ESP32 displays:

- **Fullscreen camera feed** — live video from the ESP32-S3's onboard OV2640 camera.
- **Dual virtual XY joysticks** — touch-driven overlays that map to rover movement and auxiliary functions (e.g., steering, arm control, lights).

## Hardware

### Main Processor

| Component | Description |
| --- | --- |
| **Camera MCU** | Seeed Studio XIAO ESP32-S3 Sense |
| **Camera** | OV2640, 75mm wide-angle (onboard) |
| **Wi-Fi** | ESP32-S3 built-in 2.4 GHz |
| **Microphone** | Built-in I2S PDM microphone (onboard) |
| **Storage** | Micro SD card slot (onboard) |

### Audio

| Component | Description |
| --- | --- |
| **Amplifier** | MAX98357A I2S class-D amplifier |
| **Speaker** | 4 Ω, 3 W dynamic speaker |
| **Interface** | I2S (connected to XIAO ESP32-S3) |
| **Functions** | Intercom (two-way audio with smartphone), sound effects from microSD |

### Motor Control Subsystem

| Component | Description |
| --- | --- |
| **Motor MCU** | Atmel ATmega328P |
| **Motor Driver** | Adafruit Motor Shield v1 (2× L293D + 74HC595), see [docs/hardware/adafruit-motor-shield-v1.md](docs/hardware/adafruit-motor-shield-v1.md) |
| **Gimbal Servo** | 1× SG90 on the shield's servo header |
| **Motors** | 4× DC gear motors (one per wheel) |
| **Wheels** | 4× Mecanum wheels (omnidirectional) |
| **Link** | UART serial between ESP32-S3 and ATmega328P |

### Power Management

| Component | Description |
| --- | --- |
| **Monitor** | ATmega328P (shares MCU with motor control) |
| **Sensing** | Battery voltage & current monitoring |
| **Link** | UART serial to XIAO ESP32-S3 |
| **Display** | On-screen battery indicator on smartphone UI |

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Rover Hardware                           │
│                                                                 │
│  ┌──────────────────────┐   UART    ┌────────────────────────┐ │
│  │   ESP32-S3           │ ◄────────►│    ATmega328P          │ │
│  │                      │  cmd/pwr  │                        │ │
│  │  OV2640 Cam          │           │  Motor Shield v1       │ │
│  │  I2S Mic             │           │  ├─ Motor 1 (FL)       │ │
│  │  I2S → MAX98357A     │           │  ├─ Motor 2 (FR)       │ │
│  │  SD Card (SFX)       │           │  ├─ Motor 3 (RL)       │ │
│  │  Wi-Fi ↔ Smartphone  │           │  └─ Motor 4 (RR)       │ │
│  └──────────────────────┘           │  ADC: V / I monitoring │ │
│                                     └────────────────────────┘ │
│                                                   │            │
│              ┌────────────────────────────────────┼────────┐   │
│              │                                    │        │   │
│           ┌──┴──┐                           ┌────┴────┐   │   │
│           │ FL  │                           │ Speaker │   │   │
│           │Mec  │                           │ (3W/4Ω) │   │   │
│           └─────┘                           └─────────┘   │   │
│              │                                             │   │
│           ┌──┴──┐                                        │   │
│           │ FR  │                                        │   │
│           │Mec  │                                        │   │
│           └─────┘                                        │   │
│              │                                             │   │
│           ┌──┴──┐                              ┌────────┴───┴───┐
│           │ RL  │                              │   BATTERY      │
│           │Mec  │                              │  (main pack)   │
│           └─────┘                              └────────────────┘
│              │                                                   │
│           ┌──┴──┐                                               │
│           │ RR  │                                               │
│           │Mec  │                                               │
│           └─────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐              ┌──────────────────────────────────┐
│   Smartphone     │ ◄═══════════►│    ESP32-S3 Wi-Fi AP             │
│   Web Browser    │   HTTP/MJPEG │    (control server)              │
│                  │              │                                  │
│  ┌────────────┐  │   Audio      │  Joystick Handlers:              │
│  │ Joystick R │  │  Stream    │  Right → Drive X/Y                │
│  │ (Drive X/Y)│  │◄──────────►│  Left X → Yaw                     │
│  └────────────┘  │              │  Left Y → Gimbal                  │
│  ┌────────────┐  │              │                                  │
│  │ Joystick L │  │              │  Audio / Comms:                  │
│  │ (Yaw/Gim)  │  │              │  I2S intercom (mic→SPK)          │
│  │ X→Yaw,     │  │              │  SD sound effects                │
│  │ Y→Gimbal   │  │              │                                  │
│  └────────────┘  │              │  Battery status (UART display)   │
│                  │              └──────────────────────────────────┘
└──────────────────┘
```

## Control Mapping

The smartphone web UI presents two virtual XY joysticks overlaid on the camera feed.

### Right Joystick — Drive Control

| Axis | Function | Description |
| --- | --- | --- |
| **X-axis** | Strafe (left / right) | Moves the rover laterally without changing heading |
| **Y-axis** | Thrust (forward / backward) | Moves the rover in the current heading direction |

Combined diagonal inputs produce strafed diagonal movement via the Mecanum wheel kinematics — e.g. pushing top-left drives the rover forward and left simultaneously.

### Left Joystick — Orientation & Gimbal

| Axis | Function | Description |
| --- | --- | --- |
| **X-axis** | Yaw rate | Spins the rover in place (left / right rotation) |
| **Y-axis** | Gimbal tilt | Tilts the camera up / down on its single-axis mount |

## Features

- Real-time MJPEG video streaming over HTTP/Wi-Fi
- Touch-based virtual joystick input rendered as an HTML overlay
- Low-latency UART link between ESP32-S3 (vision/control) and ATmega328P (motor control)
- Mecanum wheel kinematics for full omnidirectional movement (forward, strafe, diagonal, yaw in place)
- Dedicated camera gimbal tilt control
- I2S two-way intercom (built-in mic + MAX98357A amplifier + speaker)
- Sound effects playback from microSD card
- Battery voltage/current monitoring with on-screen status display
- Modular two-processor firmware architecture for easy extension

## Getting Started

> **Status:** Clean-slate restart. The firmware foundations and the UART link
> are proposed as OpenSpec changes (`openspec list`); nothing is wired yet.

### Development Environment

All checks run in one toolbox image ([tools/container/](tools/container/Containerfile)):
PlatformIO, the host compiler for the unit tests, clang-format, clang-tidy,
cppcheck, Python and OpenSpec, at pinned versions. Locally it runs as the
`obsidian-dev` distrobox; CI runs the same image.

| Host requirement | Purpose |
| --- | --- |
| Podman + distrobox | Run the toolbox (`tools/container.sh create`) |
| Node ≥ 22.20 + `npm i -g @fission-ai/openspec@2.1.1` | `openspec` CLI for the agents on the host |
| Claude Code | Spec planner ([.claude/spec-planning.md](.claude/spec-planning.md)) |
| OpenCode + a LiteLLM proxy (Qwen, DeepSeek, Claude) | Orchestrator and helper agents ([.opencode/agents/](.opencode/agents/)) |
| Orca | One worktree per change |
| `dialout` group | USB serial for flashing (`/dev/ttyACM*` XIAO, `/dev/ttyUSB*` CH341) |

First-time setup:

```
tools/container.sh create        # build the image, create the distrobox, prefetch toolchains
tools/verify.sh all --all-files  # should end with VERIFY PASS
```

For the agents, put the LiteLLM endpoint and key in
`~/.config/litellm/obsidian.env` (template:
[tools/obsidian.env.example](tools/obsidian.env.example)) and start OpenCode
with `tools/opencode.sh`. No secret is stored in the repo; see
[Secrets](docs/workflow.md#secrets).

### Everyday Commands

```
tools/verify.sh --fix                 # docs, specs, format, rules, lint, build, test for what you touched
tools/test.sh atmega                  # one step, one board
tools/log.sh build:xiao               # the first errors of a failed step
openspec list                         # changes in flight and their task progress
```

The `tools/` scripts enter the toolbox on their own, so they work the same
from your terminal, Claude Code and OpenCode. Details:
[tools/README.md](tools/README.md).

### Development Workflow

Work is spec-driven with [OpenSpec](https://github.com/Fission-AI/OpenSpec):

1. Claude proposes a change in `openspec/changes/<change>/`: proposal,
   delta specs, design and tasks.
2. You approve it.
3. In the change's Orca worktree, the OpenCode orchestrator runs each task
   through planner, developer, `tools/check.sh` and reviewer, commits it,
   then audits the whole change and opens a PR.
4. Claude reviews the PR, you merge it and run the hardware-in-the-loop checks.
5. The change is archived, and its specs merge into `openspec/specs/`.

Full loop and roles: [docs/workflow.md](docs/workflow.md). Feature order:
[docs/roadmap.md](docs/roadmap.md).

## Project Structure

| Path | Contents |
| --- | --- |
| `firmware/xiao/` | XIAO ESP32-S3 Sense firmware (ESP-IDF via PlatformIO) |
| `firmware/atmega/` | ATmega328P firmware (Arduino via PlatformIO) |
| `firmware/shared/` | Header-only code both boards compile (UART protocol) |
| `openspec/specs/` | Capabilities the firmware implements today |
| `openspec/changes/` | Proposed and in-progress changes; `archive/` holds finished ones |
| `docs/hardware/` | Pin maps and wiring, the single source of truth for GPIOs |
| `docs/reference/` | Board layout rules and toolchain details |
| `.opencode/agents/` | OpenCode agent definitions (orchestrator and helpers) |
| `tools/` | Verification scripts and the toolbox image |
| [AGENTS.md](AGENTS.md) | Rules every AI agent follows |

## License

[MIT No Attribution (MIT-0)](LICENSE): use, copy, modify and redistribute the
code and documentation freely, for any purpose, without asking.

Attribution is appreciated but not required. If this project helps you, a
link back to the repository or the project's blog posts is a kind gesture.

**No warranty.** The software, documentation and designs are provided "as
is", with no warranty of any kind, including for the behavior of a rover
built from them. A rover has motors, batteries and moving parts: build and
test it at your own risk.
