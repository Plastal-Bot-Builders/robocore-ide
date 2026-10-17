// GENERATED from firmware/RoboCore/examples by tools/gen_examples.py.
// Do not edit: change the example sketch and run `python3 tools/gen_examples.py`.

/// RoboCore V2 example sketches, by folder name (the .ino inside it).
const Map<String, String> kV2ExampleCode = {
  'Blink': r'''// Blink — RoboCore V2
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
''',
  'BoardTest': r'''/*
  RoboCore V2 board test
  ----------------------
  Checks every part of the RoboCore V2 (Rev 2.0) PCB one at a time and prints
  PASS / FAIL / CHECK to the Serial Monitor at 115200 baud.

  Pins come from RoboCoreV2Pins.h in the RoboCore library (schematic Rev 2.0).

  Arduino IDE 2 settings (board package "esp32 by Espressif", version 3.x):
    Board .............. ESP32S3 Dev Module
    USB CDC On Boot .... Enabled        (Serial goes out of the USB-C port)
    USB Mode ........... Hardware CDC and JTAG
    Flash Size ......... 8MB (64Mb)
    Partition Scheme ... 8M with spiffs (3MB APP/1.5MB SPIFFS)
    PSRAM .............. QSPI PSRAM     (the N8R2 module has quad PSRAM; NOT OPI)

  If the upload does not start: hold BOOT, tap RESET, release BOOT, upload again.

  Part 1 runs on its own (LED, buzzer, buttons, IMU, sonar, line sensor, battery,
  motor driver fault line). Part 2 spins the motors and moves the servos, and
  only starts when you press the USER button.
  LIFT THE ROBOT SO THE WHEELS ARE OFF THE TABLE BEFORE PRESSING USER.
  Part 2 needs the ON/OFF switch ON (the motor supply VMOT is off when it is OFF).
*/

#include <Wire.h>

// ---------------- RoboCore V2 pin map ----------------
// From the RoboCore library, so the test always uses the same pins as everything else.
#include <RoboCoreV2Pins.h>

const int PIN_BATT_SENSE  = RC_PIN_BATTERY_SENSE;
const int PIN_MOT1_ISENSE = RC_PIN_MOTOR1_ISENSE;
const int PIN_MOT2_ISENSE = RC_PIN_MOTOR2_ISENSE;
const int PIN_IR_LEFT     = RC_PIN_LINE_LEFT;
const int PIN_IR_CENTRE   = RC_PIN_LINE_CENTRE;
const int PIN_IR_RIGHT    = RC_PIN_LINE_RIGHT;
const int PIN_I2C_SDA     = RC_PIN_I2C_SDA;
const int PIN_I2C_SCL     = RC_PIN_I2C_SCL;
const int PIN_IMU_INT1    = RC_PIN_IMU_INT1;
const int PIN_MOT1_IN1    = RC_PIN_MOTOR1_IN1;
const int PIN_MOT1_IN2    = RC_PIN_MOTOR1_IN2;
const int PIN_MOT2_IN1    = RC_PIN_MOTOR2_IN1;
const int PIN_MOT2_IN2    = RC_PIN_MOTOR2_IN2;
const int PIN_ENC1_A      = RC_PIN_ENC1_A;
const int PIN_ENC1_B      = RC_PIN_ENC1_B;
const int PIN_ENC2_A      = RC_PIN_ENC2_A;
const int PIN_ENC2_B      = RC_PIN_ENC2_B;
const int PIN_MOT_NFAULT  = RC_PIN_MOTOR_NFAULT;
const int PIN_SERVO1      = RC_PIN_SERVO1;
const int PIN_SERVO2      = RC_PIN_SERVO2;
const int PIN_SERVO3      = RC_PIN_SERVO3;
const int PIN_SERVO4      = RC_PIN_SERVO4;
const int PIN_US_TRIG     = RC_PIN_SONAR_TRIG;
const int PIN_US_ECHO     = RC_PIN_SONAR_ECHO;
const int PIN_USER_BTN    = RC_PIN_USER_BUTTON;
const int PIN_BOOT_BTN    = RC_PIN_BOOT_BUTTON;
const int PIN_BUZZER      = RC_PIN_BUZZER;
const int PIN_RGB         = RC_PIN_RGB_LED;

const uint8_t IMU_ADDR = RC_IMU_I2C_ADDR;  // LSM6DSOX, SA0 = GND
const float   MV_PER_AMP = RC_MOTOR_MV_PER_AMP;  // IPROPI: 200 uA/A into 16.5k

// ---------------- results ----------------
int nPass = 0, nFail = 0, nCheck = 0;

void result(const char *name, const char *state, const String &detail) {
  if (!strcmp(state, "PASS")) nPass++;
  else if (!strcmp(state, "FAIL")) nFail++;
  else nCheck++;
  Serial.printf("  [%-5s] %-22s %s\n", state, name, detail.c_str());
}

// ---------------- encoders ----------------
volatile long enc1 = 0, enc2 = 0;
void IRAM_ATTR onEnc1() { enc1 += digitalRead(PIN_ENC1_B) ? -1 : 1; }
void IRAM_ATTR onEnc2() { enc2 += digitalRead(PIN_ENC2_B) ? -1 : 1; }

// ---------------- helpers ----------------
bool imuRead(uint8_t reg, uint8_t *buf, size_t n) {
  Wire.beginTransmission(IMU_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(IMU_ADDR, n) != n) return false;
  for (size_t i = 0; i < n; i++) buf[i] = Wire.read();
  return true;
}

bool imuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(IMU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission() == 0;
}

float sonarCm() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(4);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);
  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, 30000UL);  // 30 ms = about 5 m
  return us == 0 ? -1.0f : us / 58.0f;
}

void motor(int in1, int in2, int speed) {  // speed -255..255, 0 = coast
  if (speed > 0)      { ledcWrite(in1, speed);  ledcWrite(in2, 0); }
  else if (speed < 0) { ledcWrite(in1, 0);      ledcWrite(in2, -speed); }
  else                { ledcWrite(in1, 0);      ledcWrite(in2, 0); }
}

void servoUs(int pin, int us) {  // 50 Hz, 14-bit: 20000 us = 16384 counts
  ledcWrite(pin, (uint32_t)us * 16384UL / 20000UL);
}

bool waitForUser(unsigned long ms) {
  unsigned long t0 = millis();
  while (millis() - t0 < ms) {
    if (digitalRead(PIN_USER_BTN) == LOW) { delay(30); return true; }
    delay(5);
  }
  return false;
}

// ---------------- part 1 ----------------
void testRgbLed() {
  Serial.println("\nRGB LED (IO48): watch the LED go red, green, blue, white, off.");
  rgbLedWrite(PIN_RGB, 40, 0, 0);  delay(400);
  rgbLedWrite(PIN_RGB, 0, 40, 0);  delay(400);
  rgbLedWrite(PIN_RGB, 0, 0, 40);  delay(400);
  rgbLedWrite(PIN_RGB, 30, 30, 30); delay(400);
  rgbLedWrite(PIN_RGB, 0, 0, 0);
  result("RGB LED", "CHECK", "did it show red, green, blue, white?");
}

void testBuzzer() {
  Serial.println("\nBuzzer (IO47): three rising beeps.");
  const int notes[] = {1047, 1319, 1568};
  for (int f : notes) { tone(PIN_BUZZER, f, 180); delay(230); }
  noTone(PIN_BUZZER);
  digitalWrite(PIN_BUZZER, LOW);
  result("Buzzer", "CHECK", "did you hear three beeps?");
}

void testButtons() {
  Serial.println("\nButtons: press and release USER (IO42) within 8 seconds.");
  bool userIdle = digitalRead(PIN_USER_BTN) == HIGH;
  bool bootIdle = digitalRead(PIN_BOOT_BTN) == HIGH;
  result("BOOT button idle", bootIdle ? "PASS" : "FAIL", bootIdle ? "reads HIGH" : "reads LOW: stuck or no pull-up");
  if (!userIdle) { result("USER button", "FAIL", "reads LOW before pressing: stuck or no pull-up"); return; }
  bool pressed = waitForUser(8000);
  if (pressed) {
    rgbLedWrite(PIN_RGB, 0, 40, 0);
    unsigned long t0 = millis();
    while (digitalRead(PIN_USER_BTN) == LOW && millis() - t0 < 3000) delay(5);
    rgbLedWrite(PIN_RGB, 0, 0, 0);
  }
  result("USER button", pressed ? "PASS" : "FAIL", pressed ? "press seen" : "no press seen in 8 s");
}

void testImu() {
  Serial.println("\nIMU LSM6DSOX (I2C 0x6A on IO8/IO9): keep the board flat and still.");
  uint8_t who = 0;
  if (!imuRead(0x0F, &who, 1)) { result("IMU", "FAIL", "no answer at 0x6A: check I2C, pull-ups, SA0"); return; }
  if (who != 0x6C) { result("IMU", "FAIL", String("WHO_AM_I = 0x") + String(who, HEX) + " (expected 0x6C)"); return; }
  result("IMU found", "PASS", "WHO_AM_I = 0x6C");
  imuWrite(0x12, 0x44);   // CTRL3_C: BDU + auto-increment
  imuWrite(0x10, 0x40);   // CTRL1_XL: 104 Hz, +/-2 g
  imuWrite(0x11, 0x40);   // CTRL2_G: 104 Hz, 250 dps
  delay(120);
  uint8_t b[14];
  if (!imuRead(0x20, b, 14)) { result("IMU data", "FAIL", "read failed"); return; }
  int16_t t  = (int16_t)(b[1] << 8 | b[0]);
  int16_t gx = (int16_t)(b[3] << 8 | b[2]), gy = (int16_t)(b[5] << 8 | b[4]), gz = (int16_t)(b[7] << 8 | b[6]);
  int16_t ax = (int16_t)(b[9] << 8 | b[8]), ay = (int16_t)(b[11] << 8 | b[10]), az = (int16_t)(b[13] << 8 | b[12]);
  float g = 0.061f / 1000.0f;           // g per count at +/-2 g
  float dps = 8.75f / 1000.0f;          // dps per count at 250 dps
  float axg = ax * g, ayg = ay * g, azg = az * g;
  float total = sqrtf(axg * axg + ayg * ayg + azg * azg);
  float tempC = 25.0f + t / 256.0f;
  bool accOk = total > 0.8f && total < 1.2f;
  result("IMU accelerometer", accOk ? "PASS" : "FAIL",
         String("x ") + String(axg, 2) + " y " + String(ayg, 2) + " z " + String(azg, 2) + " g (total " + String(total, 2) + ", expect about 1)");
  float gmax = max(fabsf(gx * dps), max(fabsf(gy * dps), fabsf(gz * dps)));
  result("IMU gyro", gmax < 15.0f ? "PASS" : "CHECK",
         String("x ") + String(gx * dps, 1) + " y " + String(gy * dps, 1) + " z " + String(gz * dps, 1) + " dps (still: all near 0)");
  result("IMU temperature", (tempC > 0 && tempC < 60) ? "PASS" : "CHECK", String(tempC, 1) + " C");
}

void testSonar() {
  Serial.println("\nUltrasonic (TRIG IO40, ECHO IO41): point it at a wall 20-100 cm away.");
  int got = 0; float sum = 0;
  for (int i = 0; i < 5; i++) { float d = sonarCm(); if (d > 0) { got++; sum += d; } delay(60); }
  if (got == 0) result("Ultrasonic", "FAIL", "no echo: plugged in? TRIG/ECHO swapped?");
  else result("Ultrasonic", "PASS", String(sum / got, 1) + " cm (" + got + "/5 echoes): does that match?");
}

void testLineSensor() {
  Serial.println("\nLine sensor (IO7 left, IO10 centre, IO2 right): readings for 4 s.");
  Serial.println("  Slide white paper and black tape under the sensors.");
  int lo[3] = {4095, 4095, 4095}, hi[3] = {0, 0, 0};
  const int pins[3] = {PIN_IR_LEFT, PIN_IR_CENTRE, PIN_IR_RIGHT};
  unsigned long t0 = millis();
  while (millis() - t0 < 4000) {
    for (int i = 0; i < 3; i++) { int v = analogRead(pins[i]); lo[i] = min(lo[i], v); hi[i] = max(hi[i], v); }
    delay(10);
  }
  const char *names[3] = {"Line left", "Line centre", "Line right"};
  for (int i = 0; i < 3; i++) {
    int span = hi[i] - lo[i];
    result(names[i], span > 400 ? "PASS" : "CHECK",
           String("min ") + lo[i] + " max " + hi[i] + (span > 400 ? "" : ": little change; was the sensor moved over black and white?"));
  }
}

void testBattery() {
  Serial.println("\nBattery sense (IO4, battery / 2).");
  uint32_t mv = 0;
  for (int i = 0; i < 16; i++) mv += analogReadMilliVolts(PIN_BATT_SENSE);
  float v = (mv / 16.0f) * 2.0f / 1000.0f;
  const char *st = (v > 3.0f && v < 4.3f) ? "PASS" : (v < 0.5f ? "CHECK" : "FAIL");
  String note = v < 0.5f ? ": no battery fitted, or the pack is behind the protection FETs" : (v > 4.3f ? ": too high for 1S Li-ion" : "");
  result("Battery voltage", st, String(v, 2) + " V" + note);
}

void testDriverIdle() {
  Serial.println("\nMotor driver DRV8411A (nFAULT IO21, current IO5/IO6), motors off.");
  bool ok = digitalRead(PIN_MOT_NFAULT) == HIGH;
  result("Driver fault line", ok ? "PASS" : "FAIL", ok ? "no fault" : "nFAULT is LOW");
  int m1 = analogReadMilliVolts(PIN_MOT1_ISENSE), m2 = analogReadMilliVolts(PIN_MOT2_ISENSE);
  result("Motor current at rest", (m1 < 150 && m2 < 150) ? "PASS" : "CHECK",
         String("M1 ") + int(m1 / MV_PER_AMP * 1000) + " mA, M2 " + int(m2 / MV_PER_AMP * 1000) + " mA (expect about 0)");
}

// ---------------- part 2 (needs USER press) ----------------
void testMotor(const char *name, int in1, int in2, int isense, volatile long *enc) {
  for (int dir = 1; dir >= -1; dir -= 2) {
    noInterrupts(); *enc = 0; interrupts();
    int peakMv = 0;
    motor(in1, in2, 160 * dir);
    unsigned long t0 = millis();
    while (millis() - t0 < 900) { peakMv = max(peakMv, (int)analogReadMilliVolts(isense)); delay(10); }
    motor(in1, in2, 0);
    delay(300);
    noInterrupts(); long counts = *enc; interrupts();
    bool fault = digitalRead(PIN_MOT_NFAULT) == LOW;
    String label = String(name) + (dir > 0 ? " forward" : " reverse");
    String detail = String("encoder ") + counts + " counts, peak " + int(peakMv / MV_PER_AMP * 1000) + " mA";
    if (fault) result(label.c_str(), "FAIL", detail + ", driver fault");
    else if (counts == 0) result(label.c_str(), "FAIL", detail + ": no encoder pulses (motor plugged in? VMOT on?)");
    else if ((counts > 0) != (dir > 0)) result(label.c_str(), "CHECK", detail + ": counts the other way; swap A/B in code");
    else result(label.c_str(), "PASS", detail);
  }
}

void testServos() {
  Serial.println("\nServos (IO38, IO39, IO35, IO36): each sweeps left, right, centre.");
  const int pins[4] = {PIN_SERVO1, PIN_SERVO2, PIN_SERVO3, PIN_SERVO4};
  for (int i = 0; i < 4; i++) {
    ledcAttach(pins[i], 50, 14);
    servoUs(pins[i], 1000); delay(500);
    servoUs(pins[i], 2000); delay(500);
    servoUs(pins[i], 1500); delay(400);
    ledcDetach(pins[i]);
    pinMode(pins[i], OUTPUT);
    digitalWrite(pins[i], LOW);
  }
  result("Servos 1-4", "CHECK", "did each connected servo sweep?");
}

void summary() {
  Serial.println("\n==============================================");
  Serial.printf("  %d PASS   %d FAIL   %d to CHECK by eye or ear\n", nPass, nFail, nCheck);
  Serial.println("==============================================");
  rgbLedWrite(PIN_RGB, nFail ? 40 : 0, nFail ? 0 : 40, 0);
}

// ---------------- main ----------------
void setup() {
  // Motor pins first, so the motors stay off from power-up.
  for (int p : {PIN_MOT1_IN1, PIN_MOT1_IN2, PIN_MOT2_IN1, PIN_MOT2_IN2}) {
    ledcAttach(p, 20000, 8);
    ledcWrite(p, 0);
  }
  pinMode(PIN_BUZZER, OUTPUT);   digitalWrite(PIN_BUZZER, LOW);
  pinMode(PIN_US_TRIG, OUTPUT);  digitalWrite(PIN_US_TRIG, LOW);
  pinMode(PIN_US_ECHO, INPUT);
  pinMode(PIN_USER_BTN, INPUT);
  pinMode(PIN_BOOT_BTN, INPUT);
  pinMode(PIN_MOT_NFAULT, INPUT);
  pinMode(PIN_IMU_INT1, INPUT);
  pinMode(PIN_ENC1_A, INPUT); pinMode(PIN_ENC1_B, INPUT);
  pinMode(PIN_ENC2_A, INPUT); pinMode(PIN_ENC2_B, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC1_A), onEnc1, RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC2_A), onEnc2, RISING);
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, 400000);

  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < 4000) delay(10);  // give the Serial Monitor time to open
  delay(500);

  Serial.println("\n\nRoboCore V2 board test (schematic Rev 2.0)");
  Serial.printf("Chip %s rev %d, %d cores, flash %u MB, PSRAM %u KB\n",
                ESP.getChipModel(), ESP.getChipRevision(), ESP.getChipCores(),
                (unsigned)(ESP.getFlashChipSize() / (1024 * 1024)), (unsigned)(ESP.getPsramSize() / 1024));
  bool memOk = ESP.getFlashChipSize() >= 8UL * 1024 * 1024 && ESP.getPsramSize() >= 1024UL * 1024;
  result("Flash and PSRAM", memOk ? "PASS" : "FAIL",
         memOk ? "8 MB flash, 2 MB PSRAM" : "expected 8 MB flash and 2 MB PSRAM: set PSRAM to QSPI PSRAM in Tools");
  result("USB serial", "PASS", "you are reading this over USB-C");

  Serial.println("\n----- PART 1: no moving parts -----");
  testRgbLed();
  testBuzzer();
  testButtons();
  testImu();
  testSonar();
  testLineSensor();
  testBattery();
  testDriverIdle();

  Serial.println("\n----- PART 2: motors and servos -----");
  Serial.println("LIFT THE ROBOT so the wheels are off the table, switch it ON,");
  Serial.println("then press USER to start. (Skips after 30 s.)");
  if (waitForUser(30000)) {
    while (digitalRead(PIN_USER_BTN) == LOW) delay(5);
    delay(500);
    Serial.println("\nMotors (motor 1 IN IO11/IO12, enc IO15/IO16; motor 2 IN IO13/IO14, enc IO17/IO18).");
    testMotor("Motor 1", PIN_MOT1_IN1, PIN_MOT1_IN2, PIN_MOT1_ISENSE, &enc1);
    testMotor("Motor 2", PIN_MOT2_IN1, PIN_MOT2_IN2, PIN_MOT2_ISENSE, &enc2);
    testServos();
  } else {
    Serial.println("  Skipped (no USER press). Press RESET to run the whole test again.");
  }
  summary();
  Serial.println("\nLive readings below. Press RESET to run the test again.");
}

void loop() {
  static unsigned long last = 0;
  if (millis() - last < 500) return;
  last = millis();
  Serial.printf("sonar %5.1f cm | line L %4d C %4d R %4d | batt %.2f V | enc1 %6ld enc2 %6ld | USER %s\n",
                sonarCm(), analogRead(PIN_IR_LEFT), analogRead(PIN_IR_CENTRE), analogRead(PIN_IR_RIGHT),
                analogReadMilliVolts(PIN_BATT_SENSE) * 2 / 1000.0f, enc1, enc2,
                digitalRead(PIN_USER_BTN) == LOW ? "down" : "up");
}
''',
  'ButtonLed': r'''// Button-controlled LED
// Lights the built-in LED while the USER button (IO42) is held down.
#include <RoboCore.h>

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(RC_PIN_USER_BUTTON, INPUT);  // the board has a 10k pull-up
}

void loop() {
  bool pressed = digitalRead(RC_PIN_USER_BUTTON) == LOW;
  digitalWrite(LED_BUILTIN, pressed ? HIGH : LOW);
  delay(10);
}
''',
  'BuzzerMelody': r'''// Buzzer melody
// Plays a short tune on the buzzer (IO47).
#include <RoboCore.h>

const int BUZZER = RC_PIN_BUZZER;

void note(int freq, int ms) {
  tone(BUZZER, freq, ms);
  delay(ms + 50);
}

void setup() {
  pinMode(BUZZER, OUTPUT);
}

void loop() {
  note(262, 400);
  note(262, 400);
  note(392, 400);
  note(392, 400);
  note(440, 400);
  note(440, 400);
  note(392, 800);
  noTone(BUZZER);
  delay(1500);
}
''',
  'BuzzerTones': r'''// Buzzer tones
// Plays a rising scale on the buzzer (IO47).
#include <RoboCore.h>

const int BUZZER = RC_PIN_BUZZER;

void setup() {
  pinMode(BUZZER, OUTPUT);
}

void loop() {
  tone(BUZZER, 262, 300);   // C4
  delay(350);
  tone(BUZZER, 330, 300);   // E4
  delay(350);
  tone(BUZZER, 392, 300);   // G4
  delay(350);
  tone(BUZZER, 523, 600);   // C5
  delay(650);
  noTone(BUZZER);
  delay(1000);
}
''',
  'DistanceMonitor': r'''// Distance monitor
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
''',
  'LineFollower': r'''// Line follower
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
''',
  'MotorControl': r'''// Motor control
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
''',
  'ObstacleAvoider': r'''// Obstacle avoider
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
''',
  'RgbColours': r'''// RGB colour cycle
// Steps the on-board RGB LED (IO48) through a few colours.

void setup() {
}

void loop() {
  rgbLedWrite(RGB_BUILTIN, 255, 0, 0);    // red
  delay(500);
  rgbLedWrite(RGB_BUILTIN, 0, 255, 0);    // green
  delay(500);
  rgbLedWrite(RGB_BUILTIN, 0, 0, 255);    // blue
  delay(500);
  rgbLedWrite(RGB_BUILTIN, 255, 160, 0);  // amber
  delay(500);
}
''',
  'SensorLogger': r'''// Sensor logger
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
''',
  'SensorsToSerial': r'''// Sensors to serial
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
''',
  'SerialEcho': r'''// Serial echo
// Replies to each line you send from the Serial Monitor.

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.println("Type something and press Send");
}

void loop() {
  if (Serial.available() > 0) {
    String msg = Serial.readStringUntil('\n');
    msg.trim();
    Serial.print("You said: ");
    Serial.println(msg);
    if (msg == "led on") {
      digitalWrite(LED_BUILTIN, HIGH);
    }
    if (msg == "led off") {
      digitalWrite(LED_BUILTIN, LOW);
    }
  }
  delay(20);
}
''',
  'ServoSweep': r'''// Servo sweep
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
''',
  'TrafficLight': r'''// Traffic light
// Red, amber and green LEDs (each with a 220R resistor to GND) on the expansion header:
//   red = IO3, amber = IO37, green = IO43 (UART TX; Serial uses USB so it is free).
// Press USER to ask the light to change.
#include <RoboCore.h>

const int RED = RC_PIN_EXP_IO3;
const int AMBER = RC_PIN_EXP_IO37;
const int GREEN = RC_PIN_UART_TX;

void setup() {
  Serial.begin(115200);
  pinMode(RED, OUTPUT);
  pinMode(AMBER, OUTPUT);
  pinMode(GREEN, OUTPUT);
  pinMode(RC_PIN_USER_BUTTON, INPUT);
}

void show(int pin, const char *name) {
  digitalWrite(RED, pin == RED);
  digitalWrite(AMBER, pin == AMBER);
  digitalWrite(GREEN, pin == GREEN);
  Serial.println(name);
}

void loop() {
  show(GREEN, "green");
  // Stay green for 5 seconds, or until USER is pressed
  unsigned long start = millis();
  while (digitalRead(RC_PIN_USER_BUTTON) == HIGH && millis() - start < 5000) {
    delay(20);
  }
  show(AMBER, "amber");
  delay(1000);
  show(RED, "red");
  delay(4000);
}
''',
  'UltrasonicDistance': r'''// Ultrasonic distance
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
''',
};
