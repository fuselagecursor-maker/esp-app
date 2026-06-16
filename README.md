# ESP Drone Remote

Wi‑Fi bridge and mobile/web ground station for an STM32-based quadcopter flight controller. An **ESP32** creates a local access point, forwards UART commands to the **STM32 FC**, mirrors telemetry back over HTTP, and a **Flutter** app (`led_remote`) provides transmitter-style control, PID tuning, 3D attitude visualization, calibration wizards, and a live serial monitor.

```
┌─────────────────┐     Wi‑Fi AP        ┌──────────────────┐     UART 115200     ┌─────────────────┐
│  Phone / PC     │ ◄──────────────────► │  ESP32           │ ◄──────────────────► │  STM32 FC       │
│  led_remote     │   HTTP :80           │  src/main.cpp    │   RX=16  TX=17       │  CLI + motors   │
│  (Flutter)      │   192.168.4.1        │  ESP32-LED-CTRL  │   (cross TX/RX)     │  IMU / GPS      │
└─────────────────┘                      └──────────────────┘                      └─────────────────┘
```

---

## Features

### ESP32 firmware (`src/main.cpp`)
- Soft-AP **ESP32-LED-CTRL** (password `esp32demo`) at **192.168.4.1**
- HTTP REST API with CORS for browser and mobile clients
- UART bridge to STM32 at **115200 8N1** (pins **RX=16**, **TX=17** — change in firmware to match wiring)
- Circular serial log buffer; app polls `/drone/serial` for live telemetry
- **Fire-and-forget** path for high-rate RC (`rc`, `rudder`, `elevator`, `aileron`, `yaw`, `throttle`, `joy`) — no HTTP wait
- **Blocking** path for arm/disarm, PID, calibration — waits for STM32 reply
- **31-character line limit** on ESP→STM32 forward path (STM32 accepts up to 127 on USB)
- Onboard LED control via `esp led on/off`
- **ArduinoOTA** over Wi‑Fi for wireless firmware updates

### Flutter app (`led_remote/`)
Landscape-first ground station with shared connection session across all tabs.

| Tab | Purpose |
|-----|---------|
| **Home** | Wi‑Fi connection, Live ESP toggle, LED test, quick arm/disarm, custom command console |
| **Control** | FrSky-style transmitter UI — sticks, throttle, hold-to-arm, artificial horizon HUD |
| **Manual** | Alternate manual stick layout with arm bar |
| **Cal** | ESC and IMU calibration wizards |
| **Tune** | PID gains, filters, throttle limits, stabilize/hover, live telemetry panel, debug live toggle |
| **Map** | GPS position on map (when telemetry includes lat/lon) |
| **Serial** | Live STM32 UART log with activity indicators |
| **E-Stop** | Emergency disarm / kill flow |
| **3D** | Wireframe or Tello GLB 3D attitude view with telemetry readout |

**Platforms:** Android (APK), iOS, Web (Chrome). Default base URL: `http://192.168.4.1`.

**UI polish:** Shared motion primitives (`lib/widgets/app_motion.dart`) — tab transitions, glow on active link, animated metrics, serial line fade-in, scan overlays.

---

## Repository layout

```
esp/
├── platformio.ini          # ESP32 build (USB + OTA environments)
├── ota_upload.ps1          # Fallback OTA script if PlatformIO upload fails
├── src/
│   └── main.cpp            # ESP32 HTTP + UART bridge firmware
├── led_remote/             # Flutter ground station app
│   ├── lib/
│   │   ├── main.dart               # App shell, tabs, connection session
│   │   ├── drone_http_client.dart  # HTTP client for ESP API
│   │   ├── serial_log_cache.dart   # Shared /drone/serial polling
│   │   ├── stm32_telemetry.dart    # Telemetry line parser
│   │   ├── stm32_armed_telemetry.dart
│   │   ├── fc_tune_page.dart       # PID / filter tuning UI
│   │   ├── fc_tune_commands.dart   # STM32 command builders (31-char limit)
│   │   ├── control_page.dart       # Transmitter UI
│   │   ├── attitude_3d_page.dart   # 3D attitude tab
│   │   ├── calibration_page.dart   # ESC / IMU calibration
│   │   └── widgets/                # HUD, motion, debug live toggle, etc.
│   ├── assets/models/      # GLB 3D models (Tello, quadcopter)
│   ├── test/               # Unit tests (telemetry parsing, math, RC frames)
│   └── TUNING_UI_ESP_FIRMWARE.md   # Full STM32 CLI / telemetry spec
└── ros_integration/
    └── TUNING_UI_ESP.md    # Draft spec + gap notes (see firmware doc for truth)
```

---

