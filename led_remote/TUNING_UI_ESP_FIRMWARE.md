# STM32 flight-controller UART CLI — Flutter / ESP tuning spec

**Firmware tree:** `RT-STM32H755ZI-NUCLEO144_LSM_MS5611`  
**Parser entry:** `serial_handle_line()` — `src/comms/cli.c`  
**PID CLI:** `pid_tuning_command()` — `pid_tuning.c`  
**Telemetry:** `telemetry_print_snapshot()` — `src/comms/telemetry.c`  
**Transport:** USB ST-LINK VCP (USART3) + ESP mirror LPUART1 (D0/D1) — `src/comms/serial_io.c`, `esp_serial_start()`

Compared draft: `ros_integration/TUNING_UI_ESP.md` (gap analysis in §10).

---

## 1. Transport & limits

| Item | Source | Value |
|------|--------|-------|
| Baud | `flight_context.c` → `ser_usart3` | **115200 8N1** |
| Line ending | `serial_rx_feed()` — `cli.c` | **`\r` or `\n`** ends line; both accepted |
| Max line length (STM32) | `FC_SERIAL_LINE_MAX` — `fc_config.h` | **127** chars + NUL (`SERIAL_LINE_MAX`) |
| Max line (ESP forward) | *Not in STM32 firmware* | App/bridge doc: **31 chars** — shorten commands on ESP path |
| Case | `serial_cmd_tolower()` — `cli.c` | **Entire line lowercased** before parse |
| Command echo | `serial_print_prompt()` — `cli.c` | After **every** handled command: `> ` (no echo of typed line) |
| Telemetry echo filter | `serial_line_is_telemetry_echo()` — `cli.c` | Lines starting with `ax=`, `ARMED \|`, `DISARMED \|`, `TEST_ARM \|`, `TEST \|`, `MAG `, `GPS `, `LIVE \|`, or containing `imu offline` are **ignored** if sent back into RX |

### Reply formats

| Pattern | Function | Examples |
|---------|----------|----------|
| Success | `ser_printf_cmd()` | `OK ARMED — all motors 1050 us (throttle 0%). Use: stabilize on\r\n` |
| Success | `pid_tuning_reply()` → `ser_write_all()` | `OK pid rate roll 1.2 0 0.008\r\n` |
| Error | various | `ERR: IMU offline (WHO=0x6C) — cannot arm\r\n` |
| Error (pid) | `pid_reply()` | `ERR pid: axis must be r\|p\|y\|ar\|ap\r\n` |
| Unknown | `cli.c` | `Unknown command. Try:\r\n` + multi-line help |
| Long line | `serial_rx_feed()` | `Ignored long line (max 127 chars). Type: pid help\r\n` |

**No reply:** Commands that only call `ser_log()` (telemetry) — no prompt. Empty line after trim: no output, no prompt. *(Telemetry thread does not send `>`.)*

**Rate limits in firmware:** **None** enforced for `pid`, `filter`, `throttle`. Documented expectation only:

| Command | Recommended max rate | Firmware enforcement |
|---------|---------------------|----------------------|
| `rc …` | ≥ **20 Hz** (help text) | **300 ms** stick timeout → `rc_link_reset()` — `RC_LINK_TIMEOUT_MS` |
| `pid …` | ~10 Hz (re-inits controller on set) | None |
| `filter …` | Low | Resets filter state on change |
| `arm` / `disarm` | On edge | None |

---

## 2. Complete command table (tuning-related)

All commands are **lowercase** after RX. Args are space-separated unless noted.

### 2.1 Arm / throttle / limits

