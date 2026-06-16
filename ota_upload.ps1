# Wi-Fi OTA upload without PlatformIO tool-manager (use if "HTTPClientError" on pio upload).
# 1. Connect PC to Wi-Fi "ESP32-LED-CTRL" (password esp32demo)
# 2. Run: .\ota_upload.ps1

$ErrorActionPreference = "Stop"
$fw = Join-Path $PSScriptRoot ".pio\build\esp32dev\firmware.bin"
if (-not (Test-Path $fw)) {
    Write-Host "Building firmware first..."
    Set-Location $PSScriptRoot
    pio run -e esp32dev
    if (-not (Test-Path $fw)) { throw "Missing $fw" }
}

$pkg = Join-Path $env:USERPROFILE ".platformio\packages\framework-arduinoespressif32\tools\espota.py"
if (-not (Test-Path $pkg)) {
    throw "espota.py not found. Run once: pio run -e esp32dev -t upload"
}

Write-Host "OTA to 192.168.4.1 (password esp32demo)..."
python $pkg -i 192.168.4.1 -f $fw -a esp32demo -r
