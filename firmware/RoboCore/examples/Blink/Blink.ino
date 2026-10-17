// Blink — RoboCore V2
// Turns the built-in LED on and off every second.
// The V2 has no plain LED: LED_BUILTIN is the RGB LED (IO48), so it blinks white.

void setup() {
  Serial.begin(115200);
  Serial.println("RoboCore V2 ready");
  pinMode(LED_BUILTIN, OUTPUT);
}

void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  delay(1000);
  digitalWrite(LED_BUILTIN, LOW);
  delay(1000);
}
