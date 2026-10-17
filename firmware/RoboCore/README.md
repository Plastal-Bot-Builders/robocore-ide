# RoboCore Arduino library

C++ library for the **RoboCore V2** robot controller (Rev 2.0, ESP32-S3-WROOM-1-N8R2).
The RoboCore IDE's blocks and examples call these classes, and the compile server builds every sketch against it.

```cpp
#include <RoboCore.h>          // everything: pins, motors, sensors, board helpers
// or just what you need:
#include <RoboCoreMotors.h>    // RoboCoreMotors
#include <RoboCoreSensors.h>   // Sonar, LineSensor, IMU
```

| Class / function | What it does |
|---|---|
| `RoboCoreMotors` | `begin()`, `drive(left%, right%)` (−100…100), `stop()` (coast), `brake()`, `leftCount()` / `rightCount()` encoders, `resetEncoders()`, `leftCurrentmA()` / `rightCurrentmA()`, `fault()`, `setReversed(l, r)`, `setEncoderReversed(l, r)` |
| `Sonar` | `begin()`, `distanceCm()` (returns 400 when nothing echoes), `lastEchoOk()` |
| `LineSensor` | `begin()`, `read()` (−1 line left … 0 centred … 1 right), `left()` / `centre()` / `right()` darkness 0…1, raw readings, `resetCalibration()`, `setDarkIsHigh()` |
| `IMU` | `begin()`, `temperature()` °C, `tiltDeg()`, `accelX/Y/Z()` g, `gyroX/Y/Z()` °/s, `read(...)` |
| `RoboCore::` | `batteryVolts()`, `userPressed()`, `waitForUser()`, `beep()`, `rgb()` |
| `RC_PIN_...` | Every pin on the board, from `src/RoboCoreV2Pins.h` |

## Safety

- The motors are off at power-up and stay off until a sketch drives them.
  The driver inputs have pull-downs, and `begin()` holds them low.
- Each motor is limited to 1.0 A by the driver.
- The motor and servo supply (VMOT) is off while the ON/OFF switch is OFF, even on USB.

## Direction

Motor 1 is the **left** wheel and motor 2 the **right**. The right motor is reversed by default
(XRP-style mirrored mounting), so `drive(60, 60)` goes forward. If a wheel spins the wrong way,
call `motors.setReversed(left, right)` in `setup()`, and tell us so the default can be fixed.

## Arduino IDE settings

Board **ESP32S3 Dev Module** (esp32 by Espressif **3.3.12**), USB CDC On Boot **Enabled**,
USB Mode **Hardware CDC and JTAG**, Flash **8MB**, Partition **8M with spiffs**, PSRAM **QSPI PSRAM**.

FQBN: `esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240`

To install by hand, copy this `RoboCore` folder into your Arduino `libraries` folder.

## Examples

`BoardTest` checks every part of the board. The other 15 are the RoboCore IDE examples, with pins fixed for the V2.

## Tests

`firmware/tests/host/run.sh` checks the library and examples on a PC (no ESP32 compiler needed).
The real ESP32-S3 compile runs in `.github/workflows/firmware.yml`.
