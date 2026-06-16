#include <Arduino.h>
#include <ArduinoOTA.h>
#include <WiFi.h>
#include <WebServer.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

static const char *kApSsid = "ESP32-LED-CTRL";
static const char *kApPass = "esp32demo";
/// OTA upload password (PlatformIO: upload_flags = --auth=esp32demo)
static const char *kOtaPassword = "esp32demo";

// UART link to STM32 — cross TX/RX, common GND. Change pins to match your wiring.
static const int kStm32RxPin = 16;  // ESP32 RX2 ← STM32 TX
static const int kStm32TxPin = 17;  // ESP32 TX2 → STM32 RX
static const uint32_t kStm32Baud = 115200;

#define STM32_SERIAL Serial2

static WebServer server(80);

static bool ledOn = false;
static bool g_armed = false;

static void sendCorsHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "*");
}

static void handleOptionsGeneric() {
  sendCorsHeaders();
  server.send(204);
}

static String jsonEscape(const String &s) {
  String o;
  o.reserve(s.length() + 8);
  for (size_t i = 0; i < s.length(); ++i) {
    const unsigned char c = static_cast<unsigned char>(s[i]);
    if (c == '\\') {
      o += "\\\\";
    } else if (c == '"') {
      o += "\\\"";
    } else if (c == '\n') {
      o += "\\n";
    } else if (c == '\r') {
    } else if (c >= 0x20 && c < 0x7F) {
      o += static_cast<char>(c);
    } else {
      // Drop invalid UTF-8 / binary UART noise so phone JSON decode never crashes.
      o += '?';
    }
  }
  return o;
}

static const size_t kSerialLogMax = 64;
static const size_t kSerialExportMax = 64;
static const size_t kSerialLineMax = 160;
static const size_t kUartPollMaxBytes = 256;
static String g_serialLog[kSerialLogMax];
static size_t g_serialLogNext = 0;
static size_t g_serialLogCount = 0;
static String g_uartPartial;

static String sanitizeUartLine(const String &line) {
  String o;
  o.reserve(line.length());
  for (size_t i = 0; i < line.length(); ++i) {
    const unsigned char c = static_cast<unsigned char>(line[i]);
    if (c >= 0x20 && c < 0x7F) {
      o += static_cast<char>(c);
    } else if (c == '\t') {
      o += ' ';
    }
  }
  return o;
}

static String truncateLogLine(const String &line) {
  const String clean = sanitizeUartLine(line);
  if (clean.length() <= kSerialLineMax) {
    return clean;
  }
  return clean.substring(0, kSerialLineMax);
}

static void appendSerialLogLine(const String &line) {
  if (line.length() == 0) {
    return;
  }
  g_serialLog[g_serialLogNext] = truncateLogLine(line);
  g_serialLogNext = (g_serialLogNext + 1) % kSerialLogMax;
  if (g_serialLogCount < kSerialLogMax) {
    g_serialLogCount++;
  }
}

/// Feed one byte into the shared line buffer; returns true when [outLine] is complete.
static bool uartFeedChar(const char c, String *outLine) {
  if (c == '\r') {
    return false;
  }
  if (c == '\n') {
    if (g_uartPartial.length() > 0) {
      *outLine = g_uartPartial;
      g_uartPartial = "";
      appendSerialLogLine(*outLine);
      return true;
    }
    return false;
  }
  g_uartPartial += c;
  if (g_uartPartial.length() > 120) {
    *outLine = g_uartPartial;
    g_uartPartial = "";
    appendSerialLogLine(*outLine);
    return true;
  }
  return false;
}

/// Drain pending STM32 bytes into the serial log (never discard telemetry).
static void drainStm32UartToLog(size_t maxBytes = 512) {
  String line;
  size_t bytes = 0;
  while (STM32_SERIAL.available() && bytes < maxBytes) {
    bytes++;
    if (uartFeedChar(static_cast<char>(STM32_SERIAL.read()), &line)) {
      line = "";
    }
  }
}

/// Drain STM32 UART in small chunks so HTTP stays responsive during telemetry bursts.
static void pollStm32Uart() {
  drainStm32UartToLog(kUartPollMaxBytes);
}

