// Line follower
// Steers toward the line using the IR line sensor.
// Move the robot across the line and the white floor once at the start:
// the sensor learns what black and white look like.
#include <RoboCoreMotors.h>
#include <RoboCoreSensors.h>

RoboCoreMotors motors;
LineSensor line;

const int BASE_SPEED = 45;
const float GAIN = 30.0;

void setup() {
  Serial.begin(115200);
  motors.begin();
  line.begin();
}

void loop() {
  // line.read() returns -1.0 (line far left) to 1.0 (far right)
  float pos = line.read();
  int turn = pos * GAIN;
  motors.drive(BASE_SPEED + turn, BASE_SPEED - turn);
  Serial.print("line=");
  Serial.println(pos, 2);
  delay(50);
}
