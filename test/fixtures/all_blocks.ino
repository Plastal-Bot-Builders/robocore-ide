// All blocks
// Made with blocks in RoboCore IDE.

#include <RoboCore.h>

RoboCoreMotors motors;
Sonar sonar;
LineSensor line;
IMU imu;
RoboCoreDrive robot(motors, imu);
RoboCoreServos servos;
RoboCoreEdge when1;
int count = 0;
float distance = 0;
String word2 = "";

void blinkTwice(float times);
void on_message1();

void blinkTwice(float times) {
  digitalWrite(LED_BUILTIN, HIGH);
}

void on_message1() {
  RoboCore::beep(523, 200);  // C5
  digitalWrite(LED_BUILTIN, HIGH);
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(3, OUTPUT);
  motors.begin();
  sonar.begin();
  line.begin();
  imu.begin();
}

void loop() {
  if (RoboCore::userJustPressed()) {
    digitalWrite(LED_BUILTIN, HIGH);
  }
  if (sonar.justCloserThan(20)) {
    digitalWrite(LED_BUILTIN, HIGH);
  }
  if (line.justFound()) {
    digitalWrite(LED_BUILTIN, HIGH);
  }
  if (imu.justTilted()) {
    digitalWrite(LED_BUILTIN, HIGH);
  }
  if (RoboCore::timerPassed(10)) {
    digitalWrite(LED_BUILTIN, HIGH);
  }
  if (when1.rose(RoboCore::userPressed())) {
    digitalWrite(LED_BUILTIN, HIGH);
  }
  on_message1();
  robot.move(10, CM);
  robot.turn(90);
  robot.start(FORWARD);
  robot.steer(30);
  motors.drive(50, 50);
  robot.stop();
  robot.setSpeed(50);
  robot.setWheelCm(18.8);
  Serial.println(robot.distanceCm());
  motors.run(LEFT, 1, ROTATIONS);
  motors.start(LEFT, 50);
  motors.stop(LEFT);
  motors.resetPosition(LEFT);
  Serial.println(motors.positionDeg(LEFT));
  Serial.println(motors.speedPercent(LEFT));
  servos.write(1, 90);
  Serial.println(servos.angle(1));
  digitalWrite(LED_BUILTIN, HIGH);
  RoboCore::rgb(255, 0, 0);  // red
  RoboCore::ledBrightness(50);
  RoboCore::beep(523, 200);  // C5
  tone(RC_PIN_BUZZER, 523);  // C5
  RoboCore::melody(MELODY_POWER_UP);
  noTone(RC_PIN_BUZZER);
  Serial.println(sonar.distanceCm());
  if (sonar.distanceCm() < 20) {
  }
  Serial.println(line.read());
  if (line.centre() > 0.5) {
  }
  Serial.println(line.centre() * 100);
  Serial.println(imu.tiltDeg());
  Serial.println(imu.yawDeg());
  imu.resetYaw();
  if (imu.isTilted()) {
  }
  if (RoboCore::userPressed()) {
  }
  Serial.println(RoboCore::batteryPercent());
  Serial.println(imu.temperature());
  Serial.println(RoboCore::timer());
  RoboCore::resetTimer();
  delay(1000);
  for (int i = 0; i < 5; i++) {
  }
  if (false) {
  }
  if (false) {
  } else {
  }
  while (!(false)) {
    delay(10);
  }
  while (!false) {
  }
  Serial.println(0 + 0);
  if (0 < 20) {
  }
  if (false && false) {
  }
  if (!true) {
  }
  Serial.println(random(1, 11));
  if (0 >= -10 && 0 <= 10) {
  }
  Serial.println(round(3.6));
  Serial.println(String("cm: ") + "20");
  digitalWrite(3, HIGH);
  Serial.println(digitalRead(3));
  Serial.println(analogRead(3));
  Serial.begin(115200);
  Serial.println("RoboCore V2 ready");
  Serial.println(Serial.readStringUntil('\n'));
  count = 0;
  count += 1;
  distance = sonar.distanceCm();
  word2 = Serial.readStringUntil('\n');
  Serial.println(distance);
  blinkTwice(2);
  RoboCore::stopProgram();
}