| Command | Args | Range | RAM default | Armed? | Disarmed? | Side effects | OK line (pattern) | ERR lines |
|---------|------|-------|-------------|--------|-----------|--------------|-------------------|-----------|
| `arm` | — | — | — | — | OK | `motor_test_env=false`, throttle→0, hover off, motors **1050 µs** all equal, `fc_flight_mode_on_arm()` | `OK ARMED — all motors 1050 us (throttle 0%). Use: stabilize on\r\n` + 2 more hint lines | `ERR: IMU offline (WHO=0xXX) — cannot arm\r\n` |
| `disarm` | — | — | — | — | OK | hover off, override cleared, RC reset, **1000 µs** | `OK DISARMED — motors idle (1000 us)\r\n` | — |
| `test arm` | — | — | — | — | OK | `motor_test_env=true`, then same as arm; **TEST_PID_SCALE** mixer | `OK TEST ARM — all motors 1050 us…` | same IMU ERR |
| `throttle` | `<pct>` | 0–100 | `cmd_throttle_pct=0` | either | either | Sets `cmd_throttle_pct`; clears override; if armed **and** `!hover_mode_enabled` → constant `esc_arm_idle_base_us()` | `OK throttle N% (~U us on M1–M4)\r\n` | `Usage: throttle <0-100>\r\n` |
| `throttle` | (empty) | — | — | either | either | Readback | `throttle N% (~U us when armed, max M us)\r\n` | — |
| `armmax` | `<us>` | 1000–2000 | **2000** | **disarmed only** | — | Sets `cmd_arm_max_us` | `OK armmax U us (throttle N% -> idle ~I us on arm)\r\n` | `ERR: disarm first…`, `ERR: armmax must be 1000-2000…` |
| `testmax` | `<us>` | 1000–2000 | **2000** | disarmed only | — | `cmd_test_max_us` | `OK testmax …` | same pattern |
| `limits` | — | — | — | either | either | Print limits | multi-line `limits: armmax …` | — |
| `spin` | — | — | — | **armed** | — | All motors `ESC_US_SPIN_TEST` (**1600 µs**) | `OK spin 1600 us on M1–M4…` | `ERR: spin — arm first…` |
| `motors` | `<us>` | 1000–2000 | — | **armed** | — | Override all 4 to fixed µs | `OK motors U us held…` | `ERR: motors — arm first…` |
| `motors` | `auto` | — | — | armed | — | Clears override, PID+throttle | `OK motors auto — throttle N%…` | — |
| `motors` | (empty) | — | — | armed | — | Status | `motors U us (override=…)` | — |

**Arm throttle rule:** **No** max-throttle gate to arm. Arm always sets `cmd_throttle_pct=0`. Any throttle % is allowed before/after arm.

**Physical arm:** A0 switch — `MotorSwitchThread` — `src/app/motor_switch.c` (toggles same as `arm`/`disarm`).

---

### 2.2 Hover / stabilize (level hold)

| Command | Args | Armed? | Effect | OK |
|---------|------|--------|--------|-----|
| `hover` / `hover on` | — | **required** | `fc_stabilize_level_hold_on()` — stabilize on, **att sp 0/0**, EKF reset from accel | `OK hover ON — level hold 0/0 deg\r\n` |
| `hover off` | — | either | `hover_mode_set(false)` only | `OK hover OFF — throttle only (no level hold)\r\n` |
| `hover show` | — | either | Status | `hover: ON/OFF (armed=… throttle N%)` |
| `stabilize on` | — | **required** | Same as hover on (level 0/0) | `OK stabilize ON — level hold 0/0 deg…` |
| `stabilize off` | — | either | `stabilize_mode_set(false)` → also hover off | `OK stabilize OFF — use hover manually\r\n` |
| `stabilize show` | — | either | | `stabilize: ON/OFF threshold=N% active=yes/no\r\n` |
| `stabilize thr` | `<pct>` | either | Sets `stabilize_throttle_pct` only | `OK stabilize threshold N%\r\n` |
| `ang on` / `ang off` | — | — | **Legacy alias** → `hover on/off` | same as hover |

**`hov=1` in telemetry** = `hover_mode_enabled` (`angle_loop` in snapshot) — `telemetry.c`.

**`stabilize on` does NOT** auto-raise throttle. Arm → **1050 µs** idle; then `stabilize on` → then `throttle N`.

---

### 2.3 PID (`pid_tuning.c` + `cli.c`)

