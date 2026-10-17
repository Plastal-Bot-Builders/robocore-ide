#include "RoboCore.h"

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
}

void rgb(uint8_t r, uint8_t g, uint8_t b) {
  rgbLedWrite(RC_PIN_RGB_LED, r, g, b);
}

}  // namespace RoboCore
