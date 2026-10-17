# RoboCore V2 pin map (Rev 2.0)

Source: `RoboCore_V2_schematic_rev2.0.pdf` (draft, 2026-10-04).
The same numbers live in code in `firmware/RoboCore/src/RoboCoreV2Pins.h`. Change them there and here together.

## Chip and USB

| Item | Value |
|---|---|
| Module | ESP32-S3-WROOM-1-**N8R2**: 8 MB flash, 2 MB **quad** PSRAM |
| USB-C | Straight to the ESP32-S3 (IO19 D-, IO20 D+). No USB-UART chip. |
| Download mode | Hold **BOOT** (IO0), tap **RESET** (EN), release BOOT |
| Arduino board | **ESP32S3 Dev Module** (esp32 by Espressif 3.3.12) |
| Arduino settings | USB CDC On Boot: Enabled · USB Mode: Hardware CDC and JTAG · Flash 8MB · Partition 8M with spiffs · PSRAM: **QSPI PSRAM** (not OPI) |
| FQBN | `esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240` |

## GPIO map

| GPIO | Use | Notes |
|---|---|---|
| IO0 | BOOT button | LOW when pressed, 10k pull-up. Strapping pin. |
| IO1 | IMU INT1 | LSM6DSOX interrupt 1 |
| IO2 | Line sensor right | ADC1 |
| IO3 | Expansion (EXP_IO3) | Strapping pin (JTAG source); leave free at boot. ADC1. |
| IO4 | Battery / 2 | ADC1. 100k/100k divider: volts = reading × 2 |
| IO5 | Motor 1 current | ADC1. DRV8411A IPROPI into 16.5k: 3.3 V per amp |
| IO6 | Motor 2 current | ADC1. Same scale |
| IO7 | Line sensor left | ADC1 |
| IO8 | I²C SDA | 4.7k pull-up. IMU and Qwiic |
| IO9 | I²C SCL | 4.7k pull-up |
| IO10 | Line sensor centre | ADC1 |
| IO11, IO12 | Motor 1 IN1, IN2 | DRV8411A. PWM sets speed, the pair sets direction; both low = coast |
| IO13, IO14 | Motor 2 IN1, IN2 | DRV8411A |
| IO15, IO16 | Encoder 1 A, B | 10k pull-ups to 3.3 V |
| IO17, IO18 | Encoder 2 A, B | 10k pull-ups to 3.3 V |
| IO19, IO20 | USB D-, D+ | Do not use |
| IO21 | Motor driver nFAULT | LOW = fault (over-current, over-temperature, under-voltage) |
| IO35 | Servo 3 | Free on N8R2 only; an R8 (octal PSRAM) module uses IO35-37 |
| IO36 | Servo 4 | Same |
| IO37 | Expansion (EXP_IO37) | Same |
| IO38 | Servo 1 | |
| IO39 | Servo 2 | |
| IO40 | Ultrasonic TRIG | CS100A board (HC-SR04 timing), 3.3 V |
| IO41 | Ultrasonic ECHO | |
| IO42 | USER button | LOW when pressed, 10k pull-up. Free for sketches |
| IO43, IO44 | UART0 TX, RX | On expansion header B. `Serial` uses USB, so these are free |
| IO45, IO46 | Not connected | Strapping pins, left open |
| IO47 | Buzzer | Drives a low-side N-FET; magnetic buzzer on VSYS_SW. Use `tone()` |
| IO48 | RGB LED | WS2812B-2020-V6. `LED_BUILTIN` / `RGB_BUILTIN` in the Arduino core |

There is no plain single-colour user LED. `digitalWrite(LED_BUILTIN, HIGH)` lights the RGB LED white.

## I²C devices

| Device | Address |
|---|---|
| LSM6DSOX 6-axis IMU | 0x6A (SA0 = GND), WHO_AM_I = 0x6C |
| Qwiic socket | 3.3 V, JST SH 4-pin |

## Connectors

| Connector | Pins |
|---|---|
| Motor 1, Motor 2 (XRP JST SH 6) | 1 M+, 2 M-, 3 3.3 V, 4 encoder A, 5 encoder B, 6 GND |
| Ultrasonic (JST SH 4) | GND, 3V3, TRIG, ECHO |
| Line follower (JST SH 5) | GND, 3V3, L, C, R (3× TCRT5000, analog) |
| Servo 1-4 (3-pin) | signal, + (VMOT 5.5 V), − |
| Expansion A, B | 2.54 mm female, 330R in series with every ESP32 pin |

## Power

| Rail | Notes |
|---|---|
| VBUS / +5V_USB | USB-C 5 V, 1.5 A resettable fuse |
| +BATT | 1S Li-ion on XT30, reverse and over-voltage protected (2S/3S packs are blocked) |
| VSYS | Charger power path (MCP73871), from USB or battery |
| VSYS_SW | VSYS after the ON/OFF switch |
| +3V3 | TPS63001 buck-boost from VSYS_SW |
| VMOT | 5.5 V TPS61089 boost for the motor driver and servos. **Off when the switch is OFF**, even on USB |

Motor current is limited to 1.0 A per motor by the DRV8411A (VREF / IPROPI).