| Command | Args | Range | Persist? | Armed set | OK / output |
|---------|------|-------|----------|-----------|-------------|
| `pid` | (empty) | — | RAM | — | 5 lines: `pid r Kp Ki Kd\r\n` … `pid ap …` |
| `pid show` | — | — | RAM | — | Same 5 lines |
| `pid help` | — | — | — | — | Multi-line help |
| `pid reset` | — | — | — | armed: `pid_arm_soft_reset()` only; disarmed: `pid_reset_all()` | `OK pid reset\r\n` |
| `pid r` | `kp ki kd` | each ≥ 0 | RAM | re-inits that PID | `OK pid rate roll Kp Ki Kd\r\n` |
| `pid p` | `kp ki kd` | ≥ 0 | RAM | re-inits | `OK pid rate pitch …` |
| `pid y` | `kp ki kd` | ≥ 0 | RAM | re-inits | `OK pid rate yaw …` |
| `pid ar` | `kp ki kd` | ≥ 0 | RAM | re-inits | `OK pid att roll …` |
| `pid ap` | `kp ki kd` | ≥ 0 | RAM | re-inits | `OK pid att pitch …` |

**NOT IN FIRMWARE:** `pid dump`, `trim` (user command), attitude `pid ay` / `pid ayaw`.

**ERR pid lines:** `ERR pid: too many arguments`, `ERR pid: axis must be r|p|y|ar|ap`, `ERR pid: controller not bound`, `ERR pid: gain must be >= 0`.

---

### 2.4 Filter (`cli.c` + `gyro_filter.c`)

| Command | Args | Default | Side effect |
|---------|------|---------|-------------|
| `filter` / `filter show` | — | LPF **80 Hz**, notch **0** (off), Q **25** | Prints via `chprintf(ser_stream,…)` — may appear on **primary** USB stream only |
| `filter lpf` | `<Hz>` | 80 | `gyro_filter_set_lpf_hz`, reset state |
| `filter lpf off` / `0` | — | — | LPF bypass |
| `filter notch` | `<Hz> <Q>` | off | Notch on |
| `filter notch` | `<Hz>` | — | Q = `FC_GYRO_NOTCH_Q_DEFAULT` (25) |
| `filter notch off` | — | — | notch off |

OK examples: `OK filter LPF 80 Hz\r\n`, `OK filter notch off\r\n`, `OK filter notch 140 Hz Q=25.0\r\n`

---

### 2.5 RC teleop (`rc_input.c`)

| Command | Args | Units | OK |
|---------|------|-------|-----|
| `rc` | `<thr%> <yaw> <pitch> <roll>` | thr 0–100; sticks **deg/s** clamped ±120 yaw, ±90 pitch/roll | `OK rc thr N% yaw Y pit P rol R\r\n` |
| `rc off` | — | Clears link | `OK rc off\r\n` |
| `rc` (empty) | — | Help | `RC: rc <thr%> <yaw> <pitch> <roll> @ 20+ Hz\r\n` |
| `rudder` | `-100..100` | % of yaw max → dps | `OK rudder N% -> yaw …` |
| `elevator` | `-100..100` | % pitch max | `OK elevator …` |
| `aileron` | `-100..100` | % roll max | `OK aileron …` |
| `yaw` | `-120..120` | dps | `OK yaw …` / `OK yaw 0 dps` |

**Interaction:** `rc` sets `cmd_throttle_pct` and stick dps; if armed, one-shot `motors_pwm_constant(esc_arm_idle_base_us())` — mixer runs in control thread. With **hover on**, roll/pitch sticks **ignored** for rate setpoint (`rc_apply_stick_setpoints`); yaw still active.

**Timeout:** 300 ms without `rc` → sticks zeroed (`rc_link_active()` false).

---

### 2.6 Flight mode / estimator (optional Expert tab)

| Command | Notes |
|---------|--------|
| `mode show` / `acro` / `stabilize` / `stab` / `angle` / `althold` / `alt` | `fc_flight_mode_set()` — boot default **stabilize** (`FC_FLIGHT_MODE_DEFAULT=1`) |
| `est show` / `est mahony` / `est ekf` | Boot: **att_ekf** if mag present (`FC_ESTIMATOR_DEFAULT_EKF`) |
| `debug live on` / `off` | **10 Hz** `LIVE \| …` stream (`FC_DEBUG_LIVE_PERIOD_MS=100`) |

---

### 2.7 Calibration / bench (not tuning sliders but valid UART)

| Command | Armed? |
|---------|--------|
| `cal esc` / `calibrate` / `escal` | disarmed (forces disarm) |
| `cal imu` | disarmed |
| `cal mag` | disarmed |
| `bench on` / `bench off` | disarmed only |
| `mag probe` | disarmed |

---

