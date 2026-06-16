# Tuning UI & ESP command spec (app draft)

**Authoritative firmware spec:** `led_remote/TUNING_UI_ESP_FIRMWARE.md`  
Use that file for command spelling, telemetry fields, defaults, and gap fixes.

Transport: **115200 8N1**, lines end with `\r\n`. Same commands on USB and ESP (D0/D1). Max **31 chars** on ESP forward path; STM32 accepts up to **127** chars.

## Quick reference (firmware truth)

| Area | Commands |
|------|----------|
| Arm | `arm` (forces throttle 0%, motors 1050 µs) · `disarm` |
| Limits | `armmax <us>` (disarmed only, default **2000**) |
| Level hold | **`stabilize on`** / `stabilize off` (or `hover` alias) |
| Throttle | `throttle <0-100>` after arm + stabilize |
| Rate PID | `pid r\|p\|y <kp> <ki> <kd>` |
| Attitude PID | `pid ar\|ap <kp> <ki> <kd>` |
| Read gains | `pid show` (5 lines, RAM only) |
| Filters | `filter lpf <Hz>`, `filter notch off` |
| RC | `rc <thr> <yaw> <pitch> <roll>` · `rc off` |z

## Bench order

1. `disarm` → `armmax 2000`
2. `arm` → verify **1050 µs** on all motors
3. `stabilize on` → `hov=1`
4. `throttle 20`–`45` → tune rate then attitude PID
5. Props on: `filter notch <Hz> <Q>`

## Telemetry

Parse `ARMED |` / `DISARMED |` — see firmware doc §4 for `attR`, `attP`, `mR/mP/mY` (gyro rates), `PID r/p/y` (rate output deg/s), per-motor `throttle %` and `us`.

## Flutter files

- `led_remote/lib/fc_tune_page.dart`
- `led_remote/lib/fc_tune_commands.dart`
- `led_remote/lib/stm32_armed_telemetry.dart`
