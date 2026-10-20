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

// Which wheel, which way, and the units of the IDE's motor and movement blocks.
enum RoboCoreSide : uint8_t { LEFT, RIGHT };
enum RoboCoreDirection : int8_t { BACKWARD = -1, FORWARD = 1 };
enum RoboCoreUnit : uint8_t { CM, ROTATIONS, DEGREES, SECONDS };

// Encoder counts for one turn of the wheel. XRP motors: 3 pulses per motor turn on channel A,
// counted on both edges (6), through a 48.75:1 gearbox. Turn a wheel once by hand and read
// leftCount() to check yours, then call setCountsPerTurn().
constexpr float RC_COUNTS_PER_WHEEL_TURN = 292.5f;

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

  // ---- One wheel at a time (the IDE's Motors blocks)
  // Runs one motor for an amount (ROTATIONS, DEGREES or SECONDS; negative = backwards), then brakes it.
  // Waits until it has finished. Gives up after a while if the wheel cannot turn.
  void run(RoboCoreSide side, float amount, RoboCoreUnit unit = ROTATIONS, float percent = 50);
  // Starts one motor at a speed (-100 to 100) and leaves it running.
  void start(RoboCoreSide side, float percent);
  // Lets one motor coast to a stop.
  void stop(RoboCoreSide side);
  // Stops one motor quickly.
  void brake(RoboCoreSide side);
  // The wheel's position in degrees since begin() or resetPosition(): 360 = one turn forward.
  float positionDeg(RoboCoreSide side) const;
  void resetPosition(RoboCoreSide side);
  // The speed last set for that motor, in percent.
  float speedPercent(RoboCoreSide side) const { return side == LEFT ? _left : _right; }
  // Encoder count of one side (leftCount() or rightCount()).
  long count(RoboCoreSide side) const { return side == LEFT ? leftCount() : rightCount(); }

  // Encoder counts for one wheel turn (RC_COUNTS_PER_WHEEL_TURN unless set).
  void setCountsPerTurn(float counts) { if (counts > 0) _perTurn = counts; }
  float countsPerTurn() const { return _perTurn; }

  // The motors begin() was last called on, for RoboCore::stopProgram().
  static RoboCoreMotors *active() { return _active; }

 private:
  void _set(uint8_t in1, uint8_t in2, float percent, bool reversed);
  bool _begun = false;
  bool _revL = false, _revR = true;
  bool _encRevL = false, _encRevR = false;
  float _left = 0, _right = 0;
  float _perTurn = RC_COUNTS_PER_WHEEL_TURN;
  long _pos0[2] = {0, 0};
  static RoboCoreMotors *_active;
};
