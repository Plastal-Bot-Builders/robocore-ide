// Sensor logger
// Logs an analog sensor on the expansion pin IO3 as CSV, once a second.
// Wire a light sensor (or a potentiometer) between 3V3, IO3 and GND.
#include <RoboCore.h>

const int LIGHT_PIN = RC_PIN_EXP_IO3;

void setup() {
  Serial.begin(115200);
  Serial.println("time_ms,light,battery_v");
}

void loop() {
  int light = analogRead(LIGHT_PIN);
  Serial.print(millis());
  Serial.print(",");
  Serial.print(light);
  Serial.print(",");
  Serial.println(RoboCore::batteryVolts(), 2);
  delay(1000);
}
