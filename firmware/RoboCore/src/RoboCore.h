// RoboCore V2: everything in one include.
//   #include <RoboCore.h>
// gives the pin names (RC_PIN_...), the motors, the sensors and the board helpers below.
#pragma once
#include <Arduino.h>
#include "RoboCoreV2Pins.h"
#include "RoboCoreMotors.h"
#include "RoboCoreSensors.h"

namespace RoboCore {

// Battery pack voltage in volts (about 3.0 to 4.2 for the 1S Li-ion pack).
// Reads close to 0 when no pack is fitted.
float batteryVolts();

// true while the USER button is held down.
bool userPressed();

// Waits until USER is pressed and released. Returns false if timeoutMs passes first (0 = wait forever).
bool waitForUser(uint32_t timeoutMs = 0);

// Short beep on the buzzer.
void beep(unsigned int freqHz = 2000, unsigned long ms = 80);

// Sets the RGB LED (0-255 each).
void rgb(uint8_t r, uint8_t g, uint8_t b);

}  // namespace RoboCore
