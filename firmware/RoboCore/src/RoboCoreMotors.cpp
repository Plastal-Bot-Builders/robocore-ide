#include "RoboCoreMotors.h"
#include <cmath>

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "The RoboCore library is for the RoboCore V2 (ESP32-S3). In Tools > Board pick ESP32S3 Dev Module."
#endif

namespace {

constexpr uint32_t kPwmHz = 20000;  // above hearing
constexpr uint8_t kPwmBits = 10;
constexpr uint32_t kPwmMax = (1u << kPwmBits) - 1;

// Raw encoder counts, in the motor's own direction (before any reversing).
volatile long gEnc1 = 0;
volatile long gEnc2 = 0;

// x2 decoding: on every edge of A, B tells the direction.
void IRAM_ATTR onEnc1() {
  if (digitalRead(RC_PIN_ENC1_A) == digitalRead(RC_PIN_ENC1_B)) gEnc1 = gEnc1 - 1;
  else gEnc1 = gEnc1 + 1;
}
void IRAM_ATTR onEnc2() {
  if (digitalRead(RC_PIN_ENC2_A) == digitalRead(RC_PIN_ENC2_B)) gEnc2 = gEnc2 - 1;
  else gEnc2 = gEnc2 + 1;
}

long readCount(volatile long &c) {
  noInterrupts();
  long v = c;
  interrupts();
  return v;
}

float currentmA(uint8_t pin) {
  uint32_t mv = 0;
  for (int i = 0; i < 4; i++) mv += analogReadMilliVolts(pin);
  return (mv / 4.0f) / RC_MOTOR_MV_PER_AMP * 1000.0f;
}

}  // namespace

bool RoboCoreMotors::begin() {
  if (_begun) return true;
  bool ok = true;
  for (uint8_t p : {RC_PIN_MOTOR1_IN1, RC_PIN_MOTOR1_IN2, RC_PIN_MOTOR2_IN1, RC_PIN_MOTOR2_IN2}) {
    ok = ledcAttach(p, kPwmHz, kPwmBits) && ok;
    ledcWrite(p, 0);
  }
  pinMode(RC_PIN_MOTOR_NFAULT, INPUT);
  pinMode(RC_PIN_ENC1_A, INPUT);
  pinMode(RC_PIN_ENC1_B, INPUT);
  pinMode(RC_PIN_ENC2_A, INPUT);
  pinMode(RC_PIN_ENC2_B, INPUT);
  attachInterrupt(digitalPinToInterrupt(RC_PIN_ENC1_A), onEnc1, CHANGE);
  attachInterrupt(digitalPinToInterrupt(RC_PIN_ENC2_A), onEnc2, CHANGE);
  _begun = true;
  _left = _right = 0;
  return ok;
}

void RoboCoreMotors::_set(uint8_t in1, uint8_t in2, float percent, bool reversed) {
  if (std::isnan(percent)) percent = 0;
  if (percent > 100) percent = 100;
  if (percent < -100) percent = -100;
  if (reversed) percent = -percent;
  uint32_t duty = (uint32_t)(fabsf(percent) * kPwmMax / 100.0f + 0.5f);
  if (percent > 0) {
    ledcWrite(in2, 0);
    ledcWrite(in1, duty);
  } else if (percent < 0) {
    ledcWrite(in1, 0);
    ledcWrite(in2, duty);
  } else {
    ledcWrite(in1, 0);
    ledcWrite(in2, 0);
  }
}

void RoboCoreMotors::drive(float leftPercent, float rightPercent) {
  if (!_begun) begin();
  _left = constrain(leftPercent, -100.0f, 100.0f);
  _right = constrain(rightPercent, -100.0f, 100.0f);
  _set(RC_PIN_MOTOR1_IN1, RC_PIN_MOTOR1_IN2, _left, _revL);
  _set(RC_PIN_MOTOR2_IN1, RC_PIN_MOTOR2_IN2, _right, _revR);
}

void RoboCoreMotors::stop() {
  if (!_begun) begin();
  drive(0, 0);
}

void RoboCoreMotors::brake() {
  if (!_begun) begin();
  for (uint8_t p : {RC_PIN_MOTOR1_IN1, RC_PIN_MOTOR1_IN2, RC_PIN_MOTOR2_IN1, RC_PIN_MOTOR2_IN2}) ledcWrite(p, kPwmMax);
  _left = _right = 0;
}

void RoboCoreMotors::setReversed(bool left, bool right) {
  _revL = left;
  _revR = right;
  if (_begun) drive(_left, _right);
}

void RoboCoreMotors::setEncoderReversed(bool left, bool right) {
  _encRevL = left;
  _encRevR = right;
}

long RoboCoreMotors::leftCount() const {
  long v = readCount(gEnc1);
  return (_revL != _encRevL) ? -v : v;
}

long RoboCoreMotors::rightCount() const {
  long v = readCount(gEnc2);
  return (_revR != _encRevR) ? -v : v;
}

void RoboCoreMotors::resetEncoders() {
  noInterrupts();
  gEnc1 = 0;
  gEnc2 = 0;
  interrupts();
}

float RoboCoreMotors::leftCurrentmA() const { return currentmA(RC_PIN_MOTOR1_ISENSE); }
float RoboCoreMotors::rightCurrentmA() const { return currentmA(RC_PIN_MOTOR2_ISENSE); }

bool RoboCoreMotors::fault() const { return digitalRead(RC_PIN_MOTOR_NFAULT) == LOW; }
