// Motor control
// Drives forward, reverses, then turns on the spot.
// Switch the robot ON: the motor supply is off when the switch is OFF.
#include <RoboCoreMotors.h>

RoboCoreMotors motors;

void setup() {
  Serial.begin(115200);
  motors.begin();
}

void loop() {
  Serial.println("forward");
  motors.drive(60, 60);
  delay(1500);
  Serial.println("reverse");
  motors.drive(-60, -60);
  delay(1500);
  Serial.println("turn");
  motors.drive(-50, 50);
  delay(800);
  motors.stop();
  delay(1000);
}
