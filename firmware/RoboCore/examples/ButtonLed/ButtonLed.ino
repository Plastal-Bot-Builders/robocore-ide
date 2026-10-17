// Button-controlled LED
// Lights the built-in LED while the USER button (IO42) is held down.
#include <RoboCore.h>

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(RC_PIN_USER_BUTTON, INPUT);  // the board has a 10k pull-up
}

void loop() {
  bool pressed = digitalRead(RC_PIN_USER_BUTTON) == LOW;
  digitalWrite(LED_BUILTIN, pressed ? HIGH : LOW);
  delay(10);
}
