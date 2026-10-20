// RoboCore V2 driving base: both wheels together, with the encoders and the IMU
// (the IDE's Movement blocks).
//
//   #include <RoboCore.h>
//   RoboCoreMotors motors;
//   IMU imu;
//   RoboCoreDrive robot(motors, imu);
//   robot.move(10, CM);      // forward 10 cm (negative = backwards), waits until done
//   robot.turn(90);          // right 90 degrees (negative = left), using the IMU
//   robot.start(FORWARD);    // keeps going until robot.stop()
//
// Distances use the wheel size (one turn of a 60 mm wheel = 18.8 cm) and the encoder counts per
// wheel turn (motors.setCountsPerTurn()). Turns use the IMU heading, or the encoders if the IMU
// does not answer.
#pragma once
#include <Arduino.h>
#include "RoboCoreMotors.h"
#include "RoboCoreSensors.h"

class RoboCoreDrive {
 public:
  RoboCoreDrive(RoboCoreMotors &motors, IMU &imu) : _m(motors), _imu(imu) {}

  // Drives straight for an amount: CM, ROTATIONS (wheel turns) or SECONDS; negative goes backwards.
  // Waits until done, then brakes. Gives up after a while if the wheels cannot turn.
  void move(float amount, RoboCoreUnit unit = CM);

  // Turns on the spot: positive = right (clockwise seen from above), negative = left. Waits until done.
  void turn(float degrees);

  // Starts driving and keeps going (FORWARD or BACKWARD) until stop() or another movement.
  void start(RoboCoreDirection direction = FORWARD);

  // Starts driving with steering from -100 to 100: 0 straight, 50 one wheel stopped, 100 spins on the spot.
  // Positive steers right.
  void steer(float steering);

  // Stops both wheels quickly (brake).
  void stop();

  // Speed for move, turn, start and steer, 0 to 100 percent (default 50).
  void setSpeed(float percent);
  float speed() const { return _speed; }

  // How far the robot goes in one turn of a wheel, in cm (default 18.8, a 60 mm wheel).
  void setWheelCm(float cm) { if (cm > 0) _wheelCm = cm; }

  // Distance between the middle of the two wheels, in cm, for turns without the IMU (default 15.5).
  void setTrackCm(float cm) { if (cm > 0) _trackCm = cm; }

  // Distance driven since the program started (or resetDistance()), in cm: the average of both wheels.
  float distanceCm() const;
  void resetDistance();

 private:
  float _cmPerCount() const { return _wheelCm / _m.countsPerTurn(); }
  RoboCoreMotors &_m;
  IMU &_imu;
  float _speed = 50, _wheelCm = 18.8f, _trackCm = 15.5f;
  long _l0 = 0, _r0 = 0;
};