static void clearSerialLog() {
  g_serialLogNext = 0;
  g_serialLogCount = 0;
  g_uartPartial = "";
}

/// Read one line from STM32 UART (responses like "OK ARMED ..." then ">").
static String readStm32Line(uint32_t timeoutMs) {
  String line;
  const uint32_t deadline = millis() + timeoutMs;
  while (millis() < deadline) {
    while (STM32_SERIAL.available()) {
      if (uartFeedChar(static_cast<char>(STM32_SERIAL.read()), &line)) {
        return line;
      }
    }
    delay(2);
  }
  return "";
}

/// Collect STM32 lines until timeout or a line that looks like OK ARMED / OK DISARMED / error list.
static String readStm32Response(uint32_t timeoutMs) {
  String all;
  const uint32_t deadline = millis() + timeoutMs;
  while (millis() < deadline) {
    const String line = readStm32Line(150);
    if (line.length() == 0) {
      delay(5);
      continue;
    }
    if (all.length()) {
      all += " | ";
    }
    all += line;
    if (line.indexOf("OK") >= 0 || line.indexOf("ARMED") >= 0 || line.indexOf("DISARMED") >= 0 ||
        line.indexOf("Commands:") >= 0) {
      return all;
    }
  }
  return all;
}

static bool isCalHelpCmd(const char *cmd) { return strcmp(cmd, "cal help") == 0; }

static bool isEscCalCmd(const char *cmd) {
  return strcmp(cmd, "calibrate") == 0 || strcmp(cmd, "escal") == 0 || strcmp(cmd, "cal esc") == 0;
}

static bool isImuCalCmd(const char *cmd) { return strcmp(cmd, "cal imu") == 0; }

static bool isEscCalDone(const String &text) {
  String u = text;
  u.toUpperCase();
  return u.indexOf("ESC CAL DONE") >= 0;
}

static bool isImuCalDone(const String &text) {
  String u = text;
  u.toUpperCase();
  return u.indexOf("IMU CAL DONE") >= 0 || u.indexOf("OK IMU CAL") >= 0 ||
         u.indexOf("IMU CAL OK") >= 0 || u.indexOf("IMU CALIBRATED") >= 0;
}

static bool calibrationComplete(const String &all, const char *cmd) {
  if (isEscCalCmd(cmd)) {
    return isEscCalDone(all);
  }
  if (isImuCalCmd(cmd)) {
    return isImuCalDone(all);
  }
  return false;
}

/// Calibration: keep reading UART until DONE or timeout (do not stop on early "OK" steps).
static String readStm32CalibrationResponse(uint32_t timeoutMs, const char *cmd) {
  String all;
  const uint32_t deadline = millis() + timeoutMs;
  while (millis() < deadline) {
    const String line = readStm32Line(250);
    if (line.length() == 0) {
      delay(5);
      continue;
    }
    if (all.length()) {
      all += " | ";
    }
    all += line;
    if (calibrationComplete(all, cmd)) {
      return all;
    }
    if (line.indexOf("FAILED") >= 0 || line.indexOf("ERROR") >= 0) {
      return all;
    }
  }
  return all;
}

/// True for high-rate teleop lines — no wait for STM32 reply (low latency).
static bool isLiveTeleopCmd(const char *cmd) {
  return strcmp(cmd, "rc off") == 0 || strcmp(cmd, "disarm") == 0 ||
         strncmp(cmd, "rc ", 3) == 0 || strncmp(cmd, "rudder ", 7) == 0 ||
         strncmp(cmd, "elevator ", 9) == 0 || strncmp(cmd, "aileron ", 8) == 0 ||
         strncmp(cmd, "yaw ", 4) == 0 || strncmp(cmd, "throttle ", 9) == 0 ||
         strncmp(cmd, "joy ", 4) == 0;
}

static bool isCalibrationCmd(const char *cmd) {
  if (strncmp(cmd, "cal ", 4) == 0) {
    return true;
  }
  return strcmp(cmd, "calibrate") == 0 || strcmp(cmd, "escal") == 0;
}

