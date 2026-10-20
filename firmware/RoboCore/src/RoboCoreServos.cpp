#include "RoboCoreServos.h"

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "The RoboCore library is for the RoboCore V2 (ESP32-S3). In Tools > Board pick ESP32S3 Dev Module."
#endif

namespace {
constexpr uint32_t kServoHz = 50;    // one pulse every 20 ms
constexpr uint8_t kServoBits = 14;   // 16383 steps per 20 ms
constexpr uint32_t kServoMax = (1u << kServoBits) - 1;
constexpr uint8_t kServoPins[4] = {RC_PIN_SERVO1, RC_PIN_SERVO2, RC_PIN_SERVO3, RC_PIN_SERVO4};
}  // namespace

void RoboCoreServos::write(int port, float degrees) {
  const int i = _index(port);
  if (i < 0) return;
  if (degrees != degrees) degrees = 90;  // NaN
  degrees = constrain(degrees, 0.0f, 180.0f);
  if (!_attached[i]) _attached[i] = ledcAttach(kServoPins[i], kServoHz, kServoBits);
  _angle[i] = degrees;
  const float us = _minUs + (_maxUs - _minUs) * degrees / 180.0f;
  ledcWrite(kServoPins[i], (uint32_t)(us * kServoMax / 20000.0f + 0.5f));
}

float RoboCoreServos::angle(int port) const {
  const int i = _index(port);
  return i < 0 ? 0 : _angle[i];
}

void RoboCoreServos::release(int port) {
  const int i = _index(port);
  if (i < 0 || !_attached[i]) return;
  ledcWrite(kServoPins[i], 0);
}

void RoboCoreServos::setPulseRange(int minUs, int maxUs) {
  if (minUs < 300 || maxUs > 2800 || minUs >= maxUs) return;
  _minUs = minUs;
  _maxUs = maxUs;
}
