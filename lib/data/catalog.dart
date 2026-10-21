// Boards, libraries, examples and block definitions (same data as the web IDE).
// ignore_for_file: prefer_single_quotes
import 'robocore_v2_examples.dart';
import 'robocore_v2_pins.dart';

export 'robocore_v2_pins.dart' show RoboCoreV2Pins;

class BoardDef {
  final String id, name, full, chip, spec, arch, mcu, rev;
  final int led, max, ram, base, rbase, per;
  final List<List<String>> details;

  /// The board's USB socket, as messages name it (USB-C on the RoboCore V2).
  final String usb;

  /// How the browser's port chooser lists the board.
  final String pickAs;
  const BoardDef({
    this.usb = 'USB',
    this.pickAs = 'the board',
    required this.id,
    required this.name,
    required this.full,
    required this.chip,
    required this.spec,
    required this.arch,
    required this.led,
    required this.max,
    required this.ram,
    required this.base,
    required this.rbase,
    required this.per,
    required this.mcu,
    required this.rev,
    required this.details,
  });
}

/// Where sketches run: the simulated preview board, or a real board on USB-C.
const kPortSim = 'sim';
const kPortUsb = 'usb';

const Map<String, BoardDef> kBoards = {
  'v2': BoardDef(
      id: 'v2',
      usb: 'USB-C',
      pickAs: '“USB JTAG/serial debug unit” (ESP32-S3)',
      name: 'RoboCore V2',
      full: 'RoboCore V2 (ESP32-S3)',
      chip: 'ESP32-S3',
      spec: 'ESP32-S3 · 8 MB flash · 2 MB PSRAM',
      arch: 'esp32',
      led: RoboCoreV2Pins.rgbLed,
      max: 3145728,
      ram: 327680,
      base: 286000,
      rbase: 20100,
      per: 57,
      mcu: 'ESP32-S3, 240 MHz',
      rev: 'Prototype · rev 2.0',
      details: [
        ['MCU', 'ESP32-S3-WROOM-1-N8R2, dual-core 240 MHz'],
        ['Memory', '8 MB flash · 2 MB quad PSRAM'],
        ['USB', 'USB-C straight to the ESP32-S3 (no USB-UART chip)'],
        ['Built-in LED', 'RGB LED on IO48 (LED_BUILTIN)'],
        ['Wireless', 'Wi-Fi · Bluetooth LE'],
        ['Motors', '2 DC with encoders'],
        ['Servos', '4 ports'],
        ['Sensors', 'Sonar and line ports · IMU'],
      ]),
  'uno': BoardDef(
      id: 'uno',
      pickAs: '“Arduino Uno” (a clone with a CH340 chip shows as “USB2.0-Serial”)',
      name: 'Arduino Uno R3',
      full: 'Arduino Uno R3',
      chip: 'ATmega328P',
      spec: 'ATmega328P · 32 KB flash',
      arch: 'avr',
      led: 13,
      max: 32256,
      ram: 2048,
      base: 720,
      rbase: 9,
      per: 9,
      mcu: 'ATmega328P, 16 MHz',
      rev: 'Classic board',
      details: [
        ['MCU', 'ATmega328P, 16 MHz'],
        ['Memory', '32 KB flash · 2 KB SRAM'],
        ['USB', 'USB-B via ATmega16U2'],
        ['Wireless', 'None'],
        ['Built-in LED', 'Pin 13'],
        ['Logic level', '5 V'],
      ]),
  'devkit': BoardDef(
      id: 'devkit',
      pickAs: '“CP2102 USB to UART Bridge Controller”',
      name: 'ESP32 DevKit V1',
      full: 'ESP32 DevKit V1',
      chip: 'ESP32',
      spec: 'ESP32 · 4 MB flash',
      arch: 'esp32',
      led: 2,
      max: 1310720,
      ram: 327680,
      base: 262000,
      rbase: 19800,
      per: 52,
      mcu: 'ESP32, 240 MHz',
      rev: 'Generic dev board',
      details: [
        ['MCU', 'ESP32, dual-core 240 MHz'],
        ['Memory', '4 MB flash · 520 KB SRAM'],
        ['USB', 'Micro-USB via CP2102'],
        ['Wireless', 'Wi-Fi · Bluetooth'],
        ['Built-in LED', 'GPIO 2'],
        ['Logic level', '3.3 V'],
      ]),
  'nodemcu': BoardDef(
      id: 'nodemcu',
      pickAs: '“USB2.0-Serial” (CH340)',
      name: 'NodeMCU-32S',
      full: 'NodeMCU-32S',
      chip: 'ESP32',
      spec: 'ESP32 · 4 MB flash',
      arch: 'esp32',
      led: 2,
      max: 1310720,
      ram: 327680,
      base: 262000,
      rbase: 19800,
      per: 52,
      mcu: 'ESP32, 240 MHz',
      rev: 'Generic dev board',
      details: [
        ['MCU', 'ESP32, dual-core 240 MHz'],
        ['Memory', '4 MB flash · 520 KB SRAM'],
        ['USB', 'Micro-USB via CH340'],
        ['Wireless', 'Wi-Fi · Bluetooth'],
        ['Built-in LED', 'GPIO 2'],
        ['Logic level', '3.3 V'],
      ]),
};
const kBoardOrder = ['v2', 'uno', 'devkit', 'nodemcu'];