## 3. `pid show` / `pid` readback (CRITICAL)

### Exact format (from `pid_reply_gains()` — `pid_tuning.c`)

Five lines, CRLF terminated, gains as decimal (trailing zeros trimmed):

```text
pid r 1.2 0 0.008
pid p 1.2 0 0.008
pid y 0.8 0 0.004
pid ar 2.5 0 0
pid ap 2.5 0 0
```

After set: prefix **`OK pid `** + human name + gains, e.g. `OK pid rate roll 1.2 0 0.008\r\n`.

### Dart parse grammar

```text
^pid\s+(r|p|y|ar|ap)\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s*$
^OK pid (rate roll|rate pitch|rate yaw|att roll|att pitch) <same three floats>
```

### Persistence

**RAM only.** Reboot → `pid_init_all()` in `flight_controller.c` restores compile-time defaults. **No NV/flash** for PID or filter.

### “Load defaults” sequence (firmware truth)

```text
disarm
throttle 0
armmax 2000
pid r 1.2 0 0.008
pid p 1.2 0 0.008
pid y 0.8 0 0.004
pid ar 2.5 0 0
pid ap 2.5 0 0
filter lpf 80
filter notch off
```

*(Optional: `est ekf` if mag present — boot already selects EKF.)*

---

## 4. Telemetry

### 4.1 Main line — `telemetry_print_snapshot()` (`telemetry.c`)

**Format** (single `ser_log` line, IMU online):

```text
{STATUS} | ax={d}.{dd} ay={d}.{dd} az={d}.{dd} |a|={d}.{dd} m/s2 | gx=… gy=… gz=… dps | mR=… mP=… mY=… | attR=… attP=… yaw=… | spR=… spP=… spY=… | rawA={int} {int} {int} gR={int} {int} {int} seq={lu} hov={0|1} mode={acro|stabilize|angle|althold} | T={d}.{dd} C P={d}.{dd} hPa | throttle %={d}.{dd} ×4 | us={u} ×4 | PID r/p/y={d}.{dd} ×3
```

`{STATUS}` = `ARMED` | `DISARMED` | `TEST_ARM` | `TEST` — `tele_armed_status_str()`.

**Field meanings**

| Field | Source variable | Units / note |
|-------|-----------------|--------------|
| `ax,ay,az` | `ax_int`… / 100 | m/s² body (display; EKF may use Z-negated internal) |
| `\|a\|` | computed | m/s² |
| `gx,gy,gz` | `gx_int`… / 100 | **deg/s** (filtered gyro) |
| `mR,mP,mY` | `meas_*_dps` | **Gyro rate deg/s** — **not** attitude |
| `attR,attP` | `meas_roll_deg`, `meas_pitch_deg` | **Attitude deg** (EKF/Mahony) |
| `yaw` | `meas_yaw_deg` | Heading deg |
| `spR,spP,spY` | `set_*_dps` | **Rate setpoint deg/s** (outer loop output) |
| `rawA` | `accelX,Y,Z` | Body raw LSB |
| `gR` | `gyroX,Y,Z` | Sensor raw (pre-bias) |
| `seq` | `imu_read_seq` | IMU sample counter |
| `hov` | `hover_mode_enabled` | 1 = level hold active |
| `mode` | `fc_flight_mode_get()` | Flight mode name |
| `T,P` | baro | °C, hPa (integer display) |
| `throttle %` ×4 | `pwm_throttle_pct[]` / 100 | **Per-motor** “stick %” incl. idle+trim |
| `us` ×4 | `motor_esc_us[]` | ESC PWM µs |
| `PID r/p/y` | `out_roll`, `out_pitch`, `out_yaw` | **Rate PID output (deg/s)** before `ESC_PID_US_PER_DPS` scaling |

### 4.2 Periodic companion lines (same telemetry burst)

| Line | When |
|------|------|
| `MAG OK X=… Y=… Z=… mG head=…. field=…` | `mag_hw_present` |
| `MAG NA (no MMC5983 at boot)` | no mag HW |
| `EST att_ekf` or `EST mahony` | always |
| `PID idle — send hover (or rc) for stabilize trim` | armed, `hov=0`, PID outputs all 0 |
| `GPS FIX …` / `GPS NOFIX …` / `GPS NA (USART2 PD5/PD6 …)` | GPS |

