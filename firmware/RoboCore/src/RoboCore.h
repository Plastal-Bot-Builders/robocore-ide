// RoboCore V2: everything in one include.
//   #include <RoboCore.h>
// gives the pin names (RC_PIN_...), the motors, the sensors, the servos, the driving base
// (RoboCoreDrive) and the board helpers below.
#pragma once
#include <Arduino.h>
#include "RoboCoreV2Pins.h"
#include "RoboCoreMotors.h"
#include "RoboCoreSensors.h"
#include "RoboCoreServos.h"
#include "RoboCoreDrive.h"

// The built-in tunes for RoboCore::melody().
enum RoboCoreMelody : uint8_t { MELODY_POWER_UP, MELODY_POWER_DOWN, MELODY_SUCCESS, MELODY_ERROR, MELODY_ALARM };

// Remembers a yes / no value and says when it has just become true (the IDE's "when <condition>" block):
//   RoboCoreEdge when1;
//   if (when1.rose(sonar.distanceCm() < 20)) { ... }   // once each time it comes closer than 20 cm
class RoboCoreEdge {
 public:
  bool rose(bool now) {
    const bool fired = now && !_was;
    _was = now;
    return fired;
  }

 private:
  bool _was = false;
};

namespace RoboCore {

// Battery pack voltage in volts (about 3.0 to 4.2 for the 1S Li-ion pack).
// Reads close to 0 when no pack is fitted.
float batteryVolts();

// true while the USER button is held down.
bool userPressed();

// Waits until USER is pressed and released. Returns false if timeoutMs passes first (0 = wait forever).
bool waitForUser(uint32_t timeoutMs = 0);

// A beep on the buzzer. Waits while it plays.
void beep(unsigned int freqHz = 2000, unsigned long ms = 80);

// Sets the RGB LED (0-255 each), at the brightness set with ledBrightness().
void rgb(uint8_t r, uint8_t g, uint8_t b);

// ---- For the IDE's blocks
// true once per press of USER (the "when USER button is pressed" block).
bool userJustPressed();

// Seconds since the program started, or since resetTimer().
float timer();
void resetTimer();
// true once, when timer() passes this many seconds (again after resetTimer()).
bool timerPassed(float seconds);

// Brightness of the RGB LED, 0 to 100 percent (default 100). Applies to the colour at once.
void ledBrightness(float percent);

// Plays a built-in tune and waits until it ends.
void melody(RoboCoreMelody tune);

// Battery charge, 0 to 100 percent, from the voltage (3.3 V empty, 4.15 V full). 0 with no pack.
int batteryPercent();

// Stops the motors and the sound, then does nothing more until RESET is pressed.
void stopProgram();

}  // namespace RoboCore
