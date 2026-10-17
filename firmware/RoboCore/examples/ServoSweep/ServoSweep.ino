// Servo sweep
// Sweeps a servo on servo port 1 (IO38) from 0 to 180 degrees and back.
// Servos are powered from the motor supply: switch the robot ON.
#include <ESP32Servo.h>
#include <RoboCore.h>

Servo arm;

void setup() {
  Serial.begin(115200);
  arm.attach(RC_PIN_SERVO1);
}

void loop() {
  for (int angle = 0; angle <= 180; angle += 10) {
    arm.write(angle);
    delay(60);
  }
  for (int angle = 180; angle >= 0; angle -= 10) {
    arm.write(angle);
    delay(60);
  }
  Serial.println("sweep done");
}
