// Sensors to serial
// Prints the board temperature and tilt twice a second.
#include <RoboCoreSensors.h>

IMU imu;

void setup() {
  Serial.begin(115200);
  if (!imu.begin()) Serial.println("IMU not found");
}

void loop() {
  Serial.print("temp_c=");
  Serial.print(imu.temperature(), 1);
  Serial.print("  tilt_deg=");
  Serial.println(imu.tiltDeg(), 1);
  delay(500);
}
