#include "RoboCore.h"
#include <cmath>

namespace {
uint8_t gR = 0, gG = 0, gB = 0;  // the colour asked for, before brightness
float gBright = 1.0f;
unsigned long gTimer0 = 0;
float gTimerAt[4] = {-1, -1, -1, -1};
bool gTimerFired[4] = {false, false, false, false};
bool gUserWas = false;

struct Note {
  uint16_t hz, ms;
};
constexpr Note kPowerUp[] = {{523, 90}, {659, 90}, {784, 90}, {1047, 180}};
constexpr Note kPowerDown[] = {{1047, 90}, {784, 90}, {659, 90}, {523, 180}};
constexpr Note kSuccess[] = {{784, 100}, {1047, 220}};
constexpr Note kError[] = {{330, 180}, {262, 320}};
constexpr Note kAlarm[] = {{880, 150}, {660, 150}, {880, 150}, {660, 150}, {880, 150}, {660, 150}};

template <size_t N>
void play(const Note (&notes)[N]) {
  for (const Note &n : notes) {
    tone(RC_PIN_BUZZER, n.hz, n.ms);
    delay(n.ms + 30);  // a short gap so repeated notes are heard as separate
  }
}
}  // namespace

namespace RoboCore {

float batteryVolts() {
  analogSetPinAttenuation(RC_PIN_BATTERY_SENSE, ADC_11db);
  uint32_t mv = 0;
  for (int i = 0; i < 8; i++) mv += analogReadMilliVolts(RC_PIN_BATTERY_SENSE);
  return (mv / 8.0f) * RC_BATTERY_DIVIDER / 1000.0f;
}

bool userPressed() {
  pinMode(RC_PIN_USER_BUTTON, INPUT);  // the board has a 10k pull-up
  return digitalRead(RC_PIN_USER_BUTTON) == LOW;
}

bool waitForUser(uint32_t timeoutMs) {
  uint32_t t0 = millis();
  while (!userPressed()) {
    if (timeoutMs && millis() - t0 >= timeoutMs) return false;
    delay(5);
  }
  delay(20);  // debounce
  while (userPressed()) delay(5);
  delay(20);
  return true;
}

void beep(unsigned int freqHz, unsigned long ms) {
  tone(RC_PIN_BUZZER, freqHz, ms);
  delay(ms);
}

void rgb(uint8_t r, uint8_t g, uint8_t b) {
  gR = r;
  gG = g;
  gB = b;
  auto dim = [](uint8_t v) { return (uint8_t)(v * gBright + 0.5f); };
  rgbLedWrite(RC_PIN_RGB_LED, dim(r), dim(g), dim(b));
}

void ledBrightness(float percent) {
  if (std::isnan(percent)) return;
  gBright = constrain(percent, 0.0f, 100.0f) / 100.0f;
  rgb(gR, gG, gB);
}

bool userJustPressed() {
  const bool now = userPressed();
  const bool fired = now && !gUserWas;
  gUserWas = now;
  return fired;
}

float timer() { return (millis() - gTimer0) / 1000.0f; }

void resetTimer() {
  gTimer0 = millis();
  for (bool &f : gTimerFired) f = false;
}

bool timerPassed(float seconds) {
  int i = 0;
  while (i < 4 && gTimerAt[i] >= 0 && gTimerAt[i] != seconds) i++;
  if (i == 4) i = 3;  // more than four times share the last memory
  gTimerAt[i] = seconds;
  if (gTimerFired[i] || timer() < seconds) return false;
  gTimerFired[i] = true;
  return true;
}

void melody(RoboCoreMelody tune) {
  switch (tune) {
    case MELODY_POWER_UP: play(kPowerUp); break;
    case MELODY_POWER_DOWN: play(kPowerDown); break;
    case MELODY_SUCCESS: play(kSuccess); break;
    case MELODY_ERROR: play(kError); break;
    case MELODY_ALARM: play(kAlarm); break;
  }
}

int batteryPercent() {
  const float v = batteryVolts();
  if (v < 2.5f) return 0;  // no pack
  return (int)lroundf(constrain((v - 3.3f) / (4.15f - 3.3f) * 100.0f, 0.0f, 100.0f));
}

void stopProgram() {
  if (RoboCoreMotors::active()) RoboCoreMotors::active()->stop();
  noTone(RC_PIN_BUZZER);
  for (;;) delay(1000);
}

}  // namespace RoboCore
