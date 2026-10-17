// Ultrasonic distance
// Prints the sonar reading ten times a second.
#include <RoboCoreSensors.h>

Sonar sonar;

void setup() {
  Serial.begin(115200);
  sonar.begin();
}

void loop() {
  float cm = sonar.distanceCm();
  Serial.print("distance_cm=");
  Serial.println(cm, 1);
  delay(100);
}