/// Fire-and-forget UART for rc / rudder / yaw / legacy throttle+joy.
static String forwardStm32Live(const char *cmd) {
  if (strlen(cmd) > 31) {
    return "{\"ok\":false,\"error\":\"cmd_too_long\"}";
  }
  drainStm32UartToLog();
  STM32_SERIAL.println(cmd);
  STM32_SERIAL.flush();
  Serial.printf("[→STM32 live] %s\n", cmd);
  return String("{\"ok\":true,\"live\":true,\"forwarded\":\"") + jsonEscape(String(cmd)) + "\"}";
}

/// STM32 commands that need a reply (arm, disarm, etc.).
static String forwardStm32Command(const char *cmd) {
  if (strlen(cmd) > 31) {
    return "{\"ok\":false,\"error\":\"cmd_too_long\"}";
  }

  drainStm32UartToLog();

  STM32_SERIAL.println(cmd);
  STM32_SERIAL.flush();
  delay(80);

  const bool isCal = isCalibrationCmd(cmd);
  const bool isCalRun = isCal && !isCalHelpCmd(cmd);
  uint32_t waitMs = 2500;
  if (isEscCalCmd(cmd)) {
    waitMs = 20000;
  } else if (isImuCalCmd(cmd)) {
    waitMs = 10000;
  } else if (isCal) {
    waitMs = 16000;
  }

  const String resp =
      isCalRun ? readStm32CalibrationResponse(waitMs, cmd) : readStm32Response(waitMs);
  const bool replied = resp.length() > 0;
  const bool calDone = isCalRun && calibrationComplete(resp, cmd);
  bool stm32Ok = false;
  if (isCalRun) {
    stm32Ok = calDone;
  } else {
    stm32Ok = replied && (resp.indexOf("OK") >= 0 || resp.indexOf("ARMED") >= 0 ||
                          resp.indexOf("DISARMED") >= 0 || resp.indexOf("ESC cal DONE") >= 0);
  }
  const bool stm32Rejected = replied && resp.indexOf("Commands:") >= 0;

  Serial.printf("[→STM32] %s\n", cmd);
  if (replied) {
    Serial.printf("[←STM32] %s\n", resp.c_str());
  } else {
    Serial.println("[←STM32] (no reply — STM32 may only listen on USB until LPUART1 PB6/PB7 is enabled)");
  }

  // ok=true means ESP sent on UART; stm32_ok tells the app if the flight controller accepted it.
  String json = String("{\"ok\":true,\"forwarded\":\"") + jsonEscape(String(cmd)) + "\"";
  json += ",\"stm32_replied\":" + String(replied ? "true" : "false");
  json += ",\"stm32_ok\":" + String(stm32Ok ? "true" : "false");
  if (isCalRun) {
    json += ",\"cal_complete\":" + String(calDone ? "true" : "false");
  }
  if (resp.length()) {
    json += ",\"stm32\":\"" + jsonEscape(resp) + "\"";
  }
  if (!replied) {
    json += ",\"warning\":\"no_stm32_reply\",\"hint\":\"Enable LPUART1 on STM32 (PB6/PB7) for ESP UART, or "
            "check TX/RX/GND @ 115200\"";
  } else if (stm32Rejected) {
    json += ",\"warning\":\"unknown_command\",\"hint\":\"STM32 only accepts: arm | test arm | disarm\"";
  } else if (isCalRun && !calDone) {
    json += ",\"warning\":\"cal_not_complete\",\"hint\":\"No ESC cal DONE / IMU cal DONE on UART — "
            "check STM32 LPUART1 (PB6/PB7) and serial monitor\"";
  } else if (!stm32Ok) {
    json += ",\"warning\":\"unexpected_reply\"";
  }
  json += "}";
  return json;
}

static void handleDroneArmHttp() {
  sendCorsHeaders();
  g_armed = true;
  server.send(200, "application/json", forwardStm32Command("arm"));
}

static void handleDroneDisarmHttp() {
  sendCorsHeaders();
  g_armed = false;
  server.send(200, "application/json", forwardStm32Command("disarm"));
}

static void handleDroneTestArmHttp() {
  sendCorsHeaders();
  server.send(200, "application/json", forwardStm32Command("test arm"));
}

