#include "RoboCoreDrive.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "The RoboCore library is for the RoboCore V2 (ESP32-S3). In Tools > Board pick ESP32S3 Dev Module."
#endif

namespace {
// How long a movement may take before it gives up (a wheel is stuck, or the encoders are unplugged):
// three times as long as it should, plus 2 s. An XRP wheel turns about 1.5 times a second at full speed.
uint32_t patienceMs(float wheelTurns, float percent) {
  return (uint32_t)(wheelTurns / (1.5f * percent / 100.0f) * 3000.0f) + 2000;
}
}  // namespace

void RoboCoreDrive::move(float amount, RoboCoreUnit unit) {
  if (std::isnan(amount) || amount == 0) return;
  const float dir = amount < 0 ? -1.0f : 1.0f;
  amount = fabsf(amount);
  const float sp = constrain(_speed, 5.0f, 100.0f);
  if (unit == SECONDS) {
    _m.drive(dir * sp, dir * sp);
    delay((uint32_t)(amount * 1000.0f));
    stop();
    return;
  }
  const float turns = unit == CM ? amount / _wheelCm : unit == DEGREES ? amount / 360.0f : amount;
  const float target = turns * _m.countsPerTurn();
  const long l0 = _m.leftCount(), r0 = _m.rightCount();
  const uint32_t t0 = millis(), limit = patienceMs(turns, sp);
  for (;;) {
    const long dl = labs(_m.leftCount() - l0), dr = labs(_m.rightCount() - r0);
    const float done = (dl + dr) / 2.0f;
    if (done >= target || millis() - t0 > limit) break;
    // Slower for the last fifth; and the wheel that is ahead slows a little, to keep straight.
    const float v = done > target * 0.8f ? std::min(sp, std::max(sp * 0.6f, 20.0f)) : sp;
    const float c = constrain((dl - dr) * 0.5f, -20.0f, 20.0f);
    _m.drive(dir * (v - c), dir * (v + c));
    delay(2);
  }
  stop();
}

void RoboCoreDrive::turn(float degrees) {
  if (std::isnan(degrees) || degrees == 0) return;
  const float dir = degrees > 0 ? 1.0f : -1.0f;
  const float target = fabsf(degrees);
  const float sp = constrain(_speed, 15.0f, 60.0f);  // slower than driving, for a sharper stop
  const bool useImu = _imu.begin();
  const float y0 = useImu ? _imu.yawDeg() : 0.0f;
  const long l0 = _m.leftCount(), r0 = _m.rightCount();
  // Without the IMU, each wheel drives its share of the circle between the two wheels.
  const float countsForTurn = target / 360.0f * (float)M_PI * _trackCm / _cmPerCount();
  const uint32_t t0 = millis(), limit = patienceMs(countsForTurn / _m.countsPerTurn(), sp);
  for (;;) {
    const float done = useImu ? fabsf(_imu.yawDeg() - y0)
                              : (labs(_m.leftCount() - l0) + labs(_m.rightCount() - r0)) / 2.0f / countsForTurn * target;
    // Brake 2 degrees early: the robot turns on a little after the brake.
    if (done >= target - 2.0f || millis() - t0 > limit) break;
    const float v = target - done < 20.0f ? std::min(sp, std::max(sp * 0.5f, 15.0f)) : sp;
    _m.drive(dir * v, -dir * v);
    delay(2);
  }
  stop();
}

void RoboCoreDrive::start(RoboCoreDirection direction) {
  const float v = _speed * (direction == BACKWARD ? -1.0f : 1.0f);
  _m.drive(v, v);
}

void RoboCoreDrive::steer(float steering) {
  if (std::isnan(steering)) steering = 0;
  const float s = constrain(steering, -100.0f, 100.0f);
  float l = _speed, r = _speed;
  if (s > 0) r = _speed * (1.0f - s / 50.0f);
  if (s < 0) l = _speed * (1.0f + s / 50.0f);
  _m.drive(l, r);
}

void RoboCoreDrive::stop() { _m.brake(); }

void RoboCoreDrive::setSpeed(float percent) {
  if (!std::isnan(percent)) _speed = constrain(percent, 0.0f, 100.0f);
}

float RoboCoreDrive::distanceCm() const {
  return ((_m.leftCount() - _l0) + (_m.rightCount() - _r0)) / 2.0f * _cmPerCount();
}

void RoboCoreDrive::resetDistance() {
  _l0 = _m.leftCount();
  _r0 = _m.rightCount();
}