## Hardware wiring

| Signal | ESP32 | STM32 (typical) |
|--------|-------|-----------------|
| ESP RX | GPIO **16** (Serial2 RX) | STM32 **TX** (LPUART1 PB6/PB7 or your mirror port) |
| ESP TX | GPIO **17** (Serial2 TX) | STM32 **RX** |
| GND | GND | GND |

> **Important:** The STM32 must parse commands on the **same UART** wired to the ESP (LPUART1). USB-only CLI will not see ESP-forwarded commands.

---

## Quick start

### 1. Flash ESP32 firmware

**Requirements:** [PlatformIO](https://platformio.org/) with Espressif32 platform.

**First flash (USB):**
```bash
cd d:\esp
pio run -e esp32dev -t upload
```

**Wi‑Fi OTA (after first USB flash):**
1. Connect PC to Wi‑Fi **ESP32-LED-CTRL** / `esp32demo`
2. Run:
   ```bash
   pio run -e esp32dev_ota -t upload
   ```
   Or use the fallback script:
   ```powershell
   .\ota_upload.ps1
   ```

OTA hostname: `esp32-led-ctrl` · OTA password: `esp32demo` · AP IP: **192.168.4.1**

### 2. Run the Flutter app

**Requirements:** Flutter SDK ≥ 3.11 (Dart ^3.11.4)

```bash
cd led_remote
flutter pub get
flutter run -d chrome          # Web
flutter run -d <android-id>    # Android device/emulator
```

**Release APK:**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### 3. Connect

1. Join Wi‑Fi **ESP32-LED-CTRL** on phone/PC
2. Open the app → enable **Live ESP**
3. Base URL should be `http://192.168.4.1` → tap **Connect**
4. Open **Serial** tab — you should see STM32 telemetry (`ARMED |`, `DISARMED |`, `LIVE |`, etc.)

---

## HTTP API (ESP32)

Base URL: `http://192.168.4.1` — all responses include CORS headers.

### LED (ESP onboard)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/led/status` | `{"on":true}` or `{"on":false}` |
| GET | `/led/toggle` | Toggle onboard LED |

### Drone command console (primary path)

| Method | Path | Body / query | Description |
|--------|------|--------------|-------------|
| POST | `/drone/command` | `cmd=<url-encoded text>` | Forward line(s) to STM32. Multi-line supported (JSON array response). |
| GET | `/drone/command` | `?cmd=arm` | Same as POST |

**ESP-local commands** (not forwarded):
- `esp led on` / `esp led off`
- `esp status`

**Line limit:** 31 characters per line on the STM32 forward path.

**Example:**
```bash
curl -X POST http://192.168.4.1/drone/command -d "cmd=disarm"
curl -X POST http://192.168.4.1/drone/command -d "cmd=pid%20show"
```

**Response fields (blocking commands):**
```json
{
  "ok": true,
  "forwarded": "arm",
  "stm32_replied": true,
  "stm32_ok": true,
  "stm32": "OK ARMED — all motors 1050 us..."
}
```

**Live RC commands** return immediately:
```json
{"ok": true, "live": true, "forwarded": "rc 0 0 0 0"}
```

### Convenience GET endpoints

| Path | Forwards to STM32 |
|------|-------------------|
| `/drone/arm` | `arm` |
| `/drone/disarm` | `disarm` |
| `/drone/test_arm` | `test arm` |
| `/drone/move_forward` | stub (no-op JSON) |
| `/drone/move_back` | stub (no-op JSON) |

### Serial monitor

| Method | Path | Description |
|--------|------|-------------|
| GET | `/drone/serial` | Recent UART lines: `{"ok":true,"lines":[...],"count":N,"exported":M}` |
| GET/POST | `/drone/serial/clear` | Clear ESP serial buffer |

The app polls `/drone/serial` via `SerialLogCache` (adaptive rate: ~1.3 s normal, faster on Tune/3D tabs, turbo when debug live is on).

---

## Telemetry

STM32 prints text lines over UART. The ESP captures them; the Flutter app parses the latest relevant line.

### Line prefixes

| Prefix | Meaning |
|--------|---------|
| `ARMED \|` | Armed snapshot — attitude, motors, PID, GPS fields |
| `DISARMED \|` | Disarmed snapshot |
| `LIVE \|` | High-rate debug stream (`debug live on`) — 10 Hz attitude + motor data |
| `TEST_ARM \|` / `TEST \|` | Motor test environment |

### Parsed fields (`FcTelemetrySnapshot`)

| Field | Example tokens |
|-------|----------------|
| Armed / hover | `armed`, `hov=1` |
| Attitude | `attR`, `attP`, `att r=… p=… y=…` |
| Setpoints | `spP`, `spR`, `spY` |
| Rates | `roll`, `pitch`, `yaw` |
| Throttle | `thr`, `throttle` |
| GPS | `lat`, `lon` |

See `led_remote/lib/stm32_telemetry.dart` and `led_remote/TUNING_UI_ESP_FIRMWARE.md` for the full parser and firmware field reference.

### Debug live

Send `debug live on` / `debug live off` to STM32 (via Tune or 3D tab toggle, or command console). Enables `LIVE |` telemetry for smoother 3D view and motor readouts.

---

## STM32 command reference (summary)

Full authoritative spec: **`led_remote/TUNING_UI_ESP_FIRMWARE.md`**

| Area | Commands |
|------|----------|
| Arm / disarm | `arm`, `disarm`, `test arm` |
| Throttle | `throttle <0-100>` |
| Limits | `armmax <us>` (disarmed, 1000–2000 µs) |
| Level hold | `stabilize on` / `stabilize off` (alias: `hover`) |
| Rate PID | `pid r\|p\|y <kp> <ki> <kd>` |
| Attitude PID | `pid ar\|ap <kp> <ki> <kd>` |
| Filters | `filter lpf <Hz>`, `filter notch <Hz> <Q>` |
| RC teleop | `rc <thr%> <yaw> <pitch> <roll>` @ ~20–40 Hz, `rc off` |
| Calibration | `cal esc`, `cal imu`, `calibrate`, `escal` |
| Debug | `debug live on`, `debug live off` |

**Bench procedure (props off):**
1. `disarm` → `armmax 2000`
2. `arm` → verify **1050 µs** on all motors
3. `stabilize on`
4. `throttle 20`–`45` → tune rate then attitude PID
5. Use **Serial** and **3D** tabs to verify telemetry before props on

---

## Data flow

```
STM32 FC  ──UART──►  ESP32  ──HTTP /drone/serial──►  SerialLogCache
     ▲                      ▲                              │
     │                      │                              ▼
     └── UART ◄── POST /drone/command ◄── DroneHttpClient ◄── UI tabs
```

**RC stick path:** Control/Manual tabs → `rc` commands → ESP live forward (no reply wait) → STM32 mixer.

**Tune path:** Tune tab → `pid`, `filter`, `throttle`, etc. → ESP blocking forward → STM32 reply → toast + Serial tab.

---

## Development

### ESP32
```bash
pio run -e esp32dev              # Build
pio device monitor -b 115200     # USB serial log
```

Edit UART pins and AP credentials in `src/main.cpp`:
```cpp
static const char *kApSsid = "ESP32-LED-CTRL";
static const char *kApPass = "esp32demo";
static const int kStm32RxPin = 16;
static const int kStm32TxPin = 17;
```

### Flutter
```bash
cd led_remote
dart analyze lib/
flutter test
```

Key extension points:
- **New STM32 commands:** Add to STM32 firmware CLI — no ESP reflash needed if ≤31 chars
- **New UI commands:** `fc_tune_commands.dart` + relevant page
- **New telemetry fields:** `stm32_telemetry.dart` / `stm32_armed_telemetry.dart`

### Ignored build artifacts (`.gitignore`)
- `.pio/` — PlatformIO build cache
- `led_remote/build/` — Flutter/APK output
- `.video_frames/`, `pio-build.log`

---

## Safety

- **Always remove props** for bench arm, ESC cal, motor test, and PID tuning.
- App enforces **throttle-at-zero** before arm on Control tab.
- **E-Stop** tab and global kill button send immediate `disarm`.
- Verify `DISARMED |` on Serial tab after any kill/disarm action.
- ESP bridge does not implement flight logic — all motor output is on the STM32 FC.

---

## Related documentation

| Document | Description |
|----------|-------------|
| `led_remote/TUNING_UI_ESP_FIRMWARE.md` | Complete STM32 CLI, telemetry, PID, calibration spec |
| `led_remote/docs/TELLO_GLB_3D.md` | Tello GLB 3D viewer integration |
| `ros_integration/TUNING_UI_ESP.md` | ROS integration draft (optional future path) |

---

## Tech stack

| Component | Stack |
|-----------|-------|
| ESP32 firmware | Arduino framework, ESP32 WebServer, ArduinoOTA, PlatformIO |
| Mobile / web app | Flutter 3, Dart 3.11+, Material 3 |
| HTTP | `http` package |
| Map | `flutter_map` + `latlong2` |
| 3D | Custom wireframe + WebView GLB engine (`tello_glb_engine.js`) |
| Audio | `audioplayers` (arm feedback) |

---

## License

No license file is included yet. Add one before public distribution if required.