static String firstToken(String *restOut, const String &line) {
  String l = line;
  l.trim();
  const int sp = l.indexOf(' ');
  if (sp < 0) {
    *restOut = "";
    return l;
  }
  *restOut = l.substring(sp + 1);
  (*restOut).trim();
  return l.substring(0, sp);
}

/// ESP-local commands only when line starts with "esp " (onboard LED, etc.).
static String executeEspLocalLine(const String &espLine) {
  String rest;
  String w1 = firstToken(&rest, espLine);
  w1.toLowerCase();
  String r2 = rest;
  r2.toLowerCase();

  if (w1 == "status") {
    return String("{\"ok\":true,\"action\":\"esp_status\",\"led\":") + (ledOn ? "true" : "false") +
           ",\"armed\":" + (g_armed ? "true" : "false") + "}";
  }

  if (w1 == "led") {
    if (r2 == "on" || r2 == "1") {
      ledOn = true;
      digitalWrite(LED_BUILTIN, HIGH);
      return "{\"ok\":true,\"action\":\"esp_led\",\"on\":true}";
    }
    if (r2 == "off" || r2 == "0") {
      ledOn = false;
      digitalWrite(LED_BUILTIN, LOW);
      return "{\"ok\":true,\"action\":\"esp_led\",\"on\":false}";
    }
    if (r2 == "toggle") {
      ledOn = !ledOn;
      digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
      return String("{\"ok\":true,\"action\":\"esp_led\",\"on\":") + (ledOn ? "true" : "false") + "}";
    }
    return "{\"ok\":false,\"error\":\"esp_led_usage\",\"hint\":\"esp led on|off|toggle\"}";
  }

  return "{\"ok\":false,\"error\":\"unknown_esp_cmd\",\"hint\":\"esp status | esp led on|off|toggle\"}";
}

/// Command box: default = pass full line to STM32. No ESP update needed when you add STM32 commands.
static String executeCommandLine(const String &rawLine) {
  String line = rawLine;
  line.trim();
  if (line.length() == 0) {
    return "{\"ok\":false,\"error\":\"empty_line\"}";
  }

  String lineLower = line;
  lineLower.toLowerCase();

  if (lineLower == "help") {
    return "{\"ok\":true,\"action\":\"help\",\"text\":\"STM32: rc <thr%> <yaw> <pit> <rol> @40Hz|"
           "rudder|elevator|aileron|yaw|rc off. thr 0-100, yaw ±120, pit/rol ±90 dps. esp led|status. "
           "Max 31 chars/line.\"}";
  }

  if (lineLower.startsWith("esp ")) {
    String espPart = line.substring(4);
    espPart.trim();
    return executeEspLocalLine(espPart);
  }
  if (lineLower == "esp") {
    return "{\"ok\":false,\"error\":\"esp_usage\",\"hint\":\"esp led on | esp status\"}";
  }

  if (line.length() > 31) {
    return "{\"ok\":false,\"error\":\"line_too_long\",\"max\":31}";
  }

  if (lineLower == "arm") {
    g_armed = true;
  } else if (lineLower == "disarm") {
    g_armed = false;
  }

  if (isLiveTeleopCmd(line.c_str())) {
    return forwardStm32Live(line.c_str());
  }

  return forwardStm32Command(line.c_str());
}

