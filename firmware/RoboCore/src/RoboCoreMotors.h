// RoboCore V2 motors: two DC motors on a DRV8411A, with encoders and current sense.
//
//   #include <RoboCoreMotors.h>
//   RoboCoreMotors motors;
//   motors.begin();
//   motors.drive(60, 60);   // left %, right %  (-100 to 100)
//   motors.stop();
//
// Motor 1 is the left wheel and motor 2 the right wheel. On the XRP-style chassis the
// right motor is mounted mirrored, so it is reversed by default: drive(60, 60) goes forward.
// If a wheel turns the wrong way on your robot, call setReversed().
//
// The motors are off at power-up and stay off until your sketch drives them
// (the DRV8411A inputs have pull-downs, and begin() holds them low).
#pragma once
#include <Arduino.h>
#include "RoboCoreV2Pins.h"

class RoboCoreMotors {
 public:
  // Sets up PWM and the encoders. Returns false if a pin could not be set up.
  // Called for you on the first drive() if you forget it.
  bool begin();

  // Speed for each motor in percent, -100 (full reverse) to 100 (full forward).
  void drive(float leftPercent, float rightPercent);

  // Lets both motors coast to a stop (both driver inputs low).
  void stop();

  // Stops both motors quickly (both driver inputs high).
  void brake();

  // Flips a motor's direction (and its encoder count). Default: left false, right true.
  void setReversed(bool left, bool right);

  // Encoder counts since begin() or resetEncoders(). Positive = forward.
  long leftCount() const;
  long rightCount() const;
  void resetEncoders();

  // If a wheel drives forward but its count goes down, flip that encoder here.
  void setEncoderReversed(bool left, bool right);

  // Motor current in milliamps, from the driver's current mirror.
  float leftCurrentmA() const;
  float rightCurrentmA() const;

  // true while the driver reports a fault (over-current, over-temperature or low VMOT).
  bool fault() const;

  // Last speeds set with drive(), in percent.
  float leftSpeed() const { return _left; }
  float rightSpeed() const { return _right; }

 private:
  void _set(uint8_t in1, uint8_t in2, float percent, bool reversed);
  bool _begun = false;
  bool _revL = false, _revR = true;
  bool _encRevL = false, _encRevR = false;
  float _left = 0, _right = 0;
};