class LibDef {
  /// arch: any | esp32 | v2 (the RoboCore library only builds for the RoboCore V2).
  final String id, name, ver, h, kind, arch, desc;
  final List<String> types;
  const LibDef(this.id, this.name, this.ver, this.h, this.kind, this.arch, this.types, this.desc);
}

/// The RoboCore library (firmware/RoboCore) is one Arduino library with three headers.
const kLibs = [
  LibDef('robocore', 'RoboCore', '1.0.0', 'RoboCore.h', 'included', 'v2', ['RoboCoreDrive', 'RoboCoreServos', 'RoboCoreEdge'],
      'Everything in one include: pin names (RC_PIN_…), motors, sensors, the driving base (move, turn), servos, '
          'battery, USER button, buzzer, melodies, RGB LED and timer.'),
  LibDef('motors', 'RoboCore Motors', '1.0.0', 'RoboCoreMotors.h', 'included', 'v2', ['RoboCoreMotors'],
      'Drive the two motor ports with encoder feedback.'),
  LibDef('sensors', 'RoboCore Sensors', '1.0.0', 'RoboCoreSensors.h', 'included', 'v2', ['Sonar', 'LineSensor', 'IMU'],
      'Ultrasonic, line sensor and IMU helpers.'),
  LibDef('wire', 'Wire', 'core', 'Wire.h', 'included', 'any', ['TwoWire'], 'I²C for the Qwiic port and expansion headers.'),
  LibDef('esp32servo', 'ESP32Servo', '3.2.1', 'ESP32Servo.h', 'opt', 'esp32', ['Servo'], 'Control hobby servos with PWM.'),
  LibDef('neopixel', 'Adafruit NeoPixel', '1.12.3', 'Adafruit_NeoPixel.h', 'opt', 'any', ['Adafruit_NeoPixel'],
      'The RoboCore V2 RGB LED.'),
  LibDef('newping', 'NewPing', '1.9.7', 'NewPing.h', 'opt', 'any', ['NewPing'], 'Fast ultrasonic distance readings.'),
  LibDef('lcd', 'LiquidCrystal I2C', '1.1.2', 'LiquidCrystal_I2C.h', 'opt', 'any', ['LiquidCrystal_I2C'],
      '16×2 and 20×4 character LCDs.'),
];

/// Other headers that belong to a library above.
const kHeaderAlias = {'RoboCoreV2Pins.h': 'RoboCore.h', 'RoboCoreDrive.h': 'RoboCore.h', 'RoboCoreServos.h': 'RoboCore.h'};

/// Libraries whose headers give a sketch the RoboCore V2 pin names (RC_PIN_…).
const kRoboCoreLibs = {'robocore', 'motors', 'sensors'};