/// Runs one or more non-empty lines. Single line → one JSON object; multiple lines → JSON array.
static void handleDroneCommand() {
  sendCorsHeaders();
  String raw;
  if (server.method() == HTTP_GET) {
    raw = server.arg("cmd");
  } else if (server.method() == HTTP_POST) {
    if (server.hasArg("cmd")) {
      raw = server.arg("cmd");
    } else if (server.hasArg("plain")) {
      raw = server.arg("plain");
    } else {
      server.send(400, "application/json",
                  "{\"error\":\"missing cmd\",\"hint\":\"POST form field cmd=... (URL-encoded text, "
                  "multiple lines OK)\"}");
      return;
    }
  } else {
    server.send(405, "text/plain", "use GET or POST");
    return;
  }

  raw.trim();
  if (raw.length() == 0) {
    server.send(400, "application/json", "{\"error\":\"empty cmd\"}");
    return;
  }

  const bool multiline = raw.indexOf('\n') >= 0 || raw.indexOf('\r') >= 0;
  if (!multiline) {
    server.send(200, "application/json", executeCommandLine(raw));
    return;
  }

  String norm = raw;
  norm.replace("\r\n", "\n");
  norm.replace('\r', '\n');
  String out = "[";
  int count = 0;
  int start = 0;
  while (start <= norm.length()) {
    const int nl = norm.indexOf('\n', start);
    const String chunk = nl < 0 ? norm.substring(start) : norm.substring(start, nl);
    start = nl < 0 ? norm.length() + 1 : nl + 1;
    String line = chunk;
    line.trim();
    if (line.length() == 0) {
      continue;
    }
    if (count++) {
      out += ",";
    }
    out += executeCommandLine(line);
  }
  if (count == 0) {
    server.send(400, "application/json", "{\"error\":\"only_blank_lines\"}");
    return;
  }
  out += "]";
  server.send(200, "application/json", out);
}

static void handleStatus() {
  sendCorsHeaders();
  const char *body = ledOn ? "{\"on\":true}" : "{\"on\":false}";
  server.send(200, "application/json", body);
}

static void handleToggle() {
  ledOn = !ledOn;
  digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
  sendCorsHeaders();
  const char *body = ledOn ? "{\"on\":true}" : "{\"on\":false}";
  server.send(200, "application/json", body);
}

static void handleDroneStub() {
  sendCorsHeaders();
  server.send(200, "application/json", "{\"ok\":true,\"stub\":true}");
}

/// Recent STM32 UART lines captured by ESP (for app serial monitor).
static void handleDroneSerial() {
  sendCorsHeaders();
  const size_t exportCount =
      g_serialLogCount < kSerialExportMax ? g_serialLogCount : kSerialExportMax;
  const size_t skip = g_serialLogCount - exportCount;
  const size_t oldest = (g_serialLogNext + kSerialLogMax - g_serialLogCount) % kSerialLogMax;

  String json;
  json.reserve(exportCount * (kSerialLineMax + 8) + 48);
  json = "{\"ok\":true,\"lines\":[";
  for (size_t i = skip; i < g_serialLogCount; ++i) {
    if (i > skip) {
      json += ",";
    }
    json += "\"";
    json += jsonEscape(g_serialLog[(oldest + i) % kSerialLogMax]);
    json += "\"";
  }
  json += "],\"count\":";
  json += String(g_serialLogCount);
  json += ",\"exported\":";
  json += String(exportCount);
  json += "}";
  server.send(200, "application/json", json);
}

static void handleDroneSerialClear() {
  sendCorsHeaders();
  clearSerialLog();
  server.send(200, "application/json", "{\"ok\":true,\"cleared\":true}");
}

static void handleRoot() {
  sendCorsHeaders();
  String msg = "<h3>Command console</h3><p>POST <code>/drone/command</code> — each line is forwarded to "
                "STM32 as-is (max 31 chars). Add new STM32 commands without reflashing ESP.</p><pre>";
  msg += "help\n";
  msg += "arm | disarm | test arm | throttle ...\n";
  msg += "esp led on   (ESP onboard LED only)\n";
  msg += "esp status\n";
  msg += "</pre><p>API: http://";
  msg += WiFi.softAPIP().toString();
  msg += "</p><p>OTA: <code>pio run -e esp32dev_ota -t upload</code> (PC on this Wi‑Fi, password ";
  msg += kOtaPassword;
  msg += ")</p>";
  server.send(200, "text/html", msg);
}

static void setupOta() {
  ArduinoOTA.setHostname("esp32-led-ctrl");
  ArduinoOTA.setPassword(kOtaPassword);

  ArduinoOTA.onStart([]() {
    Serial.println("[OTA] Update starting — drone HTTP paused");
  });
  ArduinoOTA.onEnd([]() { Serial.println("\n[OTA] Update complete, rebooting…"); });
  ArduinoOTA.onProgress([](const unsigned int progress, const unsigned int total) {
    Serial.printf("[OTA] %u%%\r", total ? (progress * 100) / total : 0);
  });
  ArduinoOTA.onError([](const ota_error_t err) {
    Serial.printf("[OTA] Error %u\n", err);
  });

  ArduinoOTA.begin();
  Serial.println("[OTA] Ready — join AP then: pio run -e esp32dev_ota -t upload");
}

