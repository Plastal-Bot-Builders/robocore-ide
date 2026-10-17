// Traffic light
// Red, amber and green LEDs (each with a 220R resistor to GND) on the expansion header:
//   red = IO3, amber = IO37, green = IO43 (UART TX; Serial uses USB so it is free).
// Press USER to ask the light to change.
#include <RoboCore.h>

const int RED = RC_PIN_EXP_IO3;
const int AMBER = RC_PIN_EXP_IO37;
const int GREEN = RC_PIN_UART_TX;

void setup() {
  Serial.begin(115200);
  pinMode(RED, OUTPUT);
  pinMode(AMBER, OUTPUT);
  pinMode(GREEN, OUTPUT);
  pinMode(RC_PIN_USER_BUTTON, INPUT);
}

void show(int pin, const char *name) {
  digitalWrite(RED, pin == RED);
  digitalWrite(AMBER, pin == AMBER);
  digitalWrite(GREEN, pin == GREEN);
  Serial.println(name);
}

void loop() {
  show(GREEN, "green");
  // Stay green for 5 seconds, or until USER is pressed
  unsigned long start = millis();
  while (digitalRead(RC_PIN_USER_BUTTON) == HIGH && millis() - start < 5000) {
    delay(20);
  }
  show(AMBER, "amber");
  delay(1000);
  show(RED, "red");
  delay(4000);
}