/// The RoboCore library's own names (sides, units, directions, tunes), as in firmware/RoboCore/src.
const kRoboCoreConsts = <String, num>{
  'LEFT': 0, 'RIGHT': 1, 'BACKWARD': -1, 'FORWARD': 1, 'CM': 0, 'ROTATIONS': 1, 'DEGREES': 2, 'SECONDS': 3, //
  'MELODY_POWER_UP': 0, 'MELODY_POWER_DOWN': 1, 'MELODY_SUCCESS': 2, 'MELODY_ERROR': 3, 'MELODY_ALARM': 4,
  'RC_COUNTS_PER_WHEEL_TURN': 292.5,
};

const kConfigH = '''// config.h — shared settings for this project
#pragma once

#define BAUD_RATE 115200
#define LED_PIN LED_BUILTIN
''';

class Example {
  final String id, name, proj, cat, level, desc, tag, boards, code;
  final String? file;
  final Map<String, dynamic>? blocks;

  /// The RoboCore library example used on the RoboCore V2 (a folder in firmware/RoboCore/examples).
  final String? v2;

  /// Blocks for the RoboCore V2 when its pins differ from the other boards.
  final Map<String, dynamic>? v2Blocks;

  /// Needs the real board: uses C++ the preview board can't run (Upload to a board on USB-C).
  final bool realOnly;

  /// A Blockly workspace (Blockly's JSON) for examples made with the hardware-first blocks; [code] is its C++.
  final String? blockly;

  /// Opens with blocks (the old lists, or a Blockly workspace).
  bool get hasBlocks => blocks != null || blockly != null;

  const Example({
    required this.id,
    required this.name,
    required this.proj,
    this.file,
    required this.cat,
    required this.level,
    required this.desc,
    required this.tag,
    required this.boards,
    this.blocks,
    required this.code,
    this.v2,
    this.v2Blocks,
    this.realOnly = false,
    this.blockly,
  });

  /// The sketch for [board]: the library's own example on the RoboCore V2.
  String codeFor(String board) {
    final lib = v2 == null ? null : kV2ExampleCode[v2];
    if (lib != null && (board == 'v2' || code.isEmpty)) return lib;
    return code;
  }

  Map<String, dynamic>? blocksFor(String board) => board == 'v2' ? (v2Blocks ?? blocks) : blocks;
}

const kExCats = ['All', 'Basics', 'Sensors', 'Robotics', 'Sound & light', 'Communication'];
const kExIcon = {
  'boardtest': 'chip',
  'blink': 'light',
  'button': 'enter',
  'traffic': 'clock',
  'ultrasonic': 'radar',
  'tones': 'wave',
  'motors': 'robot',
  'imu': 'msg',
  'obstacle': 'bolt',
  'robot_avoider': 'robot',
  'melody': 'music',
  'rgb': 'light',
  'line': 'robot',
  'servo': 'gear',
  'distance': 'radar',
  'logger': 'term',
  'echo': 'msg',
};