void setup() {
  Serial.begin(115200);
  STM32_SERIAL.begin(kStm32Baud, SERIAL_8N1, kStm32RxPin, kStm32TxPin);
  delay(200);
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  ledOn = false;

  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(kApSsid, kApPass)) {
    Serial.println("softAP failed");
    while (true) {
      delay(1000);
    }
  }

  Serial.println();
  Serial.print("Join Wi-Fi SSID: ");
  Serial.println(kApSsid);
  Serial.print("HTTP API: http://");
  Serial.println(WiFi.softAPIP());
  Serial.printf("STM32 UART: %u baud, RX=%d TX=%d — command box forwards any line to STM32\\n", kStm32Baud,
                kStm32RxPin, kStm32TxPin);
  Serial.println("Note: STM32 must parse this UART (LPUART1 PB6/PB7). USB-only parser will ignore ESP.");

  setupOta();

  server.on("/", HTTP_GET, handleRoot);
  server.on("/led/status", HTTP_GET, handleStatus);
  server.on("/led/status", HTTP_OPTIONS, handleOptionsGeneric);
  server.on("/led/toggle", HTTP_GET, handleToggle);
  server.on("/led/toggle", HTTP_OPTIONS, handleOptionsGeneric);

  server.on("/drone/command", HTTP_POST, handleDroneCommand);
  server.on("/drone/command", HTTP_GET, handleDroneCommand);
  server.on("/drone/command", HTTP_OPTIONS, handleOptionsGeneric);
  // Some HTTP stacks request a trailing slash — register both.
  server.on("/drone/command/", HTTP_POST, handleDroneCommand);
  server.on("/drone/command/", HTTP_GET, handleDroneCommand);
  server.on("/drone/command/", HTTP_OPTIONS, handleOptionsGeneric);

  server.onNotFound([]() {
    sendCorsHeaders();
    const String u = server.uri();
    Serial.printf("[HTTP 404] %s method=%d\n", u.c_str(), static_cast<int>(server.method()));
    server.send(404, "application/json",
                 String("{\"error\":\"not_found\",\"uri\":\"") + jsonEscape(u) + "\",\"hint\":\"Flash "
                        "latest firmware; base URL should be http://192.168.4.1 with no extra path\"}");
  });

  server.on("/drone/arm", HTTP_GET, handleDroneArmHttp);
  server.on("/drone/disarm", HTTP_GET, handleDroneDisarmHttp);
  server.on("/drone/test_arm", HTTP_GET, handleDroneTestArmHttp);
  server.on("/drone/move_forward", HTTP_GET, handleDroneStub);
  server.on("/drone/move_back", HTTP_GET, handleDroneStub);
  server.on("/drone/arm", HTTP_OPTIONS, handleOptionsGeneric);
  server.on("/drone/disarm", HTTP_OPTIONS, handleOptionsGeneric);
  server.on("/drone/test_arm", HTTP_OPTIONS, handleOptionsGeneric);
  server.on("/drone/move_forward", HTTP_OPTIONS, handleOptionsGeneric);
  server.on("/drone/move_back", HTTP_OPTIONS, handleOptionsGeneric);

  server.on("/drone/serial", HTTP_GET, handleDroneSerial);
  server.on("/drone/serial", HTTP_OPTIONS, handleOptionsGeneric);
  server.on("/drone/serial/clear", HTTP_POST, handleDroneSerialClear);
  server.on("/drone/serial/clear", HTTP_GET, handleDroneSerialClear);
  server.on("/drone/serial/clear", HTTP_OPTIONS, handleOptionsGeneric);

  server.begin();
}

void loop() {
  server.handleClient();
  pollStm32Uart();
  ArduinoOTA.handle();
  server.handleClient();
}