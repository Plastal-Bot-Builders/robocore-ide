# RoboCore V2 pin map (Rev 2.0)

Source: the board as built (V2-01 and V2-02), pins checked at the ESP32 module's pads on 2026-11-06.
The guide for users, with example sketches, is
[`RoboCore_V2_pin_reference.md`](https://github.com/Plastal-Bot-Builders/RoboCoreDocumentation/blob/main/docs/RoboCore_V2_pin_reference.md).
The same numbers live in code in `firmware/RoboCore/src/RoboCoreV2Pins.h`. Change them there, here and in the pin
reference together.

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
| IO47 | Buzzer | Drives a low-side N-FET; magnetic buzzer on VSYS_SW. Use `tone()`: `digitalWrite(47, HIGH)` only clicks and leaves the coil on |
| IO48 | RGB LED | WS2812B-2020-V6. `LED_BUILTIN` / `RGB_BUILTIN` in the Arduino core. `digitalWrite(48, HIGH)` doesn't light it |

There is no plain single-colour user LED. `digitalWrite(LED_BUILTIN, HIGH)` lights the RGB LED white.

The parts on the board have no IO numbers printed beside them, only the headers do (errata E-016). Uno habits don't
carry over: pin 8 is I²C SDA, and `A0` means IO1, the IMU interrupt.

## I²C devices

| Device | Address |
|---|---|
| LSM6DSOX 6-axis IMU | 0x6A (SA0 = GND), WHO_AM_I = 0x6C |
| Qwiic socket | 3.3 V, JST SH 4-pin |

## Connectors

| Connector | Pins |
|---|---|
| Motor 1, Motor 2 (J301, J302, JST SH 6) | 1 M+, 2 M-, 3 3.3 V, 4 encoder A, 5 encoder B, 6 GND. **XRP motors need a reversed 6-way cable** (pin 1 to pin 6): the V2 sockets number the pins from the other end (errata E-015) |
| Ultrasonic (J403, 2.54 mm 1×4 header) | 3V3, TRIG (IO40), ECHO (IO41), GND, as printed: an HC-SR04's order, so a straight cable works. 3.3 V modules only |
| Line follower (J404, 2.54 mm 1×5 header) | 3V3, GND, L (IO7), C (IO10), R (IO2), as printed (3× TCRT5000, analog). Line modules differ: check the order first (E-009) |
| Servo 1-4 (J401, J402, J407, J408, 3-pin) | signal, + (VMOT 5.5 V), −, printed as IOnn, 5.5V, GND |
| Expansion A, B (J405, J406) | 2.54 mm female, 14 pins, names printed on the back. See below |

### Expansion headers

| Pin | A (J405) | B (J406) |
|---|---|---|
| 1 | 3.3 V | 3.3 V |
| 2 | GND | GND |
| 3 | Line L (IO7) | I²C SDA (IO8) ⚠ |
| 4 | Line C (IO10) | I²C SCL (IO9) ⚠ |
| 5 | Line R (IO2) | UART TX (IO43) |
| 6 | Ultrasonic TRIG (IO40) | UART RX (IO44) |
| 7 | Ultrasonic ECHO (IO41) | Servo 3 (IO35) |
| 8 | Servo 1 (IO38) | Servo 4 (IO36) |
| 9 | Servo 2 (IO39) | IO37 |
| 10 | Buzzer (IO47) ⚠ | IMU INT1 (IO1) ⚠ |
| 11 | RGB LED data out ⚠ | USER button (IO42) ⚠ |
| 12 | IO3 | EN (reset) ⚠ |
| 13 | VMOT 5.5 V ⚠ | VSYS_SW ⚠ |
| 14 | GND | GND |

Pins without ⚠ have a 330 Ω resistor in series to the ESP32. Pins marked ⚠ have none: SDA, SCL, IMU INT1, USER,
BUZZER and RGB data out connect straight through (errata E-004), and EN sits on B12 right next to VSYS_SW on B13
(E-003). 5.5 V from A13 on a ⚠ pin can destroy the ESP32, the IMU or the LED.

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