const List<Example> kExamples = [
  Example(
    id: 'boardtest',
    v2: 'BoardTest',
    name: 'RoboCore V2 board test',
    proj: 'Board test',
    file: 'BoardTest',
    cat: 'Basics',
    level: 'Advanced',
    desc: 'Check every part of a RoboCore V2: LED, buzzer, buttons, IMU, sensors, motors and servos.',
    tag: 'PASS / FAIL for each part',
    boards: 'RoboCore V2 · real board',
    realOnly: true,
    code: '',
  ),
  Example(
    id: 'blink',
    v2: 'Blink',
    name: 'Blink an LED',
    proj: 'Blink LED',
    file: 'Blink',
    cat: 'Basics',
    level: 'Beginner',
    desc: 'Switch the built-in LED on and off.',
    tag: 'The first sketch everyone runs',
    boards: 'V2 · Uno · ESP32',
    blocks: {"setup": [{"t": "serial", "baud": "115200"}, {"t": "print", "text": "RoboCore V2 ready"}], "loop": [{"t": "led", "state": "HIGH"}, {"t": "wait", "secs": 1}, {"t": "led", "state": "LOW"}, {"t": "wait", "secs": 1}]},
    code: r'''// Blink — RoboCore V2
// Turns the built-in LED on and off every second.

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
  ),
  Example(
    id: 'button',
    v2: 'ButtonLed',
    name: 'Button-controlled LED',
    proj: 'Button LED',
    file: null,
    cat: 'Basics',
    level: 'Beginner',
    desc: 'Light the LED while USER is pressed.',
    tag: 'Read a button, drive an LED',
    boards: 'V2 · Uno · ESP32',
    blocks: null,
    code: r'''// Button-controlled LED
// Lights the built-in LED while the USER button is held down.
#define USER_BUTTON 0

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(USER_BUTTON, INPUT_PULLUP);
}

void loop() {
  bool pressed = digitalRead(USER_BUTTON) == LOW;
  digitalWrite(LED_BUILTIN, pressed ? HIGH : LOW);
  delay(10);
}
''',
  ),
  Example(
    id: 'traffic',
    v2: 'TrafficLight',
    name: 'Traffic light',
    proj: 'Traffic light',
    file: null,
    cat: 'Basics',
    level: 'Beginner',
    desc: 'Sequence three LEDs with timing.',
    tag: 'Three LEDs and a button',
    boards: 'V2 · Uno · ESP32',
    blocks: {"setup": [{"t": "serial", "baud": "115200"}], "loop": [{"t": "pin", "pin": "6", "state": "HIGH"}, {"t": "print", "text": "green"}, {"t": "wait", "secs": 4, "unit": "secs"}, {"t": "pin", "pin": "6", "state": "LOW"}, {"t": "pin", "pin": "5", "state": "HIGH"}, {"t": "print", "text": "amber"}, {"t": "wait", "secs": 1, "unit": "secs"}, {"t": "pin", "pin": "5", "state": "LOW"}, {"t": "pin", "pin": "4", "state": "HIGH"}, {"t": "print", "text": "red"}, {"t": "wait", "secs": 4, "unit": "secs"}, {"t": "pin", "pin": "4", "state": "LOW"}]},
    // RoboCore V2: red IO3, amber IO37, green IO43 on the expansion header (4, 5 and 6 are sensor inputs there).
    v2Blocks: {"setup": [{"t": "serial", "baud": "115200"}], "loop": [{"t": "pin", "pin": "43", "state": "HIGH"}, {"t": "print", "text": "green"}, {"t": "wait", "secs": 4, "unit": "secs"}, {"t": "pin", "pin": "43", "state": "LOW"}, {"t": "pin", "pin": "37", "state": "HIGH"}, {"t": "print", "text": "amber"}, {"t": "wait", "secs": 1, "unit": "secs"}, {"t": "pin", "pin": "37", "state": "LOW"}, {"t": "pin", "pin": "3", "state": "HIGH"}, {"t": "print", "text": "red"}, {"t": "wait", "secs": 4, "unit": "secs"}, {"t": "pin", "pin": "3", "state": "LOW"}]},
    code: r'''// Traffic light
// Red, amber and green LEDs on pins 4, 5 and 6.
// A push button between pin 2 and GND asks the light to change.
#define BUTTON_PIN 2

const int RED = 4;
const int AMBER = 5;
const int GREEN = 6;

void setup() {
  Serial.begin(115200);
  pinMode(RED, OUTPUT);
  pinMode(AMBER, OUTPUT);
  pinMode(GREEN, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
}

void show(int pin, String name) {
  digitalWrite(RED, pin == RED);
  digitalWrite(AMBER, pin == AMBER);
  digitalWrite(GREEN, pin == GREEN);
  Serial.println(name);
}

void loop() {
  show(GREEN, "green");
  // Stay green for 5 seconds, or until the button is pressed
  unsigned long start = millis();
  while (digitalRead(BUTTON_PIN) == HIGH && millis() - start < 5000) {
    delay(20);
  }
  show(AMBER, "amber");
  delay(1000);
  show(RED, "red");
  delay(4000);
}
''',
  ),
  Example(
    id: 'ultrasonic',
    v2: 'UltrasonicDistance',
    name: 'Ultrasonic distance',
    proj: 'Ultrasonic distance',
    file: null,
    cat: 'Sensors',
    level: 'Intermediate',
    desc: 'Measure distance and print it.',
    tag: 'Sonar readings to serial',
    boards: 'RoboCore V2',
    blocks: null,
    code: r'''// Ultrasonic distance
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
  ),
  Example(
    id: 'tones',
    v2: 'BuzzerTones',
    name: 'Buzzer tones',
    proj: 'Buzzer tones',
    file: null,
    cat: 'Sound & light',
    level: 'Beginner',
    desc: 'Play notes with tone() and noTone().',
    tag: 'A rising scale',
    boards: 'V2 · Uno · ESP32',
    blocks: null,
    code: r'''// Buzzer tones
// Plays a rising scale on the buzzer (pin 8).
const int BUZZER = 8;

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
  ),
  Example(
    id: 'motors',
    v2: 'MotorControl',
    name: 'Motor control',
    proj: 'Motor control',
    file: null,
    cat: 'Robotics',
    level: 'Intermediate',
    desc: 'Drive, reverse and turn.',
    tag: 'Both motor ports',
    boards: 'RoboCore V2',
    blocks: null,
    code: r'''// Motor control
// Drives forward, reverses, then turns on the spot.
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
  ),
  Example(
    id: 'imu',
    v2: 'SensorsToSerial',
    name: 'Sensors to serial',
    proj: 'Sensors to serial',
    file: null,
    cat: 'Sensors',
    level: 'Beginner',
    desc: 'Print temperature and IMU readings.',
    tag: 'IMU and temperature',
    boards: 'RoboCore V2',
    blocks: null,
    code: r'''// Sensors to serial
// Prints the board temperature and tilt twice a second.
#include <RoboCoreSensors.h>

IMU imu;

void setup() {
  Serial.begin(115200);
  imu.begin();
}

void loop() {
  Serial.print("temp_c=");
  Serial.print(imu.temperature(), 1);
  Serial.print("  tilt_deg=");
  Serial.println(imu.tiltDeg(), 1);
  delay(500);
}
''',
  ),
  Example(
    id: 'obstacle',
    v2: 'ObstacleAvoider',
    name: 'Obstacle avoider',
    proj: 'Obstacle avoider',
    file: null,
    cat: 'Robotics',
    level: 'Advanced',
    desc: 'Steer around walls with sonar.',
    tag: 'Sonar + motors',
    boards: 'RoboCore V2',
    blocks: null,
    code: r'''// Obstacle avoider
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
    Serial.println("obstacle — turning left");
    motors.drive(-50, 50);
    delay(400);
  } else {
    motors.drive(60, 60);
  }
  delay(250);
}
''',
  ),
  Example(
    id: 'robot_avoider',
    name: 'Robot obstacle avoider',
    proj: 'Robot avoider',
    file: 'RobotAvoider',
    cat: 'Robotics',
    level: 'Beginner',
    desc: 'Drives forward, and beeps and turns right at anything closer than 20 cm. USER stops it.',
    tag: 'The robot blocks',
    boards: 'RoboCore V2',
    blockly: r'''{"blocks":{"languageVersion":0,"blocks":[{"type":"rc_on_start","x":24,"y":24,"inputs":{"DO":{"block":{"type":"rc_move_speed","inputs":{"PCT":{"shadow":{"type":"math_number","fields":{"NUM":50}}}}}}}},{"type":"rc_forever","x":24,"y":168,"inputs":{"DO":{"block":{"type":"controls_if","extraState":{"hasElse":true},"inputs":{"IF0":{"block":{"type":"rc_closer","inputs":{"CM":{"shadow":{"type":"math_number","fields":{"NUM":20}}}}}},"DO0":{"block":{"type":"rc_stop_moving","next":{"block":{"type":"rc_beep","fields":{"NOTE":"C5"},"inputs":{"SECS":{"shadow":{"type":"math_number","fields":{"NUM":0.2}}}},"next":{"block":{"type":"rc_turn","fields":{"DIR":"right"},"inputs":{"DEG":{"shadow":{"type":"math_number","fields":{"NUM":90}}}}}}}}}},"ELSE":{"block":{"type":"rc_start_moving","fields":{"DIR":"forward"}}}}}}}},{"type":"rc_when_user","x":460,"y":24,"inputs":{"DO":{"block":{"type":"rc_stop_moving","next":{"block":{"type":"rc_stop_program"}}}}}}]}}''',
    code: r'''// Robot avoider
// Made with blocks in RoboCore IDE.

#include <RoboCore.h>

RoboCoreMotors motors;
Sonar sonar;
IMU imu;
RoboCoreDrive robot(motors, imu);

void setup() {
  motors.begin();
  sonar.begin();
  robot.setSpeed(50);
}

void loop() {
  if (RoboCore::userJustPressed()) {
    robot.stop();
    RoboCore::stopProgram();
  }
  if (sonar.distanceCm() < 20) {
    robot.stop();
    RoboCore::beep(523, 200);  // C5
    robot.turn(90);
  } else {
    robot.start(FORWARD);
  }
}
''',
  ),
  Example(
    id: 'melody',
    v2: 'BuzzerMelody',
    name: 'Buzzer melody',
    proj: 'Buzzer melody',
    file: null,
    cat: 'Sound & light',
    level: 'Beginner',
    desc: 'Play a short tune note by note.',
    tag: 'Play a tune with tone()',
    boards: 'V2 · Uno · ESP32',
    blocks: {"setup": [], "loop": [{"t": "tone", "pin": 8, "note": "C4", "secs": 0.4}, {"t": "tone", "pin": 8, "note": "C4", "secs": 0.4}, {"t": "tone", "pin": 8, "note": "G4", "secs": 0.4}, {"t": "tone", "pin": 8, "note": "G4", "secs": 0.4}, {"t": "tone", "pin": 8, "note": "A4", "secs": 0.4}, {"t": "tone", "pin": 8, "note": "A4", "secs": 0.4}, {"t": "tone", "pin": 8, "note": "G4", "secs": 0.8}, {"t": "wait", "secs": 1}]},
    // RoboCore V2: the buzzer is IO47 (pin 8 is I²C SDA there).
    v2Blocks: {"setup": [], "loop": [{"t": "tone", "pin": "47", "note": "C4", "secs": 0.4}, {"t": "tone", "pin": "47", "note": "C4", "secs": 0.4}, {"t": "tone", "pin": "47", "note": "G4", "secs": 0.4}, {"t": "tone", "pin": "47", "note": "G4", "secs": 0.4}, {"t": "tone", "pin": "47", "note": "A4", "secs": 0.4}, {"t": "tone", "pin": "47", "note": "A4", "secs": 0.4}, {"t": "tone", "pin": "47", "note": "G4", "secs": 0.8}, {"t": "wait", "secs": 1}]},
    code: r'''// Buzzer melody
// Plays a short tune on the buzzer (pin 8).
const int BUZZER = 8;

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
  ),
  Example(
    id: 'rgb',
    v2: 'RgbColours',
    name: 'RGB colour cycle',
    proj: 'RGB colours',
    file: null,
    cat: 'Sound & light',
    level: 'Beginner',
    desc: 'Step the RGB LED through red, green and blue.',
    tag: 'The on-board RGB LED',
    boards: 'RoboCore V2',
    blocks: null,
    code: r'''// RGB colour cycle
// Steps the on-board RGB LED through a few colours.

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
  ),
  Example(
    id: 'line',
    v2: 'LineFollower',
    name: 'Line follower',
    proj: 'Line follower',
    file: null,
    cat: 'Robotics',
    level: 'Intermediate',
    desc: 'Follow a dark line with the IR line sensor.',
    tag: 'Follow a line with IR sensors',
    boards: 'RoboCore V2',
    blocks: {"setup": [{"t": "serial", "baud": "115200"}], "loop": [{"t": "linesens"}, {"t": "drive", "dir": "forward", "speed": 45}, {"t": "wait", "secs": 50, "unit": "ms"}]},
    code: r'''// Line follower
// Steers toward the line using the IR line sensor.
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
  ),
  Example(
    id: 'servo',
    v2: 'ServoSweep',
    name: 'Servo sweep',
    proj: 'Servo sweep',
    file: null,
    cat: 'Robotics',
    level: 'Beginner',
    desc: 'Sweep a servo from 0° to 180° and back.',
    tag: 'Hobby servo on PWM',
    boards: 'V2 · ESP32 boards',
    blocks: null,
    code: r'''// Servo sweep
// Sweeps a servo on pin 18 from 0 to 180 degrees and back.
#include <ESP32Servo.h>

Servo arm;

void setup() {
  Serial.begin(115200);
  arm.attach(18);
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
  ),
  Example(
    id: 'distance',
    v2: 'DistanceMonitor',
    name: 'Distance monitor',
    proj: 'Distance monitor',
    file: null,
    cat: 'Sensors',
    level: 'Beginner',
    desc: 'Print the sonar distance twice a second, built with blocks.',
    tag: 'Sonar with blocks',
    boards: 'RoboCore V2',
    blocks: {"setup": [{"t": "serial", "baud": "115200"}, {"t": "print", "text": "Distance monitor ready"}], "loop": [{"t": "distance"}, {"t": "wait", "secs": 0.5}]},
    code: r'''''',
  ),
  Example(
    id: 'logger',
    v2: 'SensorLogger',
    name: 'Sensor logger',
    proj: 'Sensor logger',
    file: null,
    cat: 'Sensors',
    level: 'Intermediate',
    desc: 'Log an analog sensor as CSV with timestamps.',
    tag: 'CSV over serial',
    boards: 'V2 · Uno · ESP32',
    blocks: null,
    code: r'''// Sensor logger
// Logs a light sensor on pin 34 as CSV, once a second.
const int LIGHT_PIN = 34;

void setup() {
  Serial.begin(115200);
  Serial.println("time_ms,light");
}

void loop() {
  int light = analogRead(LIGHT_PIN);
  Serial.print(millis());
  Serial.print(",");
  Serial.println(light);
  delay(1000);
}
''',
  ),
  Example(
    id: 'echo',
    v2: 'SerialEcho',
    name: 'Serial echo',
    proj: 'Serial echo',
    file: null,
    cat: 'Communication',
    level: 'Intermediate',
    desc: 'Reply to text you send from the Serial Monitor.',
    tag: 'Talk to your board',
    boards: 'V2 · Uno · ESP32',
    blocks: null,
    code: r'''// Serial echo
// Replies to each line you send from the Serial Monitor.

void setup() {
  Serial.begin(115200);
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
  ),
];

Example exampleById(String id) => kExamples.firstWhere((e) => e.id == id);

// ---------- blocks ----------
class BlockCat {
  final String id, name, icon;
  const BlockCat(this.id, this.name, this.icon);
}

const kCats = [
  BlockCat('output', 'Output', 'light'),
  BlockCat('input', 'Input', 'enter'),
  BlockCat('control', 'Control', 'repeat'),
  BlockCat('math', 'Math', 'sigma'),
  BlockCat('variables', 'Variables', 'varx'),
  BlockCat('robotics', 'Robotics', 'robot'),
  BlockCat('sensors', 'Sensors', 'radar'),
  BlockCat('communication', 'Communication', 'msg'),
];

const Map<String, int> kNotes = {
  'C4': 262, 'D4': 294, 'E4': 330, 'F4': 349, 'G4': 392, 'A4': 440, 'B4': 494, 'C5': 523, 'D5': 587, 'E5': 659, //
};
const Map<String, List<int>> kColors = {
  'red': [255, 0, 0],
  'green': [0, 255, 0],
  'blue': [0, 0, 255],
  'yellow': [255, 200, 0],
  'purple': [160, 0, 255],
  'white': [255, 255, 255],
  'off': [0, 0, 0],
};
const kPins = ['2', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '18', '48'];

/// Pins the "set pin" and "tone" blocks offer on [board]. On the RoboCore V2 almost every GPIO
/// already drives a motor, reads a sensor or carries USB / I²C, so only the free ones are offered
/// (and the buzzer, IO47, for tones).
List<String> pinOptions(String board, {bool tone = false}) {
  if (board != 'v2') return kPins;
  return [
    if (tone) '${RoboCoreV2Pins.buzzer}',
    for (final p in RoboCoreV2Pins.freePins) '$p',
  ];
}

/// A new block's starting values on [board].
Map<String, dynamic> blockDefaults(String type, String board) {
  final d = <String, dynamic>{...kBlockTypes[type]!.def};
  if (board == 'v2') {
    if (type == 'pin') d['pin'] = '${RoboCoreV2Pins.expIo3}';
    if (type == 'tone') d['pin'] = '${RoboCoreV2Pins.buzzer}';
  }
  return d;
}

/// A block part is either a label (String) or a field.
class BField {
  final String k, type; // type: sel | num | text
  final List<String> opts;
  const BField(this.k, this.type, [this.opts = const []]);
}

class BlockType {
  final String cat;
  final List<Object> parts;
  final Map<String, dynamic> def;
  const BlockType(this.cat, this.parts, this.def);
  bool get isControl => cat == 'control' || cat == 'input';
}

final Map<String, BlockType> kBlockTypes = {
  'button': const BlockType('input', ['wait until USER is pressed'], {}),
  'led': const BlockType('output', ['set built-in LED to', BField('state', 'sel', ['HIGH', 'LOW'])], {'state': 'HIGH'}),
  'pin': const BlockType('output', ['set pin', BField('pin', 'sel', kPins), 'to', BField('state', 'sel', ['HIGH', 'LOW'])],
      {'pin': '13', 'state': 'HIGH'}),
  'tone': BlockType('output', ['tone pin', const BField('pin', 'sel', kPins), BField('note', 'sel', kNotes.keys.toList()), 'for', const BField('secs', 'num'), 's'],
      const {'pin': '8', 'note': 'C4', 'secs': 0.5}),
  'rgb': BlockType('output', ['set RGB LED to', BField('color', 'sel', kColors.keys.toList())], const {'color': 'red'}),
  'wait': const BlockType('control', ['wait', BField('secs', 'num'), BField('unit', 'sel', ['secs', 'ms'])], {'secs': 1, 'unit': 'secs'}),
  'rand': const BlockType('math', ['set', BField('v', 'text'), 'to random', BField('a', 'num'), 'to', BField('b', 'num')],
      {'v': 'x', 'a': 0, 'b': 100}),
  'setvar': const BlockType('variables', ['set', BField('v', 'text'), 'to', BField('n', 'num')], {'v': 'count', 'n': 0}),
  'change': const BlockType('variables', ['change', BField('v', 'text'), 'by', BField('n', 'num')], {'v': 'count', 'n': 1}),
  'drive': const BlockType('robotics',
      ['drive', BField('dir', 'sel', ['forward', 'backward', 'left', 'right']), 'at', BField('speed', 'num'), '%'], {'dir': 'forward', 'speed': 60}),
  'stop': const BlockType('robotics', ['stop motors'], {}),
  'distance': const BlockType('sensors', ['print distance in cm'], {}),
  'linesens': const BlockType('sensors', ['print line sensor'], {}),
  'serial': const BlockType('communication', ['start serial at', BField('baud', 'sel', ['9600', '115200']), 'baud'], {'baud': '115200'}),
  'print': const BlockType('communication', ['print', BField('text', 'text')], {'text': 'RoboCore V2 ready'}),
  'printvar': const BlockType('communication', ['print variable', BField('v', 'text')], {'v': 'count'}),
};
