// Distance monitor
// Made with blocks in RoboCore IDE.

#include <RoboCoreSensors.h>

Sonar sonar;

void setup() {
  Serial.begin(115200);
  sonar.begin();
  Serial.println("Distance monitor ready");
}

void loop() {
  Serial.print("distance_cm=");
  Serial.println(sonar.distanceCm(), 1);
  delay(500);
}