### 4.3 Rates

| State | Interval | Source |
|-------|----------|--------|
| Disarmed | **1500 ms** (~0.67 Hz) | `FC_THD_TELE_INTERVAL` |
| Armed | **500 ms** (2 Hz) | `FC_THD_TELE_ARMED_INTERVAL` |
| `debug live on` | **100 ms** (10 Hz) | `FC_DEBUG_LIVE_PERIOD_MS` |

Telemetry runs when disarmed and armed (not suppressed when disarmed).

### 4.4 Example lines (realistic)

**Disarmed bench (IMU OK):**

```text
DISARMED | ax=0.02 ay=0.01 az=-9.81 |a|=9.81 m/s2 | gx=0.00 gy=0.00 gz=0.00 dps | mR=0.00 mP=0.00 mY=0.00 | attR=0.12 attP=-0.05 yaw=-102.10 | spR=0.00 spP=0.00 spY=0.00 | rawA=120 80 -4050 gR=0 0 0 seq=12045 hov=0 mode=stabilize | T=29.50 C P=989.80 hPa | throttle %=0.00 0.00 0.00 0.00 | us=1000 1000 1000 1000 | PID r/p/y=0.00 0.00 0.00
MAG OK X=75 Y=-285 Z=-27 mG head=345.26 field=296
EST att_ekf
GPS NA (USART2 PD5/PD6 — check NEO TX->PD6)
```

**Armed throttle-only (`hov=0`, after `arm`, no stabilize):**

```text
ARMED | ax=0.15 ay=0.20 az=-9.75 |a|=9.76 m/s2 | gx=-0.50 gy=0.30 gz=-0.20 dps | mR=-0.50 mP=0.30 mY=-0.20 | attR=0.20 attP=0.10 yaw=-101.90 | spR=0.00 spP=0.00 spY=0.00 | rawA=200 250 -4100 gR=-5 3 -2 seq=40000 hov=0 mode=stabilize | T=29.70 C P=989.75 hPa | throttle %=0.00 0.00 0.00 0.00 | us=1050 1050 1050 1050 | PID r/p/y=0.00 0.00 0.00
```

**Armed hover on (`stabilize on`, throttle 45%, level table):**

```text
ARMED | ax=0.17 ay=0.66 az=-9.56 |a|=9.58 m/s2 | gx=-1.46 gy=-1.27 gz=-1.07 dps | mR=-1.46 mP=-1.27 mY=-1.07 | attR=0.30 attP=0.15 yaw=-101.79 | spR=0.50 spP=-0.20 spY=0.00 | rawA=175 352 -4251 gR=-22 -14 -14 seq=34639 hov=1 mode=stabilize | T=29.80 C P=989.76 hPa | throttle %=45.00 44.80 45.10 44.90 | us=1580 1575 1585 1578 | PID r/p/y=-2.00 1.50 0.65
```

*(Bad pre-fix example had `spR=-45` and `PID r=-60` — attitude Z sign bug; app should treat as fault.)*

### 4.5 `LIVE |` line (`live_debug.c`)

```text
LIVE | ARMED ang=1 thr%=45 | att r=0.30 p=0.15 y=-101.79 | gyro r=-1.46 p=-1.27 y=-1.07 dps | set r=0.50 p=-0.20 y=0.00 | out r=-2.00 p=1.50 y=0.65 | us=1580 1575 1585 1578
```

Uses **float `%.2f`** — easier for debug UI than centi-int main line.

---

## 5. Live vs configuration

| Telemetry | What it is |
|-----------|------------|
| `PID r/p/y` | **Rate loop outputs** `out_roll/pitch/yaw` (deg/s) — `flight_context.c` → scaled by `rate_pid_apply_pwm()` × `ARM_PID_SCALE` × `ESC_PID_US_PER_DPS` (5.0 × 0.45) |
| `spR/spP/spY` | **Rate setpoints** (deg/s), not attitude targets |
| `mR/mP/mY` | Measured **gyro rates**, not angles |
| `attR/attP/yaw` | **Attitude** (deg) |

**Not in telemetry:** PID Kp/Ki/Kd, `att_sp_roll/pitch`, filter Hz, `armmax`, RC link flag.

