// The RoboCore V2's pins as a user sees them: the part on each GPIO, its name in RoboCore.h and where it comes out.
// From the V2 pin reference (RoboCoreDocumentation, docs/RoboCore_V2_pin_reference.md, 2026-11-09). The numbers come
// from RoboCoreV2Pins, so they follow firmware/RoboCore/src/RoboCoreV2Pins.h; test/engine_test.dart checks the names.
import 'robocore_v2_pins.dart';

class V2Pin {
  const V2Pin(this.io, this.part, this.cName, this.where, {this.note = ''});

  final int io;

  /// The part on this pin, or '' for a pin that is free for your own parts.
  final String part;

  /// Its name in RoboCore.h, or '' when it has none.
  final String cName;

  /// Where it comes out: a header and pin, a button, or '' when it stays on the board.
  final String where;

  /// What to know before using it.
  final String note;

  /// The name in the pin menus: "Buzzer (IO47)", or "IO37 (expansion B pin 9)" for a free pin.
  String get label => part.isEmpty ? 'IO$io (${where[0].toLowerCase()}${where.substring(1)})' : '$part (IO$io)';
}

/// Every GPIO of the ESP32-S3 on the board, in number order.
const kV2Pins = <V2Pin>[
  V2Pin(RoboCoreV2Pins.bootButton, 'BOOT button', 'RC_PIN_BOOT_BUTTON', 'Button', note: 'LOW while pressed'),
  V2Pin(RoboCoreV2Pins.imuInt1, 'IMU interrupt', 'RC_PIN_IMU_INT1', 'Expansion B pin 10'),
  V2Pin(RoboCoreV2Pins.lineRight, 'Line sensor R', 'RC_PIN_LINE_RIGHT', 'Line header, expansion A pin 5', note: 'Analog'),
  V2Pin(RoboCoreV2Pins.expIo3, '', 'RC_PIN_EXP_IO3', 'Expansion A pin 12', note: 'Free, analog; the ESP32 reads it at power-up'),
  V2Pin(RoboCoreV2Pins.batterySense, 'Battery voltage', 'RC_PIN_BATTERY_SENSE', '', note: 'Half the battery voltage'),
  V2Pin(RoboCoreV2Pins.motor1Isense, 'Motor 1 current', 'RC_PIN_MOTOR1_ISENSE', ''),
  V2Pin(RoboCoreV2Pins.motor2Isense, 'Motor 2 current', 'RC_PIN_MOTOR2_ISENSE', ''),
  V2Pin(RoboCoreV2Pins.lineLeft, 'Line sensor L', 'RC_PIN_LINE_LEFT', 'Line header, expansion A pin 3', note: 'Analog'),
  V2Pin(RoboCoreV2Pins.i2cSda, 'I²C SDA', 'RC_PIN_I2C_SDA', 'Qwiic, expansion B pin 3', note: 'The IMU’s bus: not a plain pin'),
  V2Pin(RoboCoreV2Pins.i2cScl, 'I²C SCL', 'RC_PIN_I2C_SCL', 'Qwiic, expansion B pin 4', note: 'The IMU’s bus: not a plain pin'),
  V2Pin(RoboCoreV2Pins.lineCentre, 'Line sensor C', 'RC_PIN_LINE_CENTRE', 'Line header, expansion A pin 4', note: 'Analog'),
  V2Pin(RoboCoreV2Pins.motor1In1, 'Motor 1 forward', 'RC_PIN_MOTOR1_IN1', 'Motor socket 1'),
  V2Pin(RoboCoreV2Pins.motor1In2, 'Motor 1 reverse', 'RC_PIN_MOTOR1_IN2', 'Motor socket 1'),
  V2Pin(RoboCoreV2Pins.motor2In1, 'Motor 2 forward', 'RC_PIN_MOTOR2_IN1', 'Motor socket 2'),
  V2Pin(RoboCoreV2Pins.motor2In2, 'Motor 2 reverse', 'RC_PIN_MOTOR2_IN2', 'Motor socket 2'),
  V2Pin(RoboCoreV2Pins.enc1A, 'Encoder 1 A', 'RC_PIN_ENC1_A', 'Motor socket 1'),
  V2Pin(RoboCoreV2Pins.enc1B, 'Encoder 1 B', 'RC_PIN_ENC1_B', 'Motor socket 1'),
  V2Pin(RoboCoreV2Pins.enc2A, 'Encoder 2 A', 'RC_PIN_ENC2_A', 'Motor socket 2'),
  V2Pin(RoboCoreV2Pins.enc2B, 'Encoder 2 B', 'RC_PIN_ENC2_B', 'Motor socket 2'),
  V2Pin(19, 'USB D−', '', 'USB-C', note: 'Leave alone'),
  V2Pin(20, 'USB D+', '', 'USB-C', note: 'Leave alone'),
  V2Pin(RoboCoreV2Pins.motorNfault, 'Motor driver fault', 'RC_PIN_MOTOR_NFAULT', '', note: 'LOW on a fault'),
  V2Pin(RoboCoreV2Pins.servo3, 'Servo 3', 'RC_PIN_SERVO3', 'SERVO 3, expansion B pin 7'),
  V2Pin(RoboCoreV2Pins.servo4, 'Servo 4', 'RC_PIN_SERVO4', 'SERVO 4, expansion B pin 8'),
  V2Pin(RoboCoreV2Pins.expIo37, '', 'RC_PIN_EXP_IO37', 'Expansion B pin 9', note: 'Free'),
  V2Pin(RoboCoreV2Pins.servo1, 'Servo 1', 'RC_PIN_SERVO1', 'SERVO 1, expansion A pin 8'),
  V2Pin(RoboCoreV2Pins.servo2, 'Servo 2', 'RC_PIN_SERVO2', 'SERVO 2, expansion A pin 9'),
  V2Pin(RoboCoreV2Pins.sonarTrig, 'Ultrasonic TRIG', 'RC_PIN_SONAR_TRIG', 'Ultrasonic header, expansion A pin 6'),
  V2Pin(RoboCoreV2Pins.sonarEcho, 'Ultrasonic ECHO', 'RC_PIN_SONAR_ECHO', 'Ultrasonic header, expansion A pin 7'),
  V2Pin(RoboCoreV2Pins.userButton, 'USER button', 'RC_PIN_USER_BUTTON', 'Button, expansion B pin 11', note: 'LOW while pressed'),
  V2Pin(RoboCoreV2Pins.uartTx, 'UART TX', 'RC_PIN_UART_TX', 'Expansion B pin 5', note: 'Free: Serial uses USB'),
  V2Pin(RoboCoreV2Pins.uartRx, 'UART RX', 'RC_PIN_UART_RX', 'Expansion B pin 6', note: 'Free: Serial uses USB'),
  V2Pin(45, 'Not connected', '', ''),
  V2Pin(46, 'Not connected', '', ''),
  V2Pin(RoboCoreV2Pins.buzzer, 'Buzzer', 'RC_PIN_BUZZER', 'Expansion A pin 10', note: 'Use tone()'),
  V2Pin(RoboCoreV2Pins.rgbLed, 'RGB LED', 'RC_PIN_RGB_LED', 'Data out on expansion A pin 11', note: 'Use rgbLedWrite()'),
];

/// The parts a sketch uses most, with the code that drives each one.
const kV2PartUses = <(String part, int io, String code, String note)>[
  ('Buzzer', RoboCoreV2Pins.buzzer, 'tone(RC_PIN_BUZZER, 523);', 'A magnetic buzzer: digitalWrite only clicks. noTone() stops it.'),
  ('RGB LED', RoboCoreV2Pins.rgbLed, 'rgbLedWrite(RGB_BUILTIN, 0, 80, 0);', 'A colour LED (WS2812B): digitalWrite(48, HIGH) doesn’t light it.'),
  ('USER button', RoboCoreV2Pins.userButton, 'digitalRead(RC_PIN_USER_BUTTON)', 'LOW while pressed.'),
  ('BOOT button', RoboCoreV2Pins.bootButton, 'digitalRead(RC_PIN_BOOT_BUTTON)', 'LOW while pressed. Held at reset, it waits for an upload.'),
  ('Battery', RoboCoreV2Pins.batterySense, 'analogReadMilliVolts(RC_PIN_BATTERY_SENSE) * 2', 'Millivolts. About 4 V on USB alone.'),
];
