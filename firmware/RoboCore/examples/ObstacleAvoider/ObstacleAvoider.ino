// Obstacle avoider
// Drives forward and turns left when something is closer than 20 cm.
#include <RoboCoreMotors.h>
#include <RoboCoreSensors.h>

RoboCoreMotors motors;
Sonar sonar;

const int LIMIT_CM = 20;

void setup() {
  Serial.begin(115200);
  motors.begin();
  sonar.begin();
}

void loop() {
  float cm = sonar.distanceCm();
  Serial.print("distance_cm=");
  Serial.println(cm, 1);

  if (cm < LIMIT_CM) {
    Serial.println("obstacle - turning left");
    motors.drive(-50, 50);
    delay(400);
  } else {
    motors.drive(60, 60);
  }
  delay(250);
}
