// RoboCore V2 servo ports 1-4 (IO38, IO39, IO35, IO36), powered from VMOT.
//
//   #include <RoboCore.h>
//   RoboCoreServos servos;
//   servos.write(1, 90);   // port 1 to 90 degrees
//
// The servos only move while the ON/OFF switch is ON (VMOT). Works with SG90 / MG90S hobby servos.
#pragma once
#include <Arduino.h>
#include "RoboCoreV2Pins.h"

class RoboCoreServos {
 public:
  // Turns the servo on a port (1 to 4) to an angle, 0 to 180 degrees.
  void write(int port, float degrees);

  // The angle last set on that port (90 before any).
  float angle(int port) const;

  // Stops the pulses on that port, so the servo goes limp and can be turned by hand.
  void release(int port);

  // Pulse widths for 0 and 180 degrees, in microseconds (default 500 and 2400, SG90 / MG90S).
  void setPulseRange(int minUs, int maxUs);

 private:
  static int _index(int port) { return port >= 1 && port <= 4 ? port - 1 : -1; }
  bool _attached[4] = {false, false, false, false};
  float _angle[4] = {90, 90, 90, 90};
  int _minUs = 500, _maxUs = 2400;
};
