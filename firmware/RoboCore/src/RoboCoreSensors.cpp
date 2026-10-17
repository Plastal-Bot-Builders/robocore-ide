#include "RoboCoreSensors.h"
#include <Wire.h>

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "The RoboCore library is for the RoboCore V2 (ESP32-S3). In Tools > Board pick ESP32S3 Dev Module."
#endif

// ============================ Sonar ============================

bool Sonar::begin() {
  pinMode(RC_PIN_SONAR_TRIG, OUTPUT);
  digitalWrite(RC_PIN_SONAR_TRIG, LOW);
  pinMode(RC_PIN_SONAR_ECHO, INPUT);
  _begun = true;
  return true;
}

float Sonar::distanceCm() {
  if (!_begun) begin();
  // Leave 30 ms between pings so a late echo from the last one is not read as this one.
  uint32_t since = millis() - _lastPingMs;
  if (since < 30) delay(30 - since);
  digitalWrite(RC_PIN_SONAR_TRIG, LOW);
  delayMicroseconds(4);
  digitalWrite(RC_PIN_SONAR_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(RC_PIN_SONAR_TRIG, LOW);
  // Sound takes 58 us per cm there and back; wait a little longer than the max range.
  unsigned long timeoutUs = (unsigned long)(_maxCm * 58.0f) + 2000UL;
  unsigned long us = pulseIn(RC_PIN_SONAR_ECHO, HIGH, timeoutUs);
  _lastPingMs = millis();
  if (us == 0) {
    _lastOk = false;
    return _maxCm;
  }
  _lastOk = true;
  float cm = us / 58.0f;
  return cm > _maxCm ? _maxCm : cm;
}

// ========================= LineSensor ==========================

bool LineSensor::begin() {
  analogReadResolution(12);
  analogSetPinAttenuation(RC_PIN_LINE_LEFT, ADC_11db);
  analogSetPinAttenuation(RC_PIN_LINE_CENTRE, ADC_11db);
  analogSetPinAttenuation(RC_PIN_LINE_RIGHT, ADC_11db);
  _begun = true;
  return true;
}

void LineSensor::resetCalibration() {
  for (int i = 0; i < 3; i++) {
    _lo[i] = 4095;
    _hi[i] = 0;
  }
}

float LineSensor::_norm(int i, int raw) {
  if (raw < _lo[i]) _lo[i] = raw;
  if (raw > _hi[i]) _hi[i] = raw;
  int span = _hi[i] - _lo[i];
  float v;
  if (span < 400) {
    // Not seen black and white yet: use the raw reading.
    v = raw / 4095.0f;
  } else {
    v = (raw - _lo[i]) / (float)span;
  }
  if (!_darkHigh) v = 1.0f - v;
  return constrain(v, 0.0f, 1.0f);
}

float LineSensor::left() {
  if (!_begun) begin();
  return _norm(0, analogRead(RC_PIN_LINE_LEFT));
}
float LineSensor::centre() {
  if (!_begun) begin();
  return _norm(1, analogRead(RC_PIN_LINE_CENTRE));
}
float LineSensor::right() {
  if (!_begun) begin();
  return _norm(2, analogRead(RC_PIN_LINE_RIGHT));
}

float LineSensor::read() {
  float l = left(), c = centre(), r = right();
  float sum = l + c + r;
  if (sum < 0.25f || (l < 0.2f && c < 0.2f && r < 0.2f)) {
    // Lost the line: say which side it was last seen on.
    return _last < 0 ? -1.0f : (_last > 0 ? 1.0f : 0.0f);
  }
  float pos = (r - l) / sum;  // weighted average of -1, 0, 1
  _last = constrain(pos, -1.0f, 1.0f);
  return _last;
}

// ============================= IMU =============================

namespace {
constexpr uint8_t kWhoAmI = 0x0F;
constexpr uint8_t kWhoAmIValue = 0x6C;  // LSM6DSOX
constexpr uint8_t kCtrl1Xl = 0x10;
constexpr uint8_t kCtrl2G = 0x11;
constexpr uint8_t kCtrl3C = 0x12;
constexpr uint8_t kOutTempL = 0x20;
constexpr uint8_t kOutxLG = 0x22;
constexpr uint8_t kOutxLA = 0x28;
constexpr float kGPerLsb = 0.061f / 1000.0f;    // +/-2 g
constexpr float kDpsPerLsb = 8.75f / 1000.0f;   // 250 dps
bool gWireStarted = false;
}  // namespace

bool IMU::_readRegs(uint8_t reg, uint8_t *buf, size_t n) {
  Wire.beginTransmission(RC_IMU_I2C_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(RC_IMU_I2C_ADDR, n) != n) return false;
  for (size_t i = 0; i < n; i++) buf[i] = Wire.read();
  return true;
}

bool IMU::_write(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(RC_IMU_I2C_ADDR);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission() == 0;
}

bool IMU::begin() {
  _begun = true;
  if (!gWireStarted) {
    Wire.begin(RC_PIN_I2C_SDA, RC_PIN_I2C_SCL, 400000);
    gWireStarted = true;
  }
  uint8_t who = 0;
  _ok = _readRegs(kWhoAmI, &who, 1) && who == kWhoAmIValue;
  if (!_ok) return false;
  _ok = _write(kCtrl3C, 0x44)       // block data update + register auto-increment
        && _write(kCtrl1Xl, 0x40)   // accelerometer 104 Hz, +/-2 g
        && _write(kCtrl2G, 0x40);   // gyro 104 Hz, 250 dps
  delay(20);
  return _ok;
}

int16_t IMU::_axis(uint8_t reg) {
  if (!_begun) begin();
  uint8_t b[2] = {0, 0};
  if (!_ok || !_readRegs(reg, b, 2)) return 0;
  return (int16_t)((b[1] << 8) | b[0]);
}

float IMU::temperature() { return 25.0f + _axis(kOutTempL) / 256.0f; }
float IMU::accelX() { return _axis(kOutxLA) * kGPerLsb; }
float IMU::accelY() { return _axis(kOutxLA + 2) * kGPerLsb; }
float IMU::accelZ() { return _axis(kOutxLA + 4) * kGPerLsb; }
float IMU::gyroX() { return _axis(kOutxLG) * kDpsPerLsb; }
float IMU::gyroY() { return _axis(kOutxLG + 2) * kDpsPerLsb; }
float IMU::gyroZ() { return _axis(kOutxLG + 4) * kDpsPerLsb; }

bool IMU::read(float &ax, float &ay, float &az, float &gx, float &gy, float &gz) {
  if (!_begun) begin();
  uint8_t b[12];
  if (!_ok || !_readRegs(kOutxLG, b, 12)) return false;
  auto v = [&](int i) { return (int16_t)((b[i + 1] << 8) | b[i]); };
  gx = v(0) * kDpsPerLsb;
  gy = v(2) * kDpsPerLsb;
  gz = v(4) * kDpsPerLsb;
  ax = v(6) * kGPerLsb;
  ay = v(8) * kGPerLsb;
  az = v(10) * kGPerLsb;
  return true;
}

float IMU::tiltDeg() {
  float ax, ay, az, gx, gy, gz;
  if (!read(ax, ay, az, gx, gy, gz)) return 0;
  float total = sqrtf(ax * ax + ay * ay + az * az);
  if (total < 0.1f) return 0;
  float c = constrain(fabsf(az) / total, 0.0f, 1.0f);
  return acosf(c) * 180.0f / (float)M_PI;
}