**Why `throttle %` ≠ 0 per motor at hover:** `esc_us_to_throttle_pct()` — `stm32_pwm_esc.c` maps each motor’s **actual µs** to 0–100% scale from `cmd_throttle_pct` idle to `armmax`; PID trim adds differential µs so **per-motor %** differ even when command throttle is 45%.

---

## 6. Arm / disarm / hover state machine

```
DISARMED (us=1000)
    | arm [+ IMU OK]
    v
ARMED, hov=0, throttle=0, us=1050 all, PID trim forced 0 (no hover, no rc)
    | stabilize on | hover on
    v
ARMED, hov=1, attitude PID active, rate PIDs drive mixer
    | stabilize off | hover off
    v
ARMED, hov=0, throttle-only (still can have stabilize_mode flag)
    | disarm
    v
DISARMED
```

| Rule | Firmware |
|------|----------|
| Arm at any `cmd_throttle_pct`? | **Yes** — arm **forces** throttle to **0** |
| Max throttle to arm? | **No** limit |
| `hov=1` | Requires `hover_mode_enabled` (stabilize/hover on after arm) |
| `stabilize` without arm | **ERR stabilize — arm first** |
| Change `armmax` | **Disarm first** |
| `bench on` | **Disarm first** |
| `cal imu` / `mag` | **Disarm first** |
| `pid reset` disarmed | Full `pid_reset_all()` + estimator reset |
| `pid reset` armed | `pid_arm_soft_reset()` only |

**After `arm`:** Expect **1050 µs** all motors; send `stabilize on` before expecting level hold; then `throttle N` for climb base.

---

## 7. Defaults & bench procedure

### Firmware compile-time defaults

| Parameter | Value | File |
|-----------|-------|------|
| Rate roll/pitch Kp,Ki,Kd | 1.2, 0, 0.008 | `flight_controller.c` `pid_init_all()` |
| Rate yaw | 0.8, 0, 0.004 | same |
| Att roll/pitch | 2.5, 0, 0 | same |
| Att output limits | ±45 dps | same |
| Rate roll/pitch out limits | ±60 dps | same |
| Rate yaw out limits | ±35 dps | same |
| LPF | 80 Hz | `FC_GYRO_LPF_HZ_DEFAULT` |
| Notch | 0 (off), Q 25 | `FC_GYRO_NOTCH_*` |
| `armmax` default | **2000 µs** | `ESC_US_ARM_MAX_DEFAULT` |
| Arm idle PWM | **1050 µs** | `FC_ESC_US_ARM_IDLE` |
| `throttle` default | **0%** | `FC_THROTTLE_PCT_DEFAULT` |
| Disarmed PWM | 1000 µs | `FC_ESC_US_DISARM` |
| Boot flight mode | stabilize | `FC_FLIGHT_MODE_DEFAULT` |
| Stabilize auto on arm | **off** | `FC_STABILIZE_AUTO_DEFAULT=0` |

### Official bench order (`gyro_filter.c` header + `TUNING_UI_ESP.md` + `live_debug.c`)

1. **Props off**, rig tied; `disarm`
2. Optional: `cal imu`, `mag probe`
3. `armmax 2000` (when disarmed)
4. `arm` → verify **1050** on all `us`
5. `stabilize on` → verify `hov=1`, `attR/attP` near 0, `PID` small
6. `throttle 20`–`45` (props may need **45+** to spin — `ESC_US_SPIN_HINT` 1480)
7. Tune **rate** `pid r/p`, then **att** `pid ar/ap` with small tilts
8. Tune **yaw** `pid y` on yaw-only rig
9. Props on: `filter notch <Hz> <Q>` at motor buzz
10. Flight: `rc` @ 20–50 Hz or stick CLI

**`test arm`:** Reduced mixer scale `TEST_PID_SCALE=0.18` — safer motor twitch tests.

---

## 8. RC teleop (summary)

See §2.5. **Required:** all four fields for `rc`. **Units:** thr = percent; yaw/pitch/roll = **deg/s** (not normalized -1..1 unless app maps). **`rc off`:** clears virtual sticks and 300 ms timer; does **not** disarm or change throttle command unless you send `throttle 0`.

---

## 9. Flutter / ESP integration checklist

