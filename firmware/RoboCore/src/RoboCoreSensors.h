// RoboCore V2 sensors: ultrasonic (Sonar), 3-channel line sensor (LineSensor) and IMU (IMU).
//
//   #include <RoboCoreSensors.h>
//   Sonar sonar;       float cm  = sonar.distanceCm();
//   LineSensor line;   float pos = line.read();        // -1 line far left .. 0 centred .. 1 far right
//   IMU imu;           float t   = imu.temperature();  float tilt = imu.tiltDeg();
//
// Call begin() in setup(). If you forget, the first reading calls it for you.
#pragma once
#include <Arduino.h>
#include "RoboCoreV2Pins.h"

// ---------------------------------------------------------------------------
// Ultrasonic distance (RoboCore ultrasonic board, CS100A / HC-SR04 timing)
class Sonar {
 public:
  explicit Sonar(float maxCm = 400.0f) : _maxCm(maxCm) {}
  bool begin();

  // Distance to the nearest object in centimetres.
  // Returns the maximum range (400 cm by default) when nothing echoes back,
  // so "if (cm < 20)" only fires for something really in front of the robot.
  float distanceCm();

  // false if the last distanceCm() got no echo (nothing in range, or the sensor is unplugged).
  bool lastEchoOk() const { return _lastOk; }

  // true once, when something comes closer than cm (the IDE's "when obstacle is closer than" block).
  // It measures each time it is called: call it often, for example on every pass of loop().
  bool justCloserThan(float cm);

 private:
  float _maxCm;
  bool _begun = false, _lastOk = false;
  uint32_t _lastPingMs = 0;
  // One memory per distance asked about.
  float _edgeCm[4] = {-1, -1, -1, -1};
  bool _edgeWas[4] = {false, false, false, false};
};

// ---------------------------------------------------------------------------
// Line sensor (RoboCore line board: 3x TCRT5000, analog)
class LineSensor {
 public:
  bool begin();

  // Line position: -1.0 = line under the left sensor, 0 = centre, 1.0 = right.
  // When no sensor sees the line it returns -1 or 1, the side it was last seen on.
  float read();

  // How dark each sensor sees the floor, 0.0 (white) to 1.0 (black line).
  float left();
  float centre();
  float right();

  // Raw ADC readings (0-4095).
  int rawLeft() const { return analogRead(RC_PIN_LINE_LEFT); }
  int rawCentre() const { return analogRead(RC_PIN_LINE_CENTRE); }
  int rawRight() const { return analogRead(RC_PIN_LINE_RIGHT); }

  // The sensor learns white and black as it moves over them. Call this to start learning again.
  void resetCalibration();

  // Default true: a dark line gives a higher reading. Set false if your sensor board is the other way round.
  void setDarkIsHigh(bool darkIsHigh) { _darkHigh = darkIsHigh; }

  // true while at least one sensor sees the line (darker than half way).
  bool onLine();
  // true once, when the line is found / lost (the IDE's "when the line is found / lost" block).
  bool justFound();
  bool justLost();

 private:
  float _norm(int i, int raw);
  bool _begun = false, _darkHigh = true;
  bool _wasFound = false, _wasLost = true;  // "lost" only after it was found
  int _lo[3] = {4095, 4095, 4095};
  int _hi[3] = {0, 0, 0};
  float _last = 0;
};

// ---------------------------------------------------------------------------
// IMU (LSM6DSOX accelerometer + gyro on I2C 0x6A)
class IMU {
 public:
  // Starts I2C on IO8/IO9 and configures the IMU. Returns false if it does not answer.
  bool begin();
  bool ok() const { return _ok; }

  // Board temperature in degrees C (from the IMU's sensor).
  float temperature();

  // How far the board is tilted from flat, in degrees (0 = flat, 90 = on its side).
  float tiltDeg();

  // Acceleration in g and rotation in degrees per second.
  float accelX();
  float accelY();
  float accelZ();
  float gyroX();
  float gyroY();
  float gyroZ();

  // Reads all six axes at once. Returns false if the read failed.
  bool read(float &ax, float &ay, float &az, float &gx, float &gy, float &gz);

  // ---- Heading and attitude (the IDE's Sensors and Events blocks)
  // Heading in degrees since begin() or resetYaw(); turning right (clockwise seen from above) counts up.
  // Kept up to date in the background from the gyro. Keep the robot still while begin() runs: it measures
  // the gyro's offset. Drifts by about a degree a minute.
  float yawDeg();
  void resetYaw();
  // If yaw counts the wrong way on your robot, reverse it here.
  void setYawReversed(bool reversed) { _yawSign = reversed ? 1.0f : -1.0f; }
  // Nose up / right side down, in degrees, from the accelerometer.
  float pitchDeg();
  float rollDeg();
  // More than 30° from flat / a knock or shake (more than 0.5 g away from still) / within 10° of flat.
  bool isTilted();
  bool isShaken();
  bool isFlat();
  // true once, when it becomes tilted / is shaken / becomes flat.
  bool justTilted();
  bool justShaken();
  bool justFlat();
  // Adds up the gyro since the last call. The background task calls it every 5 ms.
  void update();

 private:
  bool _readRegs(uint8_t reg, uint8_t *buf, size_t n);
  bool _write(uint8_t reg, uint8_t val);
  int16_t _axis(uint8_t reg);
  void _startYaw();
  bool _begun = false, _ok = false;
  volatile float _yaw = 0;
  float _bias = 0, _yawSign = -1.0f;
  unsigned long _lastUs = 0;
  bool _task = false;
  bool _wasTilted = false, _wasShaken = false, _wasFlat = true;  // "flat" only after a tilt
};