| Item | Spec |
|------|------|
| Forward format | Send line + `\r\n` (either CR or LF works) |
| JSON `{ "line": "..." }` | **Not parsed by STM32** — ESP must strip and forward ASCII only |
| STM32 max line | **127** chars |
| ESP max forward | **31** chars (bridge constraint — not in H755 repo) |
| Longest valid tuning cmds under 31 chars | `stabilize on` (12), `pid r 1.2 0 0.008` (18), `filter notch 140 25` (21), `filter lpf 80` (13), `throttle 45` (11), `armmax 2000` (11) — **`pid ar 2.5 0 0` OK (14)**; avoid `cal imu` on ESP if length OK (7) |
| Hide in Problems filter | `ARMED \|`, `DISARMED \|`, `TEST_ARM \|`, `TEST \|`, `MAG `, `GPS `, `EST `, `LIVE \|`, `ax=`, lines with `imu offline`, `PID idle —` |
| Show | `OK `, `ERR `, `Unknown command`, `> `, user-requested `pid …` responses |
| After command | Expect `OK`/`ERR` within ~100 ms; then `>` |
| Poll gains | Send `pid show` — not in telemetry stream |
| Known firmware quirks | (1) `filter show` may use `ser_stream` only. (2) `throttle` no longer resets estimator when hover on. (3) `mR`≠roll angle — use `attR`. (4) Mag slow when armed. (5) No heading-hold PID — yaw rate hold only. (6) Commands lowercased. (7) `arm` resets throttle to 0. |

---

## 10. Gap analysis vs `ros_integration/TUNING_UI_ESP.md`

| Draft doc | Firmware truth | Action for app |
|-----------|----------------|----------------|
| Default `throttle 20` | **0%**, idle **1050 µs** not 1200 | Use `throttle 0` + `arm`; climb via `throttle N` after stabilize |
| `armmax 1300` in app | Default **2000** | Change `FcTuneDefaults.armmax` to **2000** unless user sets |
| `hover` only for level hold | **`stabilize on`** equivalent | Expose both labels → same command |
| `arm` → immediate stabilize | **No** — throttle-only until `stabilize on` | UI flow: arm → stabilize → throttle |
| Telemetry `yaw` only for attitude | **`attR`/`attP` added** | Parse `attR`/`attP`; do not use `mR` as angle |
| `mR/mP/mY` as attitude | **Gyro rates** | Rename UI labels “rate meas” |
| `spR` as attitude target | **Rate setpoint deg/s** | Cap display ±45 = outer loop limit |
| `PID r/p/y` “mixer” | **Rate PID output (dps)** | Correct label |
| Default profile `throttle 20` | **0** | Fix load-defaults |
| `pid dump` | **NOT IN FIRMWARE** | Remove button |
| `trim` command | **NOT IN FIRMWARE** | Remove |
| `filter show` reply | May not mirror to ESP if `ser_stream`≠ESP | Send `filter lpf 80` and assume, or read USB |
| Persist PID | **RAM only** | “Save” = re-send on connect |
| `pid reset` | Armed ≠ full reset | Warn user |
| Bench `hover` before tune | Still valid but use **`stabilize on`** | Update copy |
| architecture-as-built “armmax 1800” | **2000** | Doc drift — trust `fc_config.h` |
| architecture “no mag” | **MMC5983 + att_ekf** present | Parse `MAG`/`EST` lines |
| 31-char ESP limit | Not in firmware | Keep short commands on ESP path |

---

## 11. Dart appendix

**Omitted** per request (firmware spec only). Use §3 regex and §4 field table to update `fc_tune_commands.dart`, `FcTuneDefaults`, and `stm32_armed_telemetry.dart` in the Flutter project.

---

## Source index (quick)

| Topic | File |
|-------|------|
| Command dispatch | `src/comms/cli.c` → `serial_handle_line()` |
| PID CLI | `pid_tuning.c` |
| RC | `src/comms/rc_input.c` |
| Telemetry | `src/comms/telemetry.c` |
| Arm | `src/app/arming.c` |
| Hover/stabilize | `src/control/flight_controller.c` |
| Defaults | `include/fc/fc_config.h`, `flight_controller.c` `pid_init_all()` |
| Mixer/PWM | `src/platform/stm32_pwm_esc.c` |
| Filters | `src/control/gyro_filter.c` |
